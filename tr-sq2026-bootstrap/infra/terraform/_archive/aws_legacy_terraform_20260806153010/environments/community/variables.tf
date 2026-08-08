variable "vpc_cidr" {
  type    = string
  default = "10.43.0.0/16"
}
variable "postgres_version" {
  type    = string
  default = null
}
variable "db_instance_class" {
  type    = string
  default = "db.t4g.medium"
}
variable "identity_jwt_signing_kms_key_arn" {
  type    = string
  default = "arn:aws:kms:us-east-1:342998331436:key/replace-at-apply"
}
variable "identity_account_id" {
  type    = string
  default = "342998331436"
}

variable "community_api_domain_name" {
  type        = string
  default     = "community-api.turksquare.com"
  description = "Branded public HTTPS host for the Community API."
}

variable "identity_api_base_url" {
  type        = string
  default     = "https://api.turksquare.com"
  description = "Existing branded Identity API origin used only by the Gatework BFF."
}

variable "community_api_base_url" {
  type        = string
  default     = "https://community-api.turksquare.com"
  description = "Existing branded Community API origin used only by the Gatework BFF."
}

variable "cloudflared_image" {
  type        = string
  default     = "cloudflare/cloudflared:2025.2.1"
  description = "Pinned cloudflared image. Upgrade deliberately after review."
}
