# AWS decommission

Step 6 of [azure-public-dns-cutover.md](./azure-public-dns-cutover.md), written
out. The legacy AWS stack no longer serves anybody: the four public hostnames
resolve to Azure Container Apps, and nothing in the running code talks to AWS.
This is the paperwork for switching it off.

**Nobody has run this yet.** There is no AWS CLI and no AWS credential on the
machine Claude works from (`~/.aws` absent, no `AWS_*` in the environment, no
`aws-actions/*` step in either GitHub workflow), so the commands below have to be
run by a human with the account. Terraform 1.15.8 *is* installed and the AWS
provider 5.100.0 is already cached under each archived environment, so the
targeted-destroy route works as soon as a credential is present.

Account `626300432889`, region `us-east-1`. The Terraform that built all of this
is archived at
`infra/terraform/_archive/aws_legacy_terraform_20260806153010/environments/`.

## Before deleting anything

All four hostnames must answer 200 from Azure. While the AWS stack is alive a
stale cache or a pinned build can still reach it, and being able to point at the
old thing beats reconstructing what it was.

```bash
for host in api community-api messages-api verify; do
  echo "$host: $(curl -s -o /dev/null -w '%{http_code}' https://$host.turksquare.com/health)"
done
```

Checked 2026-08-14: all four returned 200.

## What is safe to delete

Nothing in the deployed code reaches AWS. Verified by reading the services, not
by assumption:

| Was on AWS | Is now |
| --- | --- |
| ECS services behind three ALBs | Container Apps in `rg-turksquare-prod-centralus` |
| `aws_lambda_function.email_relay` (SES) | `services/email-relay`, an Azure Function on Resend |
| `aws_lambda_function.password_safety` | `services/password-breach-check`, an Azure Function |
| `aws_s3_bucket.community_media` | Azure Blob (`services/community-service/src/infrastructure/azureBlob.ts`) |

No service package depends on `@aws-sdk/*`; no source file references
`amazonaws.com`.

## Order

Services first, then the listeners that route to them, then the load balancers.
Backwards from that and the ALB spends a few minutes health-checking targets
that are already gone.

Per environment, from the archived directory:

```bash
cd infra/terraform/_archive/aws_legacy_terraform_20260806153010/environments/identity
terraform init -backend-config=backend.hcl
terraform destroy \
  -target=aws_ecs_service.identity \
  -target=aws_lb.identity
```

`-target` takes everything that depends on the target with it, so the ALB target
group, the HTTPS listener and the WAF association go in the same pass. Read the
plan before confirming - if it names an `aws_db_instance` or an `aws_s3_bucket`,
stop and re-check the target list.

The three environments and their targets:

**identity** (`environments/identity`)

```
-target=aws_ecs_service.identity
-target=aws_lb.identity
```

**community** (`environments/community`)

```
-target=aws_ecs_service.community
-target=aws_ecs_service.gatework
-target=aws_ecs_service.profile_projection_worker
-target=aws_ecs_service.media_processor_worker
-target=aws_lb.community
```

**vault** (`environments/vault`)

```
-target=aws_ecs_service.verification
-target=aws_lb.vault
```

If Terraform state has drifted too far to plan cleanly, the same thing from the
console, in the same order: ECS → cluster → service → **Update** → desired count
0 → wait for zero running tasks → **Delete**. Then EC2 → Load Balancers → delete
the three. Then Target Groups, which only delete once no listener references
them.

Cluster names are `turksquare-identity`, `turksquare-community`,
`turksquare-verification-vault`. Load balancers are `turksquare-identity`,
`turksquare-community`, `turksquare-verification`.

## What stays, deliberately

**The three Postgres instances and the media bucket are not in scope.**

| Resource | Identifier |
| --- | --- |
| RDS | `turksquare-identity-postgres` |
| RDS | `turksquare-community-postgres` |
| RDS | `turksquare-verification-vault-postgres` |
| S3 | `turksquare-community-media-626300432889` |

Deleting compute is reversible - the image is in ECR and the Terraform is in
this repo. Deleting a database is not. All three carry
`deletion_protection = true` and `skip_final_snapshot = false`, so they cannot
go by accident and would leave a final snapshot if they did. Whether the AWS
copies are still worth keeping now that Azure is authoritative is a call for
whoever owns the data, not something to fold into a decommission step.

The idle cost of a stopped-serving stack is the three RDS instances and the NAT
gateway in the vault VPC, so leaving them running is a real monthly bill, not
free insurance. Worth revisiting once the Azure databases have a backup history
long enough to trust.

## After

Two records in Cloudflare are left over from ACM and no longer validate
anything:

```
_<hash>.api.turksquare.com          CNAME  _<hash>.acm-validations.aws
_<hash>.community-api.turksquare.com CNAME  _<hash>.acm-validations.aws
```

Delete them from the Cloudflare dashboard. Every Cloudflare object in this
project is created by hand for a reason - no Cloudflare credential goes into
Terraform state or GitHub - so this one is a human step too.

Once the ECS services and load balancers are gone, mark step 6 done in
[azure-public-dns-cutover.md](./azure-public-dns-cutover.md).
