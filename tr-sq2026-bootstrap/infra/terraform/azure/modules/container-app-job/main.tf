terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.75"
    }
  }
}

# Schema migrations. The PostgreSQL flexible server has
# public_network_access_enabled = false and lives in a delegated subnet, so a
# GitHub runner cannot reach it. A manually triggered job in the same Container
# App environment can, and it runs the same image as the service so the schema
# and the code that depends on it are always from one commit.
#
# It is a job rather than a startup step in the service container because
# migrations must run exactly once per deploy, not once per replica.

locals {
  tags = {
    project     = "turksquare"
    environment = var.environment
    service     = var.job_name
    managed_by  = "terraform"
  }
}

resource "azurerm_user_assigned_identity" "job" {
  name                = "id-${var.job_name}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = local.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.job.principal_id
}

resource "azurerm_container_app_job" "main" {
  name                         = "caj-${var.job_name}-${var.environment}"
  resource_group_name          = var.resource_group_name
  location                     = var.location
  container_app_environment_id = var.container_app_environment_id

  # A failed migration must fail the deploy, not retry itself into a partially
  # applied schema: each migration file already runs in its own transaction.
  replica_timeout_in_seconds = var.timeout_seconds
  replica_retry_limit        = 0

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.job.id]
  }

  registry {
    server   = var.acr_login_server
    identity = azurerm_user_assigned_identity.job.id
  }

  manual_trigger_config {
    parallelism              = 1
    replica_completion_count = 1
  }

  template {
    container {
      name    = var.job_name
      image   = "${var.acr_login_server}/${var.image_repository}:${var.image_tag}"
      cpu     = 0.5
      memory  = "1Gi"
      command = var.command

      env {
        name  = "NODE_ENV"
        value = "production"
      }

      env {
        name  = "DATABASE_URL"
        value = "postgresql://${var.postgres_admin_username}:${var.postgres_admin_password}@${var.postgres_fqdn}:5432/${var.database_name}?sslmode=require"
      }
    }
  }

  tags = local.tags

  depends_on = [azurerm_role_assignment.acr_pull]
}
