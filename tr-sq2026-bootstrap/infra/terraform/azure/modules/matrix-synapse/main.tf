terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.75"
    }
  }
}

locals {
  tags = {
    project     = "turksquare"
    environment = var.environment
    service     = "matrix-synapse"
    managed_by  = "terraform"
  }

  name = "ca-matrix-synapse-${var.environment}"
}

# /data holds the three pieces of state a container cannot regenerate: the
# signing key, the media store, and the rendered config. It is a separate share
# from the media storage containers so that a lifecycle policy on user uploads
# can never reach the signing key.
resource "azurerm_storage_share" "data" {
  name                 = "synapse-data"
  storage_account_name = var.storage_account_name
  quota                = var.data_share_quota_gb

  # Deleting this share destroys the signing key, which invalidates the
  # signature on every event the homeserver has ever sent. There is no recovery
  # other than restoring the file.
  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_container_app_environment_storage" "data" {
  name                         = "synapse-data"
  container_app_environment_id = var.container_app_environment_id
  account_name                 = var.storage_account_name
  share_name                   = azurerm_storage_share.data.name
  access_key                   = var.storage_account_key
  access_mode                  = "ReadWrite"
}

resource "azurerm_user_assigned_identity" "app" {
  name                = "id-matrix-synapse-${var.environment}"
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
}

resource "azurerm_container_app" "synapse" {
  name                = local.name
  resource_group_name = var.resource_group_name

  container_app_environment_id = var.container_app_environment_id
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app.id]
  }

  # No public ingress and no federation listener. The client API is reachable
  # only from inside the container app environment, which is where the messaging
  # gateway runs; the mobile app never talks to Synapse directly.
  ingress {
    external_enabled           = false
    target_port                = 8008
    transport                  = "auto"
    allow_insecure_connections = false

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
    # A Synapse monolith is a single master process: it owns the event stream
    # writers and the background jobs, and a second copy would run them twice.
    # Scaling this deployment means splitting Synapse into worker processes with
    # Redis replication, not raising this number.
    min_replicas = 1
    max_replicas = 1

    volume {
      name         = "synapse-data"
      storage_name = azurerm_container_app_environment_storage.data.name
      storage_type = "AzureFile"
    }

    container {
      name   = "synapse"
      image  = "${var.acr_login_server}/${var.image_repository}:${var.image_tag}"
      cpu    = var.cpu
      memory = var.memory

      volume_mounts {
        name = "synapse-data"
        path = "/data"
      }

      env {
        name  = "SYNAPSE_DATA_DIR"
        value = "/data"
      }

      env {
        name  = "MATRIX_SERVER_NAME"
        value = var.server_name
      }

      env {
        name  = "MATRIX_DB_HOST"
        value = var.postgres_fqdn
      }

      env {
        name  = "MATRIX_DB_NAME"
        value = var.database_name
      }

      env {
        name  = "MATRIX_DB_USERNAME"
        value = var.postgres_admin_username
      }

      env {
        name        = "MATRIX_DB_PASSWORD"
        secret_name = "matrix-db-password"
      }

      env {
        name        = "MATRIX_MACAROON_SECRET"
        secret_name = "matrix-macaroon-secret"
      }

      env {
        name        = "MATRIX_FORM_SECRET"
        secret_name = "matrix-form-secret"
      }

      env {
        name        = "MATRIX_APPSERVICE_AS_TOKEN"
        secret_name = "matrix-appservice-as-token"
      }

      env {
        name        = "MATRIX_APPSERVICE_HS_TOKEN"
        secret_name = "matrix-appservice-hs-token"
      }

      # First boot generates the signing key and creates roughly ninety schema
      # objects before the port opens. Without a startup probe the platform
      # would apply the liveness probe immediately and restart the container
      # mid-migration.
      startup_probe {
        transport               = "HTTP"
        port                    = 8008
        path                    = "/health"
        interval_seconds        = 30
        failure_count_threshold = 10
      }

      liveness_probe {
        transport               = "HTTP"
        port                    = 8008
        path                    = "/health"
        interval_seconds        = 30
        failure_count_threshold = 3
      }

      readiness_probe {
        transport               = "HTTP"
        port                    = 8008
        path                    = "/health"
        interval_seconds        = 10
        failure_count_threshold = 3
      }
    }
  }

  secret {
    name  = "matrix-db-password"
    value = var.postgres_admin_password
  }

  secret {
    name                = "matrix-macaroon-secret"
    identity            = azurerm_user_assigned_identity.app.id
    key_vault_secret_id = "${var.key_vault_secret_uri}MATRIX-MACAROON-SECRET"
  }

  secret {
    name                = "matrix-form-secret"
    identity            = azurerm_user_assigned_identity.app.id
    key_vault_secret_id = "${var.key_vault_secret_uri}MATRIX-FORM-SECRET"
  }

  secret {
    name                = "matrix-appservice-as-token"
    identity            = azurerm_user_assigned_identity.app.id
    key_vault_secret_id = "${var.key_vault_secret_uri}${var.appservice_as_token_secret_name}"
  }

  secret {
    name                = "matrix-appservice-hs-token"
    identity            = azurerm_user_assigned_identity.app.id
    key_vault_secret_id = "${var.key_vault_secret_uri}${var.appservice_hs_token_secret_name}"
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
