# Gatework has no load balancer, public listener, NAT gateway, or database
# connectivity. cloudflared is the sole ingress path and is an outbound-only
# ECS sidecar. The task may receive a public egress address in a public subnet,
# but its security group deliberately contains no ingress rule.

resource "aws_ecr_repository" "gatework" {
  name                 = "turksquare/gatework-console"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration { scan_on_push = true }
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.community.arn
  }
}

resource "aws_cloudwatch_log_group" "gatework" {
  name              = "/turksquare/gatework"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.community.arn
}

# Values are supplied manually after Terraform creates this empty secret:
# GATEWORK_SESSION_SECRET (32+ random bytes) and CLOUDFLARE_TUNNEL_TOKEN.
# Terraform never stores their value in state.
resource "aws_secretsmanager_secret" "gatework_runtime" {
  name                    = "turksquare/community/gatework/runtime"
  description             = "Gatework session encryption and Cloudflare Tunnel runtime configuration"
  kms_key_id              = aws_kms_key.community.arn
  recovery_window_in_days = 30
}

resource "aws_security_group" "gatework" {
  name        = "turksquare-gatework"
  description = "Gatework tunnel task: no inbound connectivity"
  vpc_id      = aws_vpc.community.id
}

# DNS is limited to the VPC resolver. HTTPS/QUIC egress is needed only for the
# Cloudflare Tunnel and Gatework's server-to-server calls to existing domain
# APIs. There is intentionally no inbound rule.
resource "aws_security_group_rule" "gatework_dns_udp" {
  type              = "egress"
  security_group_id = aws_security_group.gatework.id
  cidr_blocks       = ["${cidrhost(var.vpc_cidr, 2)}/32"]
  from_port         = 53
  to_port           = 53
  protocol          = "udp"
}
resource "aws_security_group_rule" "gatework_dns_tcp" {
  type              = "egress"
  security_group_id = aws_security_group.gatework.id
  cidr_blocks       = ["${cidrhost(var.vpc_cidr, 2)}/32"]
  from_port         = 53
  to_port           = 53
  protocol          = "tcp"
}
resource "aws_security_group_rule" "gatework_https_egress" {
  type              = "egress"
  security_group_id = aws_security_group.gatework.id
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
}
resource "aws_security_group_rule" "gatework_quic_egress" {
  type              = "egress"
  security_group_id = aws_security_group.gatework.id
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 7844
  to_port           = 7844
  protocol          = "udp"
}
resource "aws_security_group_rule" "endpoint_from_gatework" {
  type                     = "ingress"
  security_group_id        = aws_security_group.community_endpoints.id
  source_security_group_id = aws_security_group.gatework.id
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
}

resource "aws_iam_role" "gatework_execution" {
  name               = "TurkSquareGateworkEcsExecutionRole"
  assume_role_policy = aws_iam_role.community_execution.assume_role_policy
}
resource "aws_iam_role_policy_attachment" "gatework_execution" {
  role       = aws_iam_role.gatework_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_iam_role_policy" "gatework_execution_secrets" {
  name = "read-gatework-runtime-secret"
  role = aws_iam_role.gatework_execution.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect   = "Allow", Action = ["secretsmanager:GetSecretValue", "kms:Decrypt"],
    Resource = [aws_secretsmanager_secret.gatework_runtime.arn, aws_kms_key.community.arn]
  }] })
}
resource "aws_iam_role" "gatework_task" {
  name               = "TurkSquareGateworkTaskRole"
  assume_role_policy = aws_iam_role.community_execution.assume_role_policy
}

resource "aws_ecs_task_definition" "gatework" {
  family                   = "turksquare-gatework"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.gatework_execution.arn
  task_role_arn            = aws_iam_role.gatework_task.arn

  container_definitions = jsonencode([
    {
      name                   = "gatework"
      image                  = "${aws_ecr_repository.gatework.repository_url}:bootstrap"
      essential              = true
      readonlyRootFilesystem = true
      portMappings           = [{ containerPort = 3000, protocol = "tcp" }]
      environment = [
        { name = "NODE_ENV", value = "production" },
        { name = "PORT", value = "3000" },
        { name = "GATEWORK_ORIGIN", value = "https://gatework.turksquare.com" },
        { name = "IDENTITY_API_BASE_URL", value = var.identity_api_base_url },
        { name = "COMMUNITY_API_BASE_URL", value = var.community_api_base_url }
      ]
      secrets = [{ name = "GATEWORK_SESSION_SECRET", valueFrom = "${aws_secretsmanager_secret.gatework_runtime.arn}:GATEWORK_SESSION_SECRET::" }]
      healthCheck = {
        command     = ["CMD-SHELL", "node -e \"fetch('http://127.0.0.1:3000/api/health').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))\""]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 45
      }
      logConfiguration = { logDriver = "awslogs", options = {
        awslogs-group         = aws_cloudwatch_log_group.gatework.name,
        awslogs-region        = data.aws_region.current.name,
        awslogs-stream-prefix = "gatework"
      } }
    },
    {
      name                   = "cloudflared"
      image                  = var.cloudflared_image
      essential              = true
      readonlyRootFilesystem = true
      command                = ["tunnel", "--no-autoupdate", "run"]
      secrets                = [{ name = "TUNNEL_TOKEN", valueFrom = "${aws_secretsmanager_secret.gatework_runtime.arn}:CLOUDFLARE_TUNNEL_TOKEN::" }]
      logConfiguration = { logDriver = "awslogs", options = {
        awslogs-group         = aws_cloudwatch_log_group.gatework.name,
        awslogs-region        = data.aws_region.current.name,
        awslogs-stream-prefix = "cloudflared"
      } }
    }
  ])
}

resource "aws_ecs_service" "gatework" {
  name            = "turksquare-gatework"
  cluster         = aws_ecs_cluster.community.id
  task_definition = aws_ecs_task_definition.gatework.arn
  desired_count   = 0
  launch_type     = "FARGATE"
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  network_configuration {
    subnets          = aws_subnet.community_public[*].id
    security_groups  = [aws_security_group.gatework.id]
    assign_public_ip = true
  }
  lifecycle { ignore_changes = [task_definition, desired_count] }
}

output "gatework_ecr_repository_url" { value = aws_ecr_repository.gatework.repository_url }
output "gatework_runtime_secret_arn" { value = aws_secretsmanager_secret.gatework_runtime.arn }
output "gatework_deploy_role_arn" { value = aws_iam_role.github_community_deploy.arn }
