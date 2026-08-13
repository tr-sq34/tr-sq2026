variable "tenant_id" {
  description = "Azure AD Tenant ID"
  type        = string
}

variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "location" {
  type    = string
  default = "eastus"
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

variable "acr_sku" {
  type    = string
  default = "Premium"
}

variable "postgres_sku" {
  type    = string
  default = "GP_Standard_D2s_v3"
}

variable "postgres_storage_mb" {
  type    = number
  default = 65536
}

variable "postgres_admin_username" {
  type    = string
  default = "turkadmin"
}

variable "identity_image_tag" {
  type    = string
  default = "latest"
}

variable "verification_vault_image_tag" {
  type    = string
  default = "latest"
}

variable "community_image_tag" {
  type    = string
  default = "latest"
}

variable "messaging_gateway_image_tag" {
  type    = string
  default = "latest"
}

variable "gatework_console_image_tag" {
  type    = string
  default = "latest"
}

variable "matrix_synapse_image_tag" {
  type    = string
  default = "latest"
}

variable "resend_api_key_initial" {
  description = "Initial placeholder value for the RESEND-API-KEY Key Vault secret. The real value must be updated manually after provisioning."
  type        = string
  sensitive   = true
  default     = "CHANGE-ME-RESEND-API-KEY"
}

variable "jwt_secret_initial" {
  description = "Initial placeholder value for the JWT-SECRET Key Vault secret. The real value must be updated manually or via a secure pipeline after provisioning."
  type        = string
  sensitive   = true
  default     = "CHANGE-ME-JWT-SECRET-PLACEHOLDER"
}

variable "key_vault_admin_object_ids" {
  description = "Object IDs of every principal that applies this stack. Set in terraform.tfvars rather than an environment variable on purpose: a run that did not happen to have the variable set would fall back to the caller alone and revoke everyone else."
  type        = list(string)
  default     = []
}

variable "deployer_object_ids" {
  description = "Object IDs of every principal that uploads function zip packages. Set in terraform.tfvars rather than an environment variable for the same reason as key_vault_admin_object_ids: a run without the variable would fall back to the caller alone and revoke everyone else."
  type        = list(string)
  default     = []
}
# The four public API hostnames, keyed by the app that answers them. Empty by
# default, and empty is what is applied until the DNS actually points at Azure:
# binding a hostname whose CNAME still resolves somewhere else fails, and this
# apply runs on every push to main. The cutover order - Cloudflare records
# first, then these, then the certificate - is in
# infra/bootstrap/azure-public-dns-cutover.md.
variable "public_api_domains" {
  description = "Public hostnames per service, e.g. { identity = [\"api.turksquare.com\"] }. Keys: identity, community, messaging, verification."
  type        = map(list(string))
  default     = {}
}
