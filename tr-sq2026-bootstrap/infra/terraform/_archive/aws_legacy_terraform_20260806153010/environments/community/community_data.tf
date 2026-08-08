data "aws_region" "current" {}
data "aws_availability_zones" "available" { state = "available" }
data "aws_prefix_list" "s3" { name = "com.amazonaws.${data.aws_region.current.name}.s3" }
locals { availability_zones = slice(data.aws_availability_zones.available.names, 0, 2) }

resource "aws_kms_key" "community" {
  description             = "TurkSquare Community encrypted data"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  # Keep the account-root delegation statement so IAM policies remain
  # effective, then grant CloudWatch Logs only the cryptographic operations
  # required for this one encrypted log group. CloudWatch Logs calls KMS as a
  # service principal, so relying on the account-root statement alone causes
  # log-group creation to fail.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableAccountIamDelegation"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowCommunityCloudWatchLogsOnly"
        Effect    = "Allow"
        Principal = { Service = "logs.${data.aws_region.current.name}.amazonaws.com" }
        Action    = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
        Resource  = "*"
        Condition = {
          ArnEquals = {
            "kms:EncryptionContext:aws:logs:arn" = [
              "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/turksquare/community-service",
              "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/turksquare/gatework"
            ]
          }
        }
      }
    ]
  })
}
resource "aws_kms_alias" "community" {
  name          = "alias/turksquare/community"
  target_key_id = aws_kms_key.community.key_id
}
resource "aws_vpc" "community" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
}
resource "aws_subnet" "community_private" {
  count                   = 2
  vpc_id                  = aws_vpc.community.id
  availability_zone       = local.availability_zones[count.index]
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)
  map_public_ip_on_launch = false
}
resource "aws_route_table" "community_private" { vpc_id = aws_vpc.community.id }
resource "aws_route_table_association" "community_private" {
  count          = 2
  subnet_id      = aws_subnet.community_private[count.index].id
  route_table_id = aws_route_table.community_private.id
}
resource "aws_db_subnet_group" "community" {
  name       = "turksquare-community-private"
  subnet_ids = aws_subnet.community_private[*].id
}
resource "aws_security_group" "community_service" {
  name   = "turksquare-community-service"
  vpc_id = aws_vpc.community.id
}
resource "aws_security_group" "community_database" {
  name   = "turksquare-community-postgres"
  vpc_id = aws_vpc.community.id
}
resource "aws_security_group" "community_endpoints" {
  name   = "turksquare-community-endpoints"
  vpc_id = aws_vpc.community.id
}
resource "aws_security_group_rule" "database_from_service" {
  type                     = "ingress"
  security_group_id        = aws_security_group.community_database.id
  source_security_group_id = aws_security_group.community_service.id
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
}
resource "aws_security_group_rule" "endpoint_from_service" {
  type                     = "ingress"
  security_group_id        = aws_security_group.community_endpoints.id
  source_security_group_id = aws_security_group.community_service.id
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
}
resource "aws_security_group_rule" "service_to_database" {
  type                     = "egress"
  security_group_id        = aws_security_group.community_service.id
  source_security_group_id = aws_security_group.community_database.id
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
}
resource "aws_security_group_rule" "service_to_endpoints" {
  type                     = "egress"
  security_group_id        = aws_security_group.community_service.id
  source_security_group_id = aws_security_group.community_endpoints.id
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
}
resource "aws_security_group_rule" "service_to_s3" {
  type              = "egress"
  security_group_id = aws_security_group.community_service.id
  prefix_list_ids   = [data.aws_prefix_list.s3.id]
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
}
resource "aws_vpc_endpoint" "community_interface" {
  for_each            = toset(["ecr.api", "ecr.dkr", "kms", "logs", "secretsmanager", "sts", "sqs"])
  vpc_id              = aws_vpc.community.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.value}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.community_private[*].id
  security_group_ids  = [aws_security_group.community_endpoints.id]
}
resource "aws_vpc_endpoint" "community_s3" {
  vpc_id            = aws_vpc.community.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.community_private.id]
}

# Cross-account producer: Identity can only send profile-projection events. It
# cannot receive, inspect, or delete messages. SQS-managed encryption avoids
# granting cross-account access to a customer KMS key.
resource "aws_sqs_queue" "identity_profile_projection_dlq" {
  name                      = "turksquare-identity-profile-projection-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
}
resource "aws_sqs_queue" "identity_profile_projection" {
  name                       = "turksquare-identity-profile-projection"
  visibility_timeout_seconds = 90
  message_retention_seconds  = 345600
  receive_wait_time_seconds  = 20
  sqs_managed_sse_enabled    = true
  redrive_policy             = jsonencode({ deadLetterTargetArn = aws_sqs_queue.identity_profile_projection_dlq.arn, maxReceiveCount = 5 })
}
resource "aws_sqs_queue_policy" "identity_profile_projection" {
  queue_url = aws_sqs_queue.identity_profile_projection.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    # The source task roles are created in later foundations.  Account
    # principals keep this queue policy free of creation-order dependencies;
    # source-role IAM policies independently limit SendMessage to this queue.
    { Sid = "IdentityAccountCanOnlySend", Effect = "Allow", Principal = { AWS = "arn:aws:iam::${var.identity_account_id}:root" }, Action = "sqs:SendMessage", Resource = aws_sqs_queue.identity_profile_projection.arn },
    { Sid = "VerificationAccountCanOnlySendCapabilities", Effect = "Allow", Principal = { AWS = "arn:aws:iam::800554367992:root" }, Action = "sqs:SendMessage", Resource = aws_sqs_queue.identity_profile_projection.arn },
    { Sid = "CommunityWorkerConsumes", Effect = "Allow", Principal = { AWS = aws_iam_role.community_task.arn }, Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:ChangeMessageVisibility", "sqs:GetQueueAttributes"], Resource = aws_sqs_queue.identity_profile_projection.arn }
  ] })
}
resource "aws_db_instance" "community" {
  identifier                      = "turksquare-community-postgres"
  engine                          = "postgres"
  engine_version                  = var.postgres_version
  instance_class                  = var.db_instance_class
  allocated_storage               = 100
  max_allocated_storage           = 500
  storage_type                    = "gp3"
  storage_encrypted               = true
  kms_key_id                      = aws_kms_key.community.arn
  db_name                         = "community_db"
  username                        = "community_admin"
  manage_master_user_password     = true
  multi_az                        = true
  publicly_accessible             = false
  deletion_protection             = true
  skip_final_snapshot             = false
  final_snapshot_identifier       = "turksquare-community-final"
  backup_retention_period         = 35
  db_subnet_group_name            = aws_db_subnet_group.community.name
  vpc_security_group_ids          = [aws_security_group.community_database.id]
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  auto_minor_version_upgrade      = true
  copy_tags_to_snapshot           = true
}
resource "aws_s3_bucket" "community_media" { bucket = "turksquare-community-media-${data.aws_caller_identity.current.account_id}" }
resource "aws_s3_bucket_public_access_block" "community_media" {
  bucket                  = aws_s3_bucket.community_media.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_versioning" "community_media" {
  bucket = aws_s3_bucket.community_media.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "community_media" {
  bucket = aws_s3_bucket.community_media.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.community.arn
    }
    bucket_key_enabled = true
  }
}
resource "aws_s3_bucket_lifecycle_configuration" "community_media" {
  bucket = aws_s3_bucket.community_media.id
  rule {
    id     = "abort-incomplete-upload"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
    noncurrent_version_expiration { noncurrent_days = 30 }
  }
}
output "community_database_endpoint" { value = aws_db_instance.community.address }
output "community_media_bucket_name" { value = aws_s3_bucket.community_media.bucket }
output "identity_profile_projection_queue_arn" { value = aws_sqs_queue.identity_profile_projection.arn }
output "identity_profile_projection_queue_url" { value = aws_sqs_queue.identity_profile_projection.id }
