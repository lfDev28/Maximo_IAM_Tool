#!/bin/sh
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
COMMON_LIB="$REPO_ROOT/scripts/lib/common.sh"

. "$COMMON_LIB"

load_env_files "$REPO_ROOT"

NS=${NS:-${NAMESPACE:-maximo-iam}}
RAW_RELEASE=${RELEASE:-mas-iam}
SC=${SC:-${STORAGE_CLASS:-}}
RELEASE=$(resolve_release "$RAW_RELEASE" 0)
NAMESPACE=$NS

export NS NAMESPACE RELEASE SC

INCLUDE_SECRETS=0
PURGE_NS=0
AUTO_YES=0
STEP=1
DEBUG=0

usage() {
  cat <<USAGE
Usage: $0 [-y|--yes] [--include-secrets] [--purge-namespace] [--debug]
  -y, --yes           Skip confirmation prompt
  --include-secrets   Delete helper secrets
  --purge-namespace   Delete the entire namespace when finished
  --debug             Print commands as they run
USAGE
}

next_step() {
  message=$1
  printf '%d) %s\n' "$STEP" "$message"
  STEP=$((STEP + 1))
}

while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes)
      AUTO_YES=1
      ;;
    --include-secrets)
      INCLUDE_SECRETS=1
      ;;
    --purge-namespace)
      PURGE_NS=1
      ;;
    --debug)
      DEBUG=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

release_note=""
if [ -n "$RAW_RELEASE" ] && [ "$RAW_RELEASE" != "$RELEASE" ]; then
  release_note=" (from '$RAW_RELEASE')"
fi

echo "Maximo IAM dev cleanup"
echo "  Namespace : $NS"
echo "  Release   : $RELEASE$release_note"
if [ -n "$SC" ]; then
  echo "  StorageClass: $SC"
fi
if [ "$INCLUDE_SECRETS" -eq 1 ]; then
  echo "  Secrets   : will remove"
else
  echo "  Secrets   : preserved"
fi
if [ "$PURGE_NS" -eq 1 ]; then
  echo "  Namespace purge: enabled"
else
  echo "  Namespace purge: disabled"
fi
if [ "$DEBUG" -eq 1 ]; then
  echo "  Debug     : enabled"
fi

if [ "$AUTO_YES" -ne 1 ]; then
  printf "Proceed with cleanup? Type 'yes' to continue: "
  read ans
  if [ "$ans" != "yes" ]; then
    echo "Aborted"
    exit 1
  fi
fi

MAKE_VARS=""
for kv in $(make_args "$NS" "$RELEASE" "$SC"); do
  MAKE_VARS="$MAKE_VARS $kv"
done

log_debug() {
  if [ "$DEBUG" -eq 1 ]; then
    printf 'DEBUG: %s\n' "$*"
  fi
}

run_cmd() {
  if [ "$DEBUG" -eq 1 ]; then
    printf '+ %s\n' "$*"
    sh -c "$*"
    status=$?
    printf 'DEBUG: exit %s for %s\n' "$status" "$*"
    return $status
  else
    sh -c "$*"
  fi
}

exec_ignore() {
  cmd=$1
  if [ "$DEBUG" -eq 1 ]; then
    run_cmd "$cmd" || true
  else
    sh -c "$cmd >/dev/null 2>&1" || true
  fi
}

wait_for_absence() {
  kind=$1
  name=$2
  timeout=${3:-60}
  start=$(date +%s)
  while :; do
    if ! kubectl -n "$NS" get "$kind" "$name" >/dev/null 2>&1; then
      log_debug "$kind/$name no longer present"
      break
    fi
    now=$(date +%s)
    elapsed=$((now - start))
    if [ "$elapsed" -ge "$timeout" ]; then
      echo "WARN: timeout waiting for $kind/$name to be removed" >&2
      break
    fi
    sleep 2
  done
}

operator_dir="$REPO_ROOT/maximo-iam-operator"

run_make() {
  target=$1
  shift
  # shellcheck disable=SC2086
  if [ "$DEBUG" -eq 1 ]; then
    echo "+ make -C $operator_dir $MAKE_VARS $target $*"
    make -C "$operator_dir" $MAKE_VARS "$target" "$@"
    status=$?
    echo "DEBUG: make $target exit $status"
    return $status
  else
    make -C "$operator_dir" $MAKE_VARS "$target" "$@"
  fi
}

stop_operator() {
  next_step "Stopping local helm-operator (if running)..."
  if [ "$DEBUG" -eq 1 ]; then
    run_make dev-down || true
  else
    run_make dev-down >/dev/null 2>&1 || true
  fi
  rm -f "$operator_dir/.dev-operator.pid" "$operator_dir/.dev-operator.out" || true
}

remove_workload() {
  next_step "Removing MaximoIAM custom resource and owned workloads..."
  cmd="kubectl -n $NS delete maximoiam $RELEASE --ignore-not-found --wait=false"
  exec_ignore "$cmd"
  wait_for_absence maximoiam "$RELEASE" 90

  log_debug "Deleting resources labeled with app.kubernetes.io/instance=$RELEASE"
  exec_ignore "kubectl -n $NS delete all,cm,job,svc,pvc -l app.kubernetes.io/instance=$RELEASE --ignore-not-found --wait=false"

  if command -v oc >/dev/null 2>&1; then
    exec_ignore "oc -n $NS delete route -l app.kubernetes.io/instance=$RELEASE --ignore-not-found"
  fi

  log_debug "Deleting Helm release metadata via kubectl"
  exec_ignore "kubectl -n $NS delete secret -l owner=helm,name=$RELEASE --ignore-not-found"
  exec_ignore "kubectl -n $NS delete cm -l owner=helm,name=$RELEASE --ignore-not-found"

  log_debug "Deleting known resource names (fallback)"
  exec_ignore "kubectl -n $NS delete deploy/$RELEASE-keycloak-mas-ldap --ignore-not-found --wait=false"
  exec_ignore "kubectl -n $NS delete svc/$RELEASE-keycloak-mas-ldap --ignore-not-found --wait=false"
  exec_ignore "kubectl -n $NS delete pvc/$RELEASE-keycloak-mas-ldap --ignore-not-found --wait=false"
  exec_ignore "kubectl -n $NS delete cm/$RELEASE-keycloak-mas-ldap-seed --ignore-not-found"
  exec_ignore "kubectl -n $NS delete cm/$RELEASE-keycloak-mas-realm --ignore-not-found"
  exec_ignore "kubectl -n $NS delete cm/$RELEASE-keycloak-env-vars --ignore-not-found"
  exec_ignore "kubectl -n $NS delete job/$RELEASE-keycloak-mas-realm-import --ignore-not-found --wait=false"
  exec_ignore "kubectl -n $NS delete svc/$RELEASE-keycloak --ignore-not-found --wait=false"

  if command -v oc >/dev/null 2>&1; then
    exec_ignore "oc -n $NS delete route $RELEASE-keycloak-mas-keycloak --ignore-not-found"
  fi

  log_debug "Resource deletion commands issued"
  if [ "$INCLUDE_SECRETS" -eq 1 ]; then
    echo "   • Removing helper secrets from namespace $NS"
    if command -v kubectl >/dev/null 2>&1; then
      cmd="kubectl -n $NS delete secret mas-iam-kc-admin mas-iam-ldap-admin mas-iam-pg-auth --ignore-not-found"
      log_debug "$cmd"
      if [ "$DEBUG" -eq 1 ]; then
        run_cmd "$cmd" || true
      else
        kubectl -n "$NS" delete secret mas-iam-kc-admin mas-iam-ldap-admin mas-iam-pg-auth --ignore-not-found >/dev/null 2>&1 || true
      fi
    else
      echo "WARN: kubectl not available; skipping secret deletion" >&2
    fi
  fi
}

cleanup_helm_metadata() {
  next_step "Scrubbing Helm release metadata..."
  if command -v kubectl >/dev/null 2>&1; then
    log_debug "RELEASE=$RELEASE $REPO_ROOT/scripts/dev-nuke-helm.sh --yes"
    if [ "$DEBUG" -eq 1 ]; then
      run_cmd "RELEASE=$RELEASE $REPO_ROOT/scripts/dev-nuke-helm.sh --yes" || true
    else
      RELEASE="$RELEASE" "$REPO_ROOT/scripts/dev-nuke-helm.sh" --yes >/dev/null 2>&1 || true
    fi
  else
    echo "WARN: kubectl not available; skipping Helm metadata cleanup" >&2
  fi
}

delete_namespace() {
  if [ "$PURGE_NS" -eq 1 ]; then
    next_step "Deleting namespace '$NS'..."
    if command -v kubectl >/dev/null 2>&1; then
      cmd="kubectl delete namespace $NS --ignore-not-found"
      log_debug "$cmd"
      if [ "$DEBUG" -eq 1 ]; then
        run_cmd "$cmd" || true
      else
        kubectl delete namespace "$NS" --ignore-not-found >/dev/null 2>&1 || true
      fi
    else
      echo "WARN: kubectl not available; skipping namespace deletion" >&2
    fi
  fi
}

cleanup_files() {
  next_step "Removing local overrides..."
  rm -f "$REPO_ROOT/.env.override" || true
}

stop_operator
remove_workload
cleanup_helm_metadata
delete_namespace
cleanup_files

echo "Cleanup complete. Next step: ./scripts/dev-up.sh"
