# TurkSquare Identity Service - Azure Migration Runbook

Bu doküman, Identity Service'in AWS tabanli altyapisindan Azure'a tamamen native gecisini saglayan adimlari ve kontrolleri icerir.

## Hedef Mimari (Azure Native)

| Bilesen | Azure Hizmeti |
|---------|--------------|
| Identity API | Azure Container Apps |
| Transactional Email | Azure Functions (Node.js v4) + Resend |
| Password Breach Check | Azure Functions (Node.js v4) + Have I Been Pwned |
| PostgreSQL | Azure Database for PostgreSQL Flexible Server |
| Secrets | Azure Key Vault |
| Container Registry | Azure Container Registry |
| Service Bus | Azure Service Bus |
| Logs/Monitoring | Application Insights + Log Analytics |
| CI/CD | GitHub Actions + Azure OIDC |
| State | Terraform with Azure Storage backend |

## 1. On Kosullar

- Azure CLI yuklu ve `az login` yapilmis.
- Hedef subscription secili:
  ```bash
  az account set --subscription ae28daea-9900-4161-8c87-dc2fa5951304
  ```
- RBAC yetkileri:
  - Subscription/Resource Group: Contributor
  - Storage Accounts: Storage Blob Data Contributor / Storage Account Contributor
  - Key Vault: Key Vault Secrets Officer (deployer icin)
  - ACR: AcrPush
- GitHub repository secrets ayarlanmis:
  - `AZURE_CLIENT_ID_PROD` (Azure AD App Registration / Managed Identity client ID)
  - `RESEND_API_KEY_INITIAL`
  - `JWT_SECRET_INITIAL` (Guclu, rastgele, en az 32 byte)
  - `POSTGRES_ADMIN_PASSWORD`
  - `CONTAINER_APP_FQDN` (Ornegin `ca-identity-prod.xxxxx.centralus.azurecontainerapps.io`)
  - `AWS_DEPLOY_ROLE_ARN` (Legacy kaynaklari kapatmak icin)

## 2. Terraform Degisiklikleri

Guncellenen dosyalar:

- `infra/terraform/azure/modules/shared/main.tf`
  - Service Bus connection string Key Vault secret olarak saklaniyor.
  - `JWT-SECRET` Key Vault secret eklendi.
- `infra/terraform/azure/modules/shared/outputs.tf`
  - `servicebus_connection_string_secret_uri` output eklendi.
- `infra/terraform/azure/modules/shared/variables.tf`
  - `jwt_secret_initial` variable eklendi.
- `infra/terraform/azure/modules/function-app/main.tf`
  - Function App storage managed identity kullaniyor (`storage_uses_managed_identity = true`).
  - `FUNCTIONS_WORKER_RUNTIME=node`, `WEBSITE_NODE_DEFAULT_VERSION=~20`, `AzureWebJobsFeatureFlags=EnableWorkerIndexing` eklendi.
  - Storage rol atamalari: `Storage Blob Data Owner` + `Storage Account Contributor`.
- `infra/terraform/azure/modules/container-app/main.tf`
  - Service Bus connection string icin Key Vault secret referans destegi eklendi.
- `infra/terraform/azure/environments/prod/main.tf`
  - Yeni Key Vault secret'lar (`JWT-SECRET`, `EMAIL-DELIVERY-WEBHOOK`, `PWNED-PASSWORDS-RANGE-URL`) eklendi.
  - Container App secret_env listesi guncellendi.
  - Service Bus Key Vault secret URI container app'e baglandi.
- `infra/terraform/environments/identity/identity_email_relay.tf`
  - AWS Lambda/SQS email relay kaynaklari `enable_legacy_aws_resources=false` ile devre disi birakilabilir.
- `infra/terraform/environments/identity/identity_compute.tf`
  - Lambda referanslari `try(...[0], "")` ile guvenli hale getirildi.

## 3. Auth Service Kod Degisiklikleri

- `backend/auth-service/Dockerfile` eklendi.
- `backend/auth-service/.dockerignore` eklendi.
- `backend/auth-service/src/server.ts`:
  - `EMAIL_RELAY_FUNCTION_NAME` secret'i varsa otomatik `/api/emailRelay` yolundan webhook URL cozumleniyor.
  - `PWNED_PASSWORDS_RANGE_URL` Azure Function URL'si iceriyorsa POST `{prefix, suffix}` ile kontrol ediyor.

## 4. CI/CD Pipeline

Workflow: `.github/workflows/azure-prod-deploy.yml`

Jobs:
1. **build**: Container image build/push ACR + function zip paketleme.
2. **terraform-plan**: `prod` ortami icin plan (manuel onay gerektiren environment).
3. **terraform-apply**: Onaylanan plani uygula.
4. **deploy-functions**: Function zipleri blob'a yukle + restart.
5. **smoke-tests**: Password breach check ve Container App health testi.
6. **disable-aws-legacy** (istege bagli): AWS Lambda/SQS kaynaklarini kapat.

Manuel calistirma:
```bash
git checkout main
git pull
# Gerekirse tag override
gh workflow run azure-prod-deploy.yml -f identity_image_tag=$(git rev-parse --short HEAD)
```

## 5. Manuel Deploy (Script ile)

Pipeline calistirilamiyorsa:

```powershell
# 1. Azure login
az login
az account set --subscription ae28daea-9900-4161-8c87-dc2fa5951304

# 2. Container App FQDN bul
az containerapp show --name ca-identity-prod `
  --resource-group rg-turksquare-prod-centralus `
  --query properties.configuration.ingress.fqdn -o tsv

# 3. Script icindeki $containerAppFqdn guncelle (veya env variable)
$env:CONTAINER_APP_FQDN = "ca-identity-prod.xxxxx.centralus.azurecontainerapps.io"

# 4. Calistir
cd tr-sq2026-bootstrap/services
.\deploy_azure_functions_v2.ps1
```

Script asagidaki adimlari otomatik yapar:
- password-breach-check zip'ini blob'a yukle, SAS URL al.
- App settings yaz + restart.
- 30 sn bekle + smoke test.
- email-relay icin ayni islemleri yap.
- Container App `/v1/auth/register` uctan uca test.

## 6. Sorun Giderme

### 404 hatasi devam ederse (Function App)

```powershell
az functionapp logs tail `
  --name func-password-breach-check-prod-cu `
  --resource-group rg-turksquare-prod-centralus
```

Sik nedenler:
- `WEBSITE_RUN_FROM_PACKAGE` gecersiz SAS URL veya yetki yetersiz.
- `AzureWebJobsFeatureFlags=EnableWorkerIndexing` eksik.
- Node.js v4 modelde `src/functions/*.js` dosyalari ve `host.json` uyumsuz.
- `FUNCTIONS_WORKER_RUNTIME` set edilmemis.

### Container App secret referans hatasi

Container App managed identity'nin Key Vault'a erisim izni varligini dogrula:
```bash
az keyvault show --name kv-turksquare-prod-cu --resource-group rg-turksquare-prod-centralus
az role assignment list --assignee <container-app-managed-identity-principal-id> --scope <keyvault-id>
```

### Function App storage managed identity hatasi

```bash
az role assignment list --assignee <function-app-managed-identity-principal-id> --scope <function-storage-account-id>
```
Gerekli roller: `Storage Blob Data Owner`, `Storage Account Contributor`.

## 7. AWS Legacy Kaynaklarini Kapatma

Azure Functions ve Container App tamamen dogrulandiktan sonra:

```bash
cd infra/terraform/environments/identity
terraform init
terraform plan -var enable_legacy_aws_resources=false
terraform apply -var enable_legacy_aws_resources=false
```

Pipeline icerisinde `disable_aws_legacy=true` input ile calistirilabilir.

## 8. Nihai Kontrol Listesi

- [ ] Azure Container App `ca-identity-prod` saglikli calisiyor.
- [ ] `POST /v1/auth/register` basarili yanit donuyor.
- [ ] `POST /api/passwordBreachCheck` 200 donuyor.
- [ ] `POST /api/emailRelay` (Resend API key ile) email gonderiyor.
- [ ] Container App managed identity Key Vault'a erisebiliyor.
- [ ] Function App managed identity storage account'a erisebiliyor.
- [ ] PostgreSQL flexible server private erisimle calisiyor.
- [ ] Terraform state backend Azure Storage'da tutuluyor.
- [ ] GitHub Actions OIDC ile Azure login calisiyor.
- [ ] AWS Lambda/SQS email relay kaynaklari disable edildi (gecis tamamlandiktan sonra).
- [ ] `JWT-SECRET`, `RESEND-API-KEY` gibi sensitive secret'lar uretim degerleriyle guncellendi.
- [ ] Application Insights uzerinde canli log/metric goruluyor.

## 9. Ileriye Donuk Gelistirmeler

- Azure AD B2C / Entra External ID entegrasyonu ile sosyal login.
- Azure Front Door + WAF (Web Application Firewall) onune koyma.
- Azure DDoS Protection Standard.
- PostgreSQL geo-redundant backup ve fail-over plani.
- Key Vault secret rotation otomasyonu.
- Container App custom domain ve managed certificate yapilandirmasi.

## 10. Acil Rollback

Eger bir problem olursa:
1. Container App revision'unu onceki saglikli imaja don:
   ```bash
   az containerapp revision list --name ca-identity-prod -g rg-turksquare-prod-centralus
   az containerapp revision activate --name ca-identity-prod -g rg-turksquare-prod-centralus --revision <previous-revision>
   ```
2. Function App `WEBSITE_RUN_FROM_PACKAGE` onceki SAS URL'ye don:
   ```bash
   az functionapp config appsettings set --name func-password-breach-check-prod-cu `
     --resource-group rg-turksquare-prod-centralus `
     --settings "WEBSITE_RUN_FROM_PACKAGE=<onceki-sas-url>"
   ```
3. AWS legacy kaynaklarini tekrar aktif etmek icin:
   ```bash
   terraform apply -var enable_legacy_aws_resources=true
   ```
