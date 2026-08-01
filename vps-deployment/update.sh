#!/usr/bin/env bash
# ==============================================================================
# StreamPulse VPS Updater
# Designed for: Ubuntu 24.04 LTS (and compatible Debian-based Linux distributions)
# Description: Safely pulls latest codebase/images, preserves environment and DB,
#              updates containers, runs DB checks, and verifies service health.
#              Includes auto-rollback safety on failure.
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

# --- Prerequisites Checks ---
if [ "$EUID" -ne 0 ]; then
    log_error "This update script must be executed with root/sudo privileges."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

log_info "Step 1: Validating environment and checking configuration persistence..."
if [ ! -f "$ROOT_DIR/.env" ]; then
    log_error "No active environment (.env) found in project root. Run install.sh first."
    exit 1
fi

# Load variables from current .env
# Avoid executing the .env directly to prevent arbitrary code execution
log_info "Loading current database and system configuration..."
STORAGE_MODE=$(grep -E "^STORAGE_MODE=" "$ROOT_DIR/.env" | cut -d'=' -f2- || echo "postgres")
log_info "Active Storage Mode: $STORAGE_MODE"

# Create a local backup of the DB or data folder before updating
log_info "Step 2: Creating a pre-update snapshot of the data directory..."
BACKUP_DIR="$ROOT_DIR/backups/pre-update-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

if [ -d "$ROOT_DIR/data" ]; then
    cp -r "$ROOT_DIR/data" "$BACKUP_DIR/data_backup"
    log_success "Data folder backed up to $BACKUP_DIR/data_backup"
fi

# If using postgres, try to do a quick pg_dump if the container is running
if [ "$STORAGE_MODE" = "postgres" ]; then
    log_info "Backing up PostgreSQL database..."
    if docker ps --format '{{.Names}}' | grep -q "postgres_db"; then
        if docker exec postgres_db pg_dump -U streampulse_admin streampulse > "$BACKUP_DIR/db_backup.sql" 2>/dev/null; then
            log_success "Database successfully backed up to $BACKUP_DIR/db_backup.sql"
        else
            log_warning "Unable to perform database dump. PostgreSQL might be in a different state."
        fi
    else
        log_warning "PostgreSQL container is not currently running. Skipping SQL-dump backup."
    fi
fi

# --- Step 3: Fetch Codebase Updates ---
log_info "Step 3: Checking for updates from remote repository..."
if [ -d "$ROOT_DIR/.git" ]; then
    log_info "Git repository detected. Fetching latest remote changes..."
    cd "$ROOT_DIR"
    # Capture current commit hash for potential rollback
    PREVIOUS_COMMIT=$(git rev-parse HEAD)
    
    # Clean up local untracked files or stash them safely
    log_info "Stashing any local modification to prevent conflicts..."
    git stash -u || true
    
    # Pull latest from branch
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    log_info "Pulling updates from branch: $CURRENT_BRANCH..."
    if git pull origin "$CURRENT_BRANCH"; then
        log_success "Codebase updated successfully."
    else
        log_error "Failed to pull updates from git repository."
        log_info "Rolling back local branch state..."
        git reset --hard "$PREVIOUS_COMMIT" || true
        git stash pop || true
        exit 1
    fi
else
    log_warning "Git repository not found. Relying on local deployment files."
fi

# --- Step 4: Rebuilding and Restarting Containers ---
log_info "Step 4: Pulling new container images and rebuilding services..."
cd "$SCRIPT_DIR"

# Capture active container IDs to track changes
PREV_CONTAINERS=$(docker compose ps -q)

log_info "Pulling base Docker images..."
docker compose pull || log_warning "Failed to pull base images. Continuing with local cache..."

log_info "Rebuilding and recreating container services..."
if docker compose up -d --build; then
    log_success "Containers rebuilt and restarted successfully."
else
    log_error "Rebuilding containers failed. Initiating automatic rollback..."
    cd "$SCRIPT_DIR"
    docker compose down
    if [ -d "$ROOT_DIR/.git" ] && [ -n "${PREVIOUS_COMMIT:-}" ]; then
        log_info "Reverting codebase to commit $PREVIOUS_COMMIT..."
        cd "$ROOT_DIR"
        git reset --hard "$PREVIOUS_COMMIT"
        git stash pop || true
    fi
    cd "$SCRIPT_DIR"
    docker compose up -d
    log_success "Rollback completed. Original services restored."
    exit 1
fi

# --- Step 5: Verification and Post-Update Checks ---
log_info "Step 5: Performing post-update service health checks..."
# Allow services 8 seconds to initialize
sleep 8

HEALTH_CHECK_URL="http://localhost:3000/api/health"
log_info "Querying health endpoint at $HEALTH_CHECK_URL..."

HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$HEALTH_CHECK_URL" || echo "000")

if [ "$HEALTH_STATUS" = "200" ]; then
    log_success "======================================================================="
    log_success "  StreamPulse Update completed successfully! All services are active."
    log_success "======================================================================="
    exit 0
else
    log_error "Service health check failed with status: $HEALTH_STATUS"
    log_warning "Initiating automatic rollback to ensure system uptime..."
    
    # Stop failed services
    cd "$SCRIPT_DIR"
    docker compose down
    
    # Restore DB from file-system backup if exists
    if [ -d "$BACKUP_DIR/data_backup" ] && [ -d "$ROOT_DIR/data" ]; then
        log_info "Restoring file-system database..."
        rm -rf "$ROOT_DIR/data"
        cp -r "$BACKUP_DIR/data_backup" "$ROOT_DIR/data"
    fi
    
    # Rollback codebase
    if [ -d "$ROOT_DIR/.git" ] && [ -n "${PREVIOUS_COMMIT:-}" ]; then
        log_info "Restoring git branch commit..."
        cd "$ROOT_DIR"
        git reset --hard "$PREVIOUS_COMMIT"
        git stash pop || true
    fi
    
    # Restart original containers
    cd "$SCRIPT_DIR"
    docker compose up -d --build
    
    log_success "Rollback successful. System restored to pre-update state."
    exit 1
fi
