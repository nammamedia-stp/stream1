#!/usr/bin/env bash
# ==============================================================================
# StreamPulse VPS Backup Utility
# Designed for: Ubuntu 24.04 LTS (and compatible Debian-based Linux distributions)
# Description: Creates a secure compressed archive of configurations, SSL setups,
#              local storage databases, and full PostgreSQL database dumps.
# ==============================================================================

set -euo pipefail

# --- Color Definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0;37m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Define Backup Location
BACKUP_DIR="${1:-$ROOT_DIR/backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="streampulse-backup-$TIMESTAMP"
TEMP_BACKUP_PATH="/tmp/$BACKUP_NAME"

log_info "======================================================================="
log_info "  Starting StreamPulse VPS Backup Utility"
log_info "  Target Directory: $BACKUP_DIR"
log_info "======================================================================="

# Ensure clean temp and output folders
mkdir -p "$BACKUP_DIR"
rm -rf "$TEMP_BACKUP_PATH"
mkdir -p "$TEMP_BACKUP_PATH"

# Check .env file
if [ ! -f "$ROOT_DIR/.env" ]; then
    log_error "No active .env file found. Nothing to backup."
    exit 1
fi

# Load variables
STORAGE_MODE=$(grep -E "^STORAGE_MODE=" "$ROOT_DIR/.env" | cut -d'=' -f2- || echo "postgres")

# 1. Copy Configuration
log_info "Backing up configurations and environment specifications..."
cp "$ROOT_DIR/.env" "$TEMP_BACKUP_PATH/.env"
if [ -d "$SCRIPT_DIR" ]; then
    mkdir -p "$TEMP_BACKUP_PATH/vps-deployment"
    cp "$SCRIPT_DIR"/*.conf "$TEMP_BACKUP_PATH/vps-deployment/" 2>/dev/null || true
    cp "$SCRIPT_DIR"/docker-compose.yml "$TEMP_BACKUP_PATH/vps-deployment/" 2>/dev/null || true
fi

# 2. Backup Database/Data
log_info "Backing up application database (Mode: $STORAGE_MODE)..."
if [ "$STORAGE_MODE" = "postgres" ]; then
    if docker ps --format '{{.Names}}' | grep -q "postgres_db"; then
        log_info "PostgreSQL container is active. Dumping database content..."
        if docker exec postgres_db pg_dump -U streampulse_admin streampulse > "$TEMP_BACKUP_PATH/db_dump.sql" 2>/dev/null; then
            log_success "Database successfully dumped."
        else
            log_error "PostgreSQL pg_dump failed! Backup will be incomplete."
            rm -rf "$TEMP_BACKUP_PATH"
            exit 1
        fi
    else
        log_warning "PostgreSQL container 'postgres_db' is not running. Checking if offline file storage can be backed up..."
        # Backup the actual volume if possible (safely)
        if [ -d "$ROOT_DIR/data" ]; then
            log_info "Copying offline volume directory..."
            cp -r "$ROOT_DIR/data" "$TEMP_BACKUP_PATH/data"
        fi
    fi
else
    # JSON Mode
    if [ -d "$ROOT_DIR/data" ]; then
        log_info "Copying local database directories..."
        cp -r "$ROOT_DIR/data" "$TEMP_BACKUP_PATH/data"
        log_success "Local storage folder copied."
    else
        log_warning "No data directory found to copy."
    fi
fi

# 3. Create Compressed Archive
log_info "Compressing backup files into an archive..."
cd /tmp
tar -czf "$BACKUP_DIR/$BACKUP_NAME.tar.gz" "$BACKUP_NAME"

# Clean up temporary folder
rm -rf "$TEMP_BACKUP_PATH"

BACKUP_FILE="$BACKUP_DIR/$BACKUP_NAME.tar.gz"
BACKUP_SIZE=$(du -sh "$BACKUP_FILE" | cut -f1)

log_success "======================================================================="
log_success "  Backup completed successfully!"
log_success "  File: $BACKUP_FILE"
log_success "  Size: $BACKUP_SIZE"
log_success "======================================================================="
