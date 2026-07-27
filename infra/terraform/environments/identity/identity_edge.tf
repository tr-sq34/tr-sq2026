resource "aws_internet_gateway" "identity" {
  vpc_id = aws_vpc.identity.id
}

resource "aws_subnet" "identity_public" {
  count                   = 2
  vpc_id                  = aws_vpc.identity.id
  availability_zone       = local.availability_zones[count.index]
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index + 2)
  map_public_ip_on_launch = false
}

resource "aws_route_table" "identity_public" {
  vpc_id = aws_vpc.identity.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.identity.id
  }
}

resource "aws_route_table_association" "identity_public" {
  count          = 2
  subnet_id      = aws_subnet.identity_public[count.index].id
  route_table_id = aws_route_table.identity_public.id
}

resource "aws_security_group" "identity_alb" {
  name        = "turksquare-identity-alb"
  description = "Public TLS ingress only"
  vpc_id      = aws_vpc.identity.id
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.identity_service.id]
  }
}

resource "aws_lb" "identity" {
  name                       = "turksquare-identity"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.identity_alb.id]
  subnets                    = aws_subnet.identity_public[*].id
  drop_invalid_header_fields = true
}

resource "aws_wafv2_web_acl" "identity" {
  name  = "turksquare-identity"
  scope = "REGIONAL"
  default_action {
    allow {}
  }
  rule {
    name     = "AWSManagedCommonRules"
    priority = 10
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "common"
      sampled_requests_enabled   = true
    }
  }
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "identity"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "identity" {
  resource_arn = aws_lb.identity.arn
  web_acl_arn  = aws_wafv2_web_acl.identity.arn
}

resource "aws_acm_certificate" "api" {
  domain_name       = var.api_domain_name
  validation_method = "DNS"
  lifecycle { create_before_destroy = true }
}

output "api_certificate_dns_validation_records" {
  value = aws_acm_certificate.api.domain_validation_options
}

output "identity_alb_dns_name" { value = aws_lb.identity.dns_name }