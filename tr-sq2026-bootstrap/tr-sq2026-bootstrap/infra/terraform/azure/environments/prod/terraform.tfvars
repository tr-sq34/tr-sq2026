tenant_id       = "c04e6d5b-5a24-42bc-b75b-31915d61e2ed"
subscription_id = "ae28daea-9900-4161-8c87-dc2fa5951304"
environment     = "prod"
location        = "centralus"

postgres_sku            = "GP_Standard_D2s_v3"
postgres_storage_mb     = 131072
postgres_admin_username = "turkadmin"

# BU SIFRE ORNEKTIR. GUVENLI bir sifre girin.
# Terraform apply calistirmadan once mutlaka degistirin.
# Alternatif: TF_VAR_postgres_admin_password ortam degiskeni kullanin.
postgres_admin_password = "@!TrkSq2027!"
