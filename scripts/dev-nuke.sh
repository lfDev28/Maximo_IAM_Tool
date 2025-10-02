#!/usr/bin/env bash
set -euo pipefail

# Brutally remove Keycloak/OpenLDAP resources in a namespace, regardless of labels.
# Usage:
#   ./scripts/dev-nuke.sh [-y] [--include-secrets]
# Environment:
#   NS / NAMESPACE   - target namespace (default: maximo-iam)
#   RELEASE          - optional release name to target
#   PATTERN          - regex to match resource names (default: "keycloak|openldap|keycloak-mas|mas-iam-keycloak-mas")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load .env if present
if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a; . "${REPO_ROOT}/.env"; set +a
fi

NS="${NS:-${NAMESPACE:-maximo-iam}}"
RELEASE="${RELEASE:-}"
PATTERN="${PATTERN:-keycloak|openldap|keycloak-mas|mas-iam-keycloak-mas}"
NUKE_SECRETS=0
AUTO_YES=0

for arg in "$@"; do
  case "$arg" in
    -y|--yes) AUTO_YES=1 ;;
    --include-secrets) NUKE_SECRETS=1 ;;
    *) ;;
  esac
done

echo "Namespace: ${NS}"
[[ -n "$RELEASE" ]] && echo "Release:   ${RELEASE}" || true
echo "Pattern:   ${PATTERN}"
echo "Secrets:   $([[ $NUKE_SECRETS -eq 1 ]] && echo include || echo skip)"

if [[ $AUTO_YES -ne 1 ]]; then
  read -r -p "This will DELETE many resources in namespace '${NS}'. Type 'yes' to continue: " ans
  [[ "$ans" == "yes" ]] || { echo "Aborted"; exit 1; }
fi

set -x

# 1) Delete CR if present
if [[ -n "$RELEASE" ]]; then
  kubectl -n "$NS" delete maximoiam "$RELEASE" --ignore-not-found --wait=true || true
fi

# 2) Delete resources by instance labels (if RELEASE provided)
if [[ -n "$RELEASE" ]]; then
  kubectl -n "$NS" delete all,cm,job,cronjob,svc,pvc,ingress -l app.kubernetes.io/instance="$RELEASE" --ignore-not-found || true
  if command -v oc >/dev/null 2>&1; then
    oc -n "$NS" delete route -l app.kubernetes.io/instance="$RELEASE" --ignore-not-found || true
  fi
fi

# 3) Delete by component name labels
for name in openldap keycloak keycloak-realm keycloak-realm-import; do
  kubectl -n "$NS" delete all,cm,job,cronjob,svc,pvc,ingress -l app.kubernetes.io/name="$name" --ignore-not-found || true
done
if command -v oc >/dev/null 2>&1; then
  for name in keycloak openldap; do
    oc -n "$NS" delete route -l app.kubernetes.io/name="$name" --ignore-not-found || true
  done
fi

# 4) Delete any resources whose names match PATTERN (portable, no mapfile)
RES_TYPES=(deploy sts ds job cronjob svc cm pvc pod ingress)
for kind in "${RES_TYPES[@]}"; do
  items=$(kubectl -n "$NS" get "$kind" -o name 2>/dev/null | grep -E "$PATTERN" || true)
  if [[ -n "$items" ]]; then
    # shellcheck disable=SC2086
    kubectl -n "$NS" delete $items --ignore-not-found || true
  fi
done

if command -v oc >/dev/null 2>&1; then
  routes=$(oc -n "$NS" get route -o name 2>/dev/null | grep -E "$PATTERN" || true)
  if [[ -n "$routes" ]]; then
    # shellcheck disable=SC2086
    oc -n "$NS" delete $routes --ignore-not-found || true
  fi
fi

# 5) Optionally delete secrets (names commonly used by this stack)
if [[ $NUKE_SECRETS -eq 1 ]]; then
  kubectl -n "$NS" delete secret mas-iam-kc-admin mas-iam-ldap-admin mas-iam-pg-auth --ignore-not-found || true
  sec=$(kubectl -n "$NS" get secret -o name 2>/dev/null | grep -E "$PATTERN" || true)
  if [[ -n "$sec" ]]; then
    # shellcheck disable=SC2086
    kubectl -n "$NS" delete $sec --ignore-not-found || true
  fi
fi

set +x
echo "\nRemaining resources (for visibility):"
kubectl -n "$NS" get all,cm,job,cronjob,svc,pvc 2>/dev/null || true
if command -v oc >/dev/null 2>&1; then
  oc -n "$NS" get route 2>/dev/null || true
fi

echo "Nuke completed."
