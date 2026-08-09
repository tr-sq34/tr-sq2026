tenant_id       = "c04e6d5b-5a24-42bc-b75b-31915d61e2ed"
subscription_id = "ae28daea-9900-4161-8c87-dc2fa5951304"
environment     = "prod"
location        = "centralus"

# Key Vault yoneticileri. Ilki github-actions-turksquare (CI), ikincisi
# info@turksquare.com (sahip). Bunlar kimlik numarasi, parola degil; ikisinin de
# burada olmasi sart, cunku listede olmayan taraf bir sonraki apply'da vault'a
# erisimini kaybeder ve plan asamasinda 403 alir.
key_vault_admin_object_ids = [
  "8551120e-7a3e-4651-ae23-6cd9b49784b9",
  "5c8d6271-40f5-47fe-a3a8-c5adcafc8e29",
]

postgres_sku            = "GP_Standard_D2s_v3"
postgres_storage_mb     = 131072
postgres_admin_username = "turkadmin"

# Parola burada degil. Terraform uretiyor ve Key Vault'a POSTGRES-ADMIN-PASSWORD
# adiyla yaziyor; sunucuya verilen deger ile servislerin kullandigi deger ayni
# kaynaktan geldigi icin ikisi birbirinden ayrisamiyor. Buradaki eski deger git
# gecmisine girdigi icin artik gecersiz sayilmalidir.
