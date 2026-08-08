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
