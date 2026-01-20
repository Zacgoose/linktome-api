# Stripe Integration Setup Guide

This guide walks you through setting up Stripe integration for LinkTome API billing and subscriptions.

## Overview

LinkTome uses Stripe for:
- **Payment Processing**: Secure credit card payments (PCI compliant)
- **Subscription Management**: Automatic recurring billing
- **Customer Portal**: Self-service subscription management
- **Webhooks**: Real-time subscription status updates

## Prerequisites

- Active Stripe account ([sign up at stripe.com](https://stripe.com))
- Azure Function App deployed and running
- Frontend application with subscription pages

## Architecture

```
User → Frontend → API → Stripe Checkout
                   ↓
            Stripe Webhooks → API → Azure Table Storage
                              ↓
                   Billing Orchestrator Timer (syncs every 15 min)
```

## Step 1: Create Stripe Products and Prices

### 1.1 Log into Stripe Dashboard

Go to [https://dashboard.stripe.com](https://dashboard.stripe.com)

### 1.2 Create Products

Navigate to **Products** → **Add Product**

Create three products with the following configurations:

#### Pro Tier
- **Name**: Pro Plan
- **Description**: Advanced features for power users
- **Pricing**:
  - Monthly: `$9.99/month` (create price, copy `price_xxxxx` ID)
  - Annual: `$99.99/year` (create price, copy `price_xxxxx` ID)

#### Premium Tier
- **Name**: Premium Plan
- **Description**: Enhanced features for professionals
- **Pricing**:
  - Monthly: `$19.99/month` (create price, copy `price_xxxxx` ID)
  - Annual: `$199.99/year` (create price, copy `price_xxxxx` ID)

#### Enterprise Tier
- **Name**: Enterprise Plan
- **Description**: Full feature access for businesses
- **Pricing**:
  - Monthly: `$49.99/month` (create price, copy `price_xxxxx` ID)
  - Annual: `$499.99/year` (create price, copy `price_xxxxx` ID)

**Important**: Save all 6 price IDs (3 tiers × 2 billing cycles)

## Step 2: Configure Customer Portal

### 2.1 Navigate to Customer Portal Settings

Go to **Settings** → **Billing** → **Customer Portal**

### 2.2 Enable Features

✅ **Update payment method**: Allow customers to update cards  
✅ **Cancel subscription**: Allow customers to cancel  
✅ **Update subscription**: Allow tier changes  
✅ **View invoice history**: Show past invoices

### 2.3 Configure Cancellation Flow

- **Cancellation behavior**: Cancel at end of billing period (recommended)
- This ensures users keep access until their paid period ends

### 2.4 Set Branding

- Upload your logo
- Set brand colors to match your application
- Add support email and links

## Step 3: Set Up Webhooks

### 3.1 Create Webhook Endpoint

Go to **Developers** → **Webhooks** → **Add endpoint**

**Endpoint URL**:
```
https://your-function-app.azurewebsites.net/api/public/stripeWebhook
```

Replace `your-function-app` with your Azure Function App name.

### 3.2 Select Events to Listen For

Select these events:
- ✅ `checkout.session.completed`
- ✅ `customer.subscription.created`
- ✅ `customer.subscription.updated`
- ✅ `customer.subscription.deleted`
- ✅ `invoice.payment_succeeded`
- ✅ `invoice.payment_failed`

### 3.3 Copy Webhook Signing Secret

After creating the webhook, copy the **Signing secret** (starts with `whsec_`)

This is critical for verifying that webhook requests actually come from Stripe.

## Step 4: Configure Environment Variables

### 4.1 For Local Development

Update `local.settings.json`:

```json
{
  "Values": {
    "STRIPE_API_KEY": "sk_test_your_test_key_here",
    "STRIPE_WEBHOOK_SECRET": "whsec_your_webhook_secret_here",
    "STRIPE_PRICE_ID_PRO": "price_1xxxxx",
    "STRIPE_PRICE_ID_PRO_ANNUAL": "price_1xxxxx",
    "STRIPE_PRICE_ID_PREMIUM": "price_1xxxxx",
    "STRIPE_PRICE_ID_PREMIUM_ANNUAL": "price_1xxxxx",
    "STRIPE_PRICE_ID_ENTERPRISE": "price_1xxxxx",
    "STRIPE_PRICE_ID_ENTERPRISE_ANNUAL": "price_1xxxxx",
    "FRONTEND_URL": "http://localhost:3000"
  }
}
```

**Important**: Use test keys (`sk_test_`) for development

### 4.2 For Production (Azure Portal)

1. Go to your Function App in Azure Portal
2. Navigate to **Configuration** → **Application Settings**
3. Add the following settings:

| Name | Value | Notes |
|------|-------|-------|
| `STRIPE_API_KEY` | `sk_live_xxxxx` | **Use live key in production** |
| `STRIPE_WEBHOOK_SECRET` | `whsec_xxxxx` | From webhook configuration |
| `STRIPE_PRICE_ID_PRO` | `price_xxxxx` | Pro monthly price ID |
| `STRIPE_PRICE_ID_PRO_ANNUAL` | `price_xxxxx` | Pro annual price ID |
| `STRIPE_PRICE_ID_PREMIUM` | `price_xxxxx` | Premium monthly price ID |
| `STRIPE_PRICE_ID_PREMIUM_ANNUAL` | `price_xxxxx` | Premium annual price ID |
| `STRIPE_PRICE_ID_ENTERPRISE` | `price_xxxxx` | Enterprise monthly price ID |
| `STRIPE_PRICE_ID_ENTERPRISE_ANNUAL` | `price_xxxxx` | Enterprise annual price ID |
| `FRONTEND_URL` | `https://yourdomain.com` | Your production frontend URL |

4. Click **Save** and restart the Function App

## Step 5: Test Integration

### 5.1 Test with Stripe CLI (Local Development)

Install Stripe CLI: [https://stripe.com/docs/stripe-cli](https://stripe.com/docs/stripe-cli)

Forward webhooks to local dev:
```bash
stripe listen --forward-to localhost:7071/api/public/stripeWebhook
```

Trigger test events:
```bash
stripe trigger checkout.session.completed
stripe trigger invoice.payment_succeeded
stripe trigger customer.subscription.updated
```

### 5.2 Test Checkout Flow

1. **Create checkout session**:
```bash
curl -X POST http://localhost:7071/api/admin/createCheckoutSession \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "tier": "pro",
    "billingCycle": "monthly"
  }'
```

2. **Use returned checkout URL** - Complete payment with test card:
   - Success: `4242 4242 4242 4242`
   - Decline: `4000 0000 0000 0002`

3. **Verify webhook received** - Check Function App logs

4. **Check user record** - Verify subscription updated in Users table

### 5.3 Test Customer Portal

```bash
curl -X POST http://localhost:7071/api/admin/createPortalSession \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json"
```

Visit the returned `portalUrl` to test:
- Update payment method
- Change subscription tier
- Cancel subscription
- View invoices

### 5.4 Test Cancellation

```bash
curl -X POST http://localhost:7071/api/admin/cancelSubscription \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json"
```

Verify:
- Subscription marked as cancelled
- User keeps access until period end
- Webhook received and processed

## Step 6: Frontend Integration

### 6.1 Subscribe Button

```javascript
async function handleSubscribe(tier, billingCycle) {
  try {
    const response = await fetch('/api/admin/createCheckoutSession', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${userToken}`
      },
      body: JSON.stringify({ tier, billingCycle })
    });
    
    const { checkoutUrl } = await response.json();
    window.location.href = checkoutUrl; // Redirect to Stripe
  } catch (error) {
    console.error('Failed to create checkout:', error);
  }
}
```

### 6.2 Manage Subscription Button

```javascript
async function handleManageSubscription() {
  try {
    const response = await fetch('/api/admin/createPortalSession', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${userToken}`
      }
    });
    
    const { portalUrl } = await response.json();
    window.location.href = portalUrl; // Redirect to Stripe Portal
  } catch (error) {
    console.error('Failed to open portal:', error);
  }
}
```

### 6.3 Success/Cancel Pages

Create these routes in your frontend:
- `/subscription/success?session_id={CHECKOUT_SESSION_ID}` - Show success message
- `/subscription/cancel` - Show cancellation message

## Step 7: Production Deployment Checklist

### Before Going Live:

- [ ] All test webhooks working correctly
- [ ] All test payments processed successfully
- [ ] Customer Portal configured and tested
- [ ] All price IDs saved and configured
- [ ] **Switch from test keys to live keys** in Azure Portal
- [ ] Update webhook endpoint URL to production
- [ ] Test one real payment with a live card
- [ ] Monitor webhook logs for 24 hours
- [ ] Set up Stripe alerts for failed payments
- [ ] Document support process for billing issues

## Monitoring and Maintenance

### Daily Checks:
- Check Azure Function logs for webhook errors
- Monitor Stripe dashboard for failed payments

### Weekly:
- Review subscription analytics
- Check for suspended subscriptions (payment failures)

### Monthly:
- Reconcile Stripe subscriptions with database
- Review and respond to customer billing issues

## Billing Orchestrator

The API includes an automatic billing orchestrator that runs every 15 minutes:

**What it does**:
1. Finds subscriptions that should have renewed but haven't received webhook confirmation
2. Syncs with Stripe to get the latest subscription status
3. Marks expired subscriptions and downgrades users to free tier
4. Handles payment failures and suspended accounts

**Configuration**: No configuration needed - runs automatically when Stripe is configured

## Troubleshooting

### Webhooks Not Working

1. **Check webhook URL** - Ensure it's publicly accessible
2. **Verify signing secret** - Must match Stripe dashboard
3. **Check logs** - Look for signature verification errors
4. **Test with CLI** - Use `stripe listen` to debug locally

### Subscriptions Not Syncing

1. **Check API logs** - Look for errors in billing orchestrator
2. **Verify Stripe API key** - Must be valid and not expired
3. **Check user records** - Ensure `StripeCustomerId` and `StripeSubscriptionId` fields exist
4. **Manual sync** - Use billing orchestrator timer to force sync

### Payment Failures

1. **Check Stripe dashboard** - View failed payment details
2. **Verify customer has valid payment method** - May need to update card
3. **Check subscription status** - Should be marked as `suspended`
4. **Customer action required** - Direct user to Customer Portal

## Security Best Practices

✅ **Never log customer payment details**  
✅ **Always verify webhook signatures**  
✅ **Use HTTPS only** for all endpoints  
✅ **Store API keys in environment variables**, never in code  
✅ **Use test mode** until fully tested  
✅ **Rotate API keys** periodically  
✅ **Monitor for unusual activity** in Stripe dashboard

## Support Resources

- **Stripe Documentation**: [https://stripe.com/docs](https://stripe.com/docs)
- **Stripe API Reference**: [https://stripe.com/docs/api](https://stripe.com/docs/api)
- **Stripe Support**: [https://support.stripe.com](https://support.stripe.com)
- **Test Cards**: [https://stripe.com/docs/testing](https://stripe.com/docs/testing)

## Notes for Frontend Team

### API Endpoints Available:

1. **POST /api/admin/createCheckoutSession**
   - Input: `{ tier: "pro|premium|enterprise", billingCycle: "monthly|annual" }`
   - Output: `{ sessionId, checkoutUrl }`
   - Action: Redirect user to `checkoutUrl`

2. **POST /api/admin/createPortalSession**
   - Input: `{}`
   - Output: `{ portalUrl }`
   - Action: Redirect user to `portalUrl`

3. **GET /api/admin/getSubscription**
   - Output: Current subscription details including tier, status, billing dates

4. **POST /api/admin/cancelSubscription**
   - Output: Cancellation confirmation with access until date

### Frontend Tasks:
- [ ] Create subscription selection page
- [ ] Add "Upgrade" buttons that call `createCheckoutSession`
- [ ] Add "Manage Subscription" button that calls `createPortalSession`
- [ ] Create success page at `/subscription/success`
- [ ] Create cancel page at `/subscription/cancel`
- [ ] Display current subscription tier and status
- [ ] Show renewal date and payment info
- [ ] Handle loading states and errors

---

**Last Updated**: January 2026  
**API Version**: 1.0.0
