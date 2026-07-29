#!/usr/bin/env bash
set -euo pipefail

foundation="${1:?usage: validate-production-inputs.sh <community|vault>}"

require_kms_key_arn() {
  local value="${TF_VAR_identity_jwt_signing_kms_key_arn:-}"
  if [[ ! "$value" =~ ^arn:aws:kms:us-east-1:342998331436:key/[0-9a-fA-F-]{36}$ ]]; then
    echo "IDENTITY_JWT_SIGNING_KMS_KEY_ARN must be the real Identity signing KMS key ARN." >&2
    exit 1
  fi
}

require_queue_values() {
  local arn="${TF_VAR_community_capability_queue_arn:-}"
  local url="${TF_VAR_community_capability_queue_url:-}"
  if [[ ! "$arn" =~ ^arn:aws:sqs:us-east-1:936706105958:turksquare-identity-profile-projection$ ]]; then
    echo "COMMUNITY_CAPABILITY_QUEUE_ARN must be the Community projection queue ARN." >&2
    exit 1
  fi
  if [[ ! "$url" =~ ^https://sqs\.us-east-1\.amazonaws\.com/936706105958/turksquare-identity-profile-projection$ ]]; then
    echo "COMMUNITY_CAPABILITY_QUEUE_URL must be the Community projection queue URL." >&2
    exit 1
  fi
}

case "$foundation" in
  identity)
    queue_arn="${TF_VAR_community_profile_projection_queue_arn:-}"
    queue_url="${TF_VAR_community_profile_projection_queue_url:-}"
    if [[ -n "$queue_arn" || -n "$queue_url" ]]; then
      if [[ ! "$queue_arn" =~ ^arn:aws:sqs:us-east-1:936706105958:turksquare-identity-profile-projection$ || ! "$queue_url" =~ ^https://sqs\.us-east-1\.amazonaws\.com/936706105958/turksquare-identity-profile-projection$ ]]; then
        echo "Identity projection queue inputs must be supplied together and match the Community queue." >&2
        exit 1
      fi
    fi
    ;;
  community) require_kms_key_arn ;;
  vault) require_kms_key_arn; require_queue_values ;;
  *) echo "Unknown foundation: $foundation" >&2; exit 2 ;;
esac
