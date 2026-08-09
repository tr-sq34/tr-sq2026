variable "environment" {
  type = string
}

variable "location" {
  type = string
}

variable "tenant_id" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "container_app_environment_id" {
  description = "The environment Synapse joins. It must be the same one the messaging gateway runs in: internal ingress is only resolvable from inside a single environment."
  type        = string
}

variable "acr_id" {
  type = string
}

variable "acr_login_server" {
  type = string
}

variable "key_vault_id" {
  type = string
}

variable "key_vault_secret_uri" {
  description = "Vault URI with the `secrets/` suffix, as produced by the shared module."
  type        = string
}

variable "image_repository" {
  type    = string
  default = "turksquare/matrix-synapse"
}

variable "image_tag" {
  type    = string
  default = "latest"
}

variable "server_name" {
  description = "Must equal server_name in services/matrix-synapse/homeserver.yaml.template. It is baked into every Matrix ID and event signature at first boot and can never be changed."
  type        = string
  default     = "matrix.turksquare.com"
}

variable "storage_account_name" {
  type = string
}

variable "storage_account_key" {
  type      = string
  sensitive = true
}

variable "data_share_quota_gb" {
  description = "Azure Files quota for /data. It holds the media store, so it grows with uploads; the quota can be raised in place but not lowered."
  type        = number
  default     = 256
}

variable "postgres_fqdn" {
  type = string
}

variable "postgres_admin_username" {
  type = string
}

variable "postgres_admin_password" {
  type      = string
  sensitive = true
}

variable "database_name" {
  description = "Must be a database created with collation C; Synapse refuses to start otherwise."
  type        = string
  default     = "matrix"
}

variable "appservice_as_token_secret_name" {
  description = "Key Vault secret holding the token the gateway authenticates to Synapse with. The gateway must read the same secret."
  type        = string
  default     = "MATRIX-APPSERVICE-TOKEN"
}

variable "appservice_hs_token_secret_name" {
  type    = string
  default = "MATRIX-APPSERVICE-HS-TOKEN"
}

variable "cpu" {
  type    = number
  default = 1.0
}

variable "memory" {
  type    = string
  default = "2Gi"
}
