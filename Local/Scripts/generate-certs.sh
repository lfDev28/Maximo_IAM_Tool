#!/bin/bash
set -euo pipefail

echo "--- Certificate Generation Script ---"

# --- Dependency & Setup Checks ---
if ! command -v mkcert &> /dev/null; then
    echo "Error: mkcert is not installed. Please install it first."
    echo "macOS: brew install mkcert nss"
    echo "Linux: Follow instructions at https://github.com/FiloSottile/mkcert"
    exit 1
fi

if ! mkcert -install; then
    echo "Error: Failed to install mkcert CA. Please check mkcert output and permissions."
    exit 1
fi
echo "mkcert local CA is installed."

# --- Directory Definitions ---
CERTS_DIR="./certs"
KEYCLOAK_CERTS_DIR="${CERTS_DIR}/keycloak"
LDAP_CERTS_DIR="${CERTS_DIR}/ldap"

# Always delete old alias if it exists
podman run --rm -v "$(pwd)/${CERTS_DIR}:/certs" docker.io/library/openjdk:17-jdk \
  keytool -delete \
  -alias ldapCA \
  -keystore /certs/keycloak/truststore.jks \
  -storepass changeit || true

# Import fresh CA cert
podman run --rm -v "$(pwd)/${CERTS_DIR}:/certs" docker.io/library/openjdk:17-jdk \
  keytool -importcert \
  -file /certs/ldap/ca.crt \
  -alias ldapCA \
  -keystore /certs/keycloak/truststore.jks \
  -storepass changeit \
  -noprompt

mkdir -p "$KEYCLOAK_CERTS_DIR"
mkdir -p "$LDAP_CERTS_DIR"

# --- Generate Keycloak Certificate ---
echo ""
echo "--- Processing Keycloak Certificate ---"
KEYCLOAK_KEY_PATH="${KEYCLOAK_CERTS_DIR}/keycloak-key.pem"
KEYCLOAK_CERT_PATH="${KEYCLOAK_CERTS_DIR}/keycloak.pem"

if [ -f "$KEYCLOAK_KEY_PATH" ] && [ -f "$KEYCLOAK_CERT_PATH" ]; then
    echo "Keycloak certificates already exist. Skipping."
else
    echo "Generating new certificates for Keycloak..."
    mkcert -key-file "$KEYCLOAK_KEY_PATH" -cert-file "$KEYCLOAK_CERT_PATH" \
      localhost 127.0.0.1 ::1
    echo "Keycloak certificates created successfully."
fi

# --- Generate OpenLDAP Certificate ---
echo ""
echo "--- Processing OpenLDAP Certificate ---"
LDAP_KEY_PATH="${LDAP_CERTS_DIR}/server.key"
LDAP_CERT_PATH="${LDAP_CERTS_DIR}/server.crt"
LDAP_CA_PATH="${LDAP_CERTS_DIR}/ca.crt"

if [ -f "$LDAP_KEY_PATH" ] && [ -f "$LDAP_CERT_PATH" ]; then
    echo "OpenLDAP certificates already exist. Skipping."
else
    echo "Generating new certificates for OpenLDAP..."
    mkcert -key-file "$LDAP_KEY_PATH" -cert-file "$LDAP_CERT_PATH" \
      ldap.example.com openldap localhost
    # Copy mkcert root CA for truststore
    cp "$(mkcert -CAROOT)/rootCA.pem" "$LDAP_CA_PATH"
    echo "OpenLDAP certificates created successfully."
fi

# --- Generate Keycloak Truststore ---
echo ""
echo "--- Generating Keycloak Truststore ---"
TRUSTSTORE_PATH="${KEYCLOAK_CERTS_DIR}/truststore.jks"
if [ -f "$TRUSTSTORE_PATH" ]; then
    echo "Truststore already exists. Skipping."
else
    echo "Building truststore.jks with LDAP CA..."
    podman run --rm -v "$(pwd)/${CERTS_DIR}:/certs" openjdk:17-jdk \
      keytool -importcert \
      -file /certs/ldap/ca.crt \
      -alias ldapCA \
      -keystore /certs/keycloak/truststore.jks \
      -storepass changeit \
      -noprompt
    echo "Truststore created at $TRUSTSTORE_PATH"
fi

echo ""
echo "--- Certificate setup complete. All certificates and truststore are up to date. ---"