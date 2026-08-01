# The Community API is deliberately exposed through its own public TLS edge.
# Fargate tasks and PostgreSQL remain private; the load balancer is the only
# internet-facing resource and only forwards traffic to the Community task SG.
resource "aws_internet_gateway" "community" {
  vpc_id = aws_vpc.community.id
}

resource "aws_subnet" "community_public" {
  count                   = 2
  vpc_id                  = aws_vpc.community.id
  availability_zone       = local.availability_zones[count.index]
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index + 2)
  map_public_ip_on_launch = false
}

resource "aws_route_table" "community_public" {
  vpc_id = aws_vpc.community.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.community.id
  }
}

resource "aws_route_table_association" "community_public" {
  count          = 2
  subnet_id      = aws_subnet.community_public[count.index].id
  route_table_id = aws_route_table.community_public.id
}

resource "aws_security_group" "community_alb" {
  name        = "turksquare-community-alb"
  description = "Public TLS ingress only for Community API"
  vpc_id      = aws_vpc.community.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 8081
    to_port         = 8081
    protocol        = "tcp"
    security_groups = [aws_security_group.community_service.id]
  }
}

resource "aws_security_group_rule" "community_service_from_alb" {
  type                     = "ingress"
  security_group_id        = aws_security_group.community_service.id
  source_security_group_id = aws_security_group.community_alb.id
  from_port                = 8081
  to_port                  = 8081
  protocol                 = "tcp"
}

resource "aws_lb" "community" {
  name                       = "turksquare-community"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.community_alb.id]
  subnets                    = aws_subnet.community_public[*].id
  drop_invalid_header_fields = true
}

resource "aws_wafv2_web_acl" "community" {
  name  = "turksquare-community"
  scope = "REGIONAL"

  default_action { allow {} }

  rule {
    name     = "AWSManagedCommonRules"
    priority = 10
    override_action { none {} }
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

  rule {
    name     = "ApiRateLimit"
    priority = 20
    action { block {} }
    statement {
      rate_based_statement {
        limit              = 600
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "community"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "community" {
  resource_arn = aws_lb.community.arn
  web_acl_arn  = aws_wafv2_web_acl.community.arn
}

resource "aws_acm_certificate" "community_api" {
  domain_name       = var.community_api_domain_name
  validation_method = "DNS"
  lifecycle { create_before_destroy = true }
}

resource "aws_acm_certificate_validation" "community_api" {
  certificate_arn = aws_acm_certificate.community_api.arn
}

resource "aws_lb_target_group" "community" {
  name        = "turksquare-community"
  port        = 8081
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.community.id

  health_check {
    path    = "/health"
    matcher = "200"
  }
}

resource "aws_lb_listener" "community_https" {
  load_balancer_arn = aws_lb.community.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate_validation.community_api.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.community.arn
  }
}

output "community_api_certificate_dns_validation_records" {
  value = aws_acm_certificate.community_api.domain_validation_options
}

output "community_api_alb_dns_name" {
  value = aws_lb.community.dns_name
}
