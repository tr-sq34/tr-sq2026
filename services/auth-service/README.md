# TurkSquare Identity Service

The identity service is the sole authority for passwords, sessions, email verification and WebAuthn passkeys. It runs only inside the Identity AWS account and connects to the dedicated identity PostgreSQL cluster.

## Local validation

Copy `.env.example` to `.env` and use non-production development values. Never commit that file.

```sh
npm ci
npm run build
```

Before any staging or production deployment, apply `migrations/` with a migration runner that records applied versions. Database credentials, JWT signing material, email delivery configuration and WebAuthn values are injected through Secrets Manager at runtime.
