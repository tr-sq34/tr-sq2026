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

resource "aws_vpc_endpoint" "identity_interface" {
  for_each            = toset(["ecr.api", "ecr.dkr", "logs", "secretsmanager", "sts"])
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

resource "aws_iam_role" "identity_task" {
  name               = "TurkSquareIdentityTaskRole"
  assume_role_policy = aws_iam_role.ecs_execution.assume_role_policy
}

resource "aws_iam_role_policy" "identity_task_secrets" {
  name   = "read-identity-runtime-secrets"
  role   = aws_iam_role.identity_task.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = [aws_secretsmanager_secret.identity_service_config.arn, aws_db_instance.identity.master_user_secret[0].secret_arn] }, { Effect = "Allow", Action = ["kms:Decrypt"], Resource = [aws_kms_key.identity.arn] }] })
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
  container_definitions    = jsonencode([{ name = "identity", image = "${aws_ecr_repository.identity.repository_url}:bootstrap", essential = true, portMappings = [{ containerPort = 8080, protocol = "tcp" }], logConfiguration = { logDriver = "awslogs", options = { awslogs-group = aws_cloudwatch_log_group.identity.name, awslogs-region = data.aws_region.current.name, awslogs-stream-prefix = "identity" } } }])
}

resource "aws_ecs_service" "identity" {
  name            = "turksquare-identity"
  cluster         = aws_ecs_cluster.identity.id
  task_definition = aws_ecs_task_definition.identity.arn
  desired_count   = 0
  launch_type     = "FARGATE"
  load_balancer { target_group_arn = aws_lb_target_group.identity.arn container_name = "identity" container_port = 8080 }
  network_configuration {
    subnets          = aws_subnet.identity_private[*].id
    security_groups  = [aws_security_group.identity_service.id]
    assign_public_ip = false
  }
}