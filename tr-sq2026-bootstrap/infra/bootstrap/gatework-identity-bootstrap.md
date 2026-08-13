# Gatework Identity bootstrap

> The section below describes the AWS deployment this project started on. The
> live deployment is Azure Container Apps; for it, follow "When the owner account
> does not exist yet" further down, which carries the same rules against the
> current infrastructure.

For the one-time first-owner bootstrap only, copy the current JSON value of the
`turksquare/identity/service-config` Secrets Manager secret and temporarily add
this key:

```json
{
  "GATEWORK_BOOTSTRAP_OWNER_EMAIL": "verified-owner-email@example.com"
}
```

The selected email must already belong to an email-verified TurkSquare user.
Run the one-time bootstrap task with this value, then remove it immediately.
It must never be referenced by the normal ECS task definition; normal Identity
deployments must work after the key has been removed. Terraform deliberately
does not own secret values, so future applies cannot overwrite password, email,
or Gatework rotations.

`GATEWORK_COMMUNITY_AUDIENCE` is normal task configuration, not a secret, and
is set by Terraform to `turksquare-community-gatework`.

## When the owner account does not exist yet

The rule above assumes somebody registered through the app first. An operations
address usually cannot: verification mail goes to a shared inbox, and until
somebody types the code out of it nobody can open the console at all. For that
case the bootstrap can create the account, from a hash and only from a hash:

Three variables on the Identity container app, set once and removed again:

| Variable | Value |
| --- | --- |
| `GATEWORK_BOOTSTRAP_OWNER_EMAIL` | the operations address |
| `GATEWORK_BOOTSTRAP_OWNER_PASSWORD_HASH` | an argon2id digest, via a secret reference |
| `GATEWORK_BOOTSTRAP_OWNER_DISPLAY_NAME` | the name shown in the console footer |

On the live Azure deployment (`rg-turksquare-prod-centralus`, key vault
`kv-turksquare-prod-cu`, app `ca-identity-prod`) that is:

```bash
RG=rg-turksquare-prod-centralus
VAULT=kv-turksquare-prod-cu
APP=ca-identity-prod

# 1. The digest goes into the key vault, like every other secret. --value takes
#    it as one argument, so the $ and , inside it are never parsed.
az keyvault secret set --vault-name "$VAULT" \
  --name GATEWORK-BOOTSTRAP-OWNER-PASSWORD-HASH --value '<argon2id-digest>'

# 2. The app reads it through its own managed identity; the value itself never
#    appears in the container app configuration.
SECRET_URI=$(az keyvault secret show --vault-name "$VAULT" \
  --name GATEWORK-BOOTSTRAP-OWNER-PASSWORD-HASH --query id -o tsv)
IDENTITY_ID=$(az identity show -g "$RG" -n id-identity-prod --query id -o tsv)
az containerapp secret set -g "$RG" -n "$APP" \
  --secrets "gatework-bootstrap-owner-password-hash=keyvaultref:$SECRET_URI,identityref:$IDENTITY_ID"

# 3. A new revision starts, and the seed runs on boot.
az containerapp update -g "$RG" -n "$APP" --set-env-vars \
  GATEWORK_BOOTSTRAP_OWNER_EMAIL=<owner-email> \
  GATEWORK_BOOTSTRAP_OWNER_DISPLAY_NAME='TurkSquare Operasyon' \
  GATEWORK_BOOTSTRAP_OWNER_PASSWORD_HASH=secretref:gatework-bootstrap-owner-password-hash

# 4. Confirm, then take all of it back out.
az containerapp logs show -g "$RG" -n "$APP" --tail 200 | grep -i "bootstrap owner"
az containerapp update -g "$RG" -n "$APP" --remove-env-vars \
  GATEWORK_BOOTSTRAP_OWNER_EMAIL GATEWORK_BOOTSTRAP_OWNER_DISPLAY_NAME GATEWORK_BOOTSTRAP_OWNER_PASSWORD_HASH
az containerapp secret remove -g "$RG" -n "$APP" \
  --secret-names gatework-bootstrap-owner-password-hash
```

Deliberately not in Terraform. A bootstrap variable that lives in the module is
a variable somebody forgets to remove, and then every deploy carries a way to
create an owner account. Set by hand, removed by hand, and the next
`terraform apply` reverts anything left behind.

Rules that make this safe rather than a back door:

- **The plaintext password is never an environment variable, a build argument,
  a commit, a pull request comment or a chat message that survives.** Only the
  argon2id digest reaches the secret store. Identity refuses any value that does
  not start with `$argon2id$`, so a plaintext password pasted here fails closed
  rather than being stored as if it were a hash.
- Generate the digest on a machine you trust, with the same parameters Identity
  uses for every other password (`memoryCost 19456`, `timeCost 2`,
  `parallelism 1`):

  ```bash
  node -e 'require("argon2").hash(process.argv[1],{type:require("argon2").argon2id,memoryCost:19456,timeCost:2,parallelism:1}).then(console.log)' 'THE-PASSWORD'
  ```

  Do not leave the password in shell history: run it with a leading space where
  the shell is configured to skip those, or read it from a prompt.
- The account is written with `email_verified_at` already set, because this
  address is proven by whoever holds the secret store, not by a mail round trip.
- The insert is conditional. A restart, a redeploy or a second bootstrap run
  cannot reset the password of an account whose owner has since changed it -
  once the row exists, the hash in the secret is ignored.
- Remove all three keys once the first login succeeds, exactly as with the
  email-only path, and rotate the password from inside the console.
