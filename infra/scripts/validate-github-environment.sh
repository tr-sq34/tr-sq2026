#!/usr/bin/env bash
set -euo pipefail

kind="${1:?usage: validate-github-environment.sh <terraform-plan|terraform-apply|service-deploy> <target> <role-arn>}"
target="${2:?target is required}"
role_arn="${3:-}"

case "$target" in
  identity) account_id="342998331436" ;;
  community) account_id="936706105958" ;;
  vault) account_id="800554367992" ;;
  backup) account_id="365792980830" ;;
  *) echo "Unknown TurkSquare target: $target" >&2; exit 2 ;;
esac

case "$kind" in
  terraform-plan) role_name="GitHubActionsTerraformPlanRole" ;;
  terraform-apply) role_name="GitHubActionsTerraformApplyRole" ;;
  service-deploy)
    case "$target" in
      identity) role_name="GitHubActionsIdentityDeployRole" ;;
      community) role_name="GitHubActionsCommunityDeployRole" ;;
      vault) role_name="GitHubActionsVerificationVaultDeployRole" ;;
      *) echo "No service deploy role exists for $target" >&2; exit 2 ;;
    esac
    ;;
  *) echo "Unknown validation kind: $kind" >&2; exit 2 ;;
esac

expected="arn:aws:iam::${account_id}:role/${role_name}"
if [[ "$role_arn" != "$expected" ]]; then
  echo "GitHub Environment role is missing or incorrect for ${kind}/${target}." >&2
  echo "Expected: ${expected}" >&2
  exit 1
fi
