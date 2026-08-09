variable "job_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "container_app_environment_id" {
  type = string
}

variable "acr_id" {
  type = string
}

variable "acr_login_server" {
  type = string
}

variable "image_repository" {
  type = string
}

variable "image_tag" {
  type    = string
  default = "latest"
}

variable "command" {
  type    = list(string)
  default = ["node", "dist/migrate.js"]
}

variable "postgres_admin_username" {
  type = string
}

variable "postgres_admin_password" {
  type      = string
  sensitive = true
}

variable "postgres_fqdn" {
  type = string
}

variable "database_name" {
  type = string
}

variable "timeout_seconds" {
  type    = number
  default = 600
}
