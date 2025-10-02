#!/bin/bash
set -euo pipefail

MANIFEST_DIR=/deploy/manifests
TARGET_NAMESPACE=${TARGET_NAMESPACE:-$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)}
UPSTREAM_CHANNEL=${UPSTREAM_CHANNEL:-fast}
UPSTREAM_SOURCE=${UPSTREAM_SOURCE:-community-operators}
UPSTREAM_SOURCE_NS=${UPSTREAM_SOURCE_NS:-openshift-marketplace}

log() {
  echo "[mas-iam-bootstrap] $*" >&2
}

template_apply() {
  local file=$1
  envsubst <"$file" | kubectl apply -f -
}

main() {
  log "Using namespace: ${TARGET_NAMESPACE}"

  # Ensure OperatorGroup and Subscription for upstream Keycloak operator
  log "Applying upstream Keycloak Operator subscription"
  TEMPLATE_NAMESPACE=$TARGET_NAMESPACE \
  TEMPLATE_CHANNEL=$UPSTREAM_CHANNEL \
  TEMPLATE_SOURCE=$UPSTREAM_SOURCE \
  TEMPLATE_SOURCE_NS=$UPSTREAM_SOURCE_NS \
    template_apply "$MANIFEST_DIR/keycloak-subscription.yaml"

  # Apply application secrets and components
  for manifest in db-secret.yaml postgres.yaml keycloak.yaml realm-import.yaml openldap.yaml; do
    if [ -f "$MANIFEST_DIR/$manifest" ]; then
      log "Applying $manifest"
      TEMPLATE_NAMESPACE=$TARGET_NAMESPACE template_apply "$MANIFEST_DIR/$manifest"
    fi
  done

  log "Bootstrap complete; sleeping"
  sleep infinity
}

main "$@"
