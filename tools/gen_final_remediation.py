ps = '''param(
    [string] $ContainerAppName = 'ca-identity-prod',
    [string] $ResourceGroup = 'rg-turksquare-prod-centralus',
    [string] $PasswordBreachFunctionName = 'func-password-breach-check-prod-cu',
    [string] $EmailRelayFunctionName = 'func-email-relay-prod-cu',
    [string] $GitHubAppDisplayName = 'GitHub-Actions-TurkSquare'
)

function Invoke-SmokeTest ($Uri, $Method, $Body, $Expected) {
    try {
        $wr = Invoke-WebRequest -Uri $Uri -Method $Method -Body ($Body | ConvertTo-Json -Depth 10) -ContentType 'application/json' -TimeoutSec 30 -UseBasicParsing
        $ok = $Expected -contains $wr.StatusCode
        return @{ status = if ($ok) { 'PASS' } else { 'FAIL' }; message = "HTTP $($wr.StatusCode) from $Uri"; details = ($wr.Content | ConvertFrom-Json -ErrorAction SilentlyContinue) }
    } catch {
        $status = 0
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) { $status = [int]$_.Exception.Response.StatusCode }
        $ok = $Expected -contains $status
        return @{ status = if ($ok) { 'PASS' } else { 'FAIL' }; message = "HTTP $status from $Uri : $($_.Exception.Message)"; details = $null }
    }
}

Write-Host 'Restarting Container App revisions...'
$revs = az containerapp revision list --name $ContainerAppName --resource-group $ResourceGroup --query '[].name' -o tsv
foreach ($r in $revs) {
    if ([string]::IsNullOrWhiteSpace($r)) { continue }
    Write-Host "  Restarting $r"
    az containerapp revision restart --name $ContainerAppName --resource-group $ResourceGroup --revision $r
}

Write-Host 'Restarting Function Apps...'
foreach ($fn in @($PasswordBreachFunctionName, $EmailRelayFunctionName)) {
    Write-Host "  Restarting $fn"
    az functionapp restart --name $fn --resource-group $ResourceGroup
}

Write-Host 'Waiting 60 seconds for warm-up...'
Start-Sleep -Seconds 60

$report = @{}
$breachUri = "https://$PasswordBreachFunctionName.azurewebsites.net/api/passwordBreachCheck"
$breachPayload = @{ prefix = '5BAA6'; suffix = 'E4C9D93F3F0682250B6CF8331B7EE68FD8' }
$breach = Invoke-SmokeTest -Uri $breachUri -Method POST -Body $breachPayload -Expected @(200)
$report['Smoke_PasswordBreach'] = $breach

$registerUri = "https://ca-identity-prod.bravesea-9c47c081.centralus.azurecontainerapps.io/v1/auth/register"
$uniqueEmail = "prod-smoke-test+$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())@turksquare.com"
$registerPayload = @{ name = 'Prod Smoke Test'; email = $uniqueEmail; password = 'aVeryStrongP@ssw0rd!2025Smoke' }
$register = Invoke-SmokeTest -Uri $registerUri -Method POST -Body $registerPayload -Expected @(200, 202)
$report['Smoke_Register'] = $register

Write-Host 'Querying GitHub OIDC App Registration...'
$appRegId = az ad app list --display-name "$GitHubAppDisplayName" --query '[0].id' -o tsv
$report['GitHubAppRegId'] = $appRegId
if ($appRegId) {
    $fics = az ad app federated-credential list --id $appRegId --query '[].name' -o tsv
    $report['FederatedCredentials'] = $fics
}

$jsonReport = $report | ConvertTo-Json -Depth 10
Write-Host $jsonReport
$jsonReport | Out-File -FilePath "final-remediation-report-$(Get-Date -Format 'yyyyMMddTHHmmss').json" -Encoding utf8
'''

with open('tools/final-remediation.ps1', 'w') as f:
    f.write(ps)
print('generated tools/final-remediation.ps1')"""

with open('tools/gen_final_remediation.py', 'w') as f:
    f.write(ps)
print('generated tools/gen_final_remediation.py')