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

variable "postgres_admin_password" {
  type      = string
  sensitive = true
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

variable "deployer_object_id" {
  description = "Azure AD object ID of the user, group or service principal that deploys function zip packages to the storage accounts. If empty, the Terraform caller is used."
  type        = string
  default     = ""
}