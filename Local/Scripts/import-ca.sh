#!/bin/bash
set -e

CA_CERT_PATH="/opt/keycloak/conf/ldap-ca.crt"
TRUSTSTORE_PASS="changeit"

# Preferred truststore path for UBI/OpenJDK
if [ -f "/etc/pki/java/cacerts" ]; then
    TRUSTSTORE_PATH="/etc/pki/java/cacerts"
elif [ -f "/etc/pki/ca-trust/extracted/java/cacerts" ]; then
    TRUSTSTORE_PATH="/etc/pki/ca-trust/extracted/java/cacerts"
else
    TRUSTSTORE_PATH=$(find /etc/java -name cacerts 2>/dev/null | head -n 1)
fi

echo "=== Keycloak LDAPS CA Import Script ==="
echo "Using truststore: ${TRUSTSTORE_PATH:-NOT FOUND}"

if [ -f "$CA_CERT_PATH" ] && [ -n "$TRUSTSTORE_PATH" ]; then
    echo "Importing LDAP CA cert into JVM truststore..."
    keytool -importcert \
        -file "$CA_CERT_PATH" \
        -alias ldapCA \
        -keystore "$TRUSTSTORE_PATH" \
        -storepass "$TRUSTSTORE_PASS" \
        -noprompt || true
    echo "CA cert import complete."
else
    echo "WARNING: CA cert or truststore not found."
    echo "LDAPS connections may fail."
fi

echo "Starting Keycloak..."
exec /opt/keycloak/bin/kc.sh start