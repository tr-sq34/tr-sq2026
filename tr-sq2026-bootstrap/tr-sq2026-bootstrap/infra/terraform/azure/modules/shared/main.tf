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
  base_tags = {
    project     = "turksquare"
    environment = var.environment
    managed_by  = "terraform"
  }
}

resource "azurerm_resource_group" "turksquare" {
  name     = "rg-turksquare-${var.environment}-${var.location}"
  location = var.location
  tags     = local.base_tags
}

resource "azurerm_virtual_network" "main" {
  name                = "vnet-turksquare-${var.environment}"
  location            = azurerm_resource_group.turksquare.location
  resource_group_name = azurerm_resource_group.turksquare.name
  address_space       = var.vnet_address_space
  tags                = local.base_tags
}

resource "azurerm_subnet" "aca" {
  name                 = "snet-aca"
  resource_group_name  = azurerm_resource_group.turksquare.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = var.aca_subnet_prefix

  delegation {
    name = "aca-delegation"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "snet-private-endpoints"
  resource_group_name  = azurerm_resource_group.turksquare.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = var.private_endpoint_subnet_prefix
}

resource "azurerm_subnet" "postgres" {
  name                 = "snet-postgres"
  resource_group_name  = azurerm_resource_group.turksquare.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = var.postgres_subnet_prefix

  delegation {
    name = "postgres-delegation"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-turksquare-${var.environment}"
  location            = azurerm_resource_group.turksquare.location
  resource_group_name = azurerm_resource_group.turksquare.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.base_tags
}

resource "azurerm_application_insights" "main" {
  name                = "appi-turksquare-${var.environment}"
  location            = azurerm_resource_group.turksquare.location
  resource_group_name = azurerm_resource_group.turksquare.name
  application_type    = "Node.JS"
  workspace_id        = azurerm_log_analytics_workspace.main.id
  tags                = local.base_tags
}

resource "azurerm_container_registry" "main" {
  name                = "crturksquare${var.environment}cu"
  resource_group_name = azurerm_resource_group.turksquare.name
  location            = azurerm_resource_group.turksquare.location
  sku                 = var.acr_sku
  admin_enabled       = false
  tags                = local.base_tags
}

resource "azurerm_key_vault" "main" {
  name                = "kv-turksquare-${var.environment}-cu"
  location            = azurerm_resource_group.turksquare.location
  resource_group_name = azurerm_resource_group.turksquare.name
  tenant_id           = var.tenant_id
  sku_name            = "standard"

  public_network_access_enabled = true
  purge_protection_enabled      = true
  soft_delete_retention_days    = 7

  tags = local.base_tags
}

resource "azurerm_key_vault_access_policy" "deployer" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = var.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = ["Get", "List", "Set", "Delete", "Purge", "Recover"]
  key_permissions    = ["Get", "List", "Create", "Delete", "Purge", "Recover", "Sign", "Verify", "GetRotationPolicy"]

  depends_on = [azurerm_key_vault.main]
}

resource "azurerm_key_vault_secret" "app" {
  for_each = nonsensitive(var.key_vault_secrets)

  name         = each.key
  value        = each.value
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault_access_policy.deployer]
}

moved {
  from = azurerm_key_vault_secret.app["RESEND-API-KEY"]
  to   = azurerm_key_vault_secret.resend_api_key
}

resource "azurerm_key_vault_secret" "resend_api_key" {
  name         = "RESEND-API-KEY"
  value        = var.resend_api_key_initial
  key_vault_id = azurerm_key_vault.main.id

  lifecycle {
    ignore_changes = [value]
  }

  depends_on = [azurerm_key_vault_access_policy.deployer]
}

resource "azurerm_key_vault_secret" "jwt_secret" {
  name         = "JWT-SECRET"
  value        = var.jwt_secret_initial
  key_vault_id = azurerm_key_vault.main.id

  lifecycle {
    ignore_changes = [value]
  }

  depends_on = [azurerm_key_vault_access_policy.deployer]
}

resource "azurerm_key_vault_key" "jwt_signing" {
  name         = "turksquare-identity-jwt-signing"
  key_vault_id = azurerm_key_vault.main.id
  key_type     = "RSA"
  key_size     = 2048
  key_opts     = ["sign", "verify"]

  tags = local.base_tags

  depends_on = [azurerm_key_vault_access_policy.deployer]

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [key_size, key_type]
  }
}

resource "azurerm_servicebus_namespace" "main" {
  name                = "sb-turksquare-${var.environment}-cu"
  location            = azurerm_resource_group.turksquare.location
  resource_group_name = azurerm_resource_group.turksquare.name
  sku                 = "Standard"
  minimum_tls_version = "1.2"
  tags                = local.base_tags
}

resource "azurerm_servicebus_namespace_authorization_rule" "root" {
  name         = "terraform-managed-access"
  namespace_id = azurerm_servicebus_namespace.main.id

  listen = true
  send   = true
  manage = true
}

resource "azurerm_key_vault_secret" "service_bus_connection_string" {
  name         = "SERVICE-BUS-CONNECTION-STRING"
  value        = azurerm_servicebus_namespace_authorization_rule.root.primary_connection_string
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault_access_policy.deployer]

  lifecycle {
    ignore_changes = [value]
  }
}

resource "azurerm_servicebus_queue" "community_profile_projection" {
  name         = "community-profile-projection"
  namespace_id = azurerm_servicebus_namespace.main.id

  default_message_ttl = "P14D"
  lock_duration       = "PT5M"
  max_size_in_megabytes = 1024
}

resource "azurerm_servicebus_queue" "verification_capability" {
  name         = "verification-capability"
  namespace_id = azurerm_servicebus_namespace.main.id

  default_message_ttl = "P14D"
  lock_duration       = "PT5M"
  max_size_in_megabytes = 1024
}

resource "azurerm_servicebus_queue" "document_scan" {
  name         = "document-scan"
  namespace_id = azurerm_servicebus_namespace.main.id

  default_message_ttl = "P14D"
  lock_duration       = "PT5M"
  max_size_in_megabytes = 1024
}

resource "azurerm_storage_account" "media" {
  name                     = "stturksquaremedia${var.environment}cu"
  resource_group_name      = azurerm_resource_group.turksquare.name
  location                 = azurerm_resource_group.turksquare.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  allow_nested_items_to_be_public = false

  tags = local.base_tags
}

resource "azurerm_storage_container" "community_media" {
  name                  = "community-media"
  storage_account_name  = azurerm_storage_account.media.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "verification" {
  name                  = "verification"
  storage_account_name  = azurerm_storage_account.media.name
  container_access_type = "private"
}

resource "azurerm_key_vault_secret" "storage_account_key" {
  name         = "STORAGE-ACCOUNT-KEY"
  value        = azurerm_storage_account.media.primary_access_key
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault_access_policy.deployer]

  lifecycle {
    ignore_changes = [value]
  }
}

resource "azurerm_key_vault_secret" "storage_account_name" {
  name         = "STORAGE-ACCOUNT-NAME"
  value        = azurerm_storage_account.media.name
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault_access_policy.deployer]
}

resource "azurerm_private_dns_zone" "postgres" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.turksquare.name
  tags                = local.base_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "postgres-link-${var.environment}"
  resource_group_name   = azurerm_resource_group.turksquare.name
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.main.id
}

resource "azurerm_postgresql_flexible_server" "main" {
  name                = "psql-turksquare-${var.environment}-cu"
  resource_group_name = azurerm_resource_group.turksquare.name
  location            = azurerm_resource_group.turksquare.location

  version               = "16"
  sku_name              = var.postgres_sku
  storage_mb            = var.postgres_storage_mb
  backup_retention_days = 7

  administrator_login    = var.postgres_admin_username
  administrator_password = var.postgres_admin_password

  delegated_subnet_id = azurerm_subnet.postgres.id
  private_dns_zone_id = azurerm_private_dns_zone.postgres.id

  public_network_access_enabled = false

  tags = local.base_tags

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [zone]
  }
}

resource "azurerm_postgresql_flexible_server_configuration" "extensions" {
  name      = "azure.extensions"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "POSTGIS"
}
