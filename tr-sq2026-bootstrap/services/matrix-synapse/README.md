# Matrix Synapse deployment contract

Upstream [Synapse](https://github.com/element-hq/synapse) plus a startup script
that renders `homeserver.yaml` and the application service registration from
environment variables. No Synapse code is patched.

TurkSquare uses Synapse only for backend-created 1:1 DMs. See
[`docs/matrix_private_dm_architecture.md`](../../docs/matrix_private_dm_architecture.md)
for the mandatory product and security constraints.

Deployed by `infra/terraform/azure/modules/matrix-synapse` as a single-replica
Container App with **internal ingress only**. The mobile app never talks to it;
`messaging-gateway` is the only client, which is why both must run in the same
Container App environment — an internal FQDN does not resolve outside one.

## Files

| File | Purpose |
| --- | --- |
| `Dockerfile` | Pins the Synapse version and installs the entrypoint. |
| `entrypoint.sh` | Renders both templates into `/data`, writes a default `log.config`, generates the signing key, starts Synapse. |
| `render_config.py` | `${VAR}` substitution that fails hard on an unset variable. |
| `homeserver.yaml.template` | Server config. Federation, public registration and presence are all off. |
| `turksquare-appservice.yaml.template` | Application service registration. `url: null` — Synapse never calls the gateway. |

## Things that cannot be changed after the first boot

Four values are permanent. Changing any of them is a migration, not a config
edit.

- **`server_name`** (`homeserver.yaml.template`) is written into every Matrix ID
  and every event signature. The Key Vault secret `MATRIX-SERVER-NAME` follows
  this file, not the other way round; the gateway compares the two against the
  live homeserver at startup and refuses to serve on a mismatch.
- **The signing key** at `/data/matrix.turksquare.com.signing.key` is generated
  on first boot onto the Azure Files share. Losing it invalidates the signature
  on every event the server has ever sent. The share carries `prevent_destroy`
  for this reason.
- **`MATRIX-MACAROON-SECRET`** signs every access token Synapse issues. Rotating
  it logs out every device on the platform. Terraform generates it once and then
  ignores changes to it.
- **The database collation.** Synapse requires `C`; the `matrix` database is
  created with it explicitly in the shared module, and PostgreSQL cannot change
  a database's collation in place.

## Upgrading Synapse

Bump `SYNAPSE_VERSION` in the `Dockerfile` **in its own commit**. Synapse schema
upgrades are one-way: once a newer version has started against the database, the
previous version refuses to run, so rolling the image back alone will not
recover the service. Read the upstream release notes for schema changes before
bumping more than one minor version at a time.

## Operational notes

- Scaling is fixed at one replica. A Synapse monolith is a single master
  process; a second copy would run the background jobs twice. Horizontal scale
  means splitting into worker processes with Redis replication, not raising
  `max_replicas`.
- A deploy briefly overlaps the old and new revision. This is tolerated but not
  ideal; a zero-overlap restart means deactivating the running revision before
  activating the new one.
- `/health` on port 8008 backs the startup, liveness and readiness probes. First
  boot creates the schema before that port opens, hence the generous startup
  probe.
- SQL and `synapse.http.server` logging is pinned to `WARNING` so access tokens
  and message bodies never reach Log Analytics.
