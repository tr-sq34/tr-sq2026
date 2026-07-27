data "aws_region" "current" {}

resource "aws_route_table" "identity_private" {
  vpc_id = aws_vpc.identity.id
}

resource "aws_route_table_association" "identity_private" {
  count          = 2
  subnet_id      = aws_subnet.identity_private[count.index].id
  route_table_id = aws_route_table.identity_private.id
}

resource "aws_ecr_repository" "identity" {
  name                 = "turksquare/identity-service"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.identity.arn
  }
}

resource "aws_cloudwatch_log_group" "identity" {
  name              = "/turksquare/identity-service"
  retention_in_days = 90
}

resource "aws_security_group" "identity_service" {
  name        = "turksquare-identity-service"
  description = "Identity Fargate tasks; no public ingress"
  vpc_id      = aws_vpc.identity.id
}

resource "aws_security_group_rule" "database_from_identity_service" {
  type                     = "ingress"
  security_group_id        = aws_security_group.identity_database.id
  source_security_group_id = aws_security_group.identity_service.id
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
}

resource "aws_security_group_rule" "identity_service_from_alb" {
  type                     = "ingress"
  security_group_id        = aws_security_group.identity_service.id
  source_security_group_id = aws_security_group.identity_alb.id
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  description              = "Only the Identity ALB may reach application tasks"
}

resource "aws_security_group" "endpoints" {
  name        = "turksquare-identity-endpoints"
  description = "AWS PrivateLink endpoints for identity tasks"
  vpc_id      = aws_vpc.identity.id
}

resource "aws_security_group_rule" "endpoint_https_from_service" {
  type                     = "ingress"
  security_group_id        = aws_security_group.endpoints.id
  source_security_group_id = aws_security_group.identity_service.id
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
}

# Keep task egress explicit: application containers can reach AWS control-plane
# services only through the PrivateLink endpoint security group on HTTPS.
resource "aws_security_group_rule" "identity_service_https_to_endpoints" {
  type                     = "egress"
  security_group_id        = aws_security_group.identity_service.id
  source_security_group_id = aws_security_group.endpoints.id
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  description              = "HTTPS only to Identity PrivateLink endpoints"
}

resource "aws_vpc_endpoint" "identity_interface" {
  for_each            = toset(["ecr.api", "ecr.dkr", "email", "lambda", "logs", "secretsmanager", "sts"])
  vpc_id              = aws_vpc.identity.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.value}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.identity_private[*].id
  security_group_ids  = [aws_security_group.endpoints.id]
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.identity.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.identity_private.id]
}

resource "aws_iam_role" "ecs_execution" {
  name               = "TurkSquareIdentityEcsExecutionRole"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" }, Action = "sts:AssumeRole" }] })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_execution_runtime_secrets" {
  name = "read-identity-runtime-secrets"
  role = aws_iam_role.ecs_execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [aws_secretsmanager_secret.identity_service_config.arn, aws_db_instance.identity.master_user_secret[0].secret_arn]
      }, {
      Effect   = "Allow"
      Action   = ["kms:Decrypt"]
      Resource = [aws_kms_key.identity.arn]
    }]
  })
}

resource "aws_iam_role" "identity_task" {
  name               = "TurkSquareIdentityTaskRole"
  assume_role_policy = aws_iam_role.ecs_execution.assume_role_policy
}

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_role" "github_identity_deploy" {
  name                 = "GitHubActionsIdentityDeployRole"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = data.aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:tr-sq34@309652758/tr-sq2026@1313519494:environment:identity-production"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "github_identity_deploy" {
  name = "deploy-identity-container-only"
  role = aws_iam_role.github_identity_deploy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "PushIdentityImage"
      Effect   = "Allow"
      Action   = ["ecr:GetAuthorizationToken"]
      Resource = "*"
      }, {
      Sid      = "ManageIdentityRepositoryImages"
      Effect   = "Allow"
      Action   = ["ecr:BatchCheckLayerAvailability", "ecr:CompleteLayerUpload", "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart"]
      Resource = aws_ecr_repository.identity.arn
      }, {
      Sid      = "DeployIdentityService"
      Effect   = "Allow"
      Action   = ["ecs:DescribeServices", "ecs:DescribeTaskDefinition", "ecs:DescribeTasks", "ecs:RegisterTaskDefinition", "ecs:RunTask", "ecs:UpdateService", "logs:FilterLogEvents", "ec2:DescribeVpcEndpoints", "ec2:DescribeRouteTables", "ec2:DescribeSubnets", "ec2:DescribeVpcs", "ec2:DescribeDhcpOptions"]
      Resource = "*"
      }, {
      Sid       = "PassOnlyIdentityTaskRoles"
      Effect    = "Allow"
      Action    = ["iam:PassRole"]
      Resource  = [aws_iam_role.ecs_execution.arn, aws_iam_role.identity_task.arn]
      Condition = { StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" } }
    }]
  })
}

resource "aws_iam_role_policy" "identity_task_secrets" {
  name = "read-identity-runtime-secrets"
  role = aws_iam_role.identity_task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [aws_secretsmanager_secret.identity_service_config.arn, aws_db_instance.identity.master_user_secret[0].secret_arn]
      }, {
      Effect   = "Allow"
      Action   = ["kms:Decrypt"]
      Resource = [aws_kms_key.identity.arn]
      }, {
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = aws_lambda_function.email_relay.arn
      }, {
      Effect    = "Allow"
      Action    = ["ses:SendEmail"]
      Resource  = ["arn:aws:ses:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:identity/${var.email_domain}"]
      Condition = { StringEquals = { "ses:FromAddress" = "${var.email_from_local_part}@${var.email_domain}" } }
    }]
  })
}

resource "aws_ecs_cluster" "identity" { name = "turksquare-identity" }

resource "aws_ecs_task_definition" "identity" {
  family                   = "turksquare-identity-service"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.identity_task.arn
  container_definitions = jsonencode([{
    name                   = "identity"
    image                  = "${aws_ecr_repository.identity.repository_url}:bootstrap"
    essential              = true
    readonlyRootFilesystem = true
    portMappings           = [{ containerPort = 8080, protocol = "tcp" }]
    environment = [
      { name = "NODE_ENV", value = "production" },
      { name = "PORT", value = "8080" },
      { name = "DATABASE_NAME", value = "identity_db" },
      { name = "DATABASE_HOST", value = aws_db_instance.identity.address },
      { name = "DATABASE_PORT", value = tostring(aws_db_instance.identity.port) },
      { name = "EMAIL_RELAY_FUNCTION_NAME", value = aws_lambda_function.email_relay.function_name },
    ]
    secrets = concat(
      [
        for key in ["JWT_SECRET", "JWT_ISSUER", "JWT_AUDIENCE", "WEBAUTHN_RP_ID", "WEBAUTHN_ORIGIN", "EMAIL_FROM", "AUTH_ACTION_BASE_URL", "PWNED_PASSWORDS_MODE"] :
        { name = key, valueFrom = "${aws_secretsmanager_secret.identity_service_config.arn}:${key}::" }
      ],
      [
        { name = "DATABASE_USER", valueFrom = "${aws_db_instance.identity.master_user_secret[0].secret_arn}:username::" },
        { name = "DATABASE_PASSWORD", valueFrom = "${aws_db_instance.identity.master_user_secret[0].secret_arn}:password::" },
      ],
    )
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.identity.name
        awslogs-region        = data.aws_region.current.name
        awslogs-stream-prefix = "identity"
      }
    }
  }])
}

resource "aws_ecs_service" "identity" {
  # ECS refuses to attach a target group until a listener associates it with
  # the ALB.  This explicit dependency also prevents a first-apply race.
  depends_on = [aws_lb_listener.https]

  name                              = "turksquare-identity"
  cluster                           = aws_ecs_cluster.identity.id
  task_definition                   = aws_ecs_task_definition.identity.arn
  desired_count                     = 0
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 60
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.identity.arn
    container_name   = "identity"
    container_port   = 8080
  }
  network_configuration {
    subnets          = aws_subnet.identity_private[*].id
    security_groups  = [aws_security_group.identity_service.id]
    assign_public_ip = false
  }
}

output "identity_deploy_role_arn" {
  value = aws_iam_role.github_identity_deploy.arn
}
