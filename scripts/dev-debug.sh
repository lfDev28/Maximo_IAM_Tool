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
UPDATED_RELEASE=$(grep '^RELEASE=' "$REPO_ROOT/.env.override" 2>/dev/null | cut -d= -f2 | tail -n1)
if [ -n "$UPDATED_RELEASE" ]; then
  RELEASE=$UPDATED_RELEASE
fi

printf 'Namespace: %s\n' "$NS"
printf 'Release:   %s\n' "$RELEASE"

echo "-- Pods --"
if ! kubectl -n "$NS" get pods -l app.kubernetes.io/instance="$RELEASE"; then
  echo "(no pods or error)"
fi

echo "-- Services --"
if ! kubectl -n "$NS" get svc -l app.kubernetes.io/instance="$RELEASE"; then
  echo "(no services or error)"
fi

echo "-- StatefulSets --"
if ! kubectl -n "$NS" get sts -l app.kubernetes.io/instance="$RELEASE"; then
  echo "(no statefulsets or error)"
fi

echo "-- PVCs --"
if ! kubectl -n "$NS" get pvc -l app.kubernetes.io/instance="$RELEASE"; then
  echo "(no pvcs or error)"
fi

 echo "-- Events (last 30) --"
kubectl -n "$NS" get events --sort-by=.metadata.creationTimestamp | tail -n 30 || true

if kubectl -n "$NS" get sts "$RELEASE-postgresql" >/dev/null 2>&1; then
  echo "-- PostgreSQL pod describe --"
  kubectl -n "$NS" describe pod "$RELEASE-postgresql-0" || true
else
  echo "PostgreSQL statefulset not found."
fi

if kubectl -n "$NS" get sts "$RELEASE-keycloak" >/dev/null 2>&1; then
  echo "-- Keycloak pod describe --"
  kubectl -n "$NS" describe pod "$RELEASE-keycloak-0" || true
else
  echo "Keycloak statefulset not found."
fi
