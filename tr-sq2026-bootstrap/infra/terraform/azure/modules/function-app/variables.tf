variable "function_name" {
  description = "Name of the Azure Function (used in resource names)"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the function resources"
  type        = string
}

variable "tenant_id" {
  description = "Azure AD Tenant ID"
  type        = string
}

variable "deployer_object_ids" {
  description = "Object IDs of every principal that uploads function zip packages to this storage account - the CI service principal and any human operator. All of them get Storage Blob Data Contributor. Empty means the Terraform caller only, which leaves everyone else with 403 on the data plane even if they are Contributor on the account."
  type        = list(string)
  default     = []
}

variable "service_plan_sku" {
  description = "SKU for the Linux service plan"
  type        = string
  default     = "Y1"
}

variable "key_vault_id" {
  description = "Optional Key Vault ID to grant secret access"
  type        = string
  default     = ""
}

variable "application_insights_connection_string" {
  description = "Application Insights connection string"
  type        = string
  default     = ""
}

variable "app_settings" {
  description = "Additional app settings for the function app"
  type        = map(string)
  default     = {}
}

variable "cors_allowed_origins" {
  description = "List of allowed CORS origins"
  type        = list(string)
  default     = []
}

variable "key_vault_secret_references" {
  description = "Map of app setting names to Key Vault secret URIs using @Microsoft.KeyVault syntax"
  type        = map(string)
  default     = {}
}