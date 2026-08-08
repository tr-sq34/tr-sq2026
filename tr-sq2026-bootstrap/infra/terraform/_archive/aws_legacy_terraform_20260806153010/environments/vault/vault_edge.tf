resource "aws_security_group" "vault_alb" {
  name        = "turksquare-verification-vault-alb"
  description = "Public TLS ingress for Stripe webhooks and branded verification return"
  vpc_id      = aws_vpc.vault.id
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port       = 8082
    to_port         = 8082
    protocol        = "tcp"
    security_groups = [aws_security_group.vault_service.id]
  }
}
resource "aws_security_group_rule" "vault_service_from_alb" {
  type                     = "ingress"
  security_group_id        = aws_security_group.vault_service.id
  source_security_group_id = aws_security_group.vault_alb.id
  from_port                = 8082
  to_port                  = 8082
  protocol                 = "tcp"
}
resource "aws_lb" "vault" {
  name                       = "turksquare-verification"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.vault_alb.id]
  subnets                    = aws_subnet.vault_public[*].id
  drop_invalid_header_fields = true
}
resource "aws_wafv2_web_acl" "vault" {
  name  = "turksquare-verification-vault"
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
  rule {
    name     = "RateLimit"
    priority = 20
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = 300
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
    metric_name                = "verification-vault"
    sampled_requests_enabled   = true
  }
}
resource "aws_wafv2_web_acl_association" "vault" {
  resource_arn = aws_lb.vault.arn
  web_acl_arn  = aws_wafv2_web_acl.vault.arn
}
resource "aws_acm_certificate" "verification" {
  domain_name       = var.verification_domain_name
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}
resource "aws_acm_certificate_validation" "verification" {
  certificate_arn = aws_acm_certificate.verification.arn
}
resource "aws_lb_target_group" "vault" {
  name        = "turksquare-verification"
  port        = 8082
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.vault.id
  health_check {
    path    = "/health"
    matcher = "200"
  }
}
resource "aws_lb_listener" "vault_https" {
  load_balancer_arn = aws_lb.vault.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate_validation.verification.certificate_arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.vault.arn
  }
}
output "verification_certificate_dns_validation_records" { value = aws_acm_certificate.verification.domain_validation_options }
output "verification_alb_dns_name" { value = aws_lb.vault.dns_name }
