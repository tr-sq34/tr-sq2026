<#
.SYNOPSIS
  Push TurkSquare Azure migration changes to https://github.com/tr-sq34/tr-sq2026.git

.DESCRIPTION
  1. Clones or refreshes the target GitHub repo.
  2. Removes old AWS paths in the cloned repo.
  3. Copies updated Azure files from C:\AmericaHub.
  4. Updates .gitignore.
  5. Commits and pushes the changes.

  You must be authenticated to GitHub (credential manager, SSH, or PAT).
#>
param(
  [string]$SourceRoot = "C:\AmericaHub",
  [string]$RepoUrl = "https://github.com/tr-sq34/tr-sq2026.git",
  [string]$Branch = "main",
  [string]$CommitMessage = "fix: resolve Azure OIDC, security-baseline paths and Node cache errors"
)

$ErrorActionPreference = "Stop"

$parent = Split-Path $SourceRoot -Parent
$repoName = [System.IO.Path]::GetFileNameWithoutExtension($RepoUrl) -replace '.git$', ''
$target = Join-Path $parent $repoName

if (-not (Test-Path $target)) {
  Write-Host "Cloning $RepoUrl into $target ..." -ForegroundColor Cyan
  git clone $RepoUrl $target
  if ($LASTEXITCODE -ne 0) { throw "git clone failed" }
} else {
  Write-Host "Using existing repo at $target" -ForegroundColor Cyan
  Set-Location $target
  git checkout $Branch
  git pull origin $Branch
  Set-Location (Get-Location).Path
}

$pathsToRemove = @(
  (Join-Path $target "tr-sq2026-bootstrap/services/auth-service"),
  (Join-Path $target "tr-sq2026-bootstrap/services/verification-vault-service"),
  (Join-Path $target "tr-sq2026-bootstrap/services/community-service"),
  (Join-Path $target "tr-sq2026-bootstrap/services/messaging-gateway"),
  (Join-Path $target "tr-sq2026-bootstrap/services/deploy_azure_prod.ps1"),
  (Join-Path $target "tr-sq2026-bootstrap/infra/terraform/azure/environments/prod/main.tf"),
  (Join-Path $target "tr-sq2026-bootstrap/infra/terraform/azure/environments/prod/variables.tf"),
  (Join-Path $target "tr-sq2026-bootstrap/infra/terraform/azure/modules/container-app/main.tf"),
  (Join-Path $target "tr-sq2026-bootstrap/infra/terraform/azure/modules/container-app/variables.tf"),
  (Join-Path $target "tr-sq2026-bootstrap/infra/terraform/azure/modules/shared/main.tf"),
  (Join-Path $target "tr-sq2026-bootstrap/infra/terraform/azure/modules/shared/outputs.tf"),
  (Join-Path $target ".github/workflows/azure-prod-deploy.yml"),
  (Join-Path $target ".github/workflows/security-baseline.yml"),
  (Join-Path $target "backend/auth-service")
)

foreach ($p in $pathsToRemove) {
  if (Test-Path $p) {
    Remove-Item -Path $p -Recurse -Force
    Write-Host "Removed $p" -ForegroundColor Yellow
  }
}

$copySpecs = @(
  @{ Source = "tr-sq2026-bootstrap/services/auth-service"; Destination = "tr-sq2026-bootstrap/services/auth-service" },
  @{ Source = "tr-sq2026-bootstrap/services/verification-vault-service"; Destination = "tr-sq2026-bootstrap/services/verification-vault-service" },
  @{ Source = "tr-sq2026-bootstrap/services/community-service"; Destination = "tr-sq2026-bootstrap/services/community-service" },
  @{ Source = "tr-sq2026-bootstrap/services/messaging-gateway"; Destination = "tr-sq2026-bootstrap/services/messaging-gateway" },
  @{ Source = "tr-sq2026-bootstrap/services/password-breach-check"; Destination = "tr-sq2026-bootstrap/services/password-breach-check" },
  @{ Source = "tr-sq2026-bootstrap/services/email-relay"; Destination = "tr-sq2026-bootstrap/services/email-relay" },
  @{ Source = "tr-sq2026-bootstrap/services/deploy_azure_prod.ps1"; Destination = "tr-sq2026-bootstrap/services/deploy_azure_prod.ps1" },
  @{ Source = "tr-sq2026-bootstrap/infra/terraform/azure"; Destination = "tr-sq2026-bootstrap/infra/terraform/azure" },
  @{ Source = ".github/workflows"; Destination = ".github/workflows" }
)

foreach ($spec in $copySpecs) {
  $src = Join-Path $SourceRoot $spec.Source
  $dst = Join-Path $target $spec.Destination
  if (Test-Path $src) {
    $dstParent = Split-Path $dst -Parent
    if (-not (Test-Path $dstParent)) { New-Item -ItemType Directory -Path $dstParent -Force | Out-Null }
    if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
    Copy-Item -Path $src -Destination $dst -Recurse -Force
    Write-Host "Copied $($spec.Source) -> $($spec.Destination)" -ForegroundColor Green
  }
}

$backendAuth = Join-Path $target "backend/auth-service"
if (Test-Path $backendAuth) {
  Remove-Item $backendAuth -Recurse -Force
  Write-Host "Removed backend/auth-service from target" -ForegroundColor Yellow
}

$gitignore = Join-Path $target ".gitignore"
$linesToAdd = @(
  "**/node_modules/",
  "**/.terraform/",
  "**/*.tfstate",
  "**/*.tfstate.*",
  "**/tfplan*",
  "**/function.zip",
  "backend/_archive/",
  "tr-sq2026-bootstrap/infra/terraform/_archive/",
  ".env",
  ".env.local",
  "**/dist/"
)
$existing = if (Test-Path $gitignore) { Get-Content $gitignore -Raw } else { "" }
$missing = $linesToAdd | Where-Object { $existing -notmatch [regex]::Escape($_) }
if ($missing) {
  $append = ($missing -join "`n") + "`n"
  Add-Content -Path $gitignore -Value $append -Encoding UTF8
  Write-Host "Updated .gitignore" -ForegroundColor Green
}

Set-Location $target
git status --short

git add -A
if ($LASTEXITCODE -ne 0) { throw "git add failed" }

git commit -m "$CommitMessage"
if ($LASTEXITCODE -ne 0) { Write-Warning "No changes to commit or commit failed."; exit 0 }

Write-Host "Pushing to origin/$Branch ..." -ForegroundColor Cyan
git push origin $Branch
if ($LASTEXITCODE -ne 0) { throw "git push failed" }

Write-Host "Done. Changes pushed to $RepoUrl" -ForegroundColor Green
