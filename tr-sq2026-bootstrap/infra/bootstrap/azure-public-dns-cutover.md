# Public API hostnames: moving turksquare.com to Azure

The four public API hostnames the mobile app is built against do not point at
the Azure container apps. Two of them point at an older AWS stack and two do
not resolve at all, which is why Mesajlar and Doğrulama cannot work in a
released build no matter what the services do.

This runbook moves them. Cloudflare objects are created by hand, from the
dashboard, for the same reason as in `gatework-cloudflare.md`: no Cloudflare
credential reaches Terraform state or GitHub.

## What is true today

The zone is on Cloudflare (`dan.ns.cloudflare.com`, `elly.ns.cloudflare.com`).

| Hostname | Mobile app uses it for | Resolves to today |
| --- | --- | --- |
| `api.turksquare.com` | Identity | `turksquare-identity-*.us-east-1.elb.amazonaws.com` |
| `community-api.turksquare.com` | Community | `turksquare-community-*.us-east-1.elb.amazonaws.com` |
| `messages-api.turksquare.com` | Messaging | nothing - NXDOMAIN |
| `verify.turksquare.com` | Verification vault | nothing - NXDOMAIN |

The AWS stack answers, but it is an old build: every `/v1/internal/gatework/*`
route on it returns 404, and the same operator email has a different user id
there than on Azure. It is a separate deployment with a separate database, not
a copy.

Gatework itself is not in this table and does not belong in it. The console has
no ingress at all; it is reached only through the cloudflared sidecar in its own
container app, and that stays as it is.

## 0. Settle the account question first

Changing a DNS record does not move a database. Whoever has an account on the
AWS identity database keeps having it there and stops being able to log in the
moment the hostname points elsewhere.

At the time of writing the Azure identity database holds **3 accounts**, all of
them ours - read it back at any time from the console's Analitik screen, or:

```sh
curl -s https://ca-identity-prod.<env>.centralus.azurecontainerapps.io/v1/auth/gatework/analytics \
  -H "authorization: Bearer $OPERATOR_TOKEN"
```

If that number is still small and the AWS stack has no real members, the cutover
is simply a redirect and nothing has to be migrated. If real members exist on
AWS, they have to be moved before step 2, not after - and that is a separate
piece of work with its own runbook.

## 1. Read the domain verification id

One value for the whole Container App environment, so all four hostnames use the
same one:

```sh
az containerapp show -n ca-identity-prod -g rg-turksquare-prod-centralus \
  --query properties.customDomainVerificationId -o tsv
```

And the ingress hostname each record has to point at:

```sh
for app in ca-identity-prod ca-community-prod ca-messaging-gateway-prod ca-verification-vault-prod; do
  az containerapp show -n "$app" -g rg-turksquare-prod-centralus \
    --query "{app:name, fqdn:properties.configuration.ingress.fqdn}" -o tsv
done
```

## 2. Create the Cloudflare records

Two records per hostname. **Proxy off (grey cloud)** for now: Azure issues the
managed certificate by resolving the hostname itself, and it has to reach the
container app, not Cloudflare's edge.

| Type | Name | Content |
| --- | --- | --- |
| CNAME | `api` | `ca-identity-prod.<env>.centralus.azurecontainerapps.io` |
| TXT | `asuid.api` | the verification id from step 1 |
| CNAME | `community-api` | `ca-community-prod.<env>.centralus.azurecontainerapps.io` |
| TXT | `asuid.community-api` | the verification id |
| CNAME | `messages-api` | `ca-messaging-gateway-prod.<env>.centralus.azurecontainerapps.io` |
| TXT | `asuid.messages-api` | the verification id |
| CNAME | `verify` | `ca-verification-vault-prod.<env>.centralus.azurecontainerapps.io` |
| TXT | `asuid.verify` | the verification id |

Delete the old `api` and `community-api` records that point at the AWS load
balancers in the same edit. Two records for one name is not a migration, it is
a coin toss.

## 3. Declare the hostnames in Terraform

Only after step 2 has propagated. Azure refuses a binding whose DNS does not
already point at it, and this apply runs on **every push to main** - a binding
declared too early fails the deploy of whatever was actually being shipped.

In `environments/prod/terraform.tfvars`:

```hcl
public_api_domains = {
  identity     = ["api.turksquare.com"]
  community    = ["community-api.turksquare.com"]
  messaging    = ["messages-api.turksquare.com"]
  verification = ["verify.turksquare.com"]
}
```

Until this variable is set it is `{}` and Terraform declares no hostname at all,
which is the safe state to be in while the records do not exist yet.

## 4. Ask for the certificates

The binding from step 3 carries no certificate. Azure's managed certificate is
requested once, per hostname, and renews itself afterwards:

```sh
az containerapp hostname bind -n ca-identity-prod -g rg-turksquare-prod-centralus \
  --hostname api.turksquare.com --validation-method CNAME
```

Repeat for the other three. Terraform ignores `certificate_binding_type` and
`container_app_environment_certificate_id` precisely so that the next `apply`
does not strip the certificate back off a live hostname.

Do not add hostnames with `az containerapp hostname add` instead of step 3. A
hostname Terraform does not know about is a hostname the next apply may remove.

## 5. Turn the proxy back on

Once `https://api.turksquare.com/health` answers from Azure, the Cloudflare
records can go back to proxied (orange). SSL/TLS mode must be **Full (strict)**;
Flexible would leave the Cloudflare-to-Azure leg unencrypted.

## 6. Check, then decommission

```sh
for host in api community-api messages-api verify; do
  echo "$host: $(curl -s -o /dev/null -w '%{http_code}' https://$host.turksquare.com/health)"
done
```

All four should answer 200 and the certificate should name `turksquare.com`.
Only then delete the AWS load balancers and ECS services - while they are alive,
a stale cache or a pinned build can still reach the old stack, and it is better
to be able to point at it than to have to reconstruct what it was.

## What is deliberately not in here

**The console's own base URLs.** `COMMUNITY_API_BASE_URL` and friends on
`ca-gatework-console-prod` stay pointed at the `*.azurecontainerapps.io`
hostnames. The console runs in the same environment as the services it calls, so
the container app hostname is the short path; sending those calls out to
Cloudflare and back would add an edge, a certificate and an outage mode to a
call that never leaves Azure, and would buy nothing. The public hostnames exist
for the mobile app, which really is on the other side of the internet.
