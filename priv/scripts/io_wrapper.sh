#!/bin/bash
# io_wrapper.sh - A script to separate stdout and stderr for JSON RPC protocols
#
# This script runs the given command and separates the output streams.
# For JSON RPC protocols, we need to be very careful about preserving the exact
# input and output format.

# Debug logging function - writes to stderr WITH THE SAME PREFIX as regular stderr
# so it will be correctly captured by the Elixir code
debug() {
    echo "[STDERR] WRAPPER: $*" >&2
}

debug "IO wrapper started at $(date)"
debug "Command: $*"
debug "PID: $$"
debug "PPID: $PPID"
debug "Environment: MCP_STDERR_LOG=${MCP_STDERR_LOG}"

# Make sure command exists
if [ $# -eq 0 ]; then
    echo >&2 "Usage: $0 command [args...]"
    exit 1
fi

# Create temporary directory for our FIFOs
TEMP_DIR=$(mktemp -d)
STDOUT_FIFO="$TEMP_DIR/stdout_fifo"
STDERR_FIFO="$TEMP_DIR/stderr_fifo"
mkfifo "$STDOUT_FIFO"
mkfifo "$STDERR_FIFO"
debug "FIFOs created in $TEMP_DIR"

# Set up stderr log file if environment variable is provided
STDERR_LOG_FILE=${MCP_STDERR_LOG:-/dev/null}
debug "STDERR_LOG_FILE: $STDERR_LOG_FILE"

# Cleanup function
cleanup() {
    debug "Cleanup called at $(date)"
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Start background process for processing stdout
cat "$STDOUT_FIFO" | while IFS= read -r line || [[ -n "$line" ]]; do
    echo "[STDOUT] $line"
done &
STDOUT_PID=$!
debug "STDOUT processor started with PID $STDOUT_PID"

# Start background process for processing stderr
cat "$STDERR_FIFO" | while IFS= read -r line || [[ -n "$line" ]]; do
    # Echo to our stdout with the STDERR prefix
    echo "[STDERR] $line" 
    
    # Debug log
    debug "Original stderr: $line"
    
    # Also append to the stderr log file if it's set
    if [ "$STDERR_LOG_FILE" != "/dev/null" ]; then
        echo "$line" >> "$STDERR_LOG_FILE"
    fi
done &
STDERR_PID=$!
debug "STDERR processor started with PID $STDERR_PID"

# Log command start
debug "Starting command at $(date)"

# Run the actual command, keeping stdin connected and redirecting stdout/stderr
# IMPORTANT: We're not modifying stdin at all, just passing it through
debug "About to execute command: $*"

# Use stdbuf to disable buffering on stdout/stderr for interactive commands
# This helps ensure we see output immediately instead of waiting for buffer flushes
if command -v stdbuf >/dev/null 2>&1; then
    debug "Using stdbuf to disable output buffering"
    stdbuf -i0 -o0 -e0 "$@" < /dev/stdin > "$STDOUT_FIFO" 2> "$STDERR_FIFO"
else
    debug "stdbuf not available, running command directly"
    "$@" < /dev/stdin > "$STDOUT_FIFO" 2> "$STDERR_FIFO"
fi

CMD_EXIT=$?
debug "Command execution completed with exit code: $CMD_EXIT"

# Log command completion
debug "Command finished at $(date) with exit code $CMD_EXIT"

# Send explicit error message for non-zero exit codes
if [ $CMD_EXIT -ne 0 ]; then
    debug "COMMAND FAILED: '$*' exited with status: $CMD_EXIT"
    echo "[STDERR] Command '$*' exited with non-zero status: $CMD_EXIT" 
    
    # Also log to the stderr log file
    if [ "$STDERR_LOG_FILE" != "/dev/null" ]; then
        echo "Command '$*' exited with non-zero status: $CMD_EXIT" >> "$STDERR_LOG_FILE"
    fi
fi

# Close the FIFOs to ensure the background processes complete
debug "Closing FIFOs"
exec 3>"$STDOUT_FIFO"
exec 4>"$STDERR_FIFO"
exec 3>&-
exec 4>&-

# Wait for the background processes to finish
debug "Waiting for STDOUT processor"
wait $STDOUT_PID 
debug "Waiting for STDERR processor"
wait $STDERR_PID

# One final message
debug "IO wrapper finished at $(date)"
debug "Exiting with code $CMD_EXIT"

# Return the original exit code
exit $CMD_EXIT