# Community production deployment order

Community is deliberately unavailable until every prerequisite below passes.

1. Apply the reviewed Identity Terraform update. Record the
   `identity_jwt_signing_kms_key_arn` output. This update permits the two named
   Community task roles to call only `kms:GetPublicKey` against that key.
2. Bootstrap/update the Community GitHub apply role and Management-account
   `TerraformStateAccessCommunity` trust policy from `infra/bootstrap/`.
3. In the protected `community-production` GitHub Environment, set the
   non-secret variables `AWS_APPLY_ROLE_ARN` and, after Terraform creates it,
   `AWS_COMMUNITY_DEPLOY_ROLE_ARN`.
4. Set `identity_jwt_signing_kms_key_arn` in the Community Terraform input to
   the exact Identity output. Never use the placeholder value in production.
5. Run the Community Terraform plan, review it, then run the apply workflow.
   Record `identity_profile_projection_queue_arn` and
   `identity_profile_projection_queue_url`. The queue is private and accepts
   `SendMessage` only from the Identity task role.
6. Apply Identity Terraform once more with those two output values as
   `community_profile_projection_queue_arn` and
   `community_profile_projection_queue_url`. This enables the durable Identity
   outbox publisher; it does not expose a cross-service HTTP endpoint.
7. Run `Deploy Community service` with `start_service=false`. It pushes an
   immutable image and runs the one-time, transactional schema migration.
8. Inspect task stop reason and CloudWatch logs. Only then start one private
   Community worker and one private API task. An authenticated health check must pass before a later edge
   gateway, ACM certificate and Cloudflare DNS change are introduced.

No production database, API DNS record, NAT gateway, public bucket or public
ECS task is created by this release step.
