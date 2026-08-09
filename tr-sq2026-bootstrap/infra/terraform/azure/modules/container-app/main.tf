terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.75"
    }
  }
}

variable "key_vault_secret_uri" {
  type = string
}

locals {
  tags = {
    project     = "turksquare"
    environment = var.environment
    service     = var.service_name
    managed_by  = "terraform"
  }

  secret_env_normalized = [
    for s in var.secret_env : {
      name                = lower(s.name)
      key_vault_secret_id = s.key_vault_secret_id
      env_name            = s.env_name
    }
  ]

  container_app_environment_id = var.container_app_environment_id != "" ? var.container_app_environment_id : one(azurerm_container_app_environment.main[*].id)
}

# Keeps callers already in state on their existing environment when the resource
# above gained `count`. Without this, Terraform would read the un-indexed address
# as orphaned and plan to destroy the environment every other service runs in.
moved {
  from = azurerm_container_app_environment.main
  to   = azurerm_container_app_environment.main[0]
}

resource "azurerm_user_assigned_identity" "app" {
  name                = "id-${var.service_name}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = local.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}

resource "azurerm_key_vault_access_policy" "app" {
  key_vault_id = var.key_vault_id
  tenant_id    = var.tenant_id
  object_id    = azurerm_user_assigned_identity.app.principal_id

  secret_permissions = ["Get", "List"]
  key_permissions    = ["Get", "List", "Sign", "Verify"]
}

# Every instance of this module declares the same environment name, so each one
# is a separate state entry pointing at a single ARM resource. That is tolerated
# for the services already in state, but new callers should pass
# container_app_environment_id instead: concurrent PUTs to one environment race
# and ARM rejects the losers with 409. Consolidating the existing callers needs a
# `terraform state mv`, so it is deliberately not done here.
resource "azurerm_container_app_environment" "main" {
  count = var.container_app_environment_id == "" ? 1 : 0

  name                = "cae-turksquare-${var.environment}-cu"
  resource_group_name = var.resource_group_name
  location            = var.location

  log_analytics_workspace_id = var.log_analytics_workspace_id
  infrastructure_subnet_id   = var.aca_subnet_id

  tags = local.tags

  lifecycle {
    ignore_changes = [
      infrastructure_resource_group_name,
    ]
  }
}

resource "azurerm_container_app" "main" {
  name                = "ca-${var.service_name}-${var.environment}"
  resource_group_name = var.resource_group_name

  container_app_environment_id = local.container_app_environment_id
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app.id]
  }

  # Workers (enable_ingress = false) have no listener. Declaring ingress for them
  # would leave the revision permanently unhealthy.
  #
  # The conditional dynamic blocks further down wrap their condition in
  # nonsensitive(). Comparing a sensitive variable yields a sensitive bool, and
  # Terraform 1.8 - the version CI pins - refuses to iterate a marked value in a
  # dynamic for_each. Only whether the URI is empty is unmasked; the URI itself
  # stays sensitive. Newer Terraform tolerates the mark, which is why this
  # passed locally and failed in CI.
  dynamic "ingress" {
    for_each = var.enable_ingress ? [1] : []
    content {
      external_enabled = var.expose_externally
      target_port      = var.container_port
      transport        = "auto"

      traffic_weight {
        latest_revision = true
        percentage      = 100
      }
    }
  }

  dynamic "dapr" {
    for_each = var.dapr_enabled ? { enabled = true } : {}
    content {
      app_id       = var.dapr_app_id != null ? var.dapr_app_id : var.service_name
      app_port     = var.dapr_app_port != null ? var.dapr_app_port : var.container_port
      app_protocol = var.dapr_app_protocol
    }
  }

  registry {
    server   = var.acr_login_server
    identity = azurerm_user_assigned_identity.app.id
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    container {
      name    = var.service_name
      image   = "${var.acr_login_server}/${var.image_repository}:${var.image_tag}"
      cpu     = var.cpu
      memory  = var.memory
      command = var.container_command
      args    = var.container_args

      env {
        name  = "NODE_ENV"
        value = "production"
      }

      env {
        name  = "AZURE_KEY_VAULT_URL"
        value = var.key_vault_uri
      }

      env {
        name  = "AZURE_TENANT_ID"
        value = var.tenant_id
      }

      env {
        name  = "DATABASE_URL"
        value = "postgresql://${var.postgres_admin_username}:${var.postgres_admin_password}@${var.postgres_fqdn}:5432/${var.database_name}?sslmode=require"
      }

      dynamic "env" {
        for_each = nonsensitive(var.servicebus_connection_string_secret_uri != "") ? [1] : []
        content {
          name        = "AZURE_SERVICE_BUS_CONNECTION_STRING"
          secret_name = "azure-service-bus-connection-string"
        }
      }

      dynamic "env" {
        for_each = nonsensitive(var.servicebus_connection_string_secret_uri == "") ? [1] : []
        content {
          name  = "AZURE_SERVICE_BUS_CONNECTION_STRING"
          value = var.servicebus_connection_string
        }
      }

      dynamic "env" {
        for_each = var.extra_env
        content {
          name  = env.value.name
          value = env.value.value
        }
      }

      dynamic "env" {
        for_each = local.secret_env_normalized
        iterator = secret_env
        content {
          name        = secret_env.value.env_name
          secret_name = secret_env.value.name
        }
      }

      dynamic "env" {
        for_each = nonsensitive(var.storage_account_key_secret_uri != "") ? [1] : []
        content {
          name        = "AZURE_STORAGE_ACCOUNT_KEY"
          secret_name = "storage-account-key"
        }
      }

    }
  }

  dynamic "secret" {
    for_each = nonsensitive(var.servicebus_connection_string_secret_uri != "") ? [1] : []
    content {
      name                = "azure-service-bus-connection-string"
      identity            = azurerm_user_assigned_identity.app.id
      key_vault_secret_id = var.servicebus_connection_string_secret_uri
    }
  }

  dynamic "secret" {
    for_each = nonsensitive(var.storage_account_key_secret_uri != "") ? [1] : []
    content {
      name                = "storage-account-key"
      identity            = azurerm_user_assigned_identity.app.id
      key_vault_secret_id = var.storage_account_key_secret_uri
    }
  }

  dynamic "secret" {
    for_each = local.secret_env_normalized
    iterator = secret_env
    content {
      name                = secret_env.value.name
      identity            = azurerm_user_assigned_identity.app.id
      key_vault_secret_id = "${var.key_vault_secret_uri}${secret_env.value.key_vault_secret_id}"
    }
  }

  tags = local.tags

  depends_on = [
    azurerm_role_assignment.acr_pull,
    azurerm_key_vault_access_policy.app
  ]

  lifecycle {
    ignore_changes = [
      workload_profile_name,
    ]
  }
}


