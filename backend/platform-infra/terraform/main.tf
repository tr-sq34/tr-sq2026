locals {
  prefix = "${var.name_prefix}-${var.environment}"
  databases = toset(["identity", "community", "verification-vault"])
}

# Dedicated CMKs prevent a media-service compromise from decrypting documents.
resource "aws_kms_key" "vault" {
  description             = "${local.prefix} verification vault encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}
resource "aws_kms_alias" "vault" { name = "alias/${local.prefix}-verification-vault" target_key_id = aws_kms_key.vault.key_id }

resource "aws_kms_key" "community" {
  description             = "${local.prefix} community data encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_s3_bucket" "verification_quarantine" {
  bucket_prefix       = "${local.prefix}-verification-quarantine-"
  object_lock_enabled = true
}
resource "aws_s3_bucket" "verification_vault" {
  bucket_prefix       = "${local.prefix}-verification-vault-"
  object_lock_enabled = true
}
resource "aws_s3_bucket" "community_media_quarantine" { bucket_prefix = "${local.prefix}-community-media-quarantine-" }
resource "aws_s3_bucket" "community_media_delivery" { bucket_prefix = "${local.prefix}-community-media-delivery-" }

resource "aws_s3_bucket_public_access_block" "verification" {
  for_each = { quarantine = aws_s3_bucket.verification_quarantine.id, vault = aws_s3_bucket.verification_vault.id }
  bucket = each.value
  block_public_acls = true
  block_public_policy = true
  ignore_public_acls = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_versioning" "verification" {
  for_each = { quarantine = aws_s3_bucket.verification_quarantine.id, vault = aws_s3_bucket.verification_vault.id }
  bucket = each.value
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_object_lock_configuration" "vault" {
  bucket = aws_s3_bucket.verification_vault.id
  rule { default_retention { mode = "COMPLIANCE" days = 30 } }
}
data "aws_iam_policy_document" "verification_bucket_tls" {
  statement {
    sid = "DenyInsecureTransport"
    effect = "Deny"
    principals { type = "*" identifiers = ["*"] }
    actions = ["s3:*"]
    resources = ["${aws_s3_bucket.verification_vault.arn}", "${aws_s3_bucket.verification_vault.arn}/*"]
    condition { test = "Bool" variable = "aws:SecureTransport" values = ["false"] }
  }
}
resource "aws_s3_bucket_policy" "verification" {
  bucket = aws_s3_bucket.verification_vault.id
  policy = data.aws_iam_policy_document.verification_bucket_tls.json
}
data "aws_iam_policy_document" "quarantine_bucket_tls" {
  statement {
    sid = "DenyInsecureTransport"
    effect = "Deny"
    principals { type = "*" identifiers = ["*"] }
    actions = ["s3:*"]
    resources = ["${aws_s3_bucket.verification_quarantine.arn}", "${aws_s3_bucket.verification_quarantine.arn}/*"]
    condition { test = "Bool" variable = "aws:SecureTransport" values = ["false"] }
  }
}
resource "aws_s3_bucket_policy" "quarantine" {
  bucket = aws_s3_bucket.verification_quarantine.id
  policy = data.aws_iam_policy_document.quarantine_bucket_tls.json
}
resource "aws_s3_bucket_server_side_encryption_configuration" "verification" {
  for_each = { quarantine = aws_s3_bucket.verification_quarantine.id, vault = aws_s3_bucket.verification_vault.id }
  bucket = each.value
  rule { apply_server_side_encryption_by_default { sse_algorithm = "aws:kms" kms_master_key_id = aws_kms_key.vault.arn } bucket_key_enabled = true }
}
resource "aws_s3_bucket_lifecycle_configuration" "quarantine" {
  bucket = aws_s3_bucket.verification_quarantine.id
  rule { id = "expire-unscanned" status = "Enabled" filter { prefix = "" } expiration { days = 2 } noncurrent_version_expiration { noncurrent_days = 2 } }
}
resource "aws_s3_bucket_lifecycle_configuration" "vault" {
  bucket = aws_s3_bucket.verification_vault.id
  rule { id = "delete-source-after-review" status = "Enabled" filter { prefix = "" } expiration { days = 30 } noncurrent_version_expiration { noncurrent_days = 30 } }
}

resource "aws_sqs_queue" "document_scan_dlq" { name = "${local.prefix}-document-scan-dlq" kms_master_key_id = aws_kms_key.vault.id message_retention_seconds = 1209600 }
resource "aws_sqs_queue" "document_scan" {
  name = "${local.prefix}-document-scan"
  kms_master_key_id = aws_kms_key.vault.id
  visibility_timeout_seconds = 900
  redrive_policy = jsonencode({ deadLetterTargetArn = aws_sqs_queue.document_scan_dlq.arn, maxReceiveCount = 3 })
}

# Each logical data boundary gets its own multi-AZ Aurora cluster. Credentials
# are created and rotated through Secrets Manager, never Terraform outputs.
resource "aws_rds_cluster" "data" {
  for_each = local.databases
  cluster_identifier = "${local.prefix}-${each.key}"
  engine = "aurora-postgresql"
  engine_mode = "provisioned"
  database_name = replace(each.key, "-", "_")
  master_username = "bootstrap_admin"
  manage_master_user_password = true
  storage_encrypted = true
  deletion_protection = true
  backup_retention_period = 35
  preferred_backup_window = "05:00-05:30"
  db_subnet_group_name = aws_db_subnet_group.private.name
  vpc_security_group_ids = var.db_security_group_ids
  copy_tags_to_snapshot = true
  enabled_cloudwatch_logs_exports = ["postgresql"]
}
resource "aws_rds_cluster_instance" "data" {
  for_each = local.databases
  identifier = "${local.prefix}-${each.key}-writer"
  cluster_identifier = aws_rds_cluster.data[each.key].id
  instance_class = "db.r6g.large"
  engine = aws_rds_cluster.data[each.key].engine
  publicly_accessible = false
}
resource "aws_db_subnet_group" "private" { name = "${local.prefix}-private-db" subnet_ids = var.private_subnet_ids }

resource "aws_backup_vault" "dr" { provider = aws.dr name = "${local.prefix}-dr" }

output "verification_quarantine_bucket" { value = aws_s3_bucket.verification_quarantine.id }
output "verification_vault_bucket" { value = aws_s3_bucket.verification_vault.id }
output "document_scan_queue_url" { value = aws_sqs_queue.document_scan.url }
