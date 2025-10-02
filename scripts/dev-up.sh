#!/bin/sh
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
COMMON_LIB="$REPO_ROOT/scripts/lib/common.sh"

. "$COMMON_LIB"

load_env_files "$REPO_ROOT"

KC_ADMIN_PASSWORD=${KC_ADMIN_PASSWORD:-${KEYCLOAK_ADMIN_PASSWORD:-}}
LDAP_ADMIN_PASSWORD=${LDAP_ADMIN_PASSWORD:-${LDAP_BIND_PASSWORD:-}}
PG_PASSWORD=${PG_PASSWORD:-}
NS=${NS:-${NAMESPACE:-maximo-iam}}
RAW_RELEASE=${RELEASE:-mas-iam}
SC=${SC:-${STORAGE_CLASS:-}}

if [ -z "$KC_ADMIN_PASSWORD" ]; then
  echo "ERROR: KC_ADMIN_PASSWORD (or KEYCLOAK_ADMIN_PASSWORD) is not set" >&2
  exit 1
fi
if [ -z "$LDAP_ADMIN_PASSWORD" ]; then
  echo "ERROR: LDAP_ADMIN_PASSWORD (or LDAP_BIND_PASSWORD) is not set" >&2
  exit 1
fi
if [ -z "$PG_PASSWORD" ]; then
  echo "INFO: PG_PASSWORD not set; generating a random password for this run." >&2
  if command -v python3 >/dev/null 2>&1; then
    PG_PASSWORD=$(python3 - <<'PY'
import secrets
import string
alphabet = string.ascii_letters + string.digits
print(''.join(secrets.choice(alphabet) for _ in range(24)))
PY
    )
  else
    PG_PASSWORD=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)
  fi
fi

RELEASE=$(resolve_release "$RAW_RELEASE" 1)
NAMESPACE=$NS

export KC_ADMIN_PASSWORD LDAP_ADMIN_PASSWORD PG_PASSWORD NS NAMESPACE RELEASE SC

persist_override "$REPO_ROOT" "$RELEASE" "$NS" "$SC"

echo "Namespace: $NS  Release: $RELEASE  StorageClass: ${SC:-<default>}"

MAKE_VARS=""
for kv in $(make_args "$NS" "$RELEASE" "$SC"); do
  MAKE_VARS="$MAKE_VARS $kv"
done

operator_dir="$REPO_ROOT/maximo-iam-operator"

run_make() {
  target=$1
  shift
  # shellcheck disable=SC2086
  make -C "$operator_dir" $MAKE_VARS "$target" "$@"
}

run_make dev-down >/dev/null 2>&1 || true
rm -f "$operator_dir/.dev-operator.out" || true

run_make dev-up

echo
echo "--- Waiting for stack to be ready ---"
"$REPO_ROOT/scripts/dev-wait.sh" || true

echo
echo "--- Final status ---"
run_make dev-status || true
