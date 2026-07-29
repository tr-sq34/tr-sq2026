# GitHub Environment deployment contract

Every AWS workflow validates this contract before it requests an OIDC token.
This turns a missing GitHub variable or a wrong-account role ARN into an
immediate, actionable failure rather than a multi-minute AWS retry.

| GitHub Environment | Purpose | Required non-secret variables |
|---|---|---|
| `identity` | Read-only Terraform plan | `AWS_PLAN_ROLE_ARN=arn:aws:iam::342998331436:role/GitHubActionsTerraformPlanRole` |
| `community-plan` | Read-only Community plan | `AWS_PLAN_ROLE_ARN=arn:aws:iam::936706105958:role/GitHubActionsTerraformPlanRole`, `IDENTITY_JWT_SIGNING_KMS_KEY_ARN` |
| `vault-plan` | Read-only Vault plan | `AWS_PLAN_ROLE_ARN=arn:aws:iam::800554367992:role/GitHubActionsTerraformPlanRole`, `IDENTITY_JWT_SIGNING_KMS_KEY_ARN`, `COMMUNITY_CAPABILITY_QUEUE_ARN`, `COMMUNITY_CAPABILITY_QUEUE_URL` |
| `backup` | Read-only Backup plan | `AWS_PLAN_ROLE_ARN=arn:aws:iam::365792980830:role/GitHubActionsTerraformPlanRole` |
| `identity-production` | Identity apply/deploy | `AWS_APPLY_ROLE_ARN=arn:aws:iam::342998331436:role/GitHubActionsTerraformApplyRole`, `AWS_IDENTITY_DEPLOY_ROLE_ARN=arn:aws:iam::342998331436:role/GitHubActionsIdentityDeployRole`; Community queue values are optional but must be supplied together. |
| `community-production` | Community apply/deploy | `AWS_APPLY_ROLE_ARN=arn:aws:iam::936706105958:role/GitHubActionsTerraformApplyRole`, `IDENTITY_JWT_SIGNING_KMS_KEY_ARN`; add `AWS_COMMUNITY_DEPLOY_ROLE_ARN` only after Community Terraform outputs it. |
| `verification-vault-production` | Vault apply/deploy | `AWS_APPLY_ROLE_ARN=arn:aws:iam::800554367992:role/GitHubActionsTerraformApplyRole`, `IDENTITY_JWT_SIGNING_KMS_KEY_ARN`, `COMMUNITY_CAPABILITY_QUEUE_ARN`, `COMMUNITY_CAPABILITY_QUEUE_URL`; add `AWS_VERIFICATION_VAULT_DEPLOY_ROLE_ARN` only after Vault Terraform outputs it. |

`us-east-1` is source-controlled in all foundation workflows. It is not an
Environment variable and must not be silently changed per deployment.

## Terraform state locking

All environments use the S3 backend's native `use_lockfile = true` locking.
The Management state-access roles already have least-privilege object access
only within their own `identity/`, `community/`, `vault/` or `backup/` prefix;
the corresponding `.tflock` object is therefore covered without widening S3
permissions. The legacy DynamoDB lock table is retained during the migration
and can be removed only after every environment has completed a successful
lockfile-backed plan or apply.
