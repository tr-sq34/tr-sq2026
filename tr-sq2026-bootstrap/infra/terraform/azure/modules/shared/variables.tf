variable "environment" {
  description = "Environment name: prod, staging, dev"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "centralus"
}

variable "tenant_id" {
  description = "Azure Active Directory Tenant ID"
  type        = string
}

variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

variable "vnet_address_space" {
  type    = list(string)
  default = ["10.0.0.0/16"]
}

variable "aca_subnet_prefix" {
  type    = list(string)
  default = ["10.0.0.0/21"]
}

variable "private_endpoint_subnet_prefix" {
  type    = list(string)
  default = ["10.0.32.0/24"]
}

variable "postgres_subnet_prefix" {
  type    = list(string)
  default = ["10.0.33.0/24"]
}

variable "acr_sku" {
  type    = string
  default = "Premium"
}

variable "postgres_sku" {
  type    = string
  default = "B_Standard_B2s"
}

variable "postgres_storage_mb" {
  type    = number
  default = 32768
}

variable "postgres_admin_username" {
  type    = string
  default = "turkadmin"
}

variable "postgres_admin_password" {
  type      = string
  sensitive = true
}

variable "azure_postgres_root_cert_url" {
  type    = string
  default = "https://cacerts.digicert.com/DigiCertGlobalRootG2.crt.pem"
}

variable "key_vault_admin_object_ids" {
  description = "Object IDs of every principal that runs Terraform against this stack - the CI service principal and any human operator. All of them get an access policy regardless of which one is applying. Empty means the current caller only, which bootstraps a new vault but leaves the others locked out."
  type        = list(string)
  default     = []
}

variable "key_vault_secrets" {
  description = "Map of secret names to secret values stored in the shared Azure Key Vault."
  type        = map(string)
  sensitive   = true
  default     = {}
}

variable "resend_api_key_initial" {
  description = "Initial placeholder value for the RESEND-API-KEY Key Vault secret. The real value must be updated manually after provisioning because Terraform ignores subsequent changes."
  type        = string
  sensitive   = true
  default     = "CHANGE-ME-RESEND-API-KEY"
}

variable "stripe_secret_key_initial" {
  description = "Initial placeholder value for the STRIPE-SECRET-KEY Key Vault secret. Stripe issues the real key; set it out of band after provisioning, since Terraform ignores subsequent changes."
  type        = string
  sensitive   = true
  default     = "sk_change_me_stripe_secret_key"
}

variable "stripe_webhook_secret_initial" {
  description = "Initial placeholder value for the STRIPE-WEBHOOK-SECRET Key Vault secret. Stripe issues the real value when the webhook endpoint is registered; set it out of band, since Terraform ignores subsequent changes."
  type        = string
  sensitive   = true
  default     = "whsec_change_me_stripe_webhook_secret"
}

variable "cloudflare_tunnel_token_initial" {
  description = "Initial placeholder value for the CLOUDFLARE-TUNNEL-TOKEN Key Vault secret. Cloudflare issues the real token when the tunnel is created; set it out of band, since Terraform ignores subsequent changes. The gatework console has no ingress, so until this is real the console is reachable from nowhere."
  type        = string
  sensitive   = true
  default     = "CHANGE-ME-CLOUDFLARE-TUNNEL-TOKEN"
}

variable "jwt_secret_initial" {
  description = "Initial placeholder value for the JWT-SECRET Key Vault secret. The real value must be updated manually or via a secure pipeline after provisioning because Terraform ignores subsequent changes."
  type        = string
  sensitive   = true
  default     = "CHANGE-ME-JWT-SECRET-PLACEHOLDER"
}
