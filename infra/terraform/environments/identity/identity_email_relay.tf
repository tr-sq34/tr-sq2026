resource "aws_secretsmanager_secret" "resend_api_key" {
  name                    = "turksquare/identity/resend-api-key"
  kms_key_id              = aws_kms_key.identity.arn
  recovery_window_in_days = 30
}

resource "aws_sqs_queue" "identity_email_dlq" {
  name                        = "turksquare-identity-email-dlq.fifo"
  fifo_queue                  = true
  content_based_deduplication = false
  # AWS-managed SQS encryption avoids a cross-service KMS poller dependency.
  # The queue carries only short-lived transactional delivery commands; secrets,
  # credentials, documents and databases remain under dedicated customer KMS keys.
  sqs_managed_sse_enabled = true
}

resource "aws_sqs_queue" "identity_email" {
  name                        = "turksquare-identity-email.fifo"
  fifo_queue                  = true
  content_based_deduplication = false
  sqs_managed_sse_enabled     = true
  visibility_timeout_seconds  = 120
  redrive_policy              = jsonencode({ deadLetterTargetArn = aws_sqs_queue.identity_email_dlq.arn, maxReceiveCount = 3 })
}

data "archive_file" "email_relay" {
  type        = "zip"
  source_file = abspath("${path.module}/../../../../services/email-relay/index.mjs")
  output_path = "${path.module}/.terraform/email-relay.zip"
}

resource "aws_iam_role" "email_relay" {
  name = "TurkSquareIdentityEmailRelayRole"
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
  role       = aws_iam_role.email_relay.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_cloudwatch_log_group" "email_relay" {
  name              = "/aws/lambda/turksquare-identity-email-relay"
  retention_in_days = 90
}

resource "aws_iam_role_policy" "email_relay" {
  name   = "consume-identity-email-queue"
  role   = aws_iam_role.email_relay.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], Resource = aws_sqs_queue.identity_email.arn }, { Effect = "Allow", Action = ["secretsmanager:GetSecretValue", "kms:Decrypt"], Resource = [aws_secretsmanager_secret.resend_api_key.arn, aws_kms_key.identity.arn] }] })
}

resource "aws_lambda_function" "email_relay" {
  function_name    = "turksquare-identity-email-relay"
  role             = aws_iam_role.email_relay.arn
  handler          = "index.handler"
  runtime          = "nodejs22.x"
  filename         = data.archive_file.email_relay.output_path
  source_code_hash = data.archive_file.email_relay.output_base64sha256
  timeout          = 30
  environment { variables = { RESEND_API_KEY_SECRET_ARN = aws_secretsmanager_secret.resend_api_key.arn } }
  depends_on = [aws_iam_role_policy_attachment.email_relay_logs, aws_cloudwatch_log_group.email_relay]
}

data "archive_file" "password_safety" {
  type        = "zip"
  source_file = abspath("${path.module}/../../../../services/password-breach-check/index.mjs")
  output_path = "${path.module}/.terraform/password-safety.zip"
}
resource "aws_iam_role" "password_safety" {
  name               = "TurkSquareIdentityPasswordSafetyRole"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }] })
}
resource "aws_iam_role_policy_attachment" "password_safety_logs" {
  role       = aws_iam_role.password_safety.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_cloudwatch_log_group" "password_safety" {
  name              = "/aws/lambda/turksquare-identity-password-safety"
  retention_in_days = 90
}
resource "aws_lambda_function" "password_safety" {
  function_name    = "turksquare-identity-password-safety"
  role             = aws_iam_role.password_safety.arn
  handler          = "index.handler"
  runtime          = "nodejs22.x"
  filename         = data.archive_file.password_safety.output_path
  source_code_hash = data.archive_file.password_safety.output_base64sha256
  timeout          = 10
  depends_on       = [aws_iam_role_policy_attachment.password_safety_logs, aws_cloudwatch_log_group.password_safety]
}

// Bump this deliberately when the SQS poller must be recreated after a
// permissions/encryption change.  An event-source mapping owns long-lived
// polling workers, so in-place IAM changes alone are not a reliable reset.
output "resend_api_key_secret_arn" { value = aws_secretsmanager_secret.resend_api_key.arn }
