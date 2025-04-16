#!/bin/bash
# MCP I/O wrapper script for JSON-RPC communication
# Properly handles stdin/stdout forwarding to ensure clean protocol communication

# Make sure we have a command to run
if [ $# -eq 0 ]; then
    echo >&2 "Usage: $0 command [args...]"
    exit 1
fi

# Create temporary directory for FIFOs
TEMP_DIR=$(mktemp -d)
STDOUT_FIFO="$TEMP_DIR/stdout_fifo"
STDERR_FIFO="$TEMP_DIR/stderr_fifo"
mkfifo "$STDOUT_FIFO"
mkfifo "$STDERR_FIFO"

# Cleanup function to remove temporary files
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Start the real command in the background with stdin/stdout redirected
"$@" < /dev/stdin > "$STDOUT_FIFO" 2> "$STDERR_FIFO" &
COMMAND_PID=$!

# Forward stdout to our stdout without modification (critical for JSON-RPC)
cat "$STDOUT_FIFO" &
STDOUT_PID=$!

# Forward stderr to our stderr
cat "$STDERR_FIFO" >&2 &
STDERR_PID=$!

# Wait for the command to finish
wait $COMMAND_PID
EXIT_CODE=$?

# Wait for output forwarding to complete
wait $STDOUT_PID
wait $STDERR_PID

# Return the original command's exit code
exit $EXIT_CODE