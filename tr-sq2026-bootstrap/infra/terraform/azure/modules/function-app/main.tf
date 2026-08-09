terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.75"
    }
  }
}

data "azurerm_client_config" "current" {}

locals {
  deployer_object_id = var.deployer_object_id != "" ? var.deployer_object_id : data.azurerm_client_config.current.object_id
  tags = {
    project     = "turksquare"
    environment = var.environment
    service     = var.function_name
    managed_by  = "terraform"
  }

  sanitized_name       = replace(lower(var.function_name), "/[^a-z0-9]/", "")
  short_name           = substr(local.sanitized_name, 0, 16)
  storage_account_name = substr("st${local.short_name}${substr(var.environment, 0, 4)}cu", 0, 24)
}

resource "azurerm_user_assigned_identity" "app" {
  name                = "id-${var.function_name}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = local.tags
}

resource "azurerm_storage_account" "app" {
  name                     = local.storage_account_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  tags                     = local.tags
}

resource "azurerm_service_plan" "app" {
  name                = "asp-${var.function_name}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Linux"
  sku_name            = var.service_plan_sku
  tags                = local.tags
}

resource "azurerm_role_assignment" "storage_blob_data_owner" {
  scope                = azurerm_storage_account.app.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}

resource "azurerm_role_assignment" "storage_account_contributor" {
  scope                = azurerm_storage_account.app.id
  role_definition_name = "Storage Account Contributor"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}

resource "azurerm_role_assignment" "deployer_storage_blob_data_contributor" {
  count = local.deployer_object_id != "" ? 1 : 0

  scope                = azurerm_storage_account.app.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = local.deployer_object_id
}

resource "azurerm_key_vault_access_policy" "function" {
  count = var.key_vault_id != "" ? 1 : 0

  key_vault_id = var.key_vault_id
  tenant_id    = var.tenant_id
  object_id    = azurerm_user_assigned_identity.app.principal_id

  secret_permissions = ["Get", "List"]
}

resource "azurerm_linux_function_app" "main" {
  name                = "func-${var.function_name}-${var.environment}-cu"
  resource_group_name = var.resource_group_name
  location            = var.location

  storage_account_name          = azurerm_storage_account.app.name
  storage_uses_managed_identity = true
  service_plan_id               = azurerm_service_plan.app.id

  # Key Vault references in app_settings require an explicit user-assigned
  # identity when the app uses UserAssigned identity type.
  key_vault_reference_identity_id = azurerm_user_assigned_identity.app.id

  site_config {
    application_insights_connection_string = var.application_insights_connection_string

    application_stack {
      node_version = "20"
    }

    dynamic "cors" {
      for_each = length(var.cors_allowed_origins) > 0 ? toset(["enabled"]) : toset([])
      content {
        allowed_origins = var.cors_allowed_origins
      }
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app.id]
  }

  app_settings = merge(
    {
      AZURE_CLIENT_ID              = azurerm_user_assigned_identity.app.client_id
      FUNCTIONS_EXTENSION_VERSION  = "~4"
      FUNCTIONS_WORKER_RUNTIME     = "node"
      WEBSITE_NODE_DEFAULT_VERSION = "~20"
      AzureWebJobsFeatureFlags     = "EnableWorkerIndexing"
      WEBSITE_RUN_FROM_PACKAGE     = "1"
    },
    var.app_settings,
    var.key_vault_secret_references
  )

  lifecycle {
    ignore_changes = [
      app_settings["WEBSITE_RUN_FROM_PACKAGE"],
    ]
  }

  tags = local.tags

  depends_on = [
    azurerm_role_assignment.storage_blob_data_owner,
    azurerm_role_assignment.storage_account_contributor,
    azurerm_key_vault_access_policy.function
  ]
}


