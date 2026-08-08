# Terraform plan foundation

Each account has an independent Terraform root and state prefix. The GitHub Actions workflow assumes the account's read-only plan role, then the S3 backend assumes a Management-account state role scoped to that root's state prefix.

| Root | AWS account | State key | Management state role |
| --- | --- | --- | --- |
| `identity` | `342998331436` | `identity/terraform.tfstate` | `TerraformStateAccessIdentity` |
| `community` | `936706105958` | `community/terraform.tfstate` | `TerraformStateAccessCommunity` |
| `vault` | `800554367992` | `vault/terraform.tfstate` | `TerraformStateAccessVault` |
| `backup` | `365792980830` | `backup/terraform.tfstate` | `TerraformStateAccessBackup` |

The roots contain only connection validation data sources until resource modules are introduced in reviewed changes. Do not run `terraform apply` from this repository: no apply role or apply workflow exists.
