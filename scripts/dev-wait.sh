#!/bin/sh
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
COMMON_LIB="$REPO_ROOT/scripts/lib/common.sh"

. "$COMMON_LIB"

load_env_files "$REPO_ROOT"

NS=${NS:-${NAMESPACE:-maximo-iam}}
RAW_RELEASE=${RELEASE:-mas-iam}
RELEASE=$(resolve_release "$RAW_RELEASE" 0)

export NS RELEASE

echo "Waiting in namespace '$NS' for release '$RELEASE'..."

deadline() {
  dl_seconds=$1
  shift
  dl_start=$(date +%s)
  while :; do
    if "$@"; then
      return 0
    fi
    dl_now=$(date +%s)
    elapsed=$((dl_now - dl_start))
    if [ "$elapsed" -ge "$dl_seconds" ]; then
      return 1
    fi
    sleep 3
  done
}

exists() {
  kubectl -n "$NS" get "$1" >/dev/null 2>&1
}

echo "• Waiting for any resources with instance label to appear..."
if ! deadline 120 sh -c "kubectl -n '$NS' get all -l app.kubernetes.io/instance='$RELEASE' | grep -q ."; then
  echo "WARN: No resources created yet. Recent operator log tail:" >&2
  sed -n '1,50p' "$REPO_ROOT/maximo-iam-operator/.dev-operator.out" 2>/dev/null | tail -n 50 || true
fi

echo "• Waiting for LDAP PVC '${RELEASE}-keycloak-mas-ldap' to be Bound..."
deadline 180 sh -c "kubectl -n '$NS' get pvc ${RELEASE}-keycloak-mas-ldap -o jsonpath='{.status.phase}' 2>/dev/null | grep -q '^Bound$'" || echo "WARN: LDAP PVC not Bound yet"

echo "• Waiting for PostgreSQL service '${RELEASE}-postgresql'..."
deadline 180 exists "svc/${RELEASE}-postgresql" || echo "WARN: Postgres service not found yet"

echo "• Waiting for PostgreSQL StatefulSet readiness..."
kubectl -n "$NS" rollout status "sts/${RELEASE}-postgresql" --timeout=10m || true

echo "• Waiting for LDAP Deployment readiness..."
kubectl -n "$NS" rollout status "deploy/${RELEASE}-keycloak-mas-ldap" --timeout=5m || true

echo "• Waiting for Keycloak StatefulSet readiness..."
kubectl -n "$NS" rollout status "sts/${RELEASE}-keycloak" --timeout=10m || true

echo "• Inspecting Keycloak database host..."
db_cm="${RELEASE}-keycloak-env-vars"
db_url=""
if kubectl -n "$NS" get configmap "$db_cm" >/dev/null 2>&1; then
  db_url=$(kubectl -n "$NS" get configmap "$db_cm" -o jsonpath='{.data.KC_DB_URL}' 2>/dev/null || true)
fi
if [ -n "$db_url" ]; then
  db_host=$(printf '%s' "$db_url" | sed -e 's|^jdbc:postgresql://||' -e 's|[:/?].*||')
  svc_name="${RELEASE}-postgresql"
  echo "  KC_DB_URL host: $db_host"
  if [ -n "$db_host" ] && [ "$db_host" != "$svc_name" ]; then
    echo "WARN: KC_DB_URL host does not match expected service '$svc_name'"
  fi
else
  echo "WARN: Unable to read KC_DB_URL from ConfigMap '$db_cm'"
fi

echo "• Checking realm import job (if present)..."
if kubectl -n "$NS" get job "${RELEASE}-keycloak-mas-realm-import" >/dev/null 2>&1; then
  deadline 300 sh -c "[ \"\$(kubectl -n '$NS' get job ${RELEASE}-keycloak-mas-realm-import -o jsonpath='{.status.succeeded}' 2>/dev/null)\" = '1' ]" || echo "WARN: Realm import job not completed yet"
fi

if command -v oc >/dev/null 2>&1; then
  echo "• Route host:"
  oc -n "$NS" get route "${RELEASE}-keycloak-mas-keycloak" -o jsonpath='{.spec.host}' 2>/dev/null || true
  echo
fi

echo "Done waiting."
