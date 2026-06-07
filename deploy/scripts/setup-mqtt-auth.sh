#!/bin/bash
# =============================================================================
# MQTT Authentication Setup Script for Danger Emergence System
# =============================================================================
# This script creates the Mosquitto password file and generates credentials
# for all user types in the system.
#
# Usage:
#   chmod +x setup-mqtt-auth.sh
#   ./setup-mqtt-auth.sh
#
# Prerequisites:
#   - mosquitto_passwd must be installed (part of mosquitto-clients package)
# =============================================================================

set -e

PASSWD_FILE="/etc/mosquitto/passwd"
ACL_FILE="/etc/mosquitto/acl"

echo "=== Danger Emergence System — MQTT Auth Setup ==="
echo ""

# Check if mosquitto_passwd is available
if ! command -v mosquitto_passwd &> /dev/null; then
    echo "ERROR: mosquitto_passwd not found. Install mosquitto-clients package."
    echo "  Ubuntu/Debian: sudo apt-get install mosquitto-clients"
    echo "  Alpine: apk add mosquitto-clients"
    exit 1
fi

# Create or clear the password file
echo "Creating password file at $PASSWD_FILE..."
> "$PASSWD_FILE"

# Function to add a user
add_user() {
    local username="$1"
    echo "Adding user: $username"
    mosquitto_passwd -b "$PASSWD_FILE" "$username" "${2:-changeme_${username}_2024}"
}

echo ""
echo "=== Creating Service Accounts ==="

# Backend service account (used by Spring Boot backend)
add_user "backend" "$(openssl rand -base64 32)"

echo ""
echo "=== Creating Admin Users ==="
echo "NOTE: Change passwords immediately after first login!"

# Admin account
add_user "admin"

echo ""
echo "=== Password file created at: $PASSWD_FILE ==="
echo "=== ACL file expected at: $ACL_FILE ==="
echo ""
echo "Next steps:"
echo "  1. Copy the ACL file to $ACL_FILE:"
echo "     sudo cp deploy/mosquitto/acl $ACL_FILE"
echo "  2. Restart Mosquitto:"
echo "     sudo systemctl restart mosquitto"
echo "     # or: docker-compose restart mosquitto"
echo "  3. Generate user-specific passwords for each app user:"
echo "     mosquitto_passwd $PASSWD_FILE <username>"
echo ""
echo "=== Done ==="
