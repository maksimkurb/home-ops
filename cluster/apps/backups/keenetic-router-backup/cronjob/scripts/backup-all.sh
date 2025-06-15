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
SSH_PORT=1122

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Track overall success
OVERALL_SUCCESS=0

# Function to backup a single router using case statement
backup_router() {
    local router_num=$1
    local ip user pass cronitor_url

    # Get router-specific variables using case statement
    case $router_num in
        1) ip="$ROUTER_1_IP"; user="$ROUTER_1_USER"; pass="$ROUTER_1_PASS"; cronitor_url="$ROUTER_1_CRONITOR_URL" ;;
        2) ip="$ROUTER_2_IP"; user="$ROUTER_2_USER"; pass="$ROUTER_2_PASS"; cronitor_url="$ROUTER_2_CRONITOR_URL" ;;
        3) ip="$ROUTER_3_IP"; user="$ROUTER_3_USER"; pass="$ROUTER_3_PASS"; cronitor_url="$ROUTER_3_CRONITOR_URL" ;;
        4) ip="$ROUTER_4_IP"; user="$ROUTER_4_USER"; pass="$ROUTER_4_PASS"; cronitor_url="$ROUTER_4_CRONITOR_URL" ;;
        5) ip="$ROUTER_5_IP"; user="$ROUTER_5_USER"; pass="$ROUTER_5_PASS"; cronitor_url="$ROUTER_5_CRONITOR_URL" ;;
        6) ip="$ROUTER_6_IP"; user="$ROUTER_6_USER"; pass="$ROUTER_6_PASS"; cronitor_url="$ROUTER_6_CRONITOR_URL" ;;
        7) ip="$ROUTER_7_IP"; user="$ROUTER_7_USER"; pass="$ROUTER_7_PASS"; cronitor_url="$ROUTER_7_CRONITOR_URL" ;;
        8) ip="$ROUTER_8_IP"; user="$ROUTER_8_USER"; pass="$ROUTER_8_PASS"; cronitor_url="$ROUTER_8_CRONITOR_URL" ;;
        9) ip="$ROUTER_9_IP"; user="$ROUTER_9_USER"; pass="$ROUTER_9_PASS"; cronitor_url="$ROUTER_9_CRONITOR_URL" ;;
        10) ip="$ROUTER_10_IP"; user="$ROUTER_10_USER"; pass="$ROUTER_10_PASS"; cronitor_url="$ROUTER_10_CRONITOR_URL" ;;
        *) echo "Router $router_num not supported (max 10 routers)"; return 1 ;;
    esac

    # Skip if required variables are not set
    if [ -z "$ip" ] || [ -z "$user" ] || [ -z "$pass" ]; then
        echo "Skipping router $router_num: Missing required environment variables (ROUTER_${router_num}_IP, ROUTER_${router_num}_USER, ROUTER_${router_num}_PASS)"
        return 0
    fi

    # Generate output filename
    local timestamp=$(date +%H-%M-%S)
    local output_file="${OUTPUT_DIR}/${ip}-${timestamp}.txt"

    echo "=== Backing up router $router_num: $ip ==="
    echo "Output file: $output_file"

    # Build command arguments
    local cmd_args="-h \"$ip\" -u \"$user\" -p \"$pass\" -P \"$SSH_PORT\" -o \"$output_file\""

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

    # Check each router using case statement
    for router_num in 1 2 3 4 5 6 7 8 9 10; do
        local ip
        case $router_num in
            1) ip="$ROUTER_1_IP" ;;
            2) ip="$ROUTER_2_IP" ;;
            3) ip="$ROUTER_3_IP" ;;
            4) ip="$ROUTER_4_IP" ;;
            5) ip="$ROUTER_5_IP" ;;
            6) ip="$ROUTER_6_IP" ;;
            7) ip="$ROUTER_7_IP" ;;
            8) ip="$ROUTER_8_IP" ;;
            9) ip="$ROUTER_9_IP" ;;
            10) ip="$ROUTER_10_IP" ;;
        esac

        if [ -n "$ip" ]; then
            count=$((count + 1))
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
    echo "  etc. (up to ROUTER_10_*)"
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
