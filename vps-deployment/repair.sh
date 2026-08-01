#!/usr/bin/env bash
# ==============================================================================
# StreamPulse VPS System Repair & Diagnostics Utility
# Designed for: Ubuntu 24.04 LTS (and compatible Debian-based Linux distributions)
# Description: Automatically diagnoses and repairs common VPS environment issues
#              such as process crashes, port conflicts, volume permission errors,
#              Docker daemon issues, database connectivity blocks, and Nginx failures.
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
    log_error "This repair script must be executed with root/sudo privileges."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

log_info "======================================================================="
log_info "  Starting StreamPulse VPS Diagnostics & Repair Utility"
log_info "======================================================================="

# --- 1. Diagnose File-System & Permissions ---
log_info "Step 1: Checking directories and file permissions..."
mkdir -p "$ROOT_DIR/data"
mkdir -p "$ROOT_DIR/backups"
mkdir -p "$ROOT_DIR/hls"

# Fix permissions so Docker can safely write/read volumes
log_info "Applying correct directory permissions for volume mounting..."
chmod 755 "$ROOT_DIR"
chmod -R 775 "$ROOT_DIR/data" || log_warning "Failed to chmod data folder."
chmod -R 775 "$ROOT_DIR/hls" || log_warning "Failed to chmod HLS folder."
log_success "Directory structure and permissions verified."

# --- 2. Check Docker Daemon & Compose ---
log_info "Step 2: Checking Docker service status..."
if ! systemctl is-active --quiet docker; then
    log_warning "Docker daemon is not running. Attempting service restart..."
    systemctl daemon-reload
    if systemctl restart docker; then
        log_success "Docker daemon restarted successfully."
    else
        log_error "Failed to restart Docker daemon. Check 'systemctl status docker' or logs."
        exit 1
    fi
else
    log_success "Docker daemon is running and healthy."
fi

# --- 3. Diagnose Port Conflicts ---
log_info "Step 3: Checking for port conflicts on critical streaming ports..."
check_port() {
    local port=$1
    local service=$2
    if lsof -Pi :"$port" -sTCP:LISTEN -t >/dev/null; then
        local pid
        pid=$(lsof -Pi :"$port" -sTCP:LISTEN -t)
        local proc_name
        proc_name=$(ps -p "$pid" -o comm=)
        log_warning "Port $port ($service) is already bound by host process '$proc_name' (PID: $pid)."
        log_warning "This might conflict with the Docker-compose container. Checking if it's Docker itself..."
        if [[ "$proc_name" != *"docker"* ]]; then
            log_warning "A non-docker process is listening on $port. You might want to stop '$proc_name'."
        fi
    else
        log_success "Port $port ($service) is free/available."
    fi
}

check_port 80 "HTTP"
check_port 443 "HTTPS Secure"
check_port 1935 "RTMP Ingest"
check_port 3000 "Manager API"

# --- 4. Diagnose .env Configuration ---
log_info "Step 4: Checking environment configuration (.env)..."
if [ ! -f "$ROOT_DIR/.env" ]; then
    log_warning "Missing .env configuration in project root."
    if [ -f "$ROOT_DIR/.env.example" ]; then
        log_info "Creating .env from example configuration..."
        cp "$ROOT_DIR/.env.example" "$ROOT_DIR/.env"
        # Generate random values
        RAND_JWT=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32)
        sed -i "s/JWT_SECRET=.*$/JWT_SECRET=${RAND_JWT}/g" "$ROOT_DIR/.env"
        log_success "Created fresh .env from template."
    else
        log_error "No template .env.example found. Re-run install.sh or repair environment manually."
        exit 1
    fi
else
    log_success ".env file exists."
fi

# --- 5. Inspect and Repair Docker Containers ---
log_info "Step 5: Verifying StreamPulse Docker Containers status..."
cd "$SCRIPT_DIR"

if ! docker compose ps &>/dev/null; then
    log_error "Docker-compose configurations are broken or misaligned."
    exit 1
fi

log_info "Attempting safe restart of the application services..."
if docker compose restart; then
    log_success "All container services restarted."
else
    log_warning "Direct restart failed. Recreating containers from scratch..."
    docker compose down || true
    if docker compose up -d; then
        log_success "Recreated and launched containers successfully."
    else
        log_error "Failed to boot containers. Review logs using 'docker compose logs'."
        exit 1
    fi
fi

# --- 6. PostgreSQL Diagnostic & Migrations ---
log_info "Step 6: Performing database connectivity diagnostics..."
STORAGE_MODE=$(grep -E "^STORAGE_MODE=" "$ROOT_DIR/.env" | cut -d'=' -f2- || echo "postgres")

if [ "$STORAGE_MODE" = "postgres" ]; then
    log_info "Verifying PostgreSQL container database engine..."
    # Wait for PostgreSQL to start up
    sleep 3
    if docker ps --format '{{.Names}}' | grep -q "postgres_db"; then
        log_info "PostgreSQL container is active. Checking SQL interface..."
        if docker exec postgres_db pg_isready -U streampulse_admin -d streampulse &>/dev/null; then
            log_success "PostgreSQL server is ready to accept connections."
            
            # Check schema status - if schema tables don't exist, we can re-inject
            log_info "Checking database table existence..."
            TABLE_COUNT=$(docker exec postgres_db psql -U streampulse_admin -d streampulse -t -A -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';" || echo "0")
            log_info "Found $TABLE_COUNT active tables in database public schema."
            if [ "$TABLE_COUNT" -eq "0" ]; then
                log_warning "No tables found. Injecting default database schema (schema.sql)..."
                if docker exec -i postgres_db psql -U streampulse_admin -d streampulse < "$SCRIPT_DIR/schema.sql"; then
                    log_success "Database schema successfully initialized."
                else
                    log_error "Failed to seed schema.sql into PostgreSQL."
                fi
            fi
        else
            log_error "PostgreSQL ping check failed. Check container database configuration."
        fi
    else
        log_error "PostgreSQL container ('postgres_db') is not running. Check database configuration."
    fi
else
    log_info "Active storage mode is JSON. Database is file-system based. Checking json file structure..."
    if [ ! -f "$ROOT_DIR/data/db.json" ]; then
        log_warning "Missing database data/db.json file. Creating default template structure..."
        mkdir -p "$ROOT_DIR/data"
        echo '{"users":[],"streams":[],"devices":[],"deviceGroups":[],"deviceGroupMembers":[],"playbackHistory":[],"deviceLogs":[],"deviceSchedules":[]}' > "$ROOT_DIR/data/db.json"
        log_success "Default local database template generated."
    else
        # Quick validation of JSON syntax
        if jq empty "$ROOT_DIR/data/db.json" &>/dev/null; then
            log_success "Local database JSON structure is healthy."
        else
            log_error "data/db.json file has invalid/corrupted JSON syntax!"
            log_info "Making a secure backup and resetting database..."
            cp "$ROOT_DIR/data/db.json" "$ROOT_DIR/data/db.json.corrupt"
            echo '{"users":[],"streams":[],"devices":[],"deviceGroups":[],"deviceGroupMembers":[],"playbackHistory":[],"deviceLogs":[],"deviceSchedules":[]}' > "$ROOT_DIR/data/db.json"
            log_success "Database reset completed. Original corrupted DB backed up to db.json.corrupt"
        fi
    fi
fi

# --- 7. Final Health Endpoint query ---
log_info "Step 7: Validating live service health..."
sleep 2
HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:3000/api/health" || echo "000")

if [ "$HEALTH_STATUS" = "200" ]; then
    log_success "======================================================================="
    log_success "  All repairs completed! StreamPulse VPS Core is fully functional."
    log_success "======================================================================="
else
    log_warning "======================================================================="
    log_warning "  Diagnostics complete, but API returned status $HEALTH_STATUS."
    log_warning "  Please review service logs using: 'docker compose logs'"
    log_warning "======================================================================="
fi
