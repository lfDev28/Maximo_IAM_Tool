#!/bin/bash
# Script to check if Keycloak is ready for configuration by polling a specific endpoint.

KEYCLOAK_URL="$1" # Expected to be like https://localhost:8443
if [ -z "$KEYCLOAK_URL" ]; then
    echo "Usage: $0 <Keycloak URL>"
    exit 1
fi

# Target a Keycloak endpoint that implies readiness, e.g., the master realm's configuration.
# Using the /clients endpoint for the master realm often requires authentication,
# but fetching realm configuration itself is usually less protected.
# Let's try the realm endpoint itself.
HEALTH_CHECK_TARGET="${KEYCLOAK_URL}/realms/master"

# --- Attempt to communicate with Keycloak ---
# Use curl with specific options:
# --silent: Suppress progress meter
# --insecure: Ignore certificate errors (essential for self-signed certs)
# --fail: Exit with 22 on HTTP errors >= 400
# --connect-timeout: Max time to establish connection (seconds)
# --max-time: Max total time for the operation (seconds)
# -o /dev/null: Discard output body
# -s: Silent mode for curl
# -w '%{http_code}': Output only the HTTP status code
HTTP_CODE=$(curl --silent --insecure --connect-timeout 5 --max-time 20 -o /dev/null -w '%{http_code}' "${HEALTH_CHECK_TARGET}")

# Check the HTTP status code
# Keycloak is considered ready if it responds with 200 OK.
# Sometimes it might respond with 401 Unauthorized if auth is strictly enforced too early,
# but 200 is the safest bet for readiness.
if [ "$HTTP_CODE" == "200" ]; then
    # echo "Keycloak readiness check: Success (HTTP 200)" # Debugging
    exit 0 # Success
else
    # echo "Keycloak readiness check: Failed (HTTP ${HTTP_CODE:-N/A})" # Debugging
    exit 1 # Failure: Keycloak endpoint is not responding with 200 OK
fi