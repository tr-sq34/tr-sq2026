# Community production deployment order

Community is deliberately unavailable until every prerequisite below passes.

1. Apply the reviewed Identity Terraform update. Record the
   `identity_jwt_signing_kms_key_arn` output. Identity grants only
   `kms:GetPublicKey` to the Community and Vault workload accounts; signing,
   decryption and key administration remain solely in Identity.
2. Bootstrap/update the Community GitHub apply role and Management-account
   `TerraformStateAccessCommunity` trust policy from `infra/bootstrap/`.
3. In the protected `community-production` GitHub Environment, set the
   non-secret variables `AWS_APPLY_ROLE_ARN`,
   `IDENTITY_JWT_SIGNING_KMS_KEY_ARN` (the exact Identity output) and, after
   Terraform creates it, `AWS_COMMUNITY_DEPLOY_ROLE_ARN`. The apply workflow
   refuses a missing or placeholder KMS key ARN.
5. Run the Community Terraform plan, review it, then run the apply workflow.
   Record `identity_profile_projection_queue_arn` and
   `identity_profile_projection_queue_url`. The queue is private and accepts
   `SendMessage` only from the Identity task role.
6. In `identity-production`, set the non-secret variables
   `COMMUNITY_PROFILE_PROJECTION_QUEUE_ARN` and
   `COMMUNITY_PROFILE_PROJECTION_QUEUE_URL` from those exact outputs. Apply
   Identity Terraform once more. The workflow accepts the two values only as a
   pair and enables the durable Identity outbox publisher; it does not expose a
   cross-service HTTP endpoint.
7. In `verification-vault-production`, set
   `IDENTITY_JWT_SIGNING_KMS_KEY_ARN`,
   `COMMUNITY_CAPABILITY_QUEUE_ARN` and `COMMUNITY_CAPABILITY_QUEUE_URL` from
   the reviewed outputs before its apply workflow is ever run. The Vault
   workflow rejects absent, placeholder or mismatched values before Terraform
   contacts AWS.
8. Run `Deploy Community service` with `start_service=false`. It pushes an
   immutable image and runs the one-time, transactional schema migration.
9. Inspect task stop reason and CloudWatch logs. Only then start one private
   Community worker and one private API task. An authenticated health check must pass before a later edge
   gateway, ACM certificate and Cloudflare DNS change are introduced.

No production database, API DNS record, NAT gateway, public bucket or public
ECS task is created by this release step.
