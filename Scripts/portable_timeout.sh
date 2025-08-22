# --- Portable Timeout Function ---
# Usage: portable_timeout <duration_in_seconds> <command_to_run> [command_args...]
# Example: portable_timeout 60 echo "Hello"
portable_timeout() {
    local duration=$1
    shift
    local cmd_to_run=("$@") # Store command and args in an array for proper handling
    local pid
    local timeout_exit_code=124 # Standard exit code for timeout

    # Start the command in the background
    "${cmd_to_run[@]}" &
    pid=$!

    # Wait for the specified duration
    ( sleep "$duration" && kill "$pid" 2>/dev/null ) &
    local sleep_pid=$!

    # Wait for the command to finish, or be killed by the sleep process
    wait "$pid" 2>/dev/null
    local cmd_exit_code=$?

    # Kill the sleep process immediately, whether the command succeeded or was killed
    kill "$sleep_pid" 2>/dev/null
    wait "$sleep_pid" 2>/dev/null # Clean up the sleep process

    # Check if the command was killed by our sleep process (indicating a timeout)
    if [ "$cmd_exit_code" -eq 137 ] || [ "$cmd_exit_code" -eq 130 ]; then
        echo "Command timed out after ${duration} seconds."
        return $timeout_exit_code
    # Check if the command exited normally but *after* the duration (less likely with simple wait, but good practice)
    # Note: This check is difficult to implement reliably without more complex process monitoring.
    # The primary way to detect timeout is via the killed signal.
    else
        # Command finished on its own before timeout
        # We return the original exit code of the command.
        # If you want to be sure it *didn't* timeout, you might check if cmd_exit_code is 0
        # but this function is primarily for detecting timeouts.
        return $cmd_exit_code
    fi
}