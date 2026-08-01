#!/usr/bin/env bash
# ==============================================================================
# StreamPulse VPS Restore Utility
# Designed for: Ubuntu 24.04 LTS (and compatible Debian-based Linux distributions)
# Description: Restores StreamPulse configurations, local database volumes,
#              and PostgreSQL dumps from a compressed backup archive.
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

# --- Check Permissions ---
if [ "$EUID" -ne 0 ]; then
    log_error "This restore script must be executed with root/sudo privileges."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Verify arguments
if [ "$#" -lt 1 ]; then
    log_error "Usage: $0 <path-to-backup-tar-gz> [--yes]"
    exit 1
fi

BACKUP_FILE=$1
FORCE_YES=false

if [ "${2:-}" = "--yes" ] || [ "${2:-}" = "-y" ]; then
    FORCE_YES=true
fi

# Validate backup file existence
if [ ! -f "$BACKUP_FILE" ]; then
    log_error "Backup file not found: $BACKUP_FILE"
    exit 1
fi

log_info "======================================================================="
log_info "  Starting StreamPulse VPS Restore Utility"
log_info "  Backup File: $BACKUP_FILE"
log_info "======================================================================="

# --- Prompt User for Confirmation ---
if [ "$FORCE_YES" = false ]; then
    log_warning "WARNING: Restoring will completely overwrite existing data, configurations, and databases!"
    echo -e -n "${RED}[PROMPT] Are you absolutely sure you want to proceed? (y/N): ${NC}"
    if [[ -t 0 ]]; then
        read -r CONFIRM
    else
        CONFIRM="y" # Fallback in non-interactive shell
    fi
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
        log_info "Restore cancelled by user."
        exit 0
    fi
fi

# --- 1. Extract Archive ---
log_info "Step 1: Extracting backup package..."
TEMP_EXTRACT_DIR="/tmp/streampulse-restore-$(date +%s)"
mkdir -p "$TEMP_EXTRACT_DIR"

# Test extraction integrity
if ! tar -xzf "$BACKUP_FILE" -C "$TEMP_EXTRACT_DIR"; then
    log_error "Failed to extract backup file or file is corrupted."
    rm -rf "$TEMP_EXTRACT_DIR"
    exit 1
fi

# Locate the actual archive content sub-folder (handles different packaging depth)
CONTENT_DIR=$(find "$TEMP_EXTRACT_DIR" -maxdepth 2 -name ".env" -print -quit | xargs dirname 2>/dev/null || echo "")

if [ -z "$CONTENT_DIR" ] || [ ! -f "$CONTENT_DIR/.env" ]; then
    log_error "Invalid backup structure. Missing '.env' configuration file inside backup."
    rm -rf "$TEMP_EXTRACT_DIR"
    exit 1
fi

log_success "Backup archive verified."

# --- 2. Stop Containers to Avoid File Locks ---
log_info "Step 2: Stopping active application containers..."
cd "$SCRIPT_DIR"
docker compose down || log_warning "Failed to run docker compose down. Continuing..."

# --- 3. Restore Environment & Files ---
log_info "Step 3: Restoring configuration files..."
cp "$CONTENT_DIR/.env" "$ROOT_DIR/.env"

if [ -d "$CONTENT_DIR/vps-deployment" ]; then
    log_info "Restoring deployment config parameters..."
    cp "$CONTENT_DIR/vps-deployment"/*.conf "$SCRIPT_DIR/" 2>/dev/null || true
    cp "$CONTENT_DIR/vps-deployment"/docker-compose.yml "$SCRIPT_DIR/" 2>/dev/null || true
fi

# Load variables from restored env
STORAGE_MODE=$(grep -E "^STORAGE_MODE=" "$ROOT_DIR/.env" | cut -d'=' -f2- || echo "postgres")

# --- 4. Restore Database Content ---
log_info "Step 4: Restoring application database (Mode: $STORAGE_MODE)..."
if [ "$STORAGE_MODE" = "postgres" ]; then
    log_info "Starting PostgreSQL database container..."
    docker compose up -d postgres_db
    
    # Wait for PostgreSQL container to be fully active and ready
    log_info "Waiting for PostgreSQL database container to be active..."
    sleep 5
    
    if [ -f "$CONTENT_DIR/db_dump.sql" ]; then
        log_info "Importing PostgreSQL database schema and data..."
        # First drop and recreate public schema to clean any current tables
        docker exec postgres_db psql -U streampulse_admin -d streampulse -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" >/dev/null
        
        if docker exec -i postgres_db psql -U streampulse_admin -d streampulse < "$CONTENT_DIR/db_dump.sql" >/dev/null; then
            log_success "PostgreSQL database successfully restored."
        else
            log_error "PostgreSQL restore failed during sql import!"
        fi
    else
        log_warning "No SQL dump file (db_dump.sql) found in backup. Looking for physical volume backup..."
        if [ -d "$CONTENT_DIR/data" ]; then
            cp -r "$CONTENT_DIR/data" "$ROOT_DIR/data"
            log_success "Physical file-system database folder restored."
        fi
    fi
else
    # JSON file-system database
    if [ -d "$CONTENT_DIR/data" ]; then
        log_info "Restoring local JSON database directories..."
        rm -rf "$ROOT_DIR/data"
        cp -r "$CONTENT_DIR/data" "$ROOT_DIR/data"
        log_success "Local storage folder restored successfully."
    else
        log_warning "No data folder found inside the backup."
    fi
fi

# --- 5. Boot Complete Application Services ---
log_info "Step 5: Restarting and rebuilding all containers..."
cd "$SCRIPT_DIR"
docker compose up -d --build

# Clean temporary restore folder
rm -rf "$TEMP_EXTRACT_DIR"

# --- 6. Verify Health ---
log_info "Step 6: Verifying post-restore health..."
sleep 5
HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:3000/api/health" || echo "000")

if [ "$HEALTH_STATUS" = "200" ]; then
    log_success "======================================================================="
    log_success "  StreamPulse Core System successfully restored from backup!"
    log_success "======================================================================="
else
    log_warning "======================================================================="
    log_warning "  Restore complete, but health API returned status $HEALTH_STATUS."
    log_warning "  Please review service logs: 'docker compose logs'"
    log_warning "======================================================================="
fi
