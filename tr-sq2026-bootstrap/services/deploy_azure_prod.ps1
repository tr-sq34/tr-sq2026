<#
.SYNOPSIS
  TurkSquare Azure production deployment orchestrator.

.DESCRIPTION
  Builds all container images, packages Function Apps, optionally runs Terraform,
  and performs smoke tests. Designed for local/interactive use after Azure
  prerequisites (Key Vault secrets, PostgreSQL DBs, Storage permissions) are ready.

.PARAMETER SkipTerraform
  Skip Terraform plan/apply and only build/push images and function zips.

.PARAMETER SkipSmokeTests
  Skip post-deployment smoke tests.

.PARAMETER ImageTag
  Override the container image tag. Defaults to the current Git commit SHA or timestamp.

.PARAMETER ResourceGroup
  Azure resource group for Container Apps and Function Apps.

.PARAMETER AcrName
  Azure Container Registry name (without .azurecr.io).

.PARAMETER SubscriptionId
  Azure subscription ID.

.PARAMETER TerraformDir
  Path to the Terraform prod environment directory.

.PARAMETER ServicesDir
  Path to the services directory.

.EXAMPLE
  .\deploy_azure_prod.ps1 -ImageTag "20250806-1" -SkipTerraform:$false
#>
param(
  [switch]$SkipTerraform = $false,
  [switch]$SkipSmokeTests = $false,
  [string]$ImageTag = "",
  [string]$ResourceGroup = "rg-turksquare-prod-centralus",
  [string]$AcrName = "crturksquareprodcu",
  [string]$SubscriptionId = "ae28daea-9900-4161-8c87-dc2fa5951304",
  [string]$TerraformDir = "..\infra\terraform\azure\environments\prod",
  [string]$ServicesDir = "."
)

$ErrorActionPreference = "Stop"

function Resolve-ProjectRoot {
  $root = Get-Location
  while ($root -and -not (Test-Path (Join-Path $root ".git"))) {
    $root = Split-Path $root -Parent
  }
  return $root
}

$projectRoot = Resolve-ProjectRoot
if (-not $projectRoot) {
  Write-Warning "Could not resolve git project root; using current directory."
  $projectRoot = Get-Location
}

if (-not $ImageTag) {
  try {
    $sha = (git -C $projectRoot rev-parse --short HEAD 2>$null)
    if ($sha) { $ImageTag = $sha }
  } catch { }
  if (-not $ImageTag) {
    $ImageTag = Get-Date -Format "yyyyMMddHHmmss"
  }
}

$TerraformDir = Join-Path $projectRoot "tr-sq2026-bootstrap\infra\terraform\azure\environments\prod"
$ServicesDir  = Join-Path $projectRoot "tr-sq2026-bootstrap\services"

Write-Host "=== TurkSquare Azure Production Deploy ===" -ForegroundColor Cyan
Write-Host "Project root : $projectRoot"
Write-Host "Image tag    : $ImageTag"
Write-Host "Resource group: $ResourceGroup"
Write-Host "ACR          : $AcrName"
Write-Host "Skip Terraform: $SkipTerraform"
Write-Host "Skip Smoke Tests: $SkipSmokeTests"
Write-Host ""

# --- Pre-flight checks ---
function Test-Command {
  param([string]$Name)
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if (-not $cmd) {
    throw "Required command '$Name' not found. Install it and ensure it is in PATH."
  }
}

Test-Command "az"
Test-Command "docker"
Test-Command "git"
if (-not $SkipTerraform) { Test-Command "terraform" }

$azAccount = az account show --query "id" -o tsv 2>$null
if (-not $azAccount) {
  throw "Not logged into Azure CLI. Run: az login --subscription $SubscriptionId"
}
if ($azAccount -ne $SubscriptionId) {
  Write-Host "Switching to subscription $SubscriptionId"
  az account set --subscription $SubscriptionId | Out-Null
}

$acrLoginServer = "$AcrName.azurecr.io"
Write-Host "Logging into ACR $acrLoginServer"
az acr login --name $AcrName | Out-Null

# --- Build & push container images ---
$services = @(
  @{ Name = "identity"; Dir = "auth-service"; Repository = "turksquare/identity-service"; Port = 8080 },
  @{ Name = "verification-vault"; Dir = "verification-vault-service"; Repository = "turksquare/verification-vault-service"; Port = 8082 },
  @{ Name = "community"; Dir = "community-service"; Repository = "turksquare/community-service"; Port = 8080 },
  @{ Name = "messaging-gateway"; Dir = "messaging-gateway"; Repository = "turksquare/messaging-gateway"; Port = 8080 }
)

foreach ($svc in $services) {
  $context = Join-Path $ServicesDir $svc.Dir
  $dockerfile = Join-Path $context "Dockerfile"
  $tag = "$acrLoginServer/$($svc.Repository):$ImageTag"
  $latest = "$acrLoginServer/$($svc.Repository):latest"

  Write-Host ""
  Write-Host "[IMAGE] Building $($svc.Name) from $context" -ForegroundColor Cyan
  docker build --pull -t $tag -t $latest -f $dockerfile $context
  if ($LASTEXITCODE -ne 0) { throw "Docker build failed for $($svc.Name)" }

  Write-Host "[IMAGE] Pushing $tag"
  docker push $tag
  if ($LASTEXITCODE -ne 0) { throw "Docker push failed for $($svc.Name)" }
  docker push $latest | Out-Null
}

# --- Package Function Apps ---
$functionApps = @(
  @{ Name = "password-breach-check"; Dir = "password-breach-check" },
  @{ Name = "email-relay"; Dir = "email-relay" }
)

foreach ($fa in $functionApps) {
  $dir = Join-Path $ServicesDir $fa.Dir
  $zip = Join-Path $dir "function.zip"
  Write-Host ""
  Write-Host "[FUNCTION] Packaging $($fa.Name)" -ForegroundColor Cyan
  Set-Location $dir
  npm ci --omit=dev | Out-Null
  if (Test-Path $zip) { Remove-Item $zip -Force }
  $items = Get-ChildItem -Path $dir -Recurse | Where-Object {
    $_.FullName -notmatch '\\\.git[\\/]' -and
    $_.FullName -notmatch 'node_modules\\\.cache' -and
    $_.FullName -notmatch '\\test[\\/]' -and
    $_.FullName -notmatch '\.ts$' -and
    $_.FullName -notmatch '\.tsx$'
  }
  Compress-Archive -Path $items.FullName -DestinationPath $zip -Force
  Set-Location $projectRoot
  Write-Host "[FUNCTION] Created $zip"
}

# --- Terraform ---
if (-not $SkipTerraform) {
  Write-Host ""
  Write-Host "[TERRAFORM] Planning and applying" -ForegroundColor Cyan
  Set-Location $TerraformDir

  $env:ARM_SUBSCRIPTION_ID = $SubscriptionId
  $env:ARM_USE_OIDC = "false"
  $env:TF_VAR_identity_image_tag = $ImageTag
  $env:TF_VAR_verification_vault_image_tag = $ImageTag
  $env:TF_VAR_community_image_tag = $ImageTag
  $env:TF_VAR_messaging_gateway_image_tag = $ImageTag

  terraform init
  if ($LASTEXITCODE -ne 0) { throw "terraform init failed" }

  terraform plan -input=false -out=tfplan
  if ($LASTEXITCODE -ne 0) { throw "terraform plan failed" }

  terraform apply -input=false tfplan
  if ($LASTEXITCODE -ne 0) { throw "terraform apply failed" }

  Set-Location $projectRoot
} else {
  Write-Host "[TERRAFORM] Skipped as requested." -ForegroundColor Yellow
}

# --- Deploy Function Apps ---
Write-Host ""
Write-Host "[FUNCTION DEPLOY] Uploading function packages via deploy_azure_functions_v2.ps1" -ForegroundColor Cyan
$deployScript = Join-Path $ServicesDir "deploy_azure_functions_v2.ps1"
if (Test-Path $deployScript) {
  & powershell -ExecutionPolicy Bypass -File $deployScript
  if ($LASTEXITCODE -ne 0) { throw "Function deploy script failed" }
} else {
  Write-Warning "Function deploy script not found at $deployScript"
}

# --- Smoke tests ---
if (-not $SkipSmokeTests) {
  Write-Host ""
  Write-Host "[SMOKE TESTS] Running health checks" -ForegroundColor Cyan
  Start-Sleep -Seconds 30

  $tests = @(
    @{ Name = "password-breach-check function"; Uri = "https://func-password-breach-check-prod-cu.azurewebsites.net/api/passwordBreachCheck"; Method = "POST"; Body = '{"prefix":"21BD1","suffix":"001F8A4C123456789012345678901234567"}' },
    @{ Name = "identity health"; Uri = "https://ca-identity-prod.$env:CONTAINER_APP_ENV_FQDN/health"; Method = "GET" },
    @{ Name = "verification-vault health"; Uri = "https://ca-verification-vault-prod.$env:CONTAINER_APP_ENV_FQDN/health"; Method = "GET" },
    @{ Name = "community health"; Uri = "https://ca-community-prod.$env:CONTAINER_APP_ENV_FQDN/health"; Method = "GET" },
    @{ Name = "messaging-gateway health"; Uri = "https://ca-messaging-gateway-prod.$env:CONTAINER_APP_ENV_FQDN/health"; Method = "GET" }
  )

  foreach ($test in $tests) {
    Write-Host "Testing $($test.Name) -> $($test.Uri)"
    try {
      if ($test.Method -eq "POST") {
        Invoke-RestMethod -Uri $test.Uri -Method POST -ContentType "application/json" -Body $test.Body -TimeoutSec 60 | Out-Null
      } else {
        Invoke-RestMethod -Uri $test.Uri -Method GET -TimeoutSec 60 | Out-Null
      }
      Write-Host "  OK" -ForegroundColor Green
    } catch {
      Write-Host "  FAILED: $($_.Exception.Message)" -ForegroundColor Red
    }
  }
}

Write-Host ""
Write-Host "=== Deployment complete ===" -ForegroundColor Cyan
