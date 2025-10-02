#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: $0 [-n namespace] [-r release] [-R realm] [-o output]

Options:
  -n  Kubernetes namespace (default: maximo-iam or DEV_NS env)
  -r  Helm release name (default: mas-iam or DEV_RELEASE env)
  -R  Realm to export (default: maximo)
  -o  Output file for the exported JSON (default: maximo-iam-operator/helm-charts/keycloak-mas/helm/seed/realm-export.json)

Dependencies: kubectl, jq (for JSON formatting), and access to the cluster context.
USAGE
}

NAMESPACE="${DEV_NS:-maximo-iam}"
RELEASE="${DEV_RELEASE:-mas-iam}"
REALM="maximo"
DEFAULT_OUTPUT="$(pwd)/maximo-iam-operator/helm-charts/keycloak-mas/helm/seed/realm-export.json"
OUTPUT="$DEFAULT_OUTPUT"

while getopts ":n:r:R:o:h" opt; do
  case $opt in
    n) NAMESPACE="$OPTARG" ;;
    r) RELEASE="$OPTARG" ;;
    R) REALM="$OPTARG" ;;
    o) OUTPUT="$(realpath "$OPTARG")" ;;
    h) usage; exit 0 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; usage; exit 1 ;;
    \?) echo "Invalid option: -$OPTARG" >&2; usage; exit 1 ;;
  esac
done

command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

ADMIN_USER="${KC_ADMIN_USER:-admin}"
SERVICE="${RELEASE}-keycloak"
LOCAL_PORT="18080"
LOG_FILE="$(mktemp)"
PF_PID=""

cleanup() {
  if [[ -n "$PF_PID" ]] && kill -0 "$PF_PID" 2>/dev/null; then
    kill "$PF_PID" >/dev/null 2>&1 || true
    wait "$PF_PID" 2>/dev/null || true
  fi
  rm -f "$LOG_FILE"
}
trap cleanup EXIT

echo "Using namespace=$NAMESPACE release=$RELEASE service=$SERVICE"

SECRET_NAME="$(kubectl -n "$NAMESPACE" get secret -l app.kubernetes.io/component=keycloak,app.kubernetes.io/instance="$RELEASE" -o jsonpath='{.items[?(@.metadata.annotations["helm\.sh/resource-policy"]=="keep")].metadata.name}' 2>/dev/null)"
if [[ -z "$SECRET_NAME" ]]; then
  SECRET_NAME="${RELEASE}-keycloak-admin"
fi

if ! kubectl -n "$NAMESPACE" get secret "$SECRET_NAME" >/dev/null 2>&1; then
  echo "Unable to locate admin secret $SECRET_NAME in namespace $NAMESPACE" >&2
  exit 1
fi

ADMIN_PASSWORD="$(kubectl -n "$NAMESPACE" get secret "$SECRET_NAME" -o jsonpath='{.data.admin-password}' | base64 --decode)"

if [[ -z "$ADMIN_PASSWORD" ]]; then
  echo "Admin password is empty; ensure secret $SECRET_NAME contains admin-password" >&2
  exit 1
fi

echo "Starting temporary port-forward on localhost:${LOCAL_PORT} ..."
set +e
kubectl -n "$NAMESPACE" port-forward svc/"$SERVICE" "${LOCAL_PORT}:8080" >"$LOG_FILE" 2>&1 &
PF_PID=$!
set -e

# Wait for the port-forward to be ready
for _ in {1..24}; do
  if grep -q "Forwarding from" "$LOG_FILE" 2>/dev/null; then
    break
  fi
  if ! kill -0 "$PF_PID" 2>/dev/null; then
    echo "Port-forward process exited unexpectedly" >&2
    cat "$LOG_FILE" >&2
    exit 1
  fi
  sleep 0.5
done

# Final readiness check by probing the health endpoint
for _ in {1..10}; do
  if curl -sf "http://127.0.0.1:${LOCAL_PORT}/health/ready" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

echo "Requesting admin access token ..."
TOKEN_RESPONSE="$(curl -s -X POST "http://127.0.0.1:${LOCAL_PORT}/realms/master/protocol/openid-connect/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d "grant_type=password" \
  -d "client_id=admin-cli" \
  -d "username=${ADMIN_USER}" \
  -d "password=${ADMIN_PASSWORD}")"

ACCESS_TOKEN="$(echo "$TOKEN_RESPONSE" | jq -r '.access_token // empty')"
if [[ -z "$ACCESS_TOKEN" ]]; then
  echo "Failed to obtain access token:" >&2
  echo "$TOKEN_RESPONSE" | jq '.' >&2
  exit 1
fi

echo "Exporting realm '${REALM}' to ${OUTPUT} ..."
mkdir -p "$(dirname "$OUTPUT")"
HTTP_STATUS=$(curl -s -o "$OUTPUT" -w '%{http_code}' \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  "http://127.0.0.1:${LOCAL_PORT}/admin/realms/${REALM}")

if [[ "$HTTP_STATUS" != "200" ]]; then
  echo "Failed to export realm (HTTP ${HTTP_STATUS}). Inspect ${OUTPUT} for details." >&2
  exit 1
fi

# Pretty-print the JSON for readability
jq '.' "$OUTPUT" >"${OUTPUT}.tmp" && mv "${OUTPUT}.tmp" "$OUTPUT"

echo "Realm export written to ${OUTPUT}"
