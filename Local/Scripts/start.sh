#!/bin/bash
echo "--- Starting Maximo Identity Testing Tool ---"
if [ ! -f .env ]; then
    echo "Error: .env file not found. Please copy .env.example to .env and fill in your secrets."
    exit 1
fi
source .env 

# Start all services defined in docker-compose.yml
if podman-compose up -d; then
    echo "Services started successfully."
    echo "You can view status with: podman-compose ps"
    echo "Access Keycloak Admin Console at: ${KEYCLOAK_HOSTNAME_URL}"
else
    echo "Error starting services. Check logs with: podman-compose logs -f keycloak"
    exit 1
fi