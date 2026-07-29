# Matrix Synapse deployment contract

This directory intentionally contains templates, not runnable local secrets.
Synapse is introduced in the Matrix package after the Community network,
separate PostgreSQL, Redis, Secrets Manager entries and private ALB are
provisioned by Terraform.

TurkSquare uses Synapse only for backend-created 1:1 DMs. See
[`docs/matrix_private_dm_architecture.md`](../../docs/matrix_private_dm_architecture.md)
for the mandatory product and security constraints.
