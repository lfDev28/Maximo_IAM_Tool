#!/bin/bash
set -euo pipefail

echo "--- Resetting Maximo Identity Testing Toolkit Environment ---"

# Stop and remove containers
echo "Stopping and removing containers..."
# 'podman-compose down' stops containers and removes networks.
# '-v' flag also removes volumes.
if ! podman-compose down -v; then
    echo "Error during 'podman-compose down -v'. Some services might not have been running or volumes may not exist."
    # Handle this gracefully, as a full reset might be attempted on a non-running state.
fi

echo "--- Reset Complete ---"