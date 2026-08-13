# Gatework Cloudflare Access and Tunnel runbook

> **Written against the AWS deployment.** Gatework now runs as the container app
> `ca-gatework-console-prod` on Azure, with the cloudflared sidecar in the same
> app and the tunnel token in Key Vault as `CLOUDFLARE-TUNNEL-TOKEN` - not in
> ECS, and not in AWS Secrets Manager. The Cloudflare half below (tunnel, Access
> application, policy, MFA) is unchanged and still correct; read every mention of
> ECS or Secrets Manager as its Azure equivalent until this file is rewritten.
> For the public API hostnames - a separate question from the console - see
> `azure-public-dns-cutover.md`.

Terraform creates the ECS service at zero tasks and creates the empty AWS
runtime secret. It does **not** create a Cloudflare API token, Access policy,
or tunnel token. Those objects are intentionally configured from the
Cloudflare dashboard so no Cloudflare credential reaches Terraform state or
GitHub.

## 1. Create the outbound-only tunnel

In Cloudflare Zero Trust, create a named tunnel: `turksquare-gatework-prod`.
Choose the cloudflared connector and copy its token. Add a public hostname:

| Hostname | Service |
| --- | --- |
| `gatework.turksquare.com` | `http://127.0.0.1:3000` |

The sidecar and the Gatework container share the same ECS task network, so the
loopback destination never opens an AWS listener. Do not create an ALB, DNS A
record, public origin, or inbound security-group rule for Gatework.

## 2. Create the Access application

Create a self-hosted Access application for `gatework.turksquare.com`:

- Session duration: 30 minutes; reauthentication: 30 minutes.
- Policy: `Allow` only Cloudflare account members or a tightly maintained
  administrator email group; turn on **Require MFA**.
- Do not add a `Bypass` policy.
- When device management is available, add WARP/device posture to the same
  allow policy.

Cloudflare Access is the first gate; it is not the Gatework authorization
system. Every admin also needs a verified TurkSquare Identity account and a
server-side Gatework role.

## 3. Store the two runtime secrets

In the **Community** AWS account, open Secrets Manager secret
`turksquare/community/gatework/runtime`, then set a JSON value like this:

```json
{
  "GATEWORK_SESSION_SECRET": "a-new-32-plus-byte-random-secret",
  "CLOUDFLARE_TUNNEL_TOKEN": "the-token-copied-from-cloudflare"
}
```

Generate the session secret locally with a password manager or `openssl
rand -base64 48`; never put either value in GitHub, Terraform variables, logs,
or chat.

## 4. Bootstrap the first owner

Before starting Gatework, provide `GATEWORK_BOOTSTRAP_OWNER_EMAIL` only to a
one-off Identity bootstrap task, using the already verified Identity email of
the first owner. It is intentionally not part of the long-lived ECS runtime
secret contract. After the owner role exists, discard the bootstrap value;
future role grants occur only in Gatework by an existing owner.

## 5. Deployment order

1. Apply the Community Terraform plan, which creates the ECR repository,
   zero-count service, CloudWatch log group, and empty secret.
2. Finish steps 1–4 above.
3. Run **Deploy Gatework console** with the exact confirmation string and
   `start_service=true`.
4. Confirm Cloudflare Access blocks a non-member before the Identity sign-in,
   then confirm a Cloudflare member with no Gatework role receives no panel
   access.

If the tunnel is stopped, Gatework becomes unreachable; Community and mobile
APIs remain unaffected.
