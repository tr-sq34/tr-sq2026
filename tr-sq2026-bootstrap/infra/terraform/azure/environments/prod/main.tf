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

  key_vault_admin_object_ids = var.key_vault_admin_object_ids

  key_vault_secrets = {
    "JWT-ISSUER"      = "https://api.turksquare.com"
    "JWT-AUDIENCE"    = "https://api.turksquare.com"
    "JWT-KEY-ID"      = "turksquare-identity-jwt-signing"
    "WEBAUTHN-RP-ID"  = "turksquare.com"
    "WEBAUTHN-ORIGIN" = "https://turksquare.com"
    # Resend verifies notify.turksquare.com, not the root domain. Sending as
    # noreply@turksquare.com gets a 403 from Resend, which the relay surfaces as
    # a 502 — no mail, and nothing wrong-looking in the identity service.
    "EMAIL-FROM"           = "noreply@notify.turksquare.com"
    "AUTH-ACTION-BASE-URL" = "https://api.turksquare.com/v1/auth/action"
    # These two are consumed as complete endpoints, not as base URLs: the
    # services POST to them verbatim. A Function App's root answers 200 with an
    # HTML "up and running" page, so leaving the route off does not fail — it
    # silently succeeds against the wrong thing. That has cost this project
    # three production outages; hence the routes live here, next to the
    # webhook/range entries that always carried them.
    "EMAIL-RELAY-FUNCTION-NAME"     = "https://func-email-relay-prod-cu.azurewebsites.net/api/emailRelay"
    "EMAIL-DELIVERY-WEBHOOK"        = "https://func-email-relay-prod-cu.azurewebsites.net/api/emailRelay"
    "PASSWORD-SAFETY-FUNCTION-NAME" = "https://func-password-breach-check-prod-cu.azurewebsites.net/api/passwordBreachCheck"
    "PWNED-PASSWORDS-RANGE-URL"     = "https://func-password-breach-check-prod-cu.azurewebsites.net/api/passwordBreachCheck"
    "GATEWORK-COMMUNITY-AUDIENCE"   = "https://community-api.turksquare.com"
    "VERIFICATION-RETURN-URL"       = "https://turksquare.com/verification/callback"
    # Must agree with server_name in services/matrix-synapse/homeserver.yaml.template.
    # server_name is written into every Matrix ID and event signature at first
    # boot and can never be changed afterwards, so the template is authoritative
    # and this value follows it — not the other way round.
    "MATRIX-SERVER-NAME" = "matrix.turksquare.com"
    # The gateway does not use this: Synapse has no public ingress, and the
    # gateway reaches it on the environment-internal FQDN below. It is kept
    # because homeserver.yaml advertises this hostname as public_baseurl.
    "MATRIX-BASE-URL" = "https://matrix.turksquare.com"
    # Secrets are not listed here. Every value in this map is a literal in a
    # public-facing repository, so INTERNAL-SERVICE-TOKEN, EMAIL-CODE-HMAC-SECRET
    # and the four MATRIX-* secrets are generated in the shared module instead.
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
  postgres_admin_password = module.shared.postgres_admin_password
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
    },
    {
      name  = "AZURE_MESSAGING_PROJECTION_QUEUE_NAME"
      value = module.shared.messaging_projection_queue_name
    }
  ]
}

module "verification_vault_container_app" {
  source = "../../modules/container-app"

  service_name = "verification-vault"
  environment  = var.environment
  location     = var.location
  tenant_id    = var.tenant_id

  # Every app shares the one environment identity created. The module would
  # otherwise declare its own, and each of those carries the same name, so the
  # second one to be applied collides with the first.
  container_app_environment_id = module.identity_container_app.container_app_environment_id

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
  postgres_admin_password = module.shared.postgres_admin_password
  postgres_fqdn           = module.shared.postgresql_server_fqdn
  database_name           = "verification"

  servicebus_connection_string            = module.shared.servicebus_connection_string
  servicebus_connection_string_secret_uri = module.shared.servicebus_connection_string_secret_uri

  secret_env = [
    { name = "STRIPE-SECRET-KEY", key_vault_secret_id = "STRIPE-SECRET-KEY", env_name = "STRIPE_SECRET_KEY" },
    { name = "STRIPE-WEBHOOK-SECRET", key_vault_secret_id = "STRIPE-WEBHOOK-SECRET", env_name = "STRIPE_WEBHOOK_SECRET" },
    { name = "VERIFICATION-RETURN-URL", key_vault_secret_id = "VERIFICATION-RETURN-URL", env_name = "VERIFICATION_RETURN_URL" },
    # user() reads both of these on every authenticated request, and they were
    # never set: the app started healthy and then rejected every call, so
    # "Onaylı Hesap" could not be started or read at all. The health check does
    # not touch them, which is why the app looked fine the whole time.
    { name = "JWT-ISSUER", key_vault_secret_id = "JWT-ISSUER", env_name = "JWT_ISSUER" },
    { name = "JWT-AUDIENCE", key_vault_secret_id = "JWT-AUDIENCE", env_name = "JWT_AUDIENCE" },
    # And this one for the operator endpoints, same secret every other
    # gatework-facing service reads: Identity stamps one delegation audience for
    # all of them.
    { name = "GATEWORK-COMMUNITY-AUDIENCE", key_vault_secret_id = "GATEWORK-COMMUNITY-AUDIENCE", env_name = "GATEWORK_JWT_AUDIENCE" }
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

  container_app_environment_id = module.identity_container_app.container_app_environment_id

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
  postgres_admin_password = module.shared.postgres_admin_password
  postgres_fqdn           = module.shared.postgresql_server_fqdn
  database_name           = "community"

  servicebus_connection_string            = module.shared.servicebus_connection_string
  servicebus_connection_string_secret_uri = module.shared.servicebus_connection_string_secret_uri
  storage_account_key_secret_uri          = "${module.shared.key_vault_secret_uri}STORAGE-ACCOUNT-KEY"

  secret_env = [
    { name = "STRIPE-SECRET-KEY", key_vault_secret_id = "STRIPE-SECRET-KEY", env_name = "STRIPE_SECRET_KEY" },
    # viewer() and gateworkActor() read these on every request. Without them the
    # service starts healthy and then rejects every authenticated call.
    { name = "JWT-ISSUER", key_vault_secret_id = "JWT-ISSUER", env_name = "JWT_ISSUER" },
    { name = "JWT-AUDIENCE", key_vault_secret_id = "JWT-AUDIENCE", env_name = "JWT_AUDIENCE" },
    { name = "GATEWORK-COMMUNITY-AUDIENCE", key_vault_secret_id = "GATEWORK-COMMUNITY-AUDIENCE", env_name = "GATEWORK_JWT_AUDIENCE" }
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
    },
    {
      name  = "AZURE_MESSAGING_PROJECTION_QUEUE_NAME"
      value = module.shared.messaging_projection_queue_name
    }
  ]
}

module "messaging_gateway_container_app" {
  source = "../../modules/container-app"

  service_name = "messaging-gateway"
  environment  = var.environment
  location     = var.location
  tenant_id    = var.tenant_id

  container_app_environment_id = module.identity_container_app.container_app_environment_id

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
  postgres_admin_password = module.shared.postgres_admin_password
  postgres_fqdn           = module.shared.postgresql_server_fqdn
  database_name           = "messaging"

  servicebus_connection_string            = module.shared.servicebus_connection_string
  servicebus_connection_string_secret_uri = module.shared.servicebus_connection_string_secret_uri

  secret_env = [
    { name = "MATRIX-APPSERVICE-TOKEN", key_vault_secret_id = "MATRIX-APPSERVICE-TOKEN", env_name = "MATRIX_APPSERVICE_TOKEN" },
    { name = "MATRIX-SERVER-NAME", key_vault_secret_id = "MATRIX-SERVER-NAME", env_name = "MATRIX_SERVER_NAME" },
    { name = "INTERNAL-SERVICE-TOKEN", key_vault_secret_id = "INTERNAL-SERVICE-TOKEN", env_name = "INTERNAL_SERVICE_TOKEN" },
    { name = "JWT-ISSUER", key_vault_secret_id = "JWT-ISSUER", env_name = "JWT_ISSUER" },
    { name = "JWT-AUDIENCE", key_vault_secret_id = "JWT-AUDIENCE", env_name = "JWT_AUDIENCE" },
    # The moderation endpoints under /v1/internal/gatework/messaging reject every
    # call without this. Identity mints one delegation token for all gatework
    # traffic and stamps it with GATEWORK-COMMUNITY-AUDIENCE, so despite the name
    # this is the audience every gatework-facing service must expect - the same
    # secret community-service reads for the same reason.
    { name = "GATEWORK-COMMUNITY-AUDIENCE", key_vault_secret_id = "GATEWORK-COMMUNITY-AUDIENCE", env_name = "GATEWORK_JWT_AUDIENCE" }
  ]

  extra_env = [
    {
      name  = "AZURE_JWT_SIGNING_KEY_NAME"
      value = "turksquare-identity-jwt-signing"
    },
    # Not the public hostname: Synapse has no public ingress. This is the
    # environment-internal FQDN, which is why both apps must live in the same
    # container app environment.
    {
      name  = "MATRIX_BASE_URL"
      value = module.matrix_synapse.internal_base_url
    }
  ]
}

# The homeserver itself. Everything the messaging gateway does — creating the
# per-user Matrix identity, the DM room, and sending the event — is a call to
# this app, so until it exists the gateway's endpoints cannot succeed.
module "matrix_synapse" {
  source = "../../modules/matrix-synapse"

  environment = var.environment
  location    = var.location
  tenant_id   = var.tenant_id

  resource_group_name = module.shared.resource_group_name
  # Internal ingress resolves only within one environment, and the gateway runs
  # in the one identity created.
  container_app_environment_id = module.identity_container_app.container_app_environment_id

  acr_id               = module.shared.acr_id
  acr_login_server     = module.shared.acr_login_server
  key_vault_id         = module.shared.key_vault_id
  key_vault_secret_uri = module.shared.key_vault_secret_uri

  image_repository = "turksquare/matrix-synapse"
  image_tag        = var.matrix_synapse_image_tag
  server_name      = "matrix.turksquare.com"

  storage_account_name = module.shared.storage_account_name
  storage_account_key  = module.shared.storage_account_primary_access_key

  postgres_fqdn           = module.shared.postgresql_server_fqdn
  postgres_admin_username = var.postgres_admin_username
  postgres_admin_password = module.shared.postgres_admin_password
  database_name           = module.shared.matrix_database_name
}

# The operator console. It deliberately has no ingress of any kind — not even
# internal — which is the same posture it had on ECS: the only way in is the
# Cloudflare Tunnel connector running beside it, and a connector dials out. So
# there is no address on this app to attack, and Cloudflare Access stays the one
# authentication gate in front of the panel.
#
# It also holds no database credential. Every screen reads a domain API over
# HTTP, which is why database_name is left unset here.
module "gatework_console_container_app" {
  source = "../../modules/container-app"

  service_name = "gatework-console"
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
  # The console calls three services on their environment-internal addresses, so
  # it has to sit in the environment they run in.
  container_app_environment_id = module.identity_container_app.container_app_environment_id

  image_repository  = "turksquare/gatework-console"
  image_tag         = var.gatework_console_image_tag
  container_port    = 3000
  enable_ingress    = false
  expose_externally = false

  # Two at most: this is a handful of operators, and every extra replica is
  # another tunnel connector registering with Cloudflare.
  min_replicas = 1
  max_replicas = 2

  secret_env = [
    { name = "GATEWORK-SESSION-SECRET", key_vault_secret_id = "GATEWORK-SESSION-SECRET", env_name = "GATEWORK_SESSION_SECRET" }
  ]

  extra_env = [
    {
      name  = "IDENTITY_API_BASE_URL"
      value = module.identity_container_app.base_url
    },
    {
      name  = "COMMUNITY_API_BASE_URL"
      value = module.community_container_app.base_url
    },
    # Without this the moderation queue falls back to localhost:8082 and every
    # report screen fails closed.
    {
      name  = "MESSAGING_API_BASE_URL"
      value = module.messaging_gateway_container_app.base_url
    },
    {
      name  = "VERIFICATION_API_BASE_URL"
      value = module.verification_vault_container_app.base_url
    }
  ]

  sidecar = {
    name = "cloudflared"
    # Mirrored into ACR by the deploy workflow rather than pulled from Docker
    # Hub: an anonymous-pull rate limit here would leave the console with no way
    # in at all.
    image = "${module.shared.acr_login_server}/cloudflare/cloudflared:2025.2.0"
    # --no-autoupdate: the image tag is the version, so a connector that updates
    # itself in place would silently diverge from what was deployed.
    args = ["tunnel", "--no-autoupdate", "run"]
    secret_env = [
      { name = "CLOUDFLARE-TUNNEL-TOKEN", key_vault_secret_id = "CLOUDFLARE-TUNNEL-TOKEN", env_name = "TUNNEL_TOKEN" }
    ]
  }
}

# The projection worker ships in the messaging-gateway image and is pinned to the
# same tag, so the consumer and the endpoints that read its output can never run
# different versions of the event contract. It has no ingress: it is driven
# entirely by Service Bus.
module "messaging_projection_worker" {
  source = "../../modules/container-app"

  # Same 32 character limit as community-media above.
  service_name = "messaging-projection"
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
  # Reuses the environment identity already owns instead of declaring a second
  # state entry for the same ARM resource.
  container_app_environment_id = module.identity_container_app.container_app_environment_id

  image_repository  = "turksquare/messaging-gateway"
  image_tag         = var.messaging_gateway_image_tag
  container_command = ["node", "--enable-source-maps", "dist/projection_worker.js"]
  enable_ingress    = false
  expose_externally = false

  # Competing consumers on one queue; the handlers are idempotent and ordered by
  # source_event_at, so replicas never need to coordinate.
  min_replicas = 1
  max_replicas = 3

  postgres_admin_username = var.postgres_admin_username
  postgres_admin_password = module.shared.postgres_admin_password
  postgres_fqdn           = module.shared.postgresql_server_fqdn
  database_name           = "messaging"

  servicebus_connection_string            = module.shared.servicebus_connection_string
  servicebus_connection_string_secret_uri = module.shared.servicebus_connection_string_secret_uri

  extra_env = [
    {
      name  = "AZURE_MESSAGING_PROJECTION_QUEUE_NAME"
      value = module.shared.messaging_projection_queue_name
    },
    {
      name  = "PROJECTION_MAX_CONCURRENCY"
      value = "8"
    }
  ]
}

# community-profile-projection had a producer (identity) and a consumer written,
# but the consumer was never deployed, so the queue only accumulated.
module "community_profile_projection_worker" {
  source = "../../modules/container-app"

  service_name = "community-profile-worker"
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
  # Reuses the environment identity already owns instead of declaring a second
  # state entry for the same ARM resource.
  container_app_environment_id = module.identity_container_app.container_app_environment_id

  image_repository  = "turksquare/community-service"
  image_tag         = var.community_image_tag
  container_command = ["node", "dist/profile_projection_worker.js"]
  enable_ingress    = false
  expose_externally = false

  min_replicas = 1
  max_replicas = 2

  postgres_admin_username = var.postgres_admin_username
  postgres_admin_password = module.shared.postgres_admin_password
  postgres_fqdn           = module.shared.postgresql_server_fqdn
  database_name           = "community"

  servicebus_connection_string            = module.shared.servicebus_connection_string
  servicebus_connection_string_secret_uri = module.shared.servicebus_connection_string_secret_uri

  extra_env = [
    {
      name  = "AZURE_COMMUNITY_PROFILE_QUEUE_NAME"
      value = module.shared.community_profile_projection_queue_name
    }
  ]
}

# Uploaded media stays in status 'pending' until this worker processes it, and
# every post/story insert requires status 'ready'.
module "community_media_processor" {
  source = "../../modules/container-app"

  # Not "community-media-processor": Azure caps a container app name at 32
  # characters and the module prefixes "ca-" and suffixes the environment.
  service_name = "community-media"
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
  # Reuses the environment identity already owns instead of declaring a second
  # state entry for the same ARM resource.
  container_app_environment_id = module.identity_container_app.container_app_environment_id

  image_repository  = "turksquare/community-service"
  image_tag         = var.community_image_tag
  container_command = ["node", "dist/media_processor_worker.js"]
  enable_ingress    = false
  expose_externally = false

  min_replicas = 1
  max_replicas = 2

  postgres_admin_username = var.postgres_admin_username
  postgres_admin_password = module.shared.postgres_admin_password
  postgres_fqdn           = module.shared.postgresql_server_fqdn
  database_name           = "community"

  servicebus_connection_string            = module.shared.servicebus_connection_string
  servicebus_connection_string_secret_uri = module.shared.servicebus_connection_string_secret_uri
  storage_account_key_secret_uri          = "${module.shared.key_vault_secret_uri}STORAGE-ACCOUNT-KEY"

  extra_env = [
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

module "email_relay_function" {
  source = "../../modules/function-app"

  function_name       = "email-relay"
  environment         = var.environment
  location            = var.location
  resource_group_name = module.shared.resource_group_name
  tenant_id           = var.tenant_id
  deployer_object_ids = var.deployer_object_ids

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
  deployer_object_ids = var.deployer_object_ids

  service_plan_sku                       = "Y1"
  key_vault_id                           = module.shared.key_vault_id
  application_insights_connection_string = module.shared.application_insights_connection_string

  app_settings = {
    WEBSITE_RUN_FROM_PACKAGE = "1"
  }
}

# --- Schema migrations --------------------------------------------------
# Triggered by the deploy workflow after terraform apply and before the smoke
# tests. Each runs the same image as its service, so a migration can never be
# newer or older than the code that reads the tables it creates.
module "identity_migrate_job" {
  source = "../../modules/container-app-job"

  job_name    = "identity-migrate"
  environment = var.environment
  location    = var.location

  resource_group_name          = module.shared.resource_group_name
  container_app_environment_id = module.identity_container_app.container_app_environment_id
  acr_id                       = module.shared.acr_id
  acr_login_server             = module.shared.acr_login_server

  image_repository = "turksquare/identity-service"
  image_tag        = var.identity_image_tag

  postgres_admin_username = var.postgres_admin_username
  postgres_admin_password = module.shared.postgres_admin_password
  postgres_fqdn           = module.shared.postgresql_server_fqdn
  database_name           = "identity"
}

module "community_migrate_job" {
  source = "../../modules/container-app-job"

  job_name    = "community-migrate"
  environment = var.environment
  location    = var.location

  resource_group_name          = module.shared.resource_group_name
  container_app_environment_id = module.identity_container_app.container_app_environment_id
  acr_id                       = module.shared.acr_id
  acr_login_server             = module.shared.acr_login_server

  image_repository = "turksquare/community-service"
  image_tag        = var.community_image_tag

  postgres_admin_username = var.postgres_admin_username
  postgres_admin_password = module.shared.postgres_admin_password
  postgres_fqdn           = module.shared.postgresql_server_fqdn
  database_name           = "community"
}

module "messaging_migrate_job" {
  source = "../../modules/container-app-job"

  job_name    = "messaging-migrate"
  environment = var.environment
  location    = var.location

  resource_group_name          = module.shared.resource_group_name
  container_app_environment_id = module.identity_container_app.container_app_environment_id
  acr_id                       = module.shared.acr_id
  acr_login_server             = module.shared.acr_login_server

  image_repository = "turksquare/messaging-gateway"
  image_tag        = var.messaging_gateway_image_tag

  postgres_admin_username = var.postgres_admin_username
  postgres_admin_password = module.shared.postgres_admin_password
  postgres_fqdn           = module.shared.postgresql_server_fqdn
  database_name           = "messaging"
}

module "verification_migrate_job" {
  source = "../../modules/container-app-job"

  job_name    = "verification-migrate"
  environment = var.environment
  location    = var.location

  resource_group_name          = module.shared.resource_group_name
  container_app_environment_id = module.identity_container_app.container_app_environment_id
  acr_id                       = module.shared.acr_id
  acr_login_server             = module.shared.acr_login_server

  image_repository = "turksquare/verification-vault-service"
  image_tag        = var.verification_vault_image_tag

  postgres_admin_username = var.postgres_admin_username
  postgres_admin_password = module.shared.postgres_admin_password
  postgres_fqdn           = module.shared.postgresql_server_fqdn
  database_name           = "verification"
}
