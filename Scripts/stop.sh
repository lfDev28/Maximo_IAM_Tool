#!/bin/bash
set -euo pipefail

echo "--- Stopping Maximo Identity Testing Toolkit Services ---"

# Use podman-compose stop to stop containers without removing volumes
if ! podman-compose stop; then
    echo "Error stopping services. Some services might not have been running."
    # It's okay if some services were already stopped, so we don't necessarily exit here.
fi

echo "Services stopped successfully."