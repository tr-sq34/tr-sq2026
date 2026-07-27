# AWS bootstrap (one time)

This directory contains the only templates needed before Terraform can manage the TurkSquare AWS estate. No AWS access keys are created or stored.

## 1. Terraform state backend

From the Management account's CloudShell in `us-east-1`, upload `state-backend.yaml`, then run:

```bash
aws cloudformation deploy \
  --region us-east-1 \
  --stack-name turksquare-terraform-state \
  --template-file state-backend.yaml
```

The template creates a versioned, KMS-encrypted private state bucket and a KMS-encrypted DynamoDB lock table. The account root retains KMS administration only; Terraform roles are granted narrowly in a later change.

## 2. GitHub Actions plan role

Create a CloudFormation StackSet from `github-oidc-plan-role.yaml` in the Management account and target only:

- Identity/Auth: `342998331436`
- Community: `936706105958`
- Verification Vault: `800554367992`
- Backup/Security Log: `365792980830`

Use the default `GitHubRepository` value only if the GitHub Actions workflow runs from `tr-sq34/tr-sq2026`. The role is intentionally read-only and accepts GitHub OIDC tokens for `main` only. Do not attach `AdministratorAccess` and do not use permanent AWS access keys.

After StackSet completion, save each non-secret role ARN in the matching protected GitHub Environment (`identity`, `community`, `vault`, `backup`). Apply roles are a separate, reviewed change after least-privilege policies are defined.
