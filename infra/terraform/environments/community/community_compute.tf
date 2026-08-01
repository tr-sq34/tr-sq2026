resource "aws_ecr_repository" "community" {
  name                 = "turksquare/community-service"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.community.arn
  }
}
resource "aws_cloudwatch_log_group" "community" {
  name              = "/turksquare/community-service"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.community.arn
}
# This configuration secret was created during the initial bootstrap.  It
# contained a generated token and consequently put a runtime secret in the
# Terraform state.  Runtime secrets must never be Terraform-managed: plan
# roles need state read access.  Keep the existing remote object untouched
# while removing every related state record; it can be retired separately
# after its consumers have been audited.
removed {
  from = aws_secretsmanager_secret.community_service_config

  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_secretsmanager_secret_version.community_service_config

  lifecycle {
    destroy = false
  }
}

removed {
  from = random_password.community_internal_token

  lifecycle {
    destroy = false
  }
}

resource "aws_iam_role" "community_execution" {
  name               = "TurkSquareCommunityEcsExecutionRole"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" }, Action = "sts:AssumeRole" }] })
}
resource "aws_iam_role_policy_attachment" "community_execution" {
  role       = aws_iam_role.community_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_iam_role_policy" "community_execution_secrets" {
  name = "read-community-runtime-secrets"
  role = aws_iam_role.community_execution.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    # The RDS-managed master credential is the only application secret
    # injected by ECS. Non-sensitive JWT configuration is supplied below as
    # ordinary task environment configuration.
    { Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = [aws_db_instance.community.master_user_secret[0].secret_arn] }
  ] })
}
resource "aws_iam_role" "community_task" {
  name               = "TurkSquareCommunityTaskRole"
  assume_role_policy = aws_iam_role.community_execution.assume_role_policy
}
resource "aws_iam_role_policy" "community_task" {
  name = "community-runtime-least-privilege"
  role = aws_iam_role.community_task.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["kms:GetPublicKey"], Resource = [var.identity_jwt_signing_kms_key_arn] },
    { Effect = "Allow", Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:ChangeMessageVisibility", "sqs:GetQueueAttributes"], Resource = [aws_sqs_queue.identity_profile_projection.arn] },
    { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:AbortMultipartUpload"], Resource = ["${aws_s3_bucket.community_media.arn}/uploads/*"] },
    { Effect = "Allow", Action = ["s3:ListBucket"], Resource = [aws_s3_bucket.community_media.arn], Condition = { StringLike = { "s3:prefix" = ["uploads/*"] } } }
  ] })
}

# Messaging receives a distinct role; it can only inspect the Identity signing public key.
resource "aws_iam_role" "messaging_task" {
  name               = "TurkSquareMessagingTaskRole"
  assume_role_policy = aws_iam_role.community_execution.assume_role_policy
}
resource "aws_iam_role_policy" "messaging_task" {
  name   = "messaging-identity-public-key"
  role   = aws_iam_role.messaging_task.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = ["kms:GetPublicKey"], Resource = [var.identity_jwt_signing_kms_key_arn] }] })
}

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# This role is intentionally environment-scoped.  Its ARN is used only by the
# protected GitHub Environment, never by a mobile client or a repository secret.
resource "aws_iam_role" "github_community_deploy" {
  name                 = "GitHubActionsCommunityDeployRole"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = data.aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = { StringEquals = {
        "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        "token.actions.githubusercontent.com:sub" = [
          "repo:tr-sq34@309652758/tr-sq2026@1313519494:environment:community-production",
          "repo:tr-sq34/tr-sq2026:environment:community-production",
        ]
      } }
    }]
  })
}

resource "aws_iam_role_policy" "github_community_deploy" {
  name = "deploy-community-container-only"
  role = aws_iam_role.github_community_deploy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
      {
        Effect   = "Allow"
        Action   = ["ecr:BatchCheckLayerAvailability", "ecr:CompleteLayerUpload", "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart"]
        Resource = aws_ecr_repository.community.arn
      },
      {
        Effect   = "Allow"
        Action   = ["ecs:DescribeServices", "ecs:DescribeTaskDefinition", "ecs:DescribeTasks", "ecs:ListTasks", "ecs:RegisterTaskDefinition", "ecs:RunTask", "ecs:UpdateService", "logs:FilterLogEvents"]
        Resource = "*"
      },
      {
        Effect    = "Allow"
        Action    = ["iam:PassRole"]
        Resource  = [aws_iam_role.community_execution.arn, aws_iam_role.community_task.arn]
        Condition = { StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" } }
      }
    ]
  })
}

resource "aws_ecs_cluster" "community" { name = "turksquare-community" }

resource "aws_ecs_task_definition" "community" {
  family                   = "turksquare-community-service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.community_execution.arn
  task_role_arn            = aws_iam_role.community_task.arn
  container_definitions = jsonencode([{
    name                   = "community"
    image                  = "${aws_ecr_repository.community.repository_url}:bootstrap"
    essential              = true
    readonlyRootFilesystem = true
    portMappings           = [{ containerPort = 8081, protocol = "tcp" }]
    healthCheck = {
      # The health endpoint verifies both the HTTP server and its private RDS
      # connection. ECS therefore does not count a process that merely starts
      # but cannot reach its encrypted database as healthy.
      command     = ["CMD-SHELL", "node -e \"fetch('http://127.0.0.1:8081/health').then((response) => process.exit(response.ok ? 0 : 1)).catch(() => process.exit(1))\""]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 45
    }
    environment = [
      { name = "NODE_ENV", value = "production" },
      { name = "PORT", value = "8081" },
      { name = "DATABASE_HOST", value = aws_db_instance.community.address },
      { name = "DATABASE_PORT", value = tostring(aws_db_instance.community.port) },
      { name = "DATABASE_NAME", value = "community_db" },
      { name = "JWT_ISSUER", value = "https://api.turksquare.com" },
      { name = "JWT_AUDIENCE", value = "turksquare-mobile" },
      { name = "IDENTITY_JWT_SIGNING_KMS_KEY_ARN", value = var.identity_jwt_signing_kms_key_arn }
    ]
    secrets = concat(
      [
        { name = "DATABASE_USER", valueFrom = "${aws_db_instance.community.master_user_secret[0].secret_arn}:username::" },
        { name = "DATABASE_PASSWORD", valueFrom = "${aws_db_instance.community.master_user_secret[0].secret_arn}:password::" }
      ]
    )
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.community.name
        awslogs-region        = data.aws_region.current.name
        awslogs-stream-prefix = "community"
      }
    }
  }])
}

# Migrations are intentionally a separate, short-lived task. Reusing the API
# task definition would also run the HTTP health check against a process that
# correctly exits after applying SQL, which can turn a successful migration
# into a false unhealthy deployment.
resource "aws_ecs_task_definition" "community_migration" {
  family                   = "turksquare-community-migration"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.community_execution.arn
  task_role_arn            = aws_iam_role.community_task.arn
  container_definitions = jsonencode([{
    name                   = "community-migration"
    image                  = "${aws_ecr_repository.community.repository_url}:bootstrap"
    essential              = true
    readonlyRootFilesystem = true
    command                = ["node", "dist/migrate.js"]
    environment = [
      { name = "NODE_ENV", value = "production" },
      { name = "DATABASE_HOST", value = aws_db_instance.community.address },
      { name = "DATABASE_PORT", value = tostring(aws_db_instance.community.port) },
      { name = "DATABASE_NAME", value = "community_db" }
    ]
    secrets = [
      { name = "DATABASE_USER", valueFrom = "${aws_db_instance.community.master_user_secret[0].secret_arn}:username::" },
      { name = "DATABASE_PASSWORD", valueFrom = "${aws_db_instance.community.master_user_secret[0].secret_arn}:password::" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.community.name
        awslogs-region        = data.aws_region.current.name
        awslogs-stream-prefix = "community-migration"
      }
    }
  }])
}

resource "aws_ecs_task_definition" "profile_projection_worker" {
  family                   = "turksquare-community-profile-projection-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.community_execution.arn
  task_role_arn            = aws_iam_role.community_task.arn
  container_definitions = jsonencode([{
    name    = "profile-projection-worker", image = "${aws_ecr_repository.community.repository_url}:bootstrap", essential = true, readonlyRootFilesystem = true,
    command = ["node", "dist/profile_projection_worker.js"],
    environment = [
      { name = "NODE_ENV", value = "production" }, { name = "DATABASE_HOST", value = aws_db_instance.community.address },
      { name = "DATABASE_PORT", value = tostring(aws_db_instance.community.port) }, { name = "DATABASE_NAME", value = "community_db" },
      { name = "IDENTITY_PROFILE_PROJECTION_QUEUE_URL", value = aws_sqs_queue.identity_profile_projection.id },
      { name = "JWT_ISSUER", value = "https://api.turksquare.com" }, { name = "JWT_AUDIENCE", value = "turksquare-mobile" },
      { name = "IDENTITY_JWT_SIGNING_KMS_KEY_ARN", value = var.identity_jwt_signing_kms_key_arn }
    ],
    secrets          = [{ name = "DATABASE_USER", valueFrom = "${aws_db_instance.community.master_user_secret[0].secret_arn}:username::" }, { name = "DATABASE_PASSWORD", valueFrom = "${aws_db_instance.community.master_user_secret[0].secret_arn}:password::" }],
    logConfiguration = { logDriver = "awslogs", options = { awslogs-group = aws_cloudwatch_log_group.community.name, awslogs-region = data.aws_region.current.name, awslogs-stream-prefix = "profile-projection-worker" } }
  }])
}
resource "aws_ecs_service" "profile_projection_worker" {
  name            = "turksquare-community-profile-projection-worker"
  cluster         = aws_ecs_cluster.community.id
  task_definition = aws_ecs_task_definition.profile_projection_worker.arn
  desired_count   = 0
  launch_type     = "FARGATE"
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  network_configuration {
    subnets          = aws_subnet.community_private[*].id
    security_groups  = [aws_security_group.community_service.id]
    assign_public_ip = false
  }
}

# Edge routing is intentionally a later step. A new service starts at zero so
# migrations and private health checks succeed before any public DNS is added.
resource "aws_ecs_service" "community" {
  name            = "turksquare-community"
  cluster         = aws_ecs_cluster.community.id
  task_definition = aws_ecs_task_definition.community.arn
  desired_count   = 0
  launch_type     = "FARGATE"
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  depends_on = [aws_lb_listener.community_https]
  load_balancer {
    target_group_arn = aws_lb_target_group.community.arn
    container_name   = "community"
    container_port   = 8081
  }
  network_configuration {
    subnets          = aws_subnet.community_private[*].id
    security_groups  = [aws_security_group.community_service.id]
    assign_public_ip = false
  }

  # Terraform owns the service's private network and security boundary.
  # The protected release workflow owns the immutable image revision and
  # desired count after the migration gate has passed. Without this boundary,
  # a later infrastructure apply could roll a healthy service back to the
  # bootstrap image or scale it down to zero.
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }
}

output "community_ecr_repository_url" { value = aws_ecr_repository.community.repository_url }
output "community_deploy_role_arn" { value = aws_iam_role.github_community_deploy.arn }
