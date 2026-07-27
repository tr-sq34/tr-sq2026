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

The role is intentionally read-only and maps each approved workload account to exactly one GitHub Environment (`identity`, `community`, `vault`, or `backup`). `GitHubOidcSubjectPrefix` uses the canonical owner and repository IDs emitted by GitHub OIDC; update it only after an explicit OIDC claim diagnostic if repository ownership changes. Each GitHub Environment is restricted to `main`, so the role remains main-branch scoped without accepting branch-subject tokens. Do not attach `AdministratorAccess` and do not use permanent AWS access keys.

After StackSet completion, save each non-secret role ARN in the matching protected GitHub Environment (`identity`, `community`, `vault`, `backup`). Apply roles are a separate, reviewed change after least-privilege policies are defined.

## 3. Cross-account Terraform state access

The plan roles live in workload accounts while the Terraform state backend lives in the Management account. Deploy `terraform-state-access-roles.yaml` from Management CloudShell before enabling the Terraform plan workflow:

```bash
aws cloudformation deploy \
  --region us-east-1 \
  --stack-name turksquare-terraform-state-access \
  --template-file terraform-state-access-roles.yaml \
  --capabilities CAPABILITY_NAMED_IAM
```

Then update the StackSet from the current `github-oidc-plan-role.yaml` so workload plan roles are permitted to assume only the matching Management-account state role. Each state role has a strict trust relationship to one workload plan role and can read or write only its own S3 state prefix (`identity/`, `community/`, `vault/`, or `backup/`).
