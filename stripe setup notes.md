# Stripe Integration Implementation Plan

## **Overview**
Use Stripe Checkout for payment collection, Customer Portal for self-service management, and Webhooks for automation. All card handling stays with Stripe (PCI compliant). Backend manages subscription state in Azure Table Storage.

---

## **Architecture Flow**

```
User → Frontend → Backend API → Stripe
                       ↓
                  Webhooks ← Stripe
                       ↓
              Azure Table Storage
                       ↓
              Scheduled Task (monitors renewals)
```

---

## **Phase 1: Backend Setup**

### **1.1 Azure Configuration**

**Application Settings to Add:**
```
STRIPE_API_KEY = sk_live_xxxxxxxxxxxxx
STRIPE_WEBHOOK_SECRET = whsec_xxxxxxxxxxxxx
STRIPE_PRICE_ID_BASIC = price_xxxxxxxxxxxxx
STRIPE_PRICE_ID_PREMIUM = price_xxxxxxxxxxxxx
STRIPE_PRICE_ID_ENTERPRISE = price_xxxxxxxxxxxxx
```

### **1.2 Azure Table Storage Schema**

**Table: `Subscriptions`**
```
PartitionKey: UserId (string)
RowKey: SubscriptionId (string) - Stripe subscription ID
Fields:
  - CustomerId (string) - Stripe customer ID
  - Email (string)
  - Status (string) - active, canceled, past_due, expired
  - CurrentTier (string) - basic, premium, enterprise
  - PriceId (string) - Stripe price ID
  - CurrentPeriodStart (DateTime)
  - CurrentPeriodEnd (DateTime)
  - LastStripeRenewal (DateTime) - Last confirmed renewal from webhook
  - CanceledAt (DateTime?) - When user canceled
  - CreatedAt (DateTime)
  - UpdatedAt (DateTime)
```

### **1.3 Backend API Endpoints to Create**

#### **A. POST /api/CreateCheckoutSession**
```
Purpose: Create Stripe Checkout session for new subscriptions
Input:
  {
    "userId": "user123",
    "email": "user@example.com",
    "priceId": "price_xxxxx",
    "tier": "premium"
  }
Output:
  {
    "checkoutUrl": "https://checkout.stripe.com/c/pay/cs_test_xxxxx"
  }
Actions:
  1. Create Stripe Checkout Session
  2. Store pending subscription in Table Storage (status: pending)
  3. Return checkout URL to frontend
```

#### **B. POST /api/CreatePortalSession**
```
Purpose: Create Stripe Customer Portal session
Input:
  {
    "userId": "user123"
  }
Output:
  {
    "portalUrl": "https://billing.stripe.com/p/session/xxxxx"
  }
Actions:
  1. Get CustomerId from Table Storage by UserId
  2. Create Stripe Portal Session
  3. Return portal URL
```

#### **C. GET /api/GetSubscriptionDetails**
```
Purpose: Get subscription details for display
Input: userId (query parameter)
Output:
  {
    "status": "active",
    "tier": "premium",
    "currentPeriodEnd": "2026-02-20T00:00:00Z",
    "cancelAtPeriodEnd": false,
    "lastRenewal": "2026-01-20T00:00:00Z",
    "paymentMethod": {
      "brand": "visa",
      "last4": "4242"
    }
  }
Actions:
  1. Get subscription from Table Storage
  2. Optionally fetch live data from Stripe API
  3. Return formatted subscription info
```

#### **D. POST /api/StripeWebhook** (Critical)
```
Purpose: Handle Stripe webhook events
Input: Raw Stripe webhook payload
Actions:
  1. Verify webhook signature
  2. Parse event type
  3. Update Table Storage based on event
  4. Return 200 OK
  
Events to handle:
  - checkout.session.completed
  - customer.subscription.created
  - customer.subscription.updated
  - customer.subscription.deleted
  - invoice.payment_succeeded
  - invoice.payment_failed
```

#### **E. POST /api/AdminCancelSubscription** (Optional - Admin only)
```
Purpose: Admin force-cancel subscription
Input:
  {
    "userId": "user123",
    "reason": "policy violation"
  }
Actions:
  1. Get subscription from Table Storage
  2. Cancel via Stripe API
  3. Update Table Storage
```

---

## **Phase 2: Frontend Implementation**

### **2.1 Subscription Page Components**

#### **A. Subscription Selection/Upgrade**
```javascript
// When user clicks "Subscribe" or "Upgrade"
async function handleSubscribe(tier) {
  try {
    const response = await fetch('/api/CreateCheckoutSession', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        userId: currentUser.id,
        email: currentUser.email,
        priceId: PRICE_IDS[tier],
        tier: tier
      })
    });
    
    const { checkoutUrl } = await response.json();
    window.location.href = checkoutUrl; // Redirect to Stripe
  } catch (error) {
    console.error('Failed to create checkout:', error);
  }
}
```

#### **B. Manage Subscription Button**
```javascript
// When user clicks "Manage Subscription"
async function handleManageSubscription() {
  try {
    const response = await fetch('/api/CreatePortalSession', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        userId: currentUser.id
      })
    });
    
    const { portalUrl } = await response.json();
    window.location.href = portalUrl; // Redirect to Stripe Portal
  } catch (error) {
    console.error('Failed to open portal:', error);
  }
}
```

#### **C. Display Current Subscription**
```javascript
// Load and display subscription details
async function loadSubscriptionDetails() {
  try {
    const response = await fetch(`/api/GetSubscriptionDetails?userId=${currentUser.id}`);
    const subscription = await response.json();
    
    // Update UI
    document.getElementById('current-tier').textContent = subscription.tier;
    document.getElementById('renewal-date').textContent = 
      new Date(subscription.currentPeriodEnd).toLocaleDateString();
    document.getElementById('status').textContent = subscription.status;
    
    if (subscription.cancelAtPeriodEnd) {
      showCancellationNotice(subscription.currentPeriodEnd);
    }
    
    if (subscription.paymentMethod) {
      document.getElementById('payment-method').textContent = 
        `${subscription.paymentMethod.brand} ending in ${subscription.paymentMethod.last4}`;
    }
  } catch (error) {
    console.error('Failed to load subscription:', error);
  }
}
```

### **2.2 Success/Cancel Pages**

#### **Success Page (after Stripe Checkout)**
```javascript
// /success page
// URL: https://yourdomain.com/success?session_id=cs_xxxxx

async function handleCheckoutSuccess() {
  const urlParams = new URLSearchParams(window.location.search);
  const sessionId = urlParams.get('session_id');
  
  // Show success message
  showSuccessMessage("Subscription activated! Welcome aboard.");
  
  // Redirect to dashboard after 3 seconds
  setTimeout(() => {
    window.location.href = '/dashboard';
  }, 3000);
}
```

#### **Cancel Page (user canceled Stripe Checkout)**
```javascript
// /cancel page
showMessage("Subscription setup was canceled. You can try again anytime.");
```

---

## **Phase 3: Webhook Implementation (Backend)**

### **3.1 Create Webhook Function**

**File: `StripeWebhook/run.ps1`**

```powershell
using namespace System.Net

param($Request, $TriggerMetadata)

Import-Module "$PSScriptRoot/../Modules/StripeHelpers/StripeHelpers.psm1" -Force

# Initialize Stripe
Initialize-Stripe

# Verify webhook signature
$signature = $Request.Headers.'Stripe-Signature'
$webhookSecret = $env:STRIPE_WEBHOOK_SECRET

try {
    $stripeEvent = [Stripe.EventUtility]::ConstructEvent(
        $Request.RawBody,
        $signature,
        $webhookSecret
    )
    
    Write-Host "Processing event: $($stripeEvent.Type)"
    
    switch ($stripeEvent.Type) {
        "checkout.session.completed" {
            $session = $stripeEvent.Data.Object -as [Stripe.Checkout.Session]
            
            # Update subscription in Table Storage
            Update-SubscriptionFromCheckout -Session $session
        }
        
        "customer.subscription.created" {
            $subscription = $stripeEvent.Data.Object -as [Stripe.Subscription]
            
            # Store/update subscription
            Update-SubscriptionRecord -Subscription $subscription
        }
        
        "customer.subscription.updated" {
            $subscription = $stripeEvent.Data.Object -as [Stripe.Subscription]
            
            # Update subscription (tier change, cancel, etc)
            Update-SubscriptionRecord -Subscription $subscription
        }
        
        "customer.subscription.deleted" {
            $subscription = $stripeEvent.Data.Object -as [Stripe.Subscription]
            
            # Mark as canceled/expired
            Set-SubscriptionExpired -SubscriptionId $subscription.Id
        }
        
        "invoice.payment_succeeded" {
            $invoice = $stripeEvent.Data.Object -as [Stripe.Invoice]
            
            # Update last renewal date
            Update-LastRenewalDate -SubscriptionId $invoice.SubscriptionId
        }
        
        "invoice.payment_failed" {
            $invoice = $stripeEvent.Data.Object -as [Stripe.Invoice]
            
            # Mark as past_due, send notification
            Set-SubscriptionPastDue -SubscriptionId $invoice.SubscriptionId
        }
    }
    
    # Always return 200 to acknowledge
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = 200
        Body = "Event processed"
    })
}
catch {
    Write-Error "Webhook error: $_"
    
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = 400
        Body = "Webhook verification failed"
    })
}
```

### **3.2 Helper Functions for Table Storage**

```powershell
function Update-SubscriptionRecord {
    param(
        [Stripe.Subscription]$Subscription
    )
    
    $storageAccount = # ... connect to storage
    $table = Get-AzStorageTable -Name "Subscriptions" -Context $storageAccount.Context
    
    # Get userId from metadata (set during checkout)
    $userId = $Subscription.Metadata["user_id"]
    
    $entity = @{
        PartitionKey = $userId
        RowKey = $Subscription.Id
        CustomerId = $Subscription.CustomerId
        Status = $Subscription.Status
        CurrentTier = $Subscription.Metadata["tier"]
        PriceId = $Subscription.Items.Data[0].Price.Id
        CurrentPeriodStart = [DateTime]::UnixEpoch.AddSeconds($Subscription.CurrentPeriodStart)
        CurrentPeriodEnd = [DateTime]::UnixEpoch.AddSeconds($Subscription.CurrentPeriodEnd)
        CanceledAt = if ($Subscription.CanceledAt) { 
            [DateTime]::UnixEpoch.AddSeconds($Subscription.CanceledAt) 
        } else { $null }
        UpdatedAt = [DateTime]::UtcNow
    }
    
    Add-AzTableRow -Table $table -PartitionKey $entity.PartitionKey -RowKey $entity.RowKey -Property $entity -UpdateExisting
}

function Update-LastRenewalDate {
    param([string]$SubscriptionId)
    
    # Update LastStripeRenewal to now
    $storageAccount = # ... connect
    $table = Get-AzStorageTable -Name "Subscriptions" -Context $storageAccount.Context
    
    $query = New-Object "Microsoft.Azure.Cosmos.Table.TableQuery"
    $query.FilterString = "RowKey eq '$SubscriptionId'"
    $entities = $table.CloudTable.ExecuteQuery($query)
    
    foreach ($entity in $entities) {
        $entity.Properties["LastStripeRenewal"] = [DateTime]::UtcNow
        $entity.Properties["Status"] = "active"
        $table.CloudTable.Execute([Microsoft.Azure.Cosmos.Table.TableOperation]::Replace($entity))
    }
}

function Set-SubscriptionExpired {
    param([string]$SubscriptionId)
    
    # Mark subscription as expired and downgrade tier
    # ... similar pattern to above
    
    # Downgrade to free tier
    $entity.Properties["Status"] = "expired"
    $entity.Properties["CurrentTier"] = "free"
}

function Set-SubscriptionPastDue {
    param([string]$SubscriptionId)
    
    # Mark as past_due
    $entity.Properties["Status"] = "past_due"
}
```

---

## **Phase 4: Scheduled Monitoring Task**

### **4.1 Timer Function: Check Stale Renewals**

**Purpose:** Find subscriptions that should have renewed but haven't received webhook confirmation

**File: `MonitorRenewals/function.json`**
```json
{
  "bindings": [
    {
      "name": "Timer",
      "type": "timerTrigger",
      "direction": "in",
      "schedule": "0 0 */6 * * *"
    }
  ]
}
```
*Runs every 6 hours*

**File: `MonitorRenewals/run.ps1`**
```powershell
param($Timer)

Import-Module "$PSScriptRoot/../Modules/StripeHelpers/StripeHelpers.psm1" -Force
Initialize-Stripe

$storageAccount = # ... connect
$table = Get-AzStorageTable -Name "Subscriptions" -Context $storageAccount.Context

# Find subscriptions that:
# 1. Status = "active"
# 2. CurrentPeriodEnd < Now
# 3. LastStripeRenewal < CurrentPeriodEnd (no recent renewal confirmation)

$now = [DateTime]::UtcNow
$query = New-Object "Microsoft.Azure.Cosmos.Table.TableQuery"
$query.FilterString = "Status eq 'active'"
$subscriptions = $table.CloudTable.ExecuteQuery($query)

foreach ($sub in $subscriptions) {
    $periodEnd = $sub.Properties["CurrentPeriodEnd"].DateTime
    $lastRenewal = $sub.Properties["LastStripeRenewal"].DateTime
    
    # If period ended and no renewal confirmation
    if ($periodEnd -lt $now -and $lastRenewal -lt $periodEnd) {
        Write-Warning "Stale subscription found: $($sub.RowKey)"
        
        # Fetch live status from Stripe
        $service = [Stripe.SubscriptionService]::new()
        try {
            $liveSubscription = $service.Get($sub.RowKey)
            
            if ($liveSubscription.Status -eq "active") {
                # Still active on Stripe, update our records
                Write-Host "Syncing subscription: $($sub.RowKey)"
                Update-SubscriptionRecord -Subscription $liveSubscription
                Update-LastRenewalDate -SubscriptionId $sub.RowKey
            }
            else {
                # Not active anymore, mark as expired
                Write-Host "Expiring subscription: $($sub.RowKey)"
                Set-SubscriptionExpired -SubscriptionId $sub.RowKey
            }
        }
        catch {
            Write-Error "Failed to check subscription $($sub.RowKey): $_"
            
            # Optional: Send alert to admin
            Send-AdminAlert -Message "Failed to verify subscription $($sub.RowKey)"
        }
    }
}

Write-Host "Renewal monitoring completed"
```

---

## **Phase 5: Stripe Dashboard Configuration**

### **5.1 Create Products and Prices**

**In Stripe Dashboard:**
1. Go to Products → Create Product
2. Create:
   - **Basic** - $9.99/month → Copy `price_xxxxx`
   - **Premium** - $19.99/month → Copy `price_xxxxx`
   - **Enterprise** - $49.99/month → Copy `price_xxxxx`

3. Add to Application Settings

### **5.2 Configure Customer Portal**

**In Stripe Dashboard:**
1. Go to Settings → Customer Portal
2. Enable features:
   - ✅ Update payment method
   - ✅ Cancel subscription
   - ✅ Update subscription (allow tier changes)
   - ✅ View invoice history
3. Set branding (logo, colors)
4. Configure cancellation flow (immediate vs end of period)

### **5.3 Set Up Webhooks**

**In Stripe Dashboard:**
1. Go to Developers → Webhooks
2. Add endpoint: `https://your-function-app.azurewebsites.net/api/StripeWebhook`
3. Select events:
   - `checkout.session.completed`
   - `customer.subscription.created`
   - `customer.subscription.updated`
   - `customer.subscription.deleted`
   - `invoice.payment_succeeded`
   - `invoice.payment_failed`
4. Copy **Signing secret** → Add to Application Settings as `STRIPE_WEBHOOK_SECRET`

---

## **Phase 6: Testing Plan**

### **6.1 Test with Stripe Test Mode**

**Test Cards:**
```
Success: 4242 4242 4242 4242
Decline: 4000 0000 0000 0002
Requires Auth: 4000 0025 0000 3155
```

**Test Flow:**
1. Create checkout session → Verify redirect to Stripe
2. Complete payment with test card → Verify webhook received
3. Check Table Storage → Verify subscription created
4. Load subscription page → Verify details displayed correctly
5. Click "Manage Subscription" → Verify portal loads
6. Update payment method in portal → Verify webhook updates storage
7. Cancel subscription in portal → Verify webhook marks as canceled
8. Wait for period end → Verify scheduled task downgrades tier

### **6.2 Webhook Testing**

Use Stripe CLI for local testing:
```bash
stripe listen --forward-to localhost:7071/api/StripeWebhook
stripe trigger checkout.session.completed
stripe trigger invoice.payment_succeeded
```

---

## **Phase 7: Deployment Checklist**

### **Frontend Team:**
- [ ] Implement subscription page with tier selection
- [ ] Add "Manage Subscription" button
- [ ] Display current subscription details
- [ ] Create success/cancel pages
- [ ] Handle loading states and errors
- [ ] Test all user flows

### **Backend Team:**
- [ ] Install Stripe.net and Newtonsoft.Json in Modules
- [ ] Create all API endpoints
- [ ] Implement webhook handler
- [ ] Create helper functions for Table Storage
- [ ] Implement scheduled monitoring task
- [ ] Add Application Settings (keys, webhook secret, price IDs)
- [ ] Test webhook signature verification
- [ ] Deploy to Azure

### **DevOps/Admin:**
- [ ] Create Stripe account
- [ ] Set up products and prices
- [ ] Configure Customer Portal
- [ ] Set up webhook endpoint
- [ ] Add all secrets to Azure Application Settings
- [ ] Configure monitoring/alerts for failed webhooks
- [ ] Test end-to-end in staging environment
- [ ] Switch to live mode for production

---

## **Data Flow Summary**

```
1. User subscribes:
   Frontend → CreateCheckoutSession → Stripe Checkout → webhook → Table Storage

2. User manages subscription:
   Frontend → CreatePortalSession → Stripe Portal → webhook → Table Storage

3. Payment succeeds:
   Stripe → webhook → Update LastStripeRenewal in Table Storage

4. Subscription expires:
   Stripe → webhook → Mark expired + downgrade tier in Table Storage

5. Monitoring task:
   Every 6 hours → Check for stale renewals → Sync with Stripe → Update Table Storage
```

---

## **Security Considerations**

1. **Never log/store raw card data**
2. **Always verify webhook signatures** - prevents fake webhooks
3. **Use HTTPS only** for all endpoints
4. **Store API keys in Application Settings**, never in code
5. **Validate user IDs** in all endpoints to prevent unauthorized access
6. **Rate limit** API endpoints to prevent abuse
7. **Use Stripe test mode** until fully tested

---