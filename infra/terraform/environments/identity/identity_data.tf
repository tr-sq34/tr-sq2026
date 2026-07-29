data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 2)
}

resource "aws_kms_key" "identity" {
  description             = "TurkSquare Identity restricted-data encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_kms_alias" "identity" {
  name          = "alias/turksquare/identity"
  target_key_id = aws_kms_key.identity.key_id
}

# Access tokens are signed inside KMS. The private RSA key is non-exportable:
# Community, Matrix, Flarum and mobile clients receive only the public JWKS.
resource "aws_kms_key" "identity_jwt_signing" {
  description              = "TurkSquare Identity RS256 access-token signing"
  deletion_window_in_days  = 30
  customer_master_key_spec = "RSA_2048"
  key_usage                = "SIGN_VERIFY"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "IdentityAccountKeyAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid    = "CommunityServicesReadOnlyPublicKey"
        Effect = "Allow"
        Principal = {
          AWS = [
            "arn:aws:iam::936706105958:role/TurkSquareCommunityTaskRole",
            "arn:aws:iam::936706105958:role/TurkSquareMessagingTaskRole"
          ]
        }
        Action   = ["kms:GetPublicKey"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "identity_jwt_signing" {
  name          = "alias/turksquare/identity-jwt-signing"
  target_key_id = aws_kms_key.identity_jwt_signing.key_id
}

resource "aws_vpc" "identity" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
}

resource "aws_subnet" "identity_private" {
  count                   = 2
  vpc_id                  = aws_vpc.identity.id
  availability_zone       = local.availability_zones[count.index]
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)
  map_public_ip_on_launch = false
}

resource "aws_db_subnet_group" "identity" {
  name       = "turksquare-identity-private"
  subnet_ids = aws_subnet.identity_private[*].id
}

resource "aws_security_group" "identity_database" {
  name        = "turksquare-identity-postgres"
  description = "Database has no ingress until private compute is configured"
  vpc_id      = aws_vpc.identity.id
}

resource "aws_db_instance" "identity" {
  identifier                      = "turksquare-identity-postgres"
  engine                          = "postgres"
  engine_version                  = var.postgres_version
  instance_class                  = var.db_instance_class
  allocated_storage               = 100
  max_allocated_storage           = 500
  storage_type                    = "gp3"
  storage_encrypted               = true
  kms_key_id                      = aws_kms_key.identity.arn
  db_name                         = "identity_db"
  username                        = "identity_admin"
  manage_master_user_password     = true
  multi_az                        = true
  publicly_accessible             = false
  deletion_protection             = true
  skip_final_snapshot             = false
  final_snapshot_identifier       = "turksquare-identity-final"
  backup_retention_period         = 35
  db_subnet_group_name            = aws_db_subnet_group.identity.name
  vpc_security_group_ids          = [aws_security_group.identity_database.id]
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  auto_minor_version_upgrade      = true
  copy_tags_to_snapshot           = true
}

resource "aws_secretsmanager_secret" "identity_service_config" {
  name                    = "turksquare/identity/service-config"
  kms_key_id              = aws_kms_key.identity.arn
  recovery_window_in_days = 30
}

output "identity_database_endpoint" {
  value = aws_db_instance.identity.address
}

output "identity_service_config_secret_arn" {
  value = aws_secretsmanager_secret.identity_service_config.arn
}

output "identity_jwt_signing_kms_key_arn" {
  value = aws_kms_key.identity_jwt_signing.arn
}

resource "random_password" "identity_email_code_hmac" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret_version" "identity_service_config" {
  secret_id = aws_secretsmanager_secret.identity_service_config.id
  secret_string = jsonencode({
    JWT_ISSUER                             = "https://api.turksquare.com"
    JWT_AUDIENCE                           = "turksquare-mobile"
    JWT_SIGNING_KMS_KEY_ID                 = aws_kms_key.identity_jwt_signing.arn
    JWT_KEY_ID                             = "identity-rs256-2026-01"
    EMAIL_CODE_HMAC_SECRET                 = random_password.identity_email_code_hmac.result
    WEBAUTHN_RP_ID                         = "turksquare.com"
    WEBAUTHN_ORIGIN                        = "https://turksquare.com"
    EMAIL_FROM                             = "TurkSquare <noreply@notify.turksquare.com>"
    AUTH_ACTION_BASE_URL                   = "https://api.turksquare.com/v1/auth/action"
    PWNED_PASSWORDS_MODE                   = "required"
    COMMUNITY_PROFILE_PROJECTION_QUEUE_URL = var.community_profile_projection_queue_url
  })
}
