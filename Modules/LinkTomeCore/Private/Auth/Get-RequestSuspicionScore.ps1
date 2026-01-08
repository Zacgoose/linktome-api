function Get-RequestSuspicionScore {
    <#
    .SYNOPSIS
        Analyzes request headers to detect non-browser clients
    .DESCRIPTION
        Returns a suspicion score and flags based on header analysis.
        Higher scores indicate more likely automation/scripting.
    .PARAMETER Request
        The request object from the function app
    .PARAMETER ExpectedOrigins
        Array of allowed origin URLs (production + localhost for dev)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Request,
        
        [Parameter()]
        [string[]]$ExpectedOrigins = @(
            $env:APP_ORIGIN,
            'http://localhost:4280',
            'http://localhost:3000',
            'http://192.168.20.140:3000'
        )
    )
    
    $Headers = $Request.Headers
    $Score = 0
    $Flags = @()
    
    # === Sec-Fetch Headers (highest signal - browser-controlled, can't be spoofed by JS) ===
    
    if (-not $Headers.'Sec-Fetch-Site') {
        $Score += 30
        $Flags += 'missing-sec-fetch-site'
    }
    elseif ($Headers.'Sec-Fetch-Site' -ne 'same-origin') {
        $Score += 25
        $Flags += "wrong-sec-fetch-site:$($Headers.'Sec-Fetch-Site')"
    }
    
    if (-not $Headers.'Sec-Fetch-Mode') {
        $Score += 20
        $Flags += 'missing-sec-fetch-mode'
    }
    elseif ($Headers.'Sec-Fetch-Mode' -notin @('cors', 'same-origin')) {
        $Score += 15
        $Flags += "wrong-sec-fetch-mode:$($Headers.'Sec-Fetch-Mode')"
    }
    
    if (-not $Headers.'Sec-Fetch-Dest') {
        $Score += 15
        $Flags += 'missing-sec-fetch-dest'
    }
    elseif ($Headers.'Sec-Fetch-Dest' -ne 'empty') {
        $Score += 15
        $Flags += "wrong-sec-fetch-dest:$($Headers.'Sec-Fetch-Dest')"
    }
    
    # === Origin Header ===
    
    $Origin = $Headers.Origin
    if (-not $Origin) {
        $Score += 25
        $Flags += 'missing-origin'
    }
    else {
        $ValidOrigin = $false
        foreach ($Expected in $ExpectedOrigins) {
            if ($Expected -and $Origin -eq $Expected) {
                $ValidOrigin = $true
                break
            }
        }
        if (-not $ValidOrigin) {
            $Score += 30
            $Flags += "wrong-origin:$Origin"
        }
    }
    
    # === Referer Header ===
    
    $Referer = $Headers.Referer
    if (-not $Referer) {
        # Some privacy extensions strip this, lower weight
        $Score += 10
        $Flags += 'missing-referer'
    }
    else {
        $ValidReferer = $false
        foreach ($Expected in $ExpectedOrigins) {
            if ($Expected -and $Referer -like "$Expected*") {
                $ValidReferer = $true
                break
            }
        }
        if (-not $ValidReferer) {
            $Score += 15
            $Flags += "wrong-referer:$Referer"
        }
    }
    
    # === User-Agent Analysis ===
    
    $UA = $Headers.'User-Agent'
    if (-not $UA) {
        $Score += 20
        $Flags += 'missing-user-agent'
    }
    else {
        # Known automation tool signatures
        $BotPatterns = @(
            'curl', 'wget', 'python-requests', 'python-urllib',
            'node-fetch', 'axios/', 'got/', 'httpie', 'okhttp',
            'PostmanRuntime', 'insomnia', 'HTTPie', 'Go-http-client',
            'Java/', 'Apache-HttpClient', 'libwww-perl'
        )
        foreach ($Pattern in $BotPatterns) {
            if ($UA -like "*$Pattern*") {
                $Score += 25
                $Flags += "bot-ua:$Pattern"
                break
            }
        }
        
        # Headless browser signatures
        $HeadlessPatterns = @('HeadlessChrome', 'PhantomJS', 'Puppeteer', 'Playwright')
        foreach ($Pattern in $HeadlessPatterns) {
            if ($UA -like "*$Pattern*") {
                $Score += 15
                $Flags += "headless-ua:$Pattern"
                break
            }
        }
    }
    
    # === Other Browser Headers ===
    
    if (-not $Headers.'Accept-Language') {
        $Score += 10
        $Flags += 'missing-accept-language'
    }
    
    if (-not $Headers.'Accept-Encoding') {
        $Score += 5
        $Flags += 'missing-accept-encoding'
    }
    
    # Content-Type check for POST requests
    $ContentType = $Headers.'Content-Type'
    if ($ContentType -and $ContentType -notlike '*application/json*') {
        $Score += 10
        $Flags += "unexpected-content-type:$ContentType"
    }
    
    # === Return Results ===
    
    return @{
        Score        = $Score
        Flags        = $Flags
        IsSuspicious = $Score -ge 200
        IsLikelyBot  = $Score -ge 200
    }
}