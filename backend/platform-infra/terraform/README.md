# Terraform deployment contract

Run only from protected CI using an AWS IAM role with short-lived OIDC credentials. Local developer credentials and manual console changes are prohibited.

1. Create the remote Terraform state bucket and DynamoDB lock table in the platform account.
2. Supply an existing VPC with at least three private subnets across availability zones; database security groups must allow inbound 5432 only from service security groups.
3. Apply this root once per isolated AWS account/environment. Do not point identity, community and verification variables at one shared RDS cluster.
4. Configure AWS Backup cross-region/cross-account copy after the backup account policy is approved. Run `terraform fmt -check`, `validate`, `plan` and policy-as-code checks in CI before apply.

The bucket lifecycle is a safety net, not authorization: vault-service must reject all access after a document's retention deadline even if object deletion is delayed.
