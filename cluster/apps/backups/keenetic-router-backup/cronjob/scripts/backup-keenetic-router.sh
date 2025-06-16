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

# Function to display usage
usage() {
    echo "Usage: $0 -h <host> -u <username> -p <password> [-o <output_file>] [-c <cronitor_url>]"
    echo "Options:"
    echo "  -h  Remote host IP or hostname"
    echo "  -u  SSH username"
    echo "  -p  SSH password"
    echo "  -P  SSH port (optional, default: 22)"
    echo "  -o  Output file (optional, default: running-config-TIMESTAMP.txt)"
    echo "  -c  Cronitor URL (optional, for job monitoring)"
    exit 1
}

# Function to call Cronitor
call_cronitor() {
    local state=$1
    if [ -n "$CRONITOR_URL" ]; then
        curl -s "${CRONITOR_URL}?state=${state}" >/dev/null 2>&1 || true
    fi
}

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
    echo "Error: Missing required parameters"
    usage
fi

# Signal job start to Cronitor
call_cronitor "run"

echo "Connecting to $REMOTE_HOST as $REMOTE_USER..."

# Create directory for output file
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Execute SSH command with no host key checking and save output
if sshpass -p "$REMOTE_PASS" ssh -p "$REMOTE_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$REMOTE_USER@$REMOTE_HOST" "show running-config" > "$OUTPUT_FILE.tmp" 2>/dev/null; then

    # Strip everything before the first "! $$$" line
    sed '1,/^! \$\$\$/{ /^! \$\$\$/!d; }' "$OUTPUT_FILE.tmp" > "$OUTPUT_FILE"
    rm -f "$OUTPUT_FILE.tmp"

    SSH_SUCCESS=0
else
    rm -f "$OUTPUT_FILE.tmp"
    SSH_SUCCESS=1
fi

# Check if the command was successful
if [ $SSH_SUCCESS -eq 0 ]; then
    # Validate backup contains model information
    if grep -q "\$\$\$ Model:" "$OUTPUT_FILE"; then
        echo "Success! Configuration saved to: $OUTPUT_FILE"
        echo "File size: $(wc -c < "$OUTPUT_FILE") bytes"
        # Signal successful completion to Cronitor
        call_cronitor "complete"
    else
        echo "Error: Backup file is invalid (missing model information)"
        rm -f "$OUTPUT_FILE"
        # Signal failure to Cronitor
        call_cronitor "fail"
        exit 1
    fi
else
    echo "Error: Failed to retrieve configuration from $REMOTE_HOST"
    # Clean up empty file if created
    [ -s "$OUTPUT_FILE" ] || rm -f "$OUTPUT_FILE"

    # Signal failure to Cronitor
    call_cronitor "fail"
    exit 1
fi

# Optional: Display first few lines of the saved config
echo ""
echo "First 5 lines of saved configuration:"
head -n 5 "$OUTPUT_FILE"
