module "shared" {
  source = "../../modules/shared"

  environment     = var.environment
  location        = var.location
  tenant_id       = var.tenant_id
  subscription_id = var.subscription_id

  vnet_address_space             = var.vnet_address_space
  aca_subnet_prefix              = var.aca_subnet_prefix
  private_endpoint_subnet_prefix = var.private_endpoint_subnet_prefix

  acr_sku                 = var.acr_sku
  postgres_sku            = var.postgres_sku
  postgres_storage_mb     = var.postgres_storage_mb
  postgres_admin_username = var.postgres_admin_username
  postgres_admin_password = var.postgres_admin_password

  key_vault_secrets = {
    "JWT-ISSUER"                    = "https://api.turksquare.com"
    "JWT-AUDIENCE"                  = "https://api.turksquare.com"
    "JWT-KEY-ID"                    = "turksquare-identity-jwt-signing"
    "EMAIL-CODE-HMAC-SECRET"        = "T-NI8OM5AGC_kCbzoAqEU_9470eLMcXwTepeLyiQKtk"
    "WEBAUTHN-RP-ID"                = "turksquare.com"
    "WEBAUTHN-ORIGIN"               = "https://turksquare.com"
    "EMAIL-FROM"                    = "noreply@turksquare.com"
    "AUTH-ACTION-BASE-URL"          = "https://api.turksquare.com/v1/auth/action"
    "EMAIL-RELAY-FUNCTION-NAME"     = "https://func-email-relay-prod-cu.azurewebsites.net"
    "EMAIL-DELIVERY-WEBHOOK"        = "https://func-email-relay-prod-cu.azurewebsites.net/api/emailRelay"
    "PASSWORD-SAFETY-FUNCTION-NAME" = "https://func-password-breach-check-prod-cu.azurewebsites.net"
    "PWNED-PASSWORDS-RANGE-URL"     = "https://func-password-breach-check-prod-cu.azurewebsites.net/api/passwordBreachCheck"
    "GATEWORK-COMMUNITY-AUDIENCE"   = "https://community-api.turksquare.com"
    "VERIFICATION-RETURN-URL"       = "https://turksquare.com/verification/callback"
    "STRIPE-SECRET-KEY"             = "sk_change_me_stripe_secret_key"
    "STRIPE-WEBHOOK-SECRET"         = "whsec_change_me_stripe_webhook_secret"
    "MATRIX-BASE-URL"               = "https://matrix-api.turksquare.com"
    "MATRIX-APPSERVICE-TOKEN"         = "change_me_matrix_appservice_token"
    "MATRIX-SERVER-NAME"              = "turksquare.com"
    "INTERNAL-SERVICE-TOKEN"          = "change_me_internal_service_token"
  }
  resend_api_key_initial = var.resend_api_key_initial
  jwt_secret_initial     = var.jwt_secret_initial
}

module "identity_container_app" {
  source = "../../modules/container-app"

  service_name = "identity"
  environment  = var.environment
  location     = var.location
  tenant_id    = var.tenant_id

  resource_group_name        = module.shared.resource_group_name
  acr_id                     = module.shared.acr_id
  acr_login_server           = module.shared.acr_login_server
  key_vault_id               = module.shared.key_vault_id
  key_vault_uri              = module.shared.key_vault_uri
  key_vault_secret_uri       = module.shared.key_vault_secret_uri
  log_analytics_workspace_id = module.shared.log_analytics_workspace_id
  aca_subnet_id              = module.shared.aca_subnet_id

  image_repository = "turksquare/identity-service"
  image_tag        = var.identity_image_tag
  container_port   = 8080

  postgres_admin_username = var.postgres_admin_username
  postgres_admin_password = var.postgres_admin_password
  postgres_fqdn           = module.shared.postgresql_server_fqdn
  database_name           = "identity"

  servicebus_connection_string            = module.shared.servicebus_connection_string
  servicebus_connection_string_secret_uri = module.shared.servicebus_connection_string_secret_uri

  secret_env = [
    { name = "JWT-ISSUER", key_vault_secret_id = "JWT-ISSUER", env_name = "JWT_ISSUER" },
    { name = "JWT-AUDIENCE", key_vault_secret_id = "JWT-AUDIENCE", env_name = "JWT_AUDIENCE" },
    { name = "JWT-KEY-ID", key_vault_secret_id = "JWT-KEY-ID", env_name = "JWT_KEY_ID" },
    { name = "EMAIL-CODE-HMAC-SECRET", key_vault_secret_id = "EMAIL-CODE-HMAC-SECRET", env_name = "EMAIL_CODE_HMAC_SECRET" },
    { name = "WEBAUTHN-RP-ID", key_vault_secret_id = "WEBAUTHN-RP-ID", env_name = "WEBAUTHN_RP_ID" },
    { name = "WEBAUTHN-ORIGIN", key_vault_secret_id = "WEBAUTHN-ORIGIN", env_name = "WEBAUTHN_ORIGIN" },
    { name = "EMAIL-FROM", key_vault_secret_id = "EMAIL-FROM", env_name = "EMAIL_FROM" },
    { name = "AUTH-ACTION-BASE-URL", key_vault_secret_id = "AUTH-ACTION-BASE-URL", env_name = "AUTH_ACTION_BASE_URL" },
    { name = "EMAIL-RELAY-FUNCTION-NAME", key_vault_secret_id = "EMAIL-RELAY-FUNCTION-NAME", env_name = "EMAIL_RELAY_FUNCTION_NAME" },
    { name = "EMAIL-DELIVERY-WEBHOOK", key_vault_secret_id = "EMAIL-DELIVERY-WEBHOOK", env_name = "EMAIL_DELIVERY_WEBHOOK" },
    { name = "PASSWORD-SAFETY-FUNCTION-NAME", key_vault_secret_id = "PASSWORD-SAFETY-FUNCTION-NAME", env_name = "PASSWORD_SAFETY_FUNCTION_NAME" },
    { name = "PWNED-PASSWORDS-RANGE-URL", key_vault_secret_id = "PWNED-PASSWORDS-RANGE-URL", env_name = "PWNED_PASSWORDS_RANGE_URL" },
    { name = "GATEWORK-COMMUNITY-AUDIENCE", key_vault_secret_id = "GATEWORK-COMMUNITY-AUDIENCE", env_name = "GATEWORK_COMMUNITY_AUDIENCE" }
  ]

  extra_env = [
    {
      name  = "GATEWORK_ALLOWED_DOMAIN"
      value = "turksquare.app"
    },
    {
      name  = "AZURE_JWT_SIGNING_KEY_NAME"
      value = "turksquare-identity-jwt-signing"
    },
    {
      name  = "AZURE_COMMUNITY_PROFILE_QUEUE_NAME"
      value = module.shared.community_profile_projection_queue_name
    }
  ]
}

module "verification_vault_container_app" {
  source = "../../modules/container-app"

  service_name = "verification-vault"
  environment  = var.environment
  location     = var.location
  tenant_id    = var.tenant_id

  resource_group_name        = module.shared.resource_group_name
  acr_id                     = module.shared.acr_id
  acr_login_server           = module.shared.acr_login_server
  key_vault_id               = module.shared.key_vault_id
  key_vault_uri              = module.shared.key_vault_uri
  key_vault_secret_uri       = module.shared.key_vault_secret_uri
  log_analytics_workspace_id = module.shared.log_analytics_workspace_id
  aca_subnet_id              = module.shared.aca_subnet_id

  image_repository = "turksquare/verification-vault-service"
  image_tag        = var.verification_vault_image_tag
  container_port   = 8082

  postgres_admin_username = var.postgres_admin_username
  postgres_admin_password = var.postgres_admin_password
  postgres_fqdn           = module.shared.postgresql_server_fqdn
  database_name           = "verification"

  servicebus_connection_string            = module.shared.servicebus_connection_string
  servicebus_connection_string_secret_uri = module.shared.servicebus_connection_string_secret_uri

  secret_env = [
    { name = "STRIPE-SECRET-KEY", key_vault_secret_id = "STRIPE-SECRET-KEY", env_name = "STRIPE_SECRET_KEY" },
    { name = "STRIPE-WEBHOOK-SECRET", key_vault_secret_id = "STRIPE-WEBHOOK-SECRET", env_name = "STRIPE_WEBHOOK_SECRET" },
    { name = "VERIFICATION-RETURN-URL", key_vault_secret_id = "VERIFICATION-RETURN-URL", env_name = "VERIFICATION_RETURN_URL" }
  ]

  extra_env = [
    {
      name  = "AZURE_JWT_SIGNING_KEY_NAME"
      value = "turksquare-identity-jwt-signing"
    },
    {
      name  = "AZURE_VERIFICATION_CAPABILITY_QUEUE_NAME"
      value = module.shared.verification_capability_queue_name
    }
  ]
}

module "community_container_app" {
  source = "../../modules/container-app"

  service_name = "community"
  environment  = var.environment
  location     = var.location
  tenant_id    = var.tenant_id

  resource_group_name        = module.shared.resource_group_name
  acr_id                     = module.shared.acr_id
  acr_login_server           = module.shared.acr_login_server
  key_vault_id               = module.shared.key_vault_id
  key_vault_uri              = module.shared.key_vault_uri
  key_vault_secret_uri       = module.shared.key_vault_secret_uri
  log_analytics_workspace_id = module.shared.log_analytics_workspace_id
  aca_subnet_id              = module.shared.aca_subnet_id

  image_repository = "turksquare/community-service"
  image_tag        = var.community_image_tag
  container_port   = 8080

  postgres_admin_username = var.postgres_admin_username
  postgres_admin_password = var.postgres_admin_password
  postgres_fqdn           = module.shared.postgresql_server_fqdn
  database_name           = "community"

  servicebus_connection_string            = module.shared.servicebus_connection_string
  servicebus_connection_string_secret_uri = module.shared.servicebus_connection_string_secret_uri
  storage_account_key_secret_uri        = "${module.shared.key_vault_secret_uri}STORAGE-ACCOUNT-KEY"

  secret_env = [
    { name = "STRIPE-SECRET-KEY", key_vault_secret_id = "STRIPE-SECRET-KEY", env_name = "STRIPE_SECRET_KEY" }
  ]

  extra_env = [
    {
      name  = "AZURE_JWT_SIGNING_KEY_NAME"
      value = "turksquare-identity-jwt-signing"
    },
    {
      name  = "AZURE_STORAGE_ACCOUNT_NAME"
      value = module.shared.storage_account_name
    },
    {
      name  = "AZURE_MEDIA_CONTAINER_NAME"
      value = module.shared.community_media_container_name
    }
  ]
}

module "messaging_gateway_container_app" {
  source = "../../modules/container-app"

  service_name = "messaging-gateway"
  environment  = var.environment
  location     = var.location
  tenant_id    = var.tenant_id

  resource_group_name        = module.shared.resource_group_name
  acr_id                     = module.shared.acr_id
  acr_login_server           = module.shared.acr_login_server
  key_vault_id               = module.shared.key_vault_id
  key_vault_uri              = module.shared.key_vault_uri
  key_vault_secret_uri       = module.shared.key_vault_secret_uri
  log_analytics_workspace_id = module.shared.log_analytics_workspace_id
  aca_subnet_id              = module.shared.aca_subnet_id

  image_repository = "turksquare/messaging-gateway"
  image_tag        = var.messaging_gateway_image_tag
  container_port   = 8080

  postgres_admin_username = var.postgres_admin_username
  postgres_admin_password = var.postgres_admin_password
  postgres_fqdn           = module.shared.postgresql_server_fqdn
  database_name           = "messaging"

  servicebus_connection_string            = module.shared.servicebus_connection_string
  servicebus_connection_string_secret_uri = module.shared.servicebus_connection_string_secret_uri

  secret_env = [
    { name = "MATRIX-BASE-URL", key_vault_secret_id = "MATRIX-BASE-URL", env_name = "MATRIX_BASE_URL" },
    { name = "MATRIX-APPSERVICE-TOKEN", key_vault_secret_id = "MATRIX-APPSERVICE-TOKEN", env_name = "MATRIX_APPSERVICE_TOKEN" },
    { name = "MATRIX-SERVER-NAME", key_vault_secret_id = "MATRIX-SERVER-NAME", env_name = "MATRIX_SERVER_NAME" },
    { name = "INTERNAL-SERVICE-TOKEN", key_vault_secret_id = "INTERNAL-SERVICE-TOKEN", env_name = "INTERNAL_SERVICE_TOKEN" }
  ]

  extra_env = [
    {
      name  = "AZURE_JWT_SIGNING_KEY_NAME"
      value = "turksquare-identity-jwt-signing"
    }
  ]
}

module "email_relay_function" {
  source = "../../modules/function-app"

  function_name       = "email-relay"
  environment         = var.environment
  location            = var.location
  resource_group_name = module.shared.resource_group_name
  tenant_id           = var.tenant_id
  deployer_object_id  = var.deployer_object_id

  service_plan_sku                       = "Y1"
  key_vault_id                           = module.shared.key_vault_id
  application_insights_connection_string = module.shared.application_insights_connection_string

  app_settings = {
    WEBSITE_RUN_FROM_PACKAGE = "1"
    RESEND_API_KEY           = "@Microsoft.KeyVault(SecretUri=${module.shared.key_vault_secret_uri}RESEND-API-KEY)"
  }
}

module "password_breach_check_function" {
  source = "../../modules/function-app"

  function_name       = "password-breach-check"
  environment         = var.environment
  location            = var.location
  resource_group_name = module.shared.resource_group_name
  tenant_id           = var.tenant_id
  deployer_object_id  = var.deployer_object_id

  service_plan_sku                       = "Y1"
  key_vault_id                           = module.shared.key_vault_id
  application_insights_connection_string = module.shared.application_insights_connection_string

  app_settings = {
    WEBSITE_RUN_FROM_PACKAGE = "1"
  }
}
