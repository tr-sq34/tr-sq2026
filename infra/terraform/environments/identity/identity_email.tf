resource "aws_ses_domain_identity" "transactional" {
  domain = var.email_domain
}

resource "aws_ses_domain_dkim" "transactional" {
  domain = aws_ses_domain_identity.transactional.domain
}

resource "aws_ses_domain_mail_from" "transactional" {
  domain           = aws_ses_domain_identity.transactional.domain
  mail_from_domain = "mail.${var.email_domain}"

  # Delivery must not silently fail just because a DNS record has a temporary
  # propagation delay. SES falls back to its default MAIL FROM while alarmed.
  behavior_on_mx_failure = "UseDefaultValue"
}

output "ses_dns_records" {
  description = "Create these Cloudflare DNS-only records, then wait for SES verification."
  value = concat(
    [{
      type  = "TXT"
      name  = "_amazonses.${var.email_domain}"
      value = aws_ses_domain_identity.transactional.verification_token
    }],
    [for token in aws_ses_domain_dkim.transactional.dkim_tokens : {
      type  = "CNAME"
      name  = "${token}._domainkey.${var.email_domain}"
      value = "${token}.dkim.amazonses.com"
    }],
    [{
      type     = "MX"
      name     = "mail.${var.email_domain}"
      priority = 10
      value    = "feedback-smtp.us-east-1.amazonses.com"
      }, {
      type  = "TXT"
      name  = "mail.${var.email_domain}"
      value = "v=spf1 include:amazonses.com ~all"
    }],
  )
}
