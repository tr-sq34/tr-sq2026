terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.75"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
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

# --- Externally issued secrets -------------------------------------------
# Stripe issues these; Terraform cannot generate them. They are created with a
# placeholder and then set to the real value out of band, so ignore_changes is
# what keeps the next apply from resetting live payment credentials back to the
# placeholder. Without it, rotating the key in the portal silently breaks the
# next deploy instead of the deploy adopting it.

moved {
  from = azurerm_key_vault_secret.app["STRIPE-SECRET-KEY"]
  to   = azurerm_key_vault_secret.stripe_secret_key
}

moved {
  from = azurerm_key_vault_secret.app["STRIPE-WEBHOOK-SECRET"]
  to   = azurerm_key_vault_secret.stripe_webhook_secret
}

resource "azurerm_key_vault_secret" "stripe_secret_key" {
  name         = "STRIPE-SECRET-KEY"
  value        = var.stripe_secret_key_initial
  key_vault_id = azurerm_key_vault.main.id

  lifecycle {
    ignore_changes = [value]
  }

  depends_on = [azurerm_key_vault_access_policy.deployer]
}

resource "azurerm_key_vault_secret" "stripe_webhook_secret" {
  name         = "STRIPE-WEBHOOK-SECRET"
  value        = var.stripe_webhook_secret_initial
  key_vault_id = azurerm_key_vault.main.id

  lifecycle {
    ignore_changes = [value]
  }

  depends_on = [azurerm_key_vault_access_policy.deployer]
}

# --- Service-to-service secrets -----------------------------------------
# Same reasoning as the Matrix block below: a value committed to key_vault_secrets
# is a value published in a git repository. Both of these were placeholders there.

# Authorises internal calls between services — the auction hand-off from
# community-service to the messaging gateway is the only current caller. Holding
# it means being able to open a conversation between any two users.
resource "random_password" "internal_service_token" {
  length  = 48
  special = false
}

# Keys the HMAC over email verification codes, so it decides whether a code is
# accepted. Replacing it invalidates codes that are already in users' inboxes;
# they are valid for minutes, so the cost is a handful of resend requests.
resource "random_password" "email_code_hmac_secret" {
  length  = 48
  special = false
}

moved {
  from = azurerm_key_vault_secret.app["INTERNAL-SERVICE-TOKEN"]
  to   = azurerm_key_vault_secret.internal_service_token
}

moved {
  from = azurerm_key_vault_secret.app["EMAIL-CODE-HMAC-SECRET"]
  to   = azurerm_key_vault_secret.email_code_hmac_secret
}

# Neither carries ignore_changes: both are replacing a value that was committed
# to the repository and must therefore actually change on this apply. Once
# written, random_password keeps its result in state, so later applies are
# no-ops. To rotate deliberately, taint the random_password and redeploy the
# consuming services together.
resource "azurerm_key_vault_secret" "internal_service_token" {
  name         = "INTERNAL-SERVICE-TOKEN"
  value        = random_password.internal_service_token.result
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault_access_policy.deployer]
}

resource "azurerm_key_vault_secret" "email_code_hmac_secret" {
  name         = "EMAIL-CODE-HMAC-SECRET"
  value        = random_password.email_code_hmac_secret.result
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault_access_policy.deployer]
}

# --- Gatework console secrets --------------------------------------------

# Encrypts the operator session cookie. Knowing it means being able to forge a
# session for any role, including owner, so it is generated rather than listed
# in key_vault_secrets. Rotating it signs every operator out; nothing else.
resource "random_password" "gatework_session_secret" {
  length  = 48
  special = false
}

resource "azurerm_key_vault_secret" "gatework_session_secret" {
  name         = "GATEWORK-SESSION-SECRET"
  value        = random_password.gatework_session_secret.result
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault_access_policy.deployer]
}

# Cloudflare issues this one, so Terraform creates it as a placeholder and the
# real token is set out of band. ignore_changes is what stops the next apply
# from resetting a working tunnel back to the placeholder. Until it is set, the
# console runs but is unreachable — which is the safe direction to fail in.
resource "azurerm_key_vault_secret" "cloudflare_tunnel_token" {
  name         = "CLOUDFLARE-TUNNEL-TOKEN"
  value        = var.cloudflare_tunnel_token_initial
  key_vault_id = azurerm_key_vault.main.id

  lifecycle {
    ignore_changes = [value]
  }

  depends_on = [azurerm_key_vault_access_policy.deployer]
}

# --- Matrix secrets ------------------------------------------------------
# These four are generated instead of being listed in key_vault_secrets. That
# map lives in environments/prod/main.tf, so anything in it is a literal in a
# git repository — and each of these values is enough on its own to impersonate
# any user on the homeserver.

# The token the gateway presents to Synapse. It authorises impersonation of
# every user in the application service namespace.
resource "random_password" "matrix_appservice_token" {
  length  = 48
  special = false
}

# Synapse presents this one when calling the application service back. It must
# never equal the as_token; Synapse rejects a registration file where they match.
resource "random_password" "matrix_appservice_hs_token" {
  length  = 48
  special = false
}

# Signs every access token Synapse issues. Knowing it means being able to mint a
# valid token for any account.
resource "random_password" "matrix_macaroon" {
  length  = 48
  special = false
}

resource "random_password" "matrix_form" {
  length  = 48
  special = false
}

moved {
  from = azurerm_key_vault_secret.app["MATRIX-APPSERVICE-TOKEN"]
  to   = azurerm_key_vault_secret.matrix_appservice_token
}

moved {
  from = azurerm_key_vault_secret.app["MATRIX-APPSERVICE-HS-TOKEN"]
  to   = azurerm_key_vault_secret.matrix_appservice_hs_token
}

# No ignore_changes on the two tokens below: they previously held a committed
# `change_me_...` placeholder, and this apply has to replace it. Both consumers
# read the secret at container start, so they stay in agreement until the next
# deploy restarts them together.
resource "azurerm_key_vault_secret" "matrix_appservice_token" {
  name         = "MATRIX-APPSERVICE-TOKEN"
  value        = random_password.matrix_appservice_token.result
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault_access_policy.deployer]
}

resource "azurerm_key_vault_secret" "matrix_appservice_hs_token" {
  name         = "MATRIX-APPSERVICE-HS-TOKEN"
  value        = random_password.matrix_appservice_hs_token.result
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault_access_policy.deployer]
}

# These two are pinned to their first value. Changing macaroon_secret_key
# invalidates every access token Synapse has ever issued, logging out every
# device on the platform, so it must survive losing and rebuilding the state
# file.
resource "azurerm_key_vault_secret" "matrix_macaroon_secret" {
  name         = "MATRIX-MACAROON-SECRET"
  value        = random_password.matrix_macaroon.result
  key_vault_id = azurerm_key_vault.main.id

  lifecycle {
    ignore_changes = [value]
  }

  depends_on = [azurerm_key_vault_access_policy.deployer]
}

resource "azurerm_key_vault_secret" "matrix_form_secret" {
  name         = "MATRIX-FORM-SECRET"
  value        = random_password.matrix_form.result
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

  default_message_ttl   = "P14D"
  lock_duration         = "PT5M"
  max_size_in_megabytes = 1024
}

# Identity publishes user upserts here and Community publishes block edges; the
# messaging projection worker is the only consumer. It is a separate queue from
# community-profile-projection so a poisoned community event cannot stall the
# projection that gates every direct message.
resource "azurerm_servicebus_queue" "messaging_projection" {
  name         = "messaging-projection"
  namespace_id = azurerm_servicebus_namespace.main.id

  default_message_ttl   = "P14D"
  lock_duration         = "PT5M"
  max_size_in_megabytes = 1024

  # Producers set message_id to the outbox row id, so a crash between the send
  # and the published_at update is collapsed by the broker instead of being
  # re-delivered. The consumer is idempotent regardless; this is defence in depth.
  requires_duplicate_detection            = true
  duplicate_detection_history_time_window = "PT1H"

  # A message that fails ten times is a poison message, not a transient fault.
  # Dead-lettering it keeps the queue draining while the failure stays visible.
  max_delivery_count                   = 10
  dead_lettering_on_message_expiration = true
}

resource "azurerm_servicebus_queue" "verification_capability" {
  name         = "verification-capability"
  namespace_id = azurerm_servicebus_namespace.main.id

  default_message_ttl   = "P14D"
  lock_duration         = "PT5M"
  max_size_in_megabytes = 1024
}

resource "azurerm_servicebus_queue" "document_scan" {
  name         = "document-scan"
  namespace_id = azurerm_servicebus_namespace.main.id

  default_message_ttl   = "P14D"
  lock_duration         = "PT5M"
  max_size_in_megabytes = 1024
}

resource "azurerm_storage_account" "media" {
  name                            = "stturksquaremedia${var.environment}cu"
  resource_group_name             = azurerm_resource_group.turksquare.name
  location                        = azurerm_resource_group.turksquare.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
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

# A flexible server is created with only `postgres` and the template databases.
# Every service's DATABASE_URL names one of these, so without them each service
# fails at the first connection with `database "identity" does not exist` — and
# the migration jobs never get far enough to create anything.
#
# If a database was already created by hand, `terraform apply` will report that
# the resource already exists; import it rather than renaming it:
#   terraform import 'module.shared.azurerm_postgresql_flexible_server_database.service["identity"]' <server_id>/databases/identity
resource "azurerm_postgresql_flexible_server_database" "service" {
  for_each = toset(["identity", "community", "messaging", "verification"])

  name      = each.key
  server_id = azurerm_postgresql_flexible_server.main.id
  charset   = "UTF8"
  collation = "en_US.utf8"

  # Both attributes above are ForceNew, and dropping a database takes every row
  # in it with no confirmation step.
  lifecycle {
    prevent_destroy = true
  }
}

# Synapse refuses to start against a database whose collation or ctype is not
# `C`: PostgreSQL sorts differently under a locale-aware collation, and Synapse's
# state resolution depends on byte ordering. This cannot be changed after
# creation, so it is deliberately not part of the loop above.
resource "azurerm_postgresql_flexible_server_database" "matrix" {
  name      = "matrix"
  server_id = azurerm_postgresql_flexible_server.main.id
  charset   = "UTF8"
  collation = "C"

  lifecycle {
    prevent_destroy = true
  }
}
