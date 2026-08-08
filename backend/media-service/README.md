# Media processing contract

1. `POST /media/uploads/presign` creates a `media_assets` row in `quarantined` state and a five-minute upload session.
2. The client uploads only to the private quarantine bucket using bound content type, size and SHA-256 checksum headers.
3. Completion verifies object metadata via `HeadObject`, sets the asset to `scanning`, and publishes `scan` then `sanitize` jobs.
4. A private worker validates magic bytes, scans malware, removes EXIF/GPS and renders a derivative. Only then it writes a private delivery object, updates `safe_url`/thumbnail metadata and marks the asset `ready`.
5. Any failure marks the asset `rejected`; quarantine objects are deleted within 48 hours. No public object URL is ever stored.

Worker execution must use a dedicated IAM role with read-only quarantine access and write-only delivery access. It must not have access to identity or verification-vault databases.
