terraform {
  required_version = ">= 1.8.0, < 2.0.0"

  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }

  backend "s3" {}
}

provider "aws" {
  region = "us-east-1"
  default_tags { tags = { ManagedBy = "Terraform", Project = "TurkSquare", Environment = "vault" } }
}

data "aws_caller_identity" "current" {}
output "plan_account_id" { value = data.aws_caller_identity.current.account_id }
data "aws_region" "current" {}
data "aws_availability_zones" "available" { state = "available" }
data "aws_prefix_list" "s3" { name = "com.amazonaws.${data.aws_region.current.name}.s3" }

locals { availability_zones = slice(data.aws_availability_zones.available.names, 0, 2) }

resource "aws_kms_key" "vault" {
  description             = "TurkSquare verification-vault encrypted data"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}
resource "aws_kms_alias" "vault" {
  name          = "alias/turksquare/verification-vault"
  target_key_id = aws_kms_key.vault.key_id
}

resource "aws_vpc" "vault" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
}
resource "aws_internet_gateway" "vault" {
  vpc_id = aws_vpc.vault.id
}
resource "aws_subnet" "vault_private" {
  count                   = 2
  vpc_id                  = aws_vpc.vault.id
  availability_zone       = local.availability_zones[count.index]
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)
  map_public_ip_on_launch = false
}
resource "aws_subnet" "vault_public" {
  count                   = 2
  vpc_id                  = aws_vpc.vault.id
  availability_zone       = local.availability_zones[count.index]
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index + 8)
  map_public_ip_on_launch = true
}
resource "aws_route_table" "vault_public" {
  vpc_id = aws_vpc.vault.id
}
resource "aws_route" "vault_public_internet" {
  route_table_id         = aws_route_table.vault_public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.vault.id
}
resource "aws_route_table_association" "vault_public" {
  count          = 2
  subnet_id      = aws_subnet.vault_public[count.index].id
  route_table_id = aws_route_table.vault_public.id
}

# Stripe is not an AWS PrivateLink service. Egress is opt-in and the ECS
# service is guarded below so a task cannot start without it.
resource "aws_eip" "vault_nat" {
  count  = var.enable_stripe_egress ? 1 : 0
  domain = "vpc"
}
resource "aws_nat_gateway" "vault" {
  count         = var.enable_stripe_egress ? 1 : 0
  allocation_id = aws_eip.vault_nat[0].id
  subnet_id     = aws_subnet.vault_public[0].id
  depends_on    = [aws_internet_gateway.vault]
}
resource "aws_route_table" "vault_private" {
  vpc_id = aws_vpc.vault.id
}
resource "aws_route" "vault_private_egress" {
  count                  = var.enable_stripe_egress ? 1 : 0
  route_table_id         = aws_route_table.vault_private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.vault[0].id
}
resource "aws_route_table_association" "vault_private" {
  count          = 2
  subnet_id      = aws_subnet.vault_private[count.index].id
  route_table_id = aws_route_table.vault_private.id
}

resource "aws_db_subnet_group" "vault" {
  name       = "turksquare-verification-vault-private"
  subnet_ids = aws_subnet.vault_private[*].id
}
resource "aws_security_group" "vault_service" {
  name   = "turksquare-verification-vault-service"
  vpc_id = aws_vpc.vault.id
}
resource "aws_security_group" "vault_database" {
  name   = "turksquare-verification-vault-postgres"
  vpc_id = aws_vpc.vault.id
}
resource "aws_security_group" "vault_endpoints" {
  name   = "turksquare-verification-vault-endpoints"
  vpc_id = aws_vpc.vault.id
}
resource "aws_security_group_rule" "vault_db_ingress" {
  type                     = "ingress"
  security_group_id        = aws_security_group.vault_database.id
  source_security_group_id = aws_security_group.vault_service.id
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
}
resource "aws_security_group_rule" "vault_db_egress" {
  type                     = "egress"
  security_group_id        = aws_security_group.vault_service.id
  source_security_group_id = aws_security_group.vault_database.id
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
}
resource "aws_security_group_rule" "vault_endpoint_ingress" {
  type                     = "ingress"
  security_group_id        = aws_security_group.vault_endpoints.id
  source_security_group_id = aws_security_group.vault_service.id
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
}
resource "aws_security_group_rule" "vault_endpoint_egress" {
  type                     = "egress"
  security_group_id        = aws_security_group.vault_service.id
  source_security_group_id = aws_security_group.vault_endpoints.id
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
}
resource "aws_security_group_rule" "vault_s3_egress" {
  type              = "egress"
  security_group_id = aws_security_group.vault_service.id
  prefix_list_ids   = [data.aws_prefix_list.s3.id]
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
}
resource "aws_security_group_rule" "vault_stripe_egress" {
  count             = var.enable_stripe_egress ? 1 : 0
  type              = "egress"
  security_group_id = aws_security_group.vault_service.id
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  description       = "HTTPS only; Stripe Identity API and hosted verification flow"
}
resource "aws_vpc_endpoint" "vault_interface" {
  for_each            = toset(["ecr.api", "ecr.dkr", "kms", "logs", "secretsmanager", "sts", "sqs"])
  vpc_id              = aws_vpc.vault.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.value}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.vault_private[*].id
  security_group_ids  = [aws_security_group.vault_endpoints.id]
}
resource "aws_vpc_endpoint" "vault_s3" {
  vpc_id            = aws_vpc.vault.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.vault_private.id]
}

resource "aws_db_instance" "vault" {
  identifier                      = "turksquare-verification-vault-postgres"
  engine                          = "postgres"
  engine_version                  = var.postgres_version
  instance_class                  = var.db_instance_class
  allocated_storage               = 50
  max_allocated_storage           = 200
  storage_type                    = "gp3"
  storage_encrypted               = true
  kms_key_id                      = aws_kms_key.vault.arn
  db_name                         = "verification_vault"
  username                        = "vault_admin"
  manage_master_user_password     = true
  multi_az                        = true
  publicly_accessible             = false
  # Normal operation prevents accidental database deletion.  A separately
  # reviewed decommission run must set vault_decommission_mode=true before a
  # final snapshot can be created and the instance removed.
  deletion_protection             = !var.vault_decommission_mode
  skip_final_snapshot             = false
  final_snapshot_identifier       = "turksquare-verification-vault-final"
  backup_retention_period         = 35
  db_subnet_group_name            = aws_db_subnet_group.vault.name
  vpc_security_group_ids          = [aws_security_group.vault_database.id]
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  auto_minor_version_upgrade      = true
  copy_tags_to_snapshot           = true
}
