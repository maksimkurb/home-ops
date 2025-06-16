#!/bin/sh

# SSH Remote Config Backup Script
# This script connects to a remote host via SSH and saves the running configuration

# Configuration variables
REMOTE_HOST=""
REMOTE_USER=""
REMOTE_PASS=""
REMOTE_PORT="22"
OUTPUT_FILE="running-config-$(date +%Y%m%d-%H%M%S).txt"
CRONITOR_URL=""
# Flag to track if the main logic succeeded
SUCCESS=false

# Function to display usage
usage() {
    cat <<EOF
Usage: $0 -h <host> -u <username> -p <password> [-o <output_file>] [-c <cronitor_url>] [-P <port>]
Options:
  -h  Remote host IP or hostname (required)
  -u  SSH username (required)
  -p  SSH password (required)
  -P  SSH port (default: 22)
  -o  Output file (default: running-config-TIMESTAMP.txt)
  -c  Cronitor URL (for job monitoring)
EOF
    exit 1
}

# Centralized cleanup and monitoring function
cleanup() {
    # Always clean up temporary files
    rm -f "$OUTPUT_FILE.tmp"

    if [ "$SUCCESS" = true ]; then
        echo "Success! Configuration saved to: $OUTPUT_FILE"
        echo "File size: $(wc -c < "$OUTPUT_FILE") bytes"
        call_cronitor "complete"
    else
        echo "Error: Script failed. See previous messages for details."
        # Remove potentially incomplete/invalid output file
        rm -f "$OUTPUT_FILE"
        call_cronitor "fail"
    fi
}

# Function to call Cronitor
call_cronitor() {
    local state=$1
    if [ -n "$CRONITOR_URL" ]; then
        curl -s --fail "${CRONITOR_URL}?state=${state}" >/dev/null || echo "Warning: Cronitor ping failed for state '${state}'." >&2
    fi
}

# Trap calls the cleanup function on any script exit (normal, error, or interrupt)
trap cleanup EXIT

# Parse command line arguments
while getopts "h:u:p:o:c:P:" opt; do
    case $opt in
        h) REMOTE_HOST="$OPTARG";;
        u) REMOTE_USER="$OPTARG";;
        p) REMOTE_PASS="$OPTARG";;
        o) OUTPUT_FILE="$OPTARG";;
        c) CRONITOR_URL="$OPTARG";;
        P) REMOTE_PORT="$OPTARG";;
        *) usage;;
    esac
done

# Validate required parameters
if [ -z "$REMOTE_HOST" ] || [ -z "$REMOTE_USER" ] || [ -z "$REMOTE_PASS" ]; then
    echo "Error: Missing required parameters."
    usage
fi

# Signal job start to Cronitor
call_cronitor "run"

echo "Connecting to $REMOTE_HOST to back up configuration..."

# Create directory for output file if it doesn't exist
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Core Logic: SSH to host, strip ANSI escape codes and start from ! $$$, save to temp file
sshpass -p "$REMOTE_PASS" ssh -p "$REMOTE_PORT" \
    -o "StrictHostKeyChecking=no" \
    -o "UserKnownHostsFile=/dev/null" \
    -o "ConnectTimeout=15" \
    -T \
    "$REMOTE_USER@$REMOTE_HOST" "show running-config" | \
    sed 's/\x1b\[[0-9;]*[A-Za-z]//g' | \
    awk '/! \$\$\$/ {f=1} f' > "$OUTPUT_FILE.tmp"

# Validate the backup file
if ! grep -q "\$\$\$ Model:" "$OUTPUT_FILE.tmp"; then
    echo "Error: Backup file is invalid (missing model information)."
    echo "---- (first 5 lines of invalid output) ----"
    head -n 5 "$OUTPUT_FILE.tmp"
    echo "-----------------------------------------"
    exit 1
fi

# Move temp file to final output only after validation
mv "$OUTPUT_FILE.tmp" "$OUTPUT_FILE"

# If we reach here, all steps were successful
SUCCESS=true

# Optional: Display first few lines of the saved config
echo ""
echo "First 5 lines of saved configuration:"
head -n 5 "$OUTPUT_FILE"
