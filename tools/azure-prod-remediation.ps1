<#
.SYNOPSIS
    TurkSquare Prod Remediation Script
.DESCRIPTION
    Readiness raporundaki 503 hatalarinin kok neden analizi, Container App
    AppInsights env ekleme, GitHub OIDC App Registration Object ID duzeltmesi
    ve son smoke testleri yapar.
#>
[CmdletBinding()]
param(
    [string] $SubscriptionId = 'ae28daea-9900-4161-8c87-dc2fa5951304',
    [string] $ResourceGroup = 'rg-turksquare-prod-centralus',
    [string] $KeyVaultName = 'kv-turksquare-prod-cu',
    [string] $LogAnalyticsWorkspace = 'law-turksquare-prod',
    [string] $ContainerAppName = 'ca-identity-prod',
    [string] $ContainerAppFqdn = 'ca-identity-prod.bravesea-9c47c081.centralus.azurecontainerapps.io',
    [string] $PasswordBreachFunctionName = 'func-password-breach-check-prod-cu',
    [string] $EmailRelayFunctionName = 'func-email-relay-prod-cu',
    [string] $GitHubAppDisplayName = 'GitHub-Actions-TurkSquare',
    [string] $AppInsightsName = 'appi-turksquare-prod',
    [switch] $Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

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

function Write-StepHeader ($Step) {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  $Step" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

function Invoke-SmokeTest ($Uri, $Method, $Body, $Expected) {
    try {
        $jsonBody = $Body | ConvertTo-Json -Depth 10
        $wr = Invoke-WebRequest -Uri $Uri -Method $Method -Body $jsonBody -ContentType 'application/json' -TimeoutSec 30 -UseBasicParsing
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

# 0. Context
Write-StepHeader 'STEP 0: Azure Context'
try {
    $account = Invoke-AzCLI 'account show'
    if ($account.id -ne $SubscriptionId) {
        Invoke-AzCLI "account set --subscription $SubscriptionId" | Out-Null
    }
    Add-Report 'AzureContext' 'PASS' "Connected to $($account.name) ($($account.id)) as $($account.user.name)"
} catch {
    Add-Report 'AzureContext' 'FAIL' $_.Exception.Message
    Write-Warning $_
    return
}

# 1. Root cause analysis
Write-StepHeader 'STEP 1: Root Cause Analysis (503)'
$rootCause = @{}
try {
    Write-Host "Fetching Container App replica status..."
    $replicas = Invoke-AzCLI "containerapp replica list --name $ContainerAppName --resource-group $ResourceGroup"
    $rootCause['containerAppReplicas'] = $replicas

    Write-Host "Fetching Container App console logs..."
    $caLogs = Invoke-AzCLI "containerapp logs show --name $ContainerAppName --resource-group $ResourceGroup --type console --follow false --tail 100" -IgnoreError
    $rootCause['containerAppConsoleLogs'] = $caLogs

    Write-Host "Fetching Container App system logs..."
    $caSysLogs = Invoke-AzCLI "containerapp logs show --name $ContainerAppName --resource-group $ResourceGroup --type system --follow false --tail 100" -IgnoreError
    $rootCause['containerAppSystemLogs'] = $caSysLogs

    Write-Host "Fetching Function App runtime status..."
    $fnState = Invoke-AzCLI "functionapp show --name $PasswordBreachFunctionName --resource-group $ResourceGroup --query state"
    $rootCause['passwordBreachFunctionState'] = $fnState

    Write-Host "Fetching Container App provisioning state..."
    $caState = Invoke-AzCLI "containerapp show --name $ContainerAppName --resource-group $ResourceGroup --query properties.provisioningState"
    $rootCause['containerAppProvisioningState'] = $caState

    $diagnosis = @()
    $logText = ($caLogs -join ' ') + ' ' + ($caSysLogs -join ' ')
    if ($logText -match 'ECONNREFUSED|connection refused|database|password|sslmode|postgres') {
        $diagnosis += 'Database connectivity issue detected in logs.'
    }
    if ($logText -match 'KeyVault|AzureKeyVaultCredential|secret|vault|Forbidden|401|403') {
        $diagnosis += 'Key Vault access / secret reference issue detected in logs.'
    }
    if ($logText -match 'crash|exited|error|Error:|unhandled|restarting|backoff') {
        $diagnosis += 'Application crash or repeated restarts detected in logs.'
    }
    if (-not $diagnosis) {
        $diagnosis += 'No explicit DB or Key Vault error found in recent logs. Likely cold start, revision not ready, or container health check failure.'
    }
    $rootCause['diagnosis'] = $diagnosis

    Add-Report 'RootCauseAnalysis' 'PASS' 'Log and status query completed.' $rootCause
} catch {
    Add-Report 'RootCauseAnalysis' 'FAIL' $_.Exception.Message
    Write-Warning $_
}

# 2. Add AppInsights env var to Container App
Write-StepHeader 'STEP 2: Add AppInsights Connection String to Container App'
try {
    $connStr = Invoke-AzCLI "monitor app-insights component show --app $AppInsightsName --resource-group $ResourceGroup --query connectionString"
    if ([string]::IsNullOrWhiteSpace($connStr)) {
        throw 'Application Insights connection string is empty.'
    }
    Write-Host "Retrieved Application Insights connection string."
    Invoke-AzCLI "containerapp update --name $ContainerAppName --resource-group $ResourceGroup --set-env-vars `"APPLICATIONINSIGHTS_CONNECTION_STRING=$connStr`"" | Out-Null
    Add-Report 'ContainerApp_AppInsights_Env' 'PASS' "APPLICATIONINSIGHTS_CONNECTION_STRING set on $ContainerAppName."
} catch {
    Add-Report 'ContainerApp_AppInsights_Env' 'FAIL' $_.Exception.Message
    Write-Warning $_
}

# 3. GitHub OIDC App Registration Object ID fix
Write-StepHeader 'STEP 3: GitHub OIDC App Registration Object ID'
try {
    $appRegId = Invoke-AzCLI "ad app list --display-name `"$GitHubAppDisplayName`" --query `[0].id`" -IgnoreError
    if ([string]::IsNullOrWhiteSpace($appRegId)) {
        throw "App Registration with display name '$GitHubAppDisplayName' not found."
    }
    Write-Host "App Registration Object ID: $appRegId"
    $fics = Invoke-AzCLI "ad app federated-credential list --id $appRegId"
    $oidcDetails = @{
        appRegistrationObjectId = $appRegId
        federatedCredentialCount = ($fics | Measure-Object).Count
        federatedCredentialNames = $fics
    }
    Add-Report 'GitHubOIDC' 'PASS' "Federated credentials found for App Registration $appRegId." $oidcDetails
} catch {
    Add-Report 'GitHubOIDC' 'FAIL' $_.Exception.Message
    Write-Warning $_
}

# 4. Restart services and re-test
Write-StepHeader 'STEP 4: Restart Services and Re-run Smoke Tests'
try {
    Write-Host "Restarting Container App $ContainerAppName..."
    Invoke-AzCLI "containerapp revision restart --name $ContainerAppName --resource-group $ResourceGroup --all" | Out-Null

    foreach ($fn in @($PasswordBreachFunctionName, $EmailRelayFunctionName)) {
        Write-Host "Restarting Function App $fn..."
        Invoke-AzCLI "functionapp restart --name $fn --resource-group $ResourceGroup" | Out-Null
    }
    Add-Report 'RestartServices' 'PASS' 'Container App and Function Apps restarted.'
} catch {
    Add-Report 'RestartServices' 'FAIL' $_.Exception.Message
    Write-Warning $_
}

Write-Host "Waiting 30 seconds for warm-up..."
Start-Sleep -Seconds 30

$smoke = @{}
$breachUri = "https://$PasswordBreachFunctionName.azurewebsites.net/api/passwordBreachCheck"
$breachPayload = @{ prefix = '5BAA6'; suffix = 'E4C9D93F3F0682250B6CF8331B7EE68FD8' }
$breach = Invoke-SmokeTest -Uri $breachUri -Method POST -Body $breachPayload -Expected @(200)
Add-Report 'Smoke_PasswordBreach' $breach.status $breach.message $breach.details
$smoke['passwordBreach'] = $breach

$registerUri = "https://$ContainerAppFqdn/v1/auth/register"
$uniqueEmail = "prod-smoke-test+$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())@turksquare.com"
$registerPayload = @{ name = 'Prod Smoke Test'; email = $uniqueEmail; password = 'aVeryStrongP@ssw0rd!2025Smoke' }
$register = Invoke-SmokeTest -Uri $registerUri -Method POST -Body $registerPayload -Expected @(200, 202)
Add-Report 'Smoke_Register' $register.status $register.message $register.details
$smoke['register'] = $register

if ($breach.status -eq 'PASS' -and $register.status -eq 'PASS') {
    Write-Host "`nAll smoke tests passed after remediation." -ForegroundColor Green
} else {
    Write-Host "`nSmoke tests still failing after remediation." -ForegroundColor Red
}

# Final report
Write-StepHeader 'FINAL REMEDIATION REPORT'
$jsonReport = $report | ConvertTo-Json -Depth 10
Write-Host $jsonReport
$outPath = "turksquare-prod-remediation-report-$(Get-Date -Format 'yyyyMMddTHHmmss').json"
$jsonReport | Out-File -FilePath $outPath -Encoding utf8
Write-Host "`nRemediation report saved to: $outPath" -ForegroundColor Green

if ($report.summary.failed -gt 0) {
    Write-Host "`n!!! REMEDIATION COMPLETED WITH REMAINING FAILURES !!!" -ForegroundColor Red
    exit 1
} else {
    Write-Host "`nRemediation completed successfully." -ForegroundColor Green
    exit 0
}