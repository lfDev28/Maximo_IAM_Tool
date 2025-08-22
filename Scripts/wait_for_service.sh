#!/bin/bash
# Script to poll a service until it's ready or a timeout occurs.
# Usage: wait_for_service <command_to_run> <command_args...> -- <max_wait_seconds> <poll_interval_seconds> <command_execution_timeout>
# Example: ./wait_for_service.sh /Scripts/healthcheck.sh https://localhost:8443 -- 180 5 30

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${SCRIPT_DIR}/portable_timeout.sh"

# --- Argument Parsing ---
# Extract command and arguments
COMMAND_TO_RUN=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --) # Separator for timeout parameters
            shift
            MAX_WAIT_SECONDS=${1:-180}
            POLL_INTERVAL_SECONDS=${2:-5}
            CMD_EXECUTION_TIMEOUT=${3:-30} # Timeout for each individual command execution
            break
            ;;
        *)
            COMMAND_TO_RUN+=("$1")
            shift
            ;;
    esac
done

# Validate required arguments
if [ ${#COMMAND_TO_RUN[@]} -eq 0 ] || [ -z "$MAX_WAIT_SECONDS" ] || [ -z "$POLL_INTERVAL_SECONDS" ] || [ -z "$CMD_EXECUTION_TIMEOUT" ]; then
    echo "Usage: $0 <command_to_run> [command_args...] -- <max_wait_seconds> <poll_interval_seconds> <command_execution_timeout>"
    echo "Example: $0 /Scripts/healthcheck.sh https://localhost:8443 -- 180 5 30"
    exit 1
fi

# --- Check if portable_timeout function is available ---
# Ensure portable_timeout is available in the environment where this script is called.
# It's best if setup.sh sources portable_timeout.sh and makes it available.
if ! command -v portable_timeout &> /dev/null; then
    echo "Error: 'portable_timeout' function is not available. Ensure it's sourced before calling this script."
    exit 1
fi

# --- Polling Logic ---
# Calculate how many times we need to poll
NUM_CHECKS=$((MAX_WAIT_SECONDS / POLL_INTERVAL_SECONDS))
if (( MAX_WAIT_SECONDS % POLL_INTERVAL_SECONDS != 0 )); then
    NUM_CHECKS=$((NUM_CHECKS + 1))
fi

echo "Polling service: '${COMMAND_TO_RUN[@]}' for up to ${MAX_WAIT_SECONDS} seconds (check interval ${POLL_INTERVAL_SECONDS}s, individual cmd timeout ${CMD_EXECUTION_TIMEOUT}s)..."

HEALTH_CHECK_SUCCESS=false
for ((i=1; i<=NUM_CHECKS; i++)); do
    echo "Attempt ${i}/${NUM_CHECKS}: Executing command..."

    # Use portable_timeout to run the health check command
    if portable_timeout $CMD_EXECUTION_TIMEOUT "${COMMAND_TO_RUN[@]}"; then
        echo "Service check successful."
        HEALTH_CHECK_SUCCESS=true
        break # Exit the loop if successful
    else
        echo "Service check failed or timed out. Waiting ${POLL_INTERVAL_SECONDS} seconds before next check..."
        sleep "$POLL_INTERVAL_SECONDS"
    fi
done

# Check if the loop finished without success
if [ "$HEALTH_CHECK_SUCCESS" = false ]; then
    echo "Service did not become ready within the ${MAX_WAIT_SECONDS} second timeout."
    exit 1 # Signal overall failure
fi

exit 0 # Signal overall success