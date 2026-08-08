variable "enable_legacy_aws_resources" {
  type        = bool
  description = "Keep AWS Lambda/SQS email relay resources active while migrating to Azure Functions. Set to false once Azure Functions are verified."
  default     = false
}

resource "aws_secretsmanager_secret" "resend_api_key" {
  count                   = var.enable_legacy_aws_resources ? 1 : 0
  name                    = "turksquare/identity/resend-api-key"
  kms_key_id              = aws_kms_key.identity.arn
  recovery_window_in_days = 30
}

resource "aws_sqs_queue" "identity_email_dlq" {
  count                       = var.enable_legacy_aws_resources ? 1 : 0
  name                        = "turksquare-identity-email-dlq.fifo"
  fifo_queue                  = true
  content_based_deduplication = false
  sqs_managed_sse_enabled     = true
}

resource "aws_sqs_queue" "identity_email" {
  count                       = var.enable_legacy_aws_resources ? 1 : 0
  name                        = "turksquare-identity-email.fifo"
  fifo_queue                  = true
  content_based_deduplication = false
  sqs_managed_sse_enabled     = true
  visibility_timeout_seconds  = 120
  redrive_policy              = jsonencode({ deadLetterTargetArn = try(aws_sqs_queue.identity_email_dlq[0].arn, ""), maxReceiveCount = 3 })
}

data "archive_file" "email_relay" {
  count       = var.enable_legacy_aws_resources ? 1 : 0
  type        = "zip"
  source_file = abspath("${path.module}/../../../../services/email-relay/index.mjs")
  output_path = "${path.module}/.terraform/email-relay.zip"
}

resource "aws_iam_role" "email_relay" {
  count = var.enable_legacy_aws_resources ? 1 : 0
  name  = "TurkSquareIdentityEmailRelayRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "email_relay_logs" {
  count      = var.enable_legacy_aws_resources ? 1 : 0
  role       = try(aws_iam_role.email_relay[0].name, "")
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_cloudwatch_log_group" "email_relay" {
  count             = var.enable_legacy_aws_resources ? 1 : 0
  name              = "/aws/lambda/turksquare-identity-email-relay"
  retention_in_days = 90
}

resource "aws_iam_role_policy" "email_relay" {
  count  = var.enable_legacy_aws_resources ? 1 : 0
  name   = "consume-identity-email-queue"
  role   = try(aws_iam_role.email_relay[0].id, "")
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], Resource = try(aws_sqs_queue.identity_email[0].arn, "") }, { Effect = "Allow", Action = ["secretsmanager:GetSecretValue", "kms:Decrypt"], Resource = [try(aws_secretsmanager_secret.resend_api_key[0].arn, ""), aws_kms_key.identity.arn] }] })
}

resource "aws_lambda_function" "email_relay" {
  count            = var.enable_legacy_aws_resources ? 1 : 0
  function_name    = "turksquare-identity-email-relay"
  role             = try(aws_iam_role.email_relay[0].arn, "")
  handler          = "index.handler"
  runtime          = "nodejs22.x"
  filename         = try(data.archive_file.email_relay[0].output_path, "")
  source_code_hash = try(data.archive_file.email_relay[0].output_base64sha256, "")
  timeout          = 30
  environment { variables = { RESEND_API_KEY_SECRET_ARN = try(aws_secretsmanager_secret.resend_api_key[0].arn, "") } }
  depends_on = [aws_iam_role_policy_attachment.email_relay_logs, aws_cloudwatch_log_group.email_relay]
}

data "archive_file" "password_safety" {
  count       = var.enable_legacy_aws_resources ? 1 : 0
  type        = "zip"
  source_file = abspath("${path.module}/../../../../services/password-breach-check/index.mjs")
  output_path = "${path.module}/.terraform/password-safety.zip"
}
resource "aws_iam_role" "password_safety" {
  count              = var.enable_legacy_aws_resources ? 1 : 0
  name               = "TurkSquareIdentityPasswordSafetyRole"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }] })
}
resource "aws_iam_role_policy_attachment" "password_safety_logs" {
  count      = var.enable_legacy_aws_resources ? 1 : 0
  role       = try(aws_iam_role.password_safety[0].name, "")
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_cloudwatch_log_group" "password_safety" {
  count             = var.enable_legacy_aws_resources ? 1 : 0
  name              = "/aws/lambda/turksquare-identity-password-safety"
  retention_in_days = 90
}
resource "aws_lambda_function" "password_safety" {
  count            = var.enable_legacy_aws_resources ? 1 : 0
  function_name    = "turksquare-identity-password-safety"
  role             = try(aws_iam_role.password_safety[0].arn, "")
  handler          = "index.handler"
  runtime          = "nodejs22.x"
  filename         = try(data.archive_file.password_safety[0].output_path, "")
  source_code_hash = try(data.archive_file.password_safety[0].output_base64sha256, "")
  timeout          = 10
  depends_on       = [aws_iam_role_policy_attachment.password_safety_logs, aws_cloudwatch_log_group.password_safety]
}

output "resend_api_key_secret_arn" {
  value = try(aws_secretsmanager_secret.resend_api_key[0].arn, "")
}
