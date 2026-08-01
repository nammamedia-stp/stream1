#!/usr/bin/env bash
# ==============================================================================
# StreamPulse VPS Uninstaller
# Designed for: Ubuntu 24.04 LTS (and compatible Debian-based Linux distributions)
# Description: Gracefully shuts down and purges all StreamPulse docker containers,
#              removes configurations, databases, persistent files, and logs.
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
    log_error "This uninstaller must be executed with root/sudo privileges."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

log_info "======================================================================="
log_info "  Starting StreamPulse VPS Uninstaller"
log_info "======================================================================="

# --- Prompt User for Confirmation ---
log_warning "CRITICAL WARNING: This script will permanently remove ALL StreamPulse components,"
log_warning "including active configurations, database files, HLS stream data, and logs!"
echo -e -n "${RED}[PROMPT] Are you absolutely sure you want to proceed? (yes/NO): ${NC}"
if [[ -t 0 ]]; then
    read -r CONFIRM
else
    CONFIRM="yes" # Fallback in non-interactive environment
fi

if [[ "$CONFIRM" != "yes" ]]; then
    log_info "Uninstall process aborted."
    exit 0
fi

# Double confirmation
log_warning "This action is completely IRREVERSIBLE!"
echo -e -n "${RED}[PROMPT] Type 'UNINSTALL' to confirm permanent removal: ${NC}"
if [[ -t 0 ]]; then
    read -r CONFIRM_TEXT
else
    CONFIRM_TEXT="UNINSTALL"
fi

if [[ "$CONFIRM_TEXT" != "UNINSTALL" ]]; then
    log_info "Uninstall process aborted."
    exit 0
fi

# --- 1. Down and Remove Docker Container Resources ---
log_info "Step 1: Stopping and removing docker-compose container services..."
cd "$SCRIPT_DIR"
if docker compose ps &>/dev/null; then
    # Down with volumes (-v) and orphan container removal
    docker compose down -v --remove-orphans || log_warning "Failed to run docker compose down. Proceeding with manual volume removals."
else
    log_info "No active docker compose stack found."
fi

# --- 2. Purge Persistent Directories ---
log_info "Step 2: Deleting persistent data, HLS folders, and configurations..."

remove_dir() {
    local dir=$1
    if [ -d "$dir" ]; then
        log_info "Removing directory: $dir..."
        rm -rf "$dir"
        log_success "Removed $dir."
    fi
}

remove_dir "$ROOT_DIR/data"
remove_dir "$ROOT_DIR/hls"
remove_dir "$ROOT_DIR/backups"

# Remove local .env
if [ -f "$ROOT_DIR/.env" ]; then
    log_info "Removing configuration file: .env..."
    rm -f "$ROOT_DIR/.env"
    log_success "Removed .env"
fi

# --- 3. Optional UFW firewall cleanup ---
log_info "Step 3: Cleaning firewall rules..."
if command -v ufw &>/dev/null && ufw status | grep -q "active"; then
    log_info "Removing opened ports from UFW..."
    ufw delete allow 1935/tcp || true # RTMP Ingest
    ufw delete allow 3000/tcp || true # Web Manager
    log_success "UFW firewall configuration updated."
fi

# Done
log_success "======================================================================="
log_success "  StreamPulse Uninstalled Successfully!"
log_success "  All application services, volumes, databases, and logs are removed."
log_success "======================================================================="
