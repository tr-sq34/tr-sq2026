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

resource "azurerm_container_app_environment" "main" {
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

  container_app_environment_id = azurerm_container_app_environment.main.id
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app.id]
  }

  ingress {
    external_enabled = var.expose_externally
    target_port      = var.container_port
    transport        = "auto"

    traffic_weight {
      latest_revision = true
      percentage      = 100
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
      name   = var.service_name
      image  = "${var.acr_login_server}/${var.image_repository}:${var.image_tag}"
      cpu    = var.cpu
      memory = var.memory

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
        for_each = var.servicebus_connection_string_secret_uri != "" ? { enabled = true } : {}
        content {
          name        = "AZURE_SERVICE_BUS_CONNECTION_STRING"
          secret_name = "azure-service-bus-connection-string"
        }
      }

            dynamic "env" {
              for_each = var.servicebus_connection_string_secret_uri == "" ? { enabled = true } : {}
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
        for_each = var.storage_account_key_secret_uri != "" ? { enabled = true } : {}
        content {
          name        = "AZURE_STORAGE_ACCOUNT_KEY"
          secret_name = "storage-account-key"
        }
      }

    }
  }

    dynamic "secret" {
    for_each = var.servicebus_connection_string_secret_uri != "" ? { enabled = true } : {}
    content {
      name                = "azure-service-bus-connection-string"
      identity            = azurerm_user_assigned_identity.app.id
      key_vault_secret_id = var.servicebus_connection_string_secret_uri
    }
  }

  dynamic "secret" {
    for_each = var.storage_account_key_secret_uri != "" ? { enabled = true } : {}
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
