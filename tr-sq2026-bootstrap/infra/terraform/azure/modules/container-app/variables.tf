variable "service_name" {
  type = string
}

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

variable "acr_id" {
  type = string
}

variable "acr_login_server" {
  type = string
}

variable "key_vault_id" {
  type = string
}

variable "key_vault_uri" {
  type = string
}

variable "log_analytics_workspace_id" {
  type = string
}

variable "aca_subnet_id" {
  type = string
}

variable "image_repository" {
  type = string
}

variable "image_tag" {
  type    = string
  default = "latest"
}

variable "container_port" {
  type    = number
  default = 3000
}

variable "expose_externally" {
  type    = bool
  default = true
}

variable "enable_ingress" {
  description = "Whether the app serves HTTP. Background workers set this to false; a container app with an ingress block but no listener is reported unhealthy and never scales up."
  type        = bool
  default     = true
}

variable "container_command" {
  description = "Overrides the image entrypoint. Used to run a worker out of the same image as its HTTP service so both always ship identical code."
  type        = list(string)
  default     = []
}

variable "container_args" {
  description = "Arguments appended to container_command."
  type        = list(string)
  default     = []
}

variable "cpu" {
  type    = number
  default = 0.5
}

variable "memory" {
  type    = string
  default = "1Gi"
}

variable "min_replicas" {
  type    = number
  default = 1
}

variable "max_replicas" {
  type    = number
  default = 3
}

# The four below default to empty for apps that hold no data of their own. The
# gatework console is the only such caller: it reaches every domain over its
# HTTP API precisely so that an operator console never holds a database
# credential. DATABASE_URL is omitted entirely when database_name is empty.
variable "postgres_admin_username" {
  type    = string
  default = ""
}

variable "postgres_admin_password" {
  type      = string
  sensitive = true
  default   = ""
}

variable "postgres_fqdn" {
  type    = string
  default = ""
}

variable "database_name" {
  type    = string
  default = ""
}

variable "servicebus_connection_string" {
  type      = string
  sensitive = true
  default   = ""
}

variable "servicebus_connection_string_secret_uri" {
  description = "Optional Key Vault secret URI (versionless) for Service Bus connection string. If provided, overrides the plaintext connection string."
  type        = string
  sensitive   = true
  default     = ""
}

variable "extra_env" {
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "secret_env" {
  type = list(object({
    name                = string
    key_vault_secret_id = string
    env_name            = string
  }))
  default = []
}

variable "storage_account_key_secret_uri" {
  description = "Optional Key Vault secret URI (versionless) for Azure Storage Account primary access key."
  type        = string
  sensitive   = true
  default     = ""
}

variable "extra_secret_env" {
  type = list(object({
    name                = string
    key_vault_secret_id = string
    env_name            = string
  }))
  default = []
}

# A second container in the same app. Containers of one container app share a
# network namespace, so a sidecar reaches the main container on localhost — which
# is what lets an app be published through a Cloudflare Tunnel while having no
# ingress of its own.
variable "sidecar" {
  type = object({
    name   = string
    image  = string
    args   = optional(list(string), [])
    cpu    = optional(number, 0.25)
    memory = optional(string, "0.5Gi")
    secret_env = optional(list(object({
      name                = string
      key_vault_secret_id = string
      env_name            = string
    })), [])
  })
  default = null
}

variable "dapr_enabled" {
  description = "Enable Dapr sidecar for the container app."
  type        = bool
  default     = false
}

variable "dapr_app_id" {
  description = "Dapr app ID. Defaults to the service name."
  type        = string
  default     = null
}

variable "dapr_app_port" {
  description = "Dapr app port. Defaults to the container port."
  type        = number
  default     = null
}

variable "dapr_app_protocol" {
  description = "Dapr app protocol (http or grpc)."
  type        = string
  default     = "http"
}


variable "container_app_environment_id" {
  description = "Reuse an existing Container App environment instead of declaring one. New callers should set this; see the comment on azurerm_container_app_environment.main."
  type        = string
  default     = ""
}

# The public hostnames this app answers, on top of the generated
# *.azurecontainerapps.io one. Empty by default and empty is the safe state: a
# binding is only accepted after the hostname's DNS already points here, so
# declaring one too early fails the apply - and this apply runs on every push to
# main. See infra/bootstrap/azure-public-dns-cutover.md for the order.
variable "custom_domains" {
  description = "Public hostnames bound to this app, e.g. [\"api.turksquare.com\"]. Each one needs a CNAME to ingress_fqdn and a TXT asuid.<host> record carrying the environment's domain verification id BEFORE it is listed here."
  type        = list(string)
  default     = []
}
