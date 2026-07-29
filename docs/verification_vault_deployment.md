# Stripe Identity Verification Vault — controlled deployment

This service is intentionally disabled after Terraform applies. It must not be
started until all of the following are complete.

1. Run the Vault Terraform plan/apply in AWS account `800554367992`.
2. Create the ACM DNS validation CNAME records emitted as
   `verification_certificate_dns_validation_records` in Cloudflare (DNS only).
3. Create `verify.turksquare.com` as a DNS-only CNAME to
   `verification_alb_dns_name` after the certificate is issued.
4. Put exactly this JSON into the Vault `stripe-credentials` secret using AWS
   Console or CloudShell; never place these values in Terraform, GitHub, CI
   output or application source:
   `{ "STRIPE_SECRET_KEY": "...", "STRIPE_WEBHOOK_SECRET": "..." }`
5. Set `community_capability_queue_arn` and `community_capability_queue_url`
   from the Community Terraform outputs, and set `enable_stripe_egress=true`.
6. Add GitHub Environment `verification-vault-production` and set its
   `AWS_VERIFICATION_VAULT_DEPLOY_ROLE_ARN` variable from Terraform output.
7. Run the protected workflow with migrations enabled, then start one task.
8. In Stripe Dashboard, register the HTTPS webhook endpoint
   `https://verify.turksquare.com/v1/verification/webhooks/stripe` and copy its
   signing secret into the AWS secret in step 4.

Only the session reference, result, policy version and audit event are stored
by TurkSquare. Identity documents and selfies remain with Stripe.
