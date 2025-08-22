#!/bin/bash
set -euo pipefail

echo "--- Maximo Identity Testing Toolkit Setup ---"

# --- Resolve project root (one level up from Scripts/) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Detect Docker or Podman ---
if command -v podman-compose &>/dev/null; then
    COMPOSE_CMD="podman-compose"
elif command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
else
    echo "Error: Neither podman-compose nor docker-compose found."
    exit 1
fi
echo "Using compose command: $COMPOSE_CMD"

# --- Paths ---
ENV_FILE="${PROJECT_ROOT}/.env"
CERTS_DIR="${PROJECT_ROOT}/certs"
REALM_FILE="${PROJECT_ROOT}/Keycloak/realms/maximo-realm.json"
GENERATE_CERTS_SCRIPT="${PROJECT_ROOT}/Scripts/generate-certs.sh"

# --- Load .env ---
if [ ! -f "$ENV_FILE" ]; then
    echo "Error: .env file not found at $ENV_FILE"
    exit 1
fi
source "$ENV_FILE"

# --- Check required env vars ---
: "${KEYCLOAK_ADMIN_USERNAME:?Missing in .env}"
: "${KEYCLOAK_ADMIN_PASSWORD:?Missing in .env}"
: "${PG_PASSWORD:?Missing in .env}"

# --- Always (re)generate certs + truststore ---
echo "Ensuring TLS certificates and truststore are up to date..."
bash "$GENERATE_CERTS_SCRIPT"

# --- Check realm file ---
if [ ! -f "$REALM_FILE" ]; then
    echo "Error: Realm file not found at $REALM_FILE"
    exit 1
fi

# --- Start services ---
echo "Starting services..."
$COMPOSE_CMD -f "${PROJECT_ROOT}/docker-compose.yml" up -d

# --- Wait for Keycloak ---
echo "Waiting for Keycloak to be ready..."
MAX_WAIT=180
START_TIME=$(date +%s)
until curl -sk https://localhost:8443/ > /dev/null; do
    sleep 5
    if (( $(date +%s) - START_TIME > MAX_WAIT )); then
        echo "Error: Keycloak did not become ready in $MAX_WAIT seconds."
        exit 1
    fi
done
echo "Keycloak is ready."

# # --- Import realm if missing ---
# echo "Checking if realm 'maximo' exists..."
# if ! $COMPOSE_CMD -f "${PROJECT_ROOT}/docker-compose.yml" exec -T keycloak \
#     /opt/keycloak/bin/kc.sh get realms/maximo >/dev/null 2>&1; then
#     echo "Realm not found. Importing..."
#     $COMPOSE_CMD -f "${PROJECT_ROOT}/docker-compose.yml" exec -T keycloak \
#         /opt/keycloak/bin/kc.sh import \
#         --file /opt/keycloak/imports/master-realm.json \
#         --override true
#     echo "Realm import complete."
# else
#     echo "Realm already exists, skipping import."
# fi

echo "--- Setup complete ---"