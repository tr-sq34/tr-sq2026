# Production authentication contract

The mobile client never decides whether a credential, session, device, or
location is trusted. The identity service is the authority for every decision.

## Session endpoints

- `POST /auth/register`: create a pending account and send a verified-email
  challenge. Do not issue a full session before the verification succeeds.
- `POST /auth/login`: return a 15-minute access JWT and a rotating refresh
  token. Return the same generic failure response for unknown users and bad
  passwords.
- `POST /auth/refresh`: consume one refresh-token family member and issue a
  replacement. Reuse of a consumed token revokes the entire family.
- `POST /auth/logout`: revoke the supplied refresh-token family. The endpoint
  is idempotent and returns no information about an unknown token.
- `POST /auth/password-reset/request` and `/confirm`: use single-use,
  short-lived reset tokens and revoke all sessions after a password change.

## Passkeys (WebAuthn)

- `POST /auth/passkeys/registration/options` returns a one-time challenge,
  server-generated user ID and RP metadata.
- `POST /auth/passkeys/registration/verify` verifies attestation and persists
  only the public credential material, counter and credential ID.
- `POST /auth/passkeys/authentication/options` returns a one-time challenge.
- `POST /auth/passkeys/authentication/verify` validates origin, RP ID hash,
  challenge, signature and counter before issuing the same rotating session.

Challenges expire in five minutes, are bound to a transaction and cannot be
reused. Passkey verification must run server-side using a maintained WebAuthn
library; the mobile client may not validate signatures itself.

## Required controls

The API independently enforces the 12–128 character length and rejects values
derived from the account email/name before Argon2id hashing. Login performs an
Argon2id comparison even for an unknown email, preventing a user-existence
timing branch. A breached-password range lookup sends only the first five
uppercase SHA-1 characters with response padding; the server compares the
returned suffix locally. In production this check fails closed when unavailable.

- Argon2id password hashing with per-password salt and server-side breached
  password screening.
- Per-account, per-IP and device-risk rate limits for registration, login,
  OTP, reset and refresh; use exponential backoff and audit events.
- TLS everywhere, HSTS at the edge, WAF/rate limiting, structured redacted
  logs, and no password, token, challenge or full IP address in application
  logs.
- Access token audience, issuer, expiry and key ID validation; publish signing
  keys through a controlled JWKS rotation process.
- Email verification and step-up reauthentication for password change,
  passkey removal, email change and sensitive marketplace actions.
