#!/bin/sh

# Backup All Routers Script
# This script calls backup-keenetic-router.sh for multiple routers and manages the overall backup process

set -e

# Install required packages
echo "Installing required packages..."
if ! apk add --no-cache openssh-client sshpass curl; then
    echo "Error: Failed to install required packages (openssh-client, sshpass, curl)"
    exit 1
fi
echo "✓ Packages installed successfully"
echo ""

# Configuration
BACKUP_SCRIPT="/app/backup-keenetic-router.sh"
BASE_OUTPUT_DIR="/data"
DATE_DIR="$(date +%Y-%m-%d)"
OUTPUT_DIR="${BASE_OUTPUT_DIR}/${DATE_DIR}"

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Track overall success
OVERALL_SUCCESS=0

# Function to backup a single router
backup_router() {
    local router_num=$1
    local ip_var="ROUTER_${router_num}_IP"
    local user_var="ROUTER_${router_num}_USER"
    local pass_var="ROUTER_${router_num}_PASS"
    local cronitor_var="ROUTER_${router_num}_CRONITOR_URL"

    local ip="${!ip_var}"
    local user="${!user_var}"
    local pass="${!pass_var}"
    local cronitor_url="${!cronitor_var}"

    # Skip if required variables are not set
    if [ -z "$ip" ] || [ -z "$user" ] || [ -z "$pass" ]; then
        echo "Skipping router $router_num: Missing required environment variables ($ip_var, $user_var, $pass_var)"
        return 0
    fi

    # Generate output filename
    local timestamp=$(date +%H%M%S)
    local output_file="${OUTPUT_DIR}/${ip}-${timestamp}.txt"

    echo "=== Backing up router $router_num: $ip ==="
    echo "Output file: $output_file"

    # Build command arguments
    local cmd_args="-h $ip -u $user -p $pass -o $output_file"

    # Add cronitor URL if provided
    if [ -n "$cronitor_url" ]; then
        cmd_args="$cmd_args -c $cronitor_url"
    fi

    # Execute backup command and capture exit code
    if $BACKUP_SCRIPT $cmd_args; then
        echo "✓ Router $ip backup completed successfully"
        return 0
    else
        echo "✗ Router $ip backup failed"
        return 1
    fi
}

# Function to get the number of configured routers
get_router_count() {
    local count=0
    local router_num=1

    while true; do
        local ip_var="ROUTER_${router_num}_IP"
        local ip="${!ip_var}"

        if [ -n "$ip" ]; then
            count=$((count + 1))
            router_num=$((router_num + 1))
        else
            break
        fi
    done

    echo $count
}

# Main execution
echo "Starting backup process at $(date)"
echo "Backup directory: $OUTPUT_DIR"

# Get number of configured routers
ROUTER_COUNT=$(get_router_count)

if [ $ROUTER_COUNT -eq 0 ]; then
    echo "Error: No routers configured. Please set environment variables:"
    echo "  ROUTER_1_IP, ROUTER_1_USER, ROUTER_1_PASS"
    echo "  ROUTER_2_IP, ROUTER_2_USER, ROUTER_2_PASS (optional)"
    echo "  etc."
    exit 1
fi

echo "Found $ROUTER_COUNT configured router(s)"
echo ""

# Backup each router
for router_num in $(seq 1 $ROUTER_COUNT); do
    if ! backup_router $router_num; then
        OVERALL_SUCCESS=1
    fi
    echo ""
done

# Summary
echo "=== Backup Summary ==="
echo "Date: $(date)"
echo "Total routers processed: $ROUTER_COUNT"
echo "Backup directory: $OUTPUT_DIR"

# List created files
if [ -d "$OUTPUT_DIR" ]; then
    echo "Created backup files:"
    ls -la "$OUTPUT_DIR"/*.txt 2>/dev/null || echo "No backup files found"
fi

# Final result
if [ $OVERALL_SUCCESS -eq 0 ]; then
    echo "✓ All router backups completed successfully"
    exit 0
else
    echo "✗ One or more router backups failed"
    exit 1
fi
