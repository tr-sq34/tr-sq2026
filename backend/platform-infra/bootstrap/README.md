# One-time AWS bootstrap

Run these from **Management account CloudShell**; do not create permanent AWS access keys.

```bash
aws cloudformation deploy --stack-name turksquare-terraform-state \
  --template-file state-backend.yaml \
  --capabilities CAPABILITY_NAMED_IAM
```

Create a StackSet from `github-oidc-role.yaml` and target only these accounts:

- Identity/Auth `342998331436`
- Community `936706105958`
- Verification Vault `800554367992`
- Backup/Security Log `365792980830`

The template intentionally creates a **read-only plan role**. Apply roles are created only after each Terraform plan and scoped policy review; never attach `AdministratorAccess` to a GitHub OIDC role.

After StackSet completion, copy each non-secret output role ARN into GitHub Environment Secrets. Use distinct environments (`identity`, `community`, `vault`, `backup`) and require approval for production apply.
