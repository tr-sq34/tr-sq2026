# TurkSquare Messaging Gateway

This service is the only mobile-facing boundary for Matrix direct messages.
It provisions and impersonates Matrix users through a private application
service token. Flutter must not call Matrix room-creation APIs and must not
receive the application-service token.

Before deployment, provision the `messaging_user_projection` and
`messaging_block_projection` outbox consumers. They make authorization decisions
from TurkSquare identity/community state without copying credentials or identity
documents into the messaging database.

Run the database schema migration with `npm run migrate`, then run `npm run
build`. The service is intentionally not deployed until the private Synapse
cluster, its isolated PostgreSQL/Redis stores, and Secrets Manager values exist.
