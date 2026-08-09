# Azure Functions Node.js v4 Migration Deploy Script
# TurkSquare Identity Service - Central US Production
#
# Gereksinimler:
#   - Azure CLI (az) yuklu ve giris yapilmis
#   - Hedef subscription secili: az account set --subscription <sub-id>
#   - Blob depolama hesaplarina yazma/yonetici izni
#   - Function App'lara Contributor/Website Contributor izni
#
# Calistirma:
#   .\deploy_azure_functions_v2.ps1

$ErrorActionPreference = "Stop"

# --- Konfigurasyon ---
$resourceGroup      = "rg-turksquare-prod-centralus"
$location           = "centralus"

$pbStorageAccount   = "stpasswordbreachchprodcu"
$pbContainer        = "function-releases"
$pbLocalZip         = "./password-breach-check/function.zip"
$pbFunctionApp      = "func-password-breach-check-prod-cu"

$erStorageAccount   = "stemailrelayprodcu"
$erContainer        = "function-releases"
$erLocalZip         = "./email-relay/function.zip"
$erFunctionApp      = "func-email-relay-prod-cu"

$containerAppFqdn   = if ($env:CONTAINER_APP_FQDN) { $env:CONTAINER_APP_FQDN } else { "ca-identity-prod.<ENV>.centralus.azurecontainerapps.io" }
# ORNEK: $env:CONTAINER_APP_FQDN = "ca-identity-prod.joyfuldune-12345678.centralus.azurecontainerapps.io"
# CI/CD ortaminda $env:CONTAINER_APP_FQDN ile override edilir.
# NOT: Degisken tam FQDN olmalidir, sonuna .azurewebsites.net eklenmemelidir.

# --- Yardimci Fonksiyonlar ---

function Get-SafeHttpStatus {
    param([object]$Exception)
    try {
        return $Exception.Response.StatusCode.value__
    }
    catch {
        return "unknown"
    }
}

function Upload-ZipAndGetSas {
    param(
        [string]$StorageAccount,
        [string]$Container,
        [string]$LocalZipPath,
        [string]$BlobName
    )

    $resolvedZip = Resolve-Path $LocalZipPath -ErrorAction Stop
    Write-Host "`n[UPLOAD] Yukleniyor: $resolvedZip -> $StorageAccount/$Container/$BlobName"

    # Deliberately not parsed. This used to ask for -o json, merge stderr in with
    # 2>&1 and pipe the lot into ConvertFrom-Json, which meant az's own output
    # broke the script twice over: the plain-text "ERROR: ..." line on failure,
    # and - once that was fixed - the "Alive[####]" progress bar az writes to
    # stderr on success. Both surfaced as "Conversion from JSON failed",
    # obscuring the real cause. Nothing here needed a field out of that JSON; the
    # blob name is already known. The exit code is the only signal required.
    #
    # The retry is for a fresh role assignment. Terraform grants Storage Blob
    # Data Contributor in the same pipeline run a couple of jobs earlier, and
    # Azure's RBAC caches can take a few minutes to catch up - the first attempt
    # gets 403 on a permission that is already correct.
    $attempt = 0
    while ($true) {
        $attempt++
        $uploadOutput = & az storage blob upload `
            --account-name $StorageAccount `
            --container-name $Container `
            --file $resolvedZip `
            --name $BlobName `
            --overwrite true `
            --auth-mode login `
            --only-show-errors `
            -o none 2>&1

        if ($LASTEXITCODE -eq 0) {
            break
        }

        if ($attempt -ge 5) {
            Write-Warning "Azure CLI cikti:`n$($uploadOutput -join "`n")"
            throw "Blob upload basarisiz: $StorageAccount/$Container/$BlobName`n`nOlasI nedenler:`n- Oturumunuzun ilgili Storage Account'ta 'Storage Blob Data Contributor' rolU yok.`n- Azure CLI dogru subscription'a bagli degil: 'az account set --subscription <id>'`n- Entra ID hesabiniz yeterli izne sahip degil.`n`nCozum: terraform.tfvars icindeki deployer_object_ids listesine deploy yapan hesabin Object ID'sini ekleyin ve tekrar apply edin."
        }

        Write-Warning "   Upload denemesi $attempt basarisiz, 30 saniye sonra tekrar denenecek."
        Write-Warning "   $($uploadOutput -join "`n")"
        Start-Sleep -Seconds 30
    }
    Write-Host "   Blob yuklendi: $BlobName"

    $sasExpiry = (Get-Date).AddYears(1).ToString("yyyy-MM-ddTHH:mm:ssZ")
    Write-Host "   SAS token olusturuluyor... (expiry: $sasExpiry)"

    # Trimmed because the token goes straight into a URL: a trailing newline off
    # the CLI would be carried into WEBSITE_RUN_FROM_PACKAGE and the Function App
    # would fetch a package URL it cannot resolve.
    $sasToken = (& az storage blob generate-sas `
            --account-name $StorageAccount `
            --container-name $Container `
            --name $BlobName `
            --permissions r `
            --expiry $sasExpiry `
            --https-only `
            --auth-mode login `
            --only-show-errors `
            -o tsv) | Out-String
    $sasToken = $sasToken.Trim()

    if ($LASTEXITCODE -ne 0 -or -not $sasToken) {
        throw "SAS token olusturulamadi: $StorageAccount/$Container/$BlobName"
    }

    $sasUrl = "https://$StorageAccount.blob.core.windows.net/$Container/$($BlobName)?$sasToken"
    Write-Host "   SAS URL: $sasUrl"
    return $sasUrl
}

function Set-FunctionAppSettings {
    param(
        [string]$FunctionApp,
        [string]$SasUrl,
        [string]$WorkerRuntime = "node",
        [string]$NodeVersion = "~20"
    )

    Write-Host "`n[APPSETTINGS] Guncelleniyor: $FunctionApp"

    $settings = @(
        "WEBSITE_RUN_FROM_PACKAGE=$SasUrl",
        "FUNCTIONS_WORKER_RUNTIME=$WorkerRuntime",
        "FUNCTIONS_EXTENSION_VERSION=~4",
        "WEBSITE_NODE_DEFAULT_VERSION=$NodeVersion",
        "AzureWebJobsFeatureFlags=EnableWorkerIndexing"
    )

    # PowerShell splatting degil; Azure CLI --settings argumani olarak genislet
    & az functionapp config appsettings set `
        --name $FunctionApp `
        --resource-group $resourceGroup `
        --settings $settings `
        -o none

    if ($LASTEXITCODE -ne 0) {
        throw "App settings guncellenemedi: $FunctionApp"
    }
    Write-Host "   App settings guncellendi."

    Write-Host "   Restart ediliyor: $FunctionApp"
    & az functionapp restart `
        --name $FunctionApp `
        --resource-group $resourceGroup

    if ($LASTEXITCODE -ne 0) {
        throw "Function App restart basarisiz: $FunctionApp"
    }
    Write-Host "   Restart tamamlandi."
}

function Test-PasswordBreachCheck {
    Write-Host "`n[TEST] 30 saniye bekleniyor (Function warm-up)..."
    Start-Sleep -Seconds 30

    $uri = "https://$pbFunctionApp.azurewebsites.net/api/passwordBreachCheck"
    $body = '{"prefix":"21BD1","suffix":"001F8A4C123456789012345678901234567"}'

    Write-Host "   Test istegi: POST $uri"
    try {
        $response = Invoke-RestMethod -Uri $uri -Method POST `
            -ContentType "application/json" -Body $body -TimeoutSec 60
        Write-Host "   Yanit HTTP 200 (basarili)"
        Write-Host ($response | ConvertTo-Json -Depth 3)
        return $true
    }
    catch {
        $status = Get-SafeHttpStatus -Exception $_.Exception
        Write-Warning "   Test basarisiz. HTTP Status: $status"
        Write-Warning "   Hata: $($_.Exception.Message)"
        return $false
    }
}

function Test-ContainerAppRegister {
    Write-Host "`n[FINAL TEST] Container App /v1/auth/register testi..."
    $uri = "https://$containerAppFqdn/v1/auth/register"
    Write-Host "   Hedef URL: $uri"

    $body = @{
        email    = "test-$(Get-Random)@example.com"
        password = "VeryStrongP@ssw0rd123!"
    } | ConvertTo-Json

    Write-Host "   POST $uri"
    try {
        $response = Invoke-RestMethod -Uri $uri -Method POST `
            -ContentType "application/json" -Body $body -TimeoutSec 60
        Write-Host "   Yanit HTTP 200"
        Write-Host ($response | ConvertTo-Json -Depth 3)
    }
    catch {
        $status = Get-SafeHttpStatus -Exception $_.Exception
        Write-Warning "   Container App test basarisiz. HTTP Status: $status"
        Write-Warning "   Hata: $($_.Exception.Message)"
    }
}

# --- Ana Akis ---

try {
    # 1-3. Password Breach Check deploy ve test
    $timestamp = Get-Date -Format "yyyyMMddHHmmss"
    $pbBlobName = "password-breach-check-$timestamp.zip"
    $pbSasUrl = Upload-ZipAndGetSas -StorageAccount $pbStorageAccount `
        -Container $pbContainer -LocalZipPath $pbLocalZip -BlobName $pbBlobName

    Set-FunctionAppSettings -FunctionApp $pbFunctionApp -SasUrl $pbSasUrl -NodeVersion "~20"

    $pbOk = Test-PasswordBreachCheck
    if (-not $pbOk) {
        Write-Warning "Password Breach Check testi basarisiz! Email relay adimina gecmek istediginize emin misiniz?"
        # Read-Host on a CI runner throws an end-of-input error, which the catch
        # at the bottom reports as "HATA: ..." with no hint that the real problem
        # was the failed test above. Ask only where someone can answer.
        if ($env:CI) {
            throw "Password Breach Check testi basarisiz ve ortam etkilesimsiz; email relay adimina gecilmiyor."
        }
        $continue = Read-Host "Devam etmek icin 'yes' yazin"
        if ($continue -ne "yes") {
            throw "Kullanici email relay adimini iptal etti."
        }
    }

    # 4. Email Relay deploy
    $erBlobName = "email-relay-$timestamp.zip"
    $erSasUrl = Upload-ZipAndGetSas -StorageAccount $erStorageAccount `
        -Container $erContainer -LocalZipPath $erLocalZip -BlobName $erBlobName

    Set-FunctionAppSettings -FunctionApp $erFunctionApp -SasUrl $erSasUrl -NodeVersion "~20"

    # 5. Nihai uctan uca test
    Test-ContainerAppRegister

    Write-Host "`n=== Tum adimlar tamamlandi ==="
}
catch {
    Write-Error "HATA: $_"
    exit 1
}
