# Gatework Identity bootstrap

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

```json
{
  "GATEWORK_BOOTSTRAP_OWNER_EMAIL": "operations@example.com",
  "GATEWORK_BOOTSTRAP_OWNER_PASSWORD_HASH": "$argon2id$v=19$m=19456,t=2,p=1$...",
  "GATEWORK_BOOTSTRAP_OWNER_DISPLAY_NAME": "TurkSquare Operasyon"
}
```

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
