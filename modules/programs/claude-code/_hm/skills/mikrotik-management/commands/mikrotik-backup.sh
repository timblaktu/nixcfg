#!/usr/bin/env bash
# mikrotik-backup.sh - Quick backup of Mikrotik RouterOS configuration
# Usage: ./mikrotik-backup.sh [host] [user] [output-dir]
# Default: host=192.168.88.1, user=admin, output-dir=.
#
# Creates both binary backup (.backup) and text export (.rsc) locally.
set -euo pipefail

HOST="${1:-192.168.88.1}"
USER="${2:-admin}"
OUTPUT_DIR="${3:-.}"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_NAME="backup-$TIMESTAMP"

ssh_exec() {
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes "${USER}@${HOST}" "$1" 2>/dev/null
}

# Test connectivity
if ! ssh_exec "/system resource print" >/dev/null; then
    echo "[ERROR] Cannot connect to $HOST"
    exit 1
fi

model=$(ssh_exec "/system routerboard get model" || echo "Unknown")
echo "Connected to $model at $HOST"

# Create binary backup on device
echo "[1/4] Creating binary backup on device..."
ssh_exec "/system backup save name=$BACKUP_NAME" || { echo "[ERROR] Binary backup failed"; exit 1; }
echo "  Created: $BACKUP_NAME.backup"

# Create text export on device
echo "[2/4] Creating text export on device..."
ssh_exec "/export file=$BACKUP_NAME" || { echo "[ERROR] Text export failed"; exit 1; }
echo "  Created: $BACKUP_NAME.rsc"

# Download both files
echo "[3/4] Downloading backup files..."
scp -o StrictHostKeyChecking=no -o BatchMode=yes "${USER}@${HOST}:/${BACKUP_NAME}.backup" "${OUTPUT_DIR}/" || { echo "[ERROR] Download .backup failed"; exit 1; }
scp -o StrictHostKeyChecking=no -o BatchMode=yes "${USER}@${HOST}:/${BACKUP_NAME}.rsc" "${OUTPUT_DIR}/" || { echo "[ERROR] Download .rsc failed"; exit 1; }

# Clean up device files
echo "[4/4] Cleaning up device files..."
ssh_exec "/file remove ${BACKUP_NAME}.backup" || true
ssh_exec "/file remove ${BACKUP_NAME}.rsc" || true

echo ""
echo "Backup complete:"
echo "  Binary: ${OUTPUT_DIR}/${BACKUP_NAME}.backup (for disaster recovery)"
echo "  Text:   ${OUTPUT_DIR}/${BACKUP_NAME}.rsc (for version control)"
