# Public API hostnames: moving turksquare.com to Azure

The four public API hostnames the mobile app is built against pointed anywhere
but at the Azure container apps. Two of them answered from an older AWS stack
and two did not resolve at all, which is why Mesajlar and Doğrulama could not
work in a released build no matter what the services did.

This runbook moved them. Cloudflare objects are created by hand, from the
dashboard, for the same reason as in `gatework-cloudflare.md`: no Cloudflare
credential reaches Terraform state or GitHub.

## Where this stands

**Steps 0-5 are done (2026-08-14).** All four hostnames resolve to their
container app, carry an Azure managed certificate, answer `/health` with 200,
and sit behind the Cloudflare proxy on Full (strict).

What is left is step 6, decommissioning AWS. It is approved but not run: there
is no AWS credential on the machine Claude works from, so it needs a human with
the account. The commands, the order and the list of what stays are written out
in [aws-decommission.md](./aws-decommission.md).

| Hostname | Serves | Resolves to |
| --- | --- | --- |
| `api.turksquare.com` | Identity | `ca-identity-prod.bravesea-9c47c081.centralus.azurecontainerapps.io` |
| `community-api.turksquare.com` | Community | `ca-community-prod....` |
| `messages-api.turksquare.com` | Messaging | `ca-messaging-gateway-prod....` |
| `verify.turksquare.com` | Verification vault | `ca-verification-vault-prod....` |

The zone is on Cloudflare (`dan.ns.cloudflare.com`, `elly.ns.cloudflare.com`).

### Why this had to happen

The AWS stack answered, but it was an old build: every `/v1/internal/gatework/*`
route on it returned 404, and the same operator email had a different user id
there than on Azure. It was a separate deployment with a separate database, not
a copy. Checked on 2026-08-13, after the Çarşı reaction work shipped to Azure in
`06b25c7`:

```
PUT https://community-api.turksquare.com/v1/marketplace/.../reactions/save  -> 404 Route not found
PUT https://ca-community-prod.bravesea-...azurecontainerapps.io/.../reactions/save -> 401 (route exists, wants a token)
```

Same request, same minute, two different services. Everything merged to main was
live on Azure and invisible to anything built against the public hostnames. Run
that pair today and the two responses are byte-identical, which is the proof the
cutover landed - the public hostname and the container app are now one service.

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
curl -s https://ca-identity-prod.bravesea-9c47c081.centralus.azurecontainerapps.io/v1/auth/gatework/analytics \
  -H "authorization: Bearer $OPERATOR_TOKEN"
```

If that number is still small and the AWS stack has no real members, the cutover
is simply a redirect and nothing has to be migrated. If real members exist on
AWS, they have to be moved before step 2, not after - and that is a separate
piece of work with its own runbook.

## 1. Read the domain verification id

One value for the whole Container App environment, so all four hostnames use the
same one. Read as of 2026-08-13:

```
D7C533E6C49CC876FE6A8CBEB3E7CAD52C3479A913DCBEFF370E5B3D2266C84D
```

It is not a secret - it is published in DNS on purpose, so that only someone who
controls the zone can claim the hostname. Read it back at any time with:

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

The environment's domain suffix is `bravesea-9c47c081.centralus.azurecontainerapps.io`.
It is fixed for the lifetime of the Container App environment, so the table below
is already filled in - but if that environment is ever rebuilt, re-read both
values before touching DNS.

## 2. Create the Cloudflare records

Two records per hostname. **Proxy off (grey cloud)** for now: Azure issues the
managed certificate by resolving the hostname itself, and it has to reach the
container app, not Cloudflare's edge.

| Type | Name | Content |
| --- | --- | --- |
| CNAME | `api` | `ca-identity-prod.bravesea-9c47c081.centralus.azurecontainerapps.io` |
| TXT | `asuid.api` | `D7C533E6C49CC876FE6A8CBEB3E7CAD52C3479A913DCBEFF370E5B3D2266C84D` |
| CNAME | `community-api` | `ca-community-prod.bravesea-9c47c081.centralus.azurecontainerapps.io` |
| TXT | `asuid.community-api` | `D7C533E6C49CC876FE6A8CBEB3E7CAD52C3479A913DCBEFF370E5B3D2266C84D` |
| CNAME | `messages-api` | `ca-messaging-gateway-prod.bravesea-9c47c081.centralus.azurecontainerapps.io` |
| TXT | `asuid.messages-api` | `D7C533E6C49CC876FE6A8CBEB3E7CAD52C3479A913DCBEFF370E5B3D2266C84D` |
| CNAME | `verify` | `ca-verification-vault-prod.bravesea-9c47c081.centralus.azurecontainerapps.io` |
| TXT | `asuid.verify` | `D7C533E6C49CC876FE6A8CBEB3E7CAD52C3479A913DCBEFF370E5B3D2266C84D` |

Delete the old `api` and `community-api` records that point at the AWS load
balancers in the same edit. Two records for one name is not a migration, it is
a coin toss.

Leave the two `_*.acm-validations.aws` CNAMEs alone until step 6. They are what
lets the AWS certificate renew, and the AWS stack is the rollback path until
step 6 says otherwise.

Grey cloud is the part that gets missed, and it fails quietly: a proxied record
resolves to Cloudflare's own addresses, Azure never sees its own fqdn and the
binding is refused. Check before moving on - a CNAME answer means grey, an A
answer in `104.21.*`/`172.67.*` means it is still orange:

```sh
for h in api community-api messages-api verify; do
  echo "$h: $(dig +short CNAME $h.turksquare.com @1.1.1.1)"
  echo "  asuid: $(dig +short TXT asuid.$h.turksquare.com @1.1.1.1)"
done
```

## 3. Add the hostname to the app

Only after step 2 has propagated. Azure refuses a binding whose DNS does not
already point at it.

```sh
az containerapp hostname add -n ca-identity-prod -g rg-turksquare-prod-centralus \
  --hostname api.turksquare.com
```

**Terraform does not own these hostnames, and cannot.** It was tried, in
`public_api_domains`, and it lasted exactly as long as it took step 4 to issue
the first certificate. `azurerm_container_app_custom_domain` reads
`container_app_environment_certificate_id` back through a parser that only
accepts `/certificates/<name>`; an Azure managed certificate lives under
`/managedCertificates/<name>`, so every plan after the first binding died with:

```
parsing segment "staticCertificates": parsing the Certificate ID: the segment
at position 8 didn't match
```

That is a read, not a diff, so `ignore_changes` on the certificate fields does
not help - it was already there. 3.117.1 is the last 3.x release and it does not
fix it. Since this apply runs on **every push to main**, one unreadable resource
failed the deploy of everything else being shipped, so the four resources were
removed from state and the block deleted.

What guards the hostnames instead is `ignore_changes = [ingress[0].custom_domain]`
on `azurerm_container_app` in the module. Without it an apply would carry an
empty customDomains list alongside the image it was actually shipping. Check
after the first deploy that follows any change to that module - the four
`/health` checks in step 6 are the test.

Getting these back into Terraform means the azurerm 4.x upgrade, which is its
own piece of work with its own blast radius.

## 4. Ask for the certificates

The binding from step 3 carries no certificate. Azure's managed certificate is
requested once, per hostname, and renews itself afterwards:

```sh
az containerapp hostname bind -n ca-identity-prod -g rg-turksquare-prod-centralus \
  --hostname api.turksquare.com --environment cae-turksquare-prod-cu \
  --validation-method CNAME
```

`--environment` is not optional even though every other argument already
identifies the app; without it the command exits with "Please specify at least
one of parameters: --certificate and --environment". The three remaining
hostnames can be bound in parallel - each takes a few minutes, and they do not
touch each other.

Repeat for the other three.

Confirm afterwards that all four report `SniEnabled` rather than `Disabled`:

```sh
for app in ca-identity-prod ca-community-prod ca-messaging-gateway-prod ca-verification-vault-prod; do
  az containerapp show -n "$app" -g rg-turksquare-prod-centralus \
    --query "properties.configuration.ingress.customDomains[].{n:name,b:bindingType}" -o tsv
done
```

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
