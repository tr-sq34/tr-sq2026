resource "aws_ecr_repository" "verification" {
  name                 = "turksquare/verification-vault-service"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.vault.arn
  }
}

resource "aws_cloudwatch_log_group" "verification" {
  name              = "/turksquare/verification-vault-service"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.vault.arn
}

resource "aws_secretsmanager_secret" "verification_config" {
  name                    = "turksquare/verification-vault/service-config"
  kms_key_id              = aws_kms_key.vault.arn
  recovery_window_in_days = 30
}
resource "aws_secretsmanager_secret_version" "verification_config" {
  secret_id = aws_secretsmanager_secret.verification_config.id
  secret_string = jsonencode({
    JWT_ISSUER                       = "https://api.turksquare.com"
    JWT_AUDIENCE                     = "turksquare-mobile"
    IDENTITY_JWT_SIGNING_KMS_KEY_ARN = var.identity_jwt_signing_kms_key_arn
    COMMUNITY_CAPABILITY_QUEUE_URL   = var.community_capability_queue_url
    VERIFICATION_RETURN_URL          = var.verification_return_url
  })
}

# Terraform deliberately creates no credential version. Stripe credentials are
# supplied out-of-band in Secrets Manager and never become Terraform state.
resource "aws_secretsmanager_secret" "stripe_credentials" {
  name                    = "turksquare/verification-vault/stripe-credentials"
  kms_key_id              = aws_kms_key.vault.arn
  recovery_window_in_days = 30
}

resource "aws_iam_role" "verification_execution" {
  name               = "TurkSquareVerificationVaultEcsExecutionRole"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" }, Action = "sts:AssumeRole" }] })
}
resource "aws_iam_role_policy_attachment" "verification_execution" {
  role       = aws_iam_role.verification_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_iam_role_policy" "verification_execution_secrets" {
  name = "read-verification-runtime-secrets"
  role = aws_iam_role.verification_execution.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = [aws_secretsmanager_secret.verification_config.arn, aws_secretsmanager_secret.stripe_credentials.arn, aws_db_instance.vault.master_user_secret[0].secret_arn] },
    { Effect = "Allow", Action = ["kms:Decrypt"], Resource = [aws_kms_key.vault.arn] }
  ] })
}
resource "aws_iam_role" "verification_task" {
  name               = "TurkSquareVerificationVaultTaskRole"
  assume_role_policy = aws_iam_role.verification_execution.assume_role_policy
}
resource "aws_iam_role_policy" "verification_task" {
  name = "verification-runtime-least-privilege"
  role = aws_iam_role.verification_task.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["kms:GetPublicKey"], Resource = [var.identity_jwt_signing_kms_key_arn] },
    { Effect = "Allow", Action = ["sqs:SendMessage"], Resource = [var.community_capability_queue_arn] }
  ] })
}

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_role" "github_verification_deploy" {
  name                 = "GitHubActionsVerificationVaultDeployRole"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = data.aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = { StringEquals = {
        "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        "token.actions.githubusercontent.com:sub" = "repo:tr-sq34@309652758/tr-sq2026@1313519494:environment:verification-vault-production"
      } }
    }]
  })
}
resource "aws_iam_role_policy" "github_verification_deploy" {
  name = "deploy-verification-vault-container-only"
  role = aws_iam_role.github_verification_deploy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
      { Effect = "Allow", Action = ["ecr:BatchCheckLayerAvailability", "ecr:CompleteLayerUpload", "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart"], Resource = aws_ecr_repository.verification.arn },
      { Effect = "Allow", Action = ["ecs:DescribeServices", "ecs:DescribeTaskDefinition", "ecs:DescribeTasks", "ecs:RegisterTaskDefinition", "ecs:RunTask", "ecs:UpdateService", "logs:FilterLogEvents"], Resource = "*" },
      { Effect = "Allow", Action = ["iam:PassRole"], Resource = [aws_iam_role.verification_execution.arn, aws_iam_role.verification_task.arn], Condition = { StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" } } }
    ]
  })
}

resource "aws_ecs_cluster" "verification" { name = "turksquare-verification-vault" }
resource "aws_ecs_task_definition" "verification" {
  family                   = "turksquare-verification-vault-service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.verification_execution.arn
  task_role_arn            = aws_iam_role.verification_task.arn
  container_definitions = jsonencode([{
    name         = "verification-vault", image = "${aws_ecr_repository.verification.repository_url}:bootstrap", essential = true, readonlyRootFilesystem = true,
    portMappings = [{ containerPort = 8082, protocol = "tcp" }],
    environment  = [{ name = "NODE_ENV", value = "production" }, { name = "PORT", value = "8082" }, { name = "DATABASE_HOST", value = aws_db_instance.vault.address }, { name = "DATABASE_PORT", value = tostring(aws_db_instance.vault.port) }, { name = "DATABASE_NAME", value = "verification_vault" }],
    secrets = concat([
      for key in ["JWT_ISSUER", "JWT_AUDIENCE", "IDENTITY_JWT_SIGNING_KMS_KEY_ARN", "COMMUNITY_CAPABILITY_QUEUE_URL", "VERIFICATION_RETURN_URL"] :
      { name = key, valueFrom = "${aws_secretsmanager_secret.verification_config.arn}:${key}::" }
      ], [
      { name = "STRIPE_SECRET_KEY", valueFrom = "${aws_secretsmanager_secret.stripe_credentials.arn}:STRIPE_SECRET_KEY::" },
      { name = "STRIPE_WEBHOOK_SECRET", valueFrom = "${aws_secretsmanager_secret.stripe_credentials.arn}:STRIPE_WEBHOOK_SECRET::" },
      { name = "DATABASE_USER", valueFrom = "${aws_db_instance.vault.master_user_secret[0].secret_arn}:username::" },
      { name = "DATABASE_PASSWORD", valueFrom = "${aws_db_instance.vault.master_user_secret[0].secret_arn}:password::" }
    ])
    logConfiguration = { logDriver = "awslogs", options = { awslogs-group = aws_cloudwatch_log_group.verification.name, awslogs-region = data.aws_region.current.name, awslogs-stream-prefix = "verification" } }
  }])
}
resource "aws_ecs_service" "verification" {
  name            = "turksquare-verification-vault"
  cluster         = aws_ecs_cluster.verification.id
  task_definition = aws_ecs_task_definition.verification.arn
  desired_count   = var.service_desired_count
  launch_type     = "FARGATE"
  depends_on      = [aws_lb_listener.vault_https]
  load_balancer {
    target_group_arn = aws_lb_target_group.vault.arn
    container_name   = "verification-vault"
    container_port   = 8082
  }
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  network_configuration {
    subnets          = aws_subnet.vault_private[*].id
    security_groups  = [aws_security_group.vault_service.id]
    assign_public_ip = false
  }
  lifecycle {
    precondition {
      condition     = var.service_desired_count == 0 || (var.enable_stripe_egress && var.community_capability_queue_arn != "" && var.community_capability_queue_url != "")
      error_message = "Stripe egress and Community queue values are required before starting the verification service."
    }
  }
}

output "verification_ecr_repository_url" { value = aws_ecr_repository.verification.repository_url }
output "verification_service_config_secret_arn" { value = aws_secretsmanager_secret.verification_config.arn }
output "stripe_credentials_secret_arn" { value = aws_secretsmanager_secret.stripe_credentials.arn }
output "verification_deploy_role_arn" { value = aws_iam_role.github_verification_deploy.arn }
