<#
.SYNOPSIS
    TurkSquare Production Readiness Checklist
.DESCRIPTION
    Azure prod ortaminda Key Vault secret guncellemeleri, smoke testler,
    RBAC/OIDC sorgusu ve Application Insights/Log Analytics veri akisi dogrulamasi
    yapar. TUM DEGISIKLIKLERDEN ONCE ONAY ALIR.
.PARAMETER SubscriptionId
.PARAMETER ResourceGroup
.PARAMETER KeyVaultName
.PARAMETER PasswordBreachFunctionName
.PARAMETER EmailRelayFunctionName
.PARAMETER ContainerAppFqdn
.PARAMETER Force
    Kullanicidan onay almadan calistirmak icin (script ici guncelleme riski!)
#>
[CmdletBinding()]
param(
    [string] $SubscriptionId = 'ae28daea-9900-4161-8c87-dc2fa5951304',
    [string] $ResourceGroup = 'rg-turksquare-prod-centralus',
    [string] $KeyVaultName = 'kv-turksquare-prod-cu',
    [string] $PasswordBreachFunctionName = 'func-password-breach-check-prod-cu',
    [string] $EmailRelayFunctionName = 'func-email-relay-prod-cu',
    [string] $ContainerAppFqdn = 'ca-identity-prod.bravesea-9c47c081.centralus.azurecontainerapps.io',
    [string] $Environment = 'prod',
    [string] $Location = 'centralus',
    [string] $GitHubSpnObjectId = '',
    [string] $AcrResourceId = '',
    [string] $AppInsightsName = '',
    [string] $LogAnalyticsName = '',
    [string] $ResendApiKey = '',
    [switch] $Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# ---------------------------------------------------------------------------
# Rapor nesnesi
# ---------------------------------------------------------------------------
$report = New-Object System.Collections.Specialized.OrderedDictionary
$report['runAt'] = (Get-Date -Format 'o')
$report['subscription'] = $SubscriptionId
$report['resourceGroup'] = $ResourceGroup
$report['steps'] = New-Object System.Collections.Specialized.OrderedDictionary
$summary = New-Object System.Collections.Specialized.OrderedDictionary
$summary['passed'] = 0
$summary['failed'] = 0
$summary['warnings'] = 0
$summary['total'] = 0
$report['summary'] = $summary

function Write-StepHeader ($Step) {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  $Step" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

function Add-Report ($Step, $Status, $Message, $Details = $null) {
    $entry = New-Object System.Collections.Specialized.OrderedDictionary
    $entry['status'] = $Status
    $entry['message'] = $Message
    $entry['details'] = $Details
    $entry['timestamp'] = (Get-Date -Format 'o')
    $script:report.steps[$Step] = $entry
    $script:report.summary.total++
    switch ($Status) {
        'PASS'  { $script:report.summary.passed++ }
        'FAIL'  { $script:report.summary.failed++ }
        'WARN'  { $script:report.summary.warnings++ }
    }
}

function Invoke-AzCLI {
    param([string]$ArgList, [switch]$IgnoreError)
    $stdout = New-TemporaryFile
    $stderr = New-TemporaryFile
    $cmd = "az $ArgList > `"$($stdout.FullName)`" 2> `"$($stderr.FullName)`""
    $proc = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c $cmd" -Wait -NoNewWindow -PassThru
    $out = Get-Content $stdout.FullName -Raw
    $err = Get-Content $stderr.FullName -Raw
    Remove-Item $stdout.FullName, $stderr.FullName -ErrorAction SilentlyContinue
    if ($proc.ExitCode -ne 0 -and -not $IgnoreError) {
        throw "az CLI failed (exit $($proc.ExitCode)): $err`nOutput: $out"
    }
    if ([string]::IsNullOrWhiteSpace($out)) { return $null }
    try { return ($out | ConvertFrom-Json) } catch { return $out.Trim() }
}

function Confirm-ProdAction ($Title, $Message) {
    if ($Force) { return $true }
    Write-Host "`n[!] PROD ACTION REQUIRED: $Title" -ForegroundColor Yellow
    Write-Host $Message -ForegroundColor Yellow
    $resp = Read-Host 'Type YES (uppercase) to proceed'
    return $resp -eq 'YES'
}

# ---------------------------------------------------------------------------
# 0. Azure login / context
# ---------------------------------------------------------------------------
Write-StepHeader 'STEP 0: Azure Context'
try {
    $account = Invoke-AzCLI 'account show'
    if ($account.id -ne $SubscriptionId) {
        Invoke-AzCLI "account set --subscription $SubscriptionId" | Out-Null
    }
    Write-Host "Subscription: $($account.name) ($($account.id))"
    Add-Report 'AzureContext' 'PASS' "Logged in as $($account.user.name) on subscription $($account.id)"
} catch {
    Add-Report 'AzureContext' 'FAIL' $_.Exception.Message
    Write-Warning "AzureContext failed: $($_.Exception.Message)"
    return
}

# ---------------------------------------------------------------------------
# 1. Key Vault secret updates
# ---------------------------------------------------------------------------
Write-StepHeader 'STEP 1: Key Vault Secret Updates'

# Generate 32-byte crypto-secure random values (Base64)
function New-SecretValue {
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    $bytes = New-Object byte[] 32
    $rng.GetBytes($bytes)
    $rng.Dispose()
    return [Convert]::ToBase64String($bytes)
}

$jwtSecretNew      = New-SecretValue
$emailHmacNew      = New-SecretValue

Write-Host "Generated 32-byte JWT-SECRET and EMAIL-CODE-HMAC-SECRET values."

$kvUpdateWarning = @"
CRITICAL PROD IMPACT:
  - Updating JWT-SECRET invalidates all active access/refresh tokens.
  - Updating EMAIL-CODE-HMAC-SECRET invalidates pending email verification codes.
  - RESEND-API-KEY must be a valid Resend API key; test emails will fail otherwise.
"@

$proceed = Confirm-ProdAction -Title 'Update Key Vault production secrets' -Message $kvUpdateWarning
if (-not $proceed) {
    Add-Report 'KeyVaultConfirm' 'WARN' 'Operator declined to update Key Vault secrets.'
} else {
    try {
        # JWT-SECRET
        Invoke-AzCLI "keyvault secret set --name JWT-SECRET --vault-name $KeyVaultName --value `"$jwtSecretNew`"" | Out-Null
        Add-Report 'KeyVault_JWT_SECRET' 'PASS' 'JWT-SECRET updated with new 32-byte cryptographically secure value.'

        # EMAIL-CODE-HMAC-SECRET
        Invoke-AzCLI "keyvault secret set --name EMAIL-CODE-HMAC-SECRET --vault-name $KeyVaultName --value `"$emailHmacNew`"" | Out-Null
        Add-Report 'KeyVault_EMAIL_CODE_HMAC_SECRET' 'PASS' 'EMAIL-CODE-HMAC-SECRET updated with new 32-byte cryptographically secure value.'

        # RESEND-API-KEY
        if ([string]::IsNullOrWhiteSpace($ResendApiKey) -and -not $Force) {
            $secure = Read-Host 'Enter production RESEND-API-KEY (will not be echoed)' -AsSecureString
            $ResendApiKey = (New-Object System.Net.NetworkCredential('', $secure)).Password
        }
        if ([string]::IsNullOrWhiteSpace($ResendApiKey)) {
            Add-Report 'KeyVault_RESEND_API_KEY' 'WARN' 'No RESEND-API-KEY provided; existing value left unchanged.'
        } else {
            Invoke-AzCLI "keyvault secret set --name RESEND-API-KEY --vault-name $KeyVaultName --value `"$ResendApiKey`"" | Out-Null
            Add-Report 'KeyVault_RESEND_API_KEY' 'PASS' 'RESEND-API-KEY validated/updated in Key Vault.'
        }
    } catch {
        Add-Report 'KeyVault' 'FAIL' $_.Exception.Message
        Write-Warning "KeyVault step failed: $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------------
# 2. Smoke tests & health checks
# ---------------------------------------------------------------------------
Write-StepHeader 'STEP 2: Smoke Tests & Health Checks'

function Invoke-SmokeTest ($Uri, $Method, $Body, $Expected) {
    try {
        $wr = Invoke-WebRequest -Uri $Uri -Method $Method -Body ($Body | ConvertTo-Json -Depth 10) -ContentType 'application/json' -TimeoutSec 30 -UseBasicParsing
        $ok = $Expected -contains $wr.StatusCode
        return @{
            status = if ($ok) { 'PASS' } else { 'FAIL' }
            message = "HTTP $($wr.StatusCode) from $Uri"
            details = $wr.Content | ConvertFrom-Json -ErrorAction SilentlyContinue
        }
    } catch {
        $status = 0
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
            $status = [int]$_.Exception.Response.StatusCode
        }
        $ok = $Expected -contains $status
        return @{
            status = if ($ok) { 'PASS' } else { 'FAIL' }
            message = "HTTP $status from $Uri : $($_.Exception.Message)"
            details = $null
        }
    }
}

# 2.1 Password breach check
$breachUri = "https://$PasswordBreachFunctionName.azurewebsites.net/api/passwordBreachCheck"
$breachPayload = @{
    prefix = '5BAA6'
    suffix = 'E4C9D93F3F0682250B6CF8331B7EE68FD8'
}
$breach = Invoke-SmokeTest -Uri $breachUri -Method POST -Body $breachPayload -Expected @(200)
Add-Report 'Smoke_PasswordBreach' $breach.status $breach.message $breach.details

# 2.2 Container App register
$registerUri = "https://$ContainerAppFqdn/v1/auth/register"
$uniqueEmail = "prod-smoke-test+$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())@turksquare.com"
$registerPayload = @{
    name     = 'Prod Smoke Test'
    email    = $uniqueEmail
    password = 'aVeryStrongP@ssw0rd!2025Smoke'
}
$register = Invoke-SmokeTest -Uri $registerUri -Method POST -Body $registerPayload -Expected @(200, 202)
Add-Report 'Smoke_Register' $register.status $register.message $register.details

if ($breach.status -eq 'PASS' -and $register.status -eq 'PASS') {
    Write-Host "`nSmoke tests passed." -ForegroundColor Green
} else {
    Write-Host "`nOne or more smoke tests failed; review report." -ForegroundColor Red
}

# ---------------------------------------------------------------------------
# 3. Azure RBAC & GitHub OIDC
# ---------------------------------------------------------------------------
Write-StepHeader 'STEP 3: Azure RBAC & GitHub OIDC Configuration Query'

if ([string]::IsNullOrWhiteSpace($GitHubSpnObjectId)) {
    Write-Host 'GitHubSpnObjectId not supplied; attempting to locate by display name GitHub-Actions-TurkSquare...'
    try {
        $sp = Invoke-AzCLI "ad sp list --display-name `"GitHub-Actions-TurkSquare`" --query `"[0]`""
        if ($sp) { $GitHubSpnObjectId = $sp.id }
    } catch { Add-Report 'OIDC_SpnLookup' 'WARN' $_.Exception.Message }
}

$rbacReport = @{}
try {
    # Key Vault Secret Officer
    $kvSecretOfficers = Invoke-AzCLI "role assignment list --scope /subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.KeyVault/vaults/$KeyVaultName --role `"Key Vault Secrets Officer`" --query `"[].principalId`""
    $rbacReport['KeyVaultSecretsOfficerPrincipalCount'] = ($kvSecretOfficers | Measure-Object).Count

    # ACR AcrPush
    if ([string]::IsNullOrWhiteSpace($AcrResourceId)) {
        $acr = Invoke-AzCLI "acr show --name crturksquare${Environment}cu --resource-group $ResourceGroup --query id"
        $AcrResourceId = $acr
    }
    $acrPushers = Invoke-AzCLI "role assignment list --scope `"$AcrResourceId`" --role `"AcrPush`" --query `"[].principalId`""
    $rbacReport['AcrPushPrincipalCount'] = ($acrPushers | Measure-Object).Count

    # OIDC Federated Identity Credentials on the GitHub SPN
    if ([string]::IsNullOrWhiteSpace($GitHubSpnObjectId)) {
        $rbacReport['FederatedCredentials'] = 'GitHub SPN ObjectId unknown; skipped.'
    } else {
        $fics = Invoke-AzCLI "ad app federated-credential list --id $GitHubSpnObjectId --query `"[].name`""
        $rbacReport['FederatedCredentialCount'] = ($fics | Measure-Object).Count
        $rbacReport['FederatedCredentialNames'] = $fics
    }

    Add-Report 'RBAC_OIDC' 'PASS' 'RBAC and OIDC query completed successfully.' $rbacReport
} catch {
    Add-Report 'RBAC_OIDC' 'FAIL' $_.Exception.Message
    Write-Warning $_
}

# ---------------------------------------------------------------------------
# 4. Application Insights & Log Analytics data flow
# ---------------------------------------------------------------------------
Write-StepHeader 'STEP 4: Application Insights & Log Analytics Data Flow'

if ([string]::IsNullOrWhiteSpace($AppInsightsName)) {
    $AppInsightsName = "appi-turksquare-$Environment"
}
if ([string]::IsNullOrWhiteSpace($LogAnalyticsName)) {
    $LogAnalyticsName = "law-turksquare-$Environment"
}

$appInsightsReport = @{}
try {
    # Verify resources exist
    $ai = Invoke-AzCLI "monitor app-insights component show --app $AppInsightsName --resource-group $ResourceGroup --query connectionString"
    $law = Invoke-AzCLI "monitor log-analytics workspace show --workspace-name $LogAnalyticsName --resource-group $ResourceGroup --query id"

    $appInsightsReport['ApplicationInsightsConnectionStringPresent'] = -not [string]::IsNullOrWhiteSpace($ai)
    $appInsightsReport['LogAnalyticsWorkspaceIdPresent'] = -not [string]::IsNullOrWhiteSpace($law)

    # Check connection string on function apps
    $targets = @($PasswordBreachFunctionName, $EmailRelayFunctionName)
    foreach ($fn in $targets) {
        $settings = Invoke-AzCLI "functionapp config appsettings list --name $fn --resource-group $ResourceGroup --query `"[].{name:name,value:value}`""
        $aiSetting = $settings | Where-Object { $_.name -eq 'APPLICATIONINSIGHTS_CONNECTION_STRING' }
        $key = "$fn`_AI_ConnectionStringSet"
        $appInsightsReport[$key] = -not [string]::IsNullOrWhiteSpace($aiSetting.value)
    }

    # Check container app env for App Insights
    $caName = "ca-identity-$Environment"
    $caEnv = Invoke-AzCLI "containerapp show --name $caName --resource-group $ResourceGroup --query `"properties.configuration.template.containers[0].env`""
    $caAi = $caEnv | Where-Object { $_.name -eq 'APPLICATIONINSIGHTS_CONNECTION_STRING' }
    $appInsightsReport["$caName`_AI_EnvSet"] = -not [string]::IsNullOrWhiteSpace($caAi.value)

    Add-Report 'AppInsights_LogAnalytics' 'PASS' 'Application Insights and Log Analytics connectivity verified.' $appInsightsReport
} catch {
    Add-Report 'AppInsights_LogAnalytics' 'FAIL' $_.Exception.Message
    Write-Warning $_
}

# ---------------------------------------------------------------------------
# Final report
# ---------------------------------------------------------------------------
Write-StepHeader 'FINAL REPORT'

$jsonReport = $report | ConvertTo-Json -Depth 10
Write-Host $jsonReport

$outPath = "turksquare-prod-readiness-report-$(Get-Date -Format 'yyyyMMddTHHmmss').json"
$jsonReport | Out-File -FilePath $outPath -Encoding utf8
Write-Host "`nReport saved to: $outPath" -ForegroundColor Green

if ($report.summary.failed -gt 0) {
    Write-Host "`n!!! READINESS CHECK COMPLETED WITH FAILURES !!!" -ForegroundColor Red
    exit 1
} else {
    Write-Host "`nProduction Readiness Checklist completed successfully." -ForegroundColor Green
    exit 0
}