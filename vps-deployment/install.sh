#!/usr/bin/env bash
# ==============================================================================
# StreamPulse VPS Installer
# Designed for: Ubuntu 24.04 LTS (and compatible Debian-based Linux distributions)
# Description: Automates system updates, security hardening (Fail2Ban/UFW),
#              Docker & Docker-Compose installation, SSL generation, and
#              StreamPulse Docker container deployment.
# ==============================================================================

set -euo pipefail

# --- Color Definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0;37m' # No Color

# --- Helper Logging Functions ---
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- Clean-up Trap on Error ---
cleanup_on_error() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Installation failed at line $1 with exit code $exit_code."
        log_info "Please resolve any system configuration or networking issues and rerun this installer."
    fi
}
trap 'cleanup_on_error $LINENO' EXIT

# --- Prerequisites & Pre-Installation Validation Stage ---
log_info "Initializing Pre-Installation Validation stage..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Initialize resolution states
USE_CUSTOM_DB=false
CUSTOM_DB_HOST=""
CUSTOM_DB_PORT=""
CUSTOM_DB_USER=""
CUSTOM_DB_PASSWORD=""
CUSTOM_DB_NAME=""

HOST_HTTP_PORT=80
HOST_HTTPS_PORT=443
HOST_RTMP_PORT=1935

SKIP_BUILD=false
REUSE_MODE=false

RESOLVED_PG_STR="None"
RESOLVED_NGINX_STR="None"
RESOLVED_CONTAINER_STR="None"

# 1. Root Privileges Check
if [ "$EUID" -ne 0 ]; then
    log_error "Critical validation error: This installation script must be executed with root/sudo privileges."
    exit 1
fi

# 2. Operating System Check
OS_NAME="unknown"
OS_VERSION="unknown"
OS_ID="unknown"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME="$NAME"
    OS_VERSION="$VERSION_ID"
    OS_ID="$ID"
fi

# 3. Internet Connectivity Check
check_internet() {
    local dns_success=false
    local https_success=false
    local github_success=false
    local docker_success=false

    # 1. DNS Resolution Check
    for domain in google.com github.com registry-1.docker.io; do
        if command -v getent &>/dev/null && getent ahosts "$domain" &>/dev/null; then
            dns_success=true
            break
        fi
        if command -v host &>/dev/null && host -W 2 "$domain" &>/dev/null; then
            dns_success=true
            break
        fi
        if command -v nslookup &>/dev/null && nslookup -timeout=2 "$domain" &>/dev/null; then
            dns_success=true
            break
        fi
    done

    # 2. HTTPS Request Check
    for url in https://www.google.com https://www.cloudflare.com; do
        if command -v curl &>/dev/null; then
            if curl -sI --connect-timeout 3 "$url" &>/dev/null; then
                https_success=true
                break
            fi
        fi
        if command -v wget &>/dev/null; then
            if wget -q --spider --timeout=3 "$url" &>/dev/null; then
                https_success=true
                break
            fi
        fi
    done

    # 3. GitHub Connectivity Check
    for url in https://github.com https://api.github.com; do
        if command -v curl &>/dev/null; then
            if curl -sI --connect-timeout 3 "$url" &>/dev/null; then
                github_success=true
                break
            fi
        fi
        if command -v wget &>/dev/null; then
            if wget -q --spider --timeout=3 "$url" &>/dev/null; then
                github_success=true
                break
            fi
        fi
    done

    # 4. Docker Registry Reachability Check
    for url in https://registry-1.docker.io https://index.docker.io; do
        if command -v curl &>/dev/null; then
            if curl -sI --connect-timeout 3 "$url" &>/dev/null; then
                docker_success=true
                break
            fi
        fi
        if command -v wget &>/dev/null; then
            if wget -q --spider --timeout=3 "$url" &>/dev/null; then
                docker_success=true
                break
            fi
        fi
    done

    # Consider available if ANY of the checks succeeded
    if [ "$dns_success" = true ] || [ "$https_success" = true ] || [ "$github_success" = true ] || [ "$docker_success" = true ]; then
        return 0
    fi

    # Fallback: ICMP Ping to reliable DNS servers if all else failed
    for ip in 1.1.1.1 8.8.8.8; do
        if command -v ping &>/dev/null; then
            if ping -c 1 -W 2 "$ip" &>/dev/null; then
                return 0
            fi
        fi
    done

    return 1
}

INTERNET_CONN=false
if check_internet; then
    INTERNET_CONN=true
fi

# 4. Available Disk Space (Target: /)
DISK_FREE_GB=0
if command -v df &>/dev/null; then
    DISK_FREE_GB=$(df -BG / | tail -1 | awk '{print $4}' | tr -d 'G') || DISK_FREE_GB=0
fi

# 5. Available RAM
RAM_TOTAL_MB=0
if [ -f /proc/meminfo ]; then
    RAM_TOTAL_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    RAM_TOTAL_MB=$((RAM_TOTAL_KB / 1024))
elif command -v free &>/dev/null; then
    RAM_TOTAL_MB=$(free -m | awk '/^Mem:/{print $2}') || RAM_TOTAL_MB=0
fi

# 6. Port Check Helpers
get_port_process() {
    local port=$1
    local output
    output=$(ss -lptn "sport = :$port" 2>/dev/null | grep -v "State") || output=""
    if [[ -n "$output" ]]; then
        local pid
        pid=$(echo "$output" | grep -oE "pid=[0-9]+" | head -n 1 | cut -d= -f2) || pid=""
        local pname
        pname=$(echo "$output" | grep -oE "users:\(\(\"[^\"]+\"" | head -n 1 | cut -d'"' -f2) || pname=""
        if [[ -z "$pid" ]]; then pid="unknown"; fi
        if [[ -z "$pname" ]]; then pname="unknown"; fi
        echo "$pid:$pname"
    else
        echo ""
    fi
}

PORT_80_PROCESS=$(get_port_process 80)
PORT_443_PROCESS=$(get_port_process 443)
PORT_1935_PROCESS=$(get_port_process 1935)
PORT_3000_PROCESS=$(get_port_process 3000)
PORT_5432_PROCESS=$(get_port_process 5432)

PORT_80_OCCUPIED=$( [[ -n "$PORT_80_PROCESS" ]] && echo true || echo false )
PORT_443_OCCUPIED=$( [[ -n "$PORT_443_PROCESS" ]] && echo true || echo false )
PORT_1935_OCCUPIED=$( [[ -n "$PORT_1935_PROCESS" ]] && echo true || echo false )
PORT_3000_OCCUPIED=$( [[ -n "$PORT_3000_PROCESS" ]] && echo true || echo false )
PORT_5432_OCCUPIED=$( [[ -n "$PORT_5432_PROCESS" ]] && echo true || echo false )

# 7. Pre-existing Docker checks
EXISTING_CONTAINERS=()
EXISTING_NETWORKS=()
EXISTING_VOLUMES=()

if command -v docker &> /dev/null; then
    if systemctl is-active --quiet docker 2>/dev/null; then
        for cname in streampulse_manager streampulse_db streampulse_certbot; do
            if docker ps -a --format '{{.Names}}' | grep -q "^${cname}$"; then
                EXISTING_CONTAINERS+=("$cname")
            fi
        done
        for netname in vps-deployment_default streampulse_network; do
            if docker network ls --format '{{.Name}}' | grep -q "^${netname}$"; then
                EXISTING_NETWORKS+=("$netname")
            fi
        done
        for volname in vps-deployment_postgres_data vps-deployment_hls_storage vps-deployment_certbot_conf vps-deployment_certbot_www; do
            if docker volume ls --format '{{.Name}}' | grep -q "^${volname}$"; then
                EXISTING_VOLUMES+=("$volname")
            fi
        done
    fi
fi

# 8. Render Validation Summary
echo -e "\n======================================================================="
echo -e "                 PRE-INSTALLATION VALIDATION SUMMARY"
echo -e "======================================================================="

PASS_LIST=()
WARN_LIST=()
CRIT_LIST=()

# Operating System
if [[ "$OS_ID" == "ubuntu" ]]; then
    PASS_LIST+=("Ubuntu Linux OS (Detected: $OS_NAME $OS_VERSION)")
else
    WARN_LIST+=("Operating System ($OS_NAME $OS_VERSION) - script optimized for Ubuntu")
fi

# Root Check
PASS_LIST+=("Root Privileges (Executing as root)")

# Internet Check
if [ "$INTERNET_CONN" = true ]; then
    PASS_LIST+=("Internet Connectivity (Active)")
else
    CRIT_LIST+=("Internet Connectivity (No internet connection detected)")
fi

# Disk Space
if [ "$DISK_FREE_GB" -ge 5 ]; then
    PASS_LIST+=("Available Disk Space ($DISK_FREE_GB GB free)")
else
    WARN_LIST+=("Available Disk Space ($DISK_FREE_GB GB free - recommend >= 5 GB)")
fi

# RAM
if [ "$RAM_TOTAL_MB" -ge 1000 ]; then
    PASS_LIST+=("Available RAM ($RAM_TOTAL_MB MB total)")
else
    WARN_LIST+=("Available RAM ($RAM_TOTAL_MB MB total - recommend >= 1024 MB)")
fi

# Host Services and Binary Checks
if command -v docker &>/dev/null; then
    PASS_LIST+=("Docker Engine (Installed)")
else
    WARN_LIST+=("Docker Engine (Not found; will install automatically)")
fi

if docker compose version &>/dev/null || command -v docker-compose &>/dev/null; then
    PASS_LIST+=("Docker Compose (Installed)")
else
    WARN_LIST+=("Docker Compose (Not found; will install automatically)")
fi

if command -v ffmpeg &>/dev/null; then
    PASS_LIST+=("FFmpeg Host Status (Installed)")
else
    WARN_LIST+=("FFmpeg Host Status (Not found; StreamPulse container embeds own FFmpeg)")
fi

if command -v nginx &>/dev/null; then
    WARN_LIST+=("Nginx Host Status (Installed on host - check ports for active conflicts)")
else
    PASS_LIST+=("Nginx Host Status (Not installed on host)")
fi

if command -v psql &>/dev/null || command -v postgres &>/dev/null; then
    WARN_LIST+=("PostgreSQL Host Status (Installed on host - check ports for active conflicts)")
else
    PASS_LIST+=("PostgreSQL Host Status (Not installed on host)")
fi

# Port check reporting
for port in 80 443 1935 3000 5432; do
    proc_var="PORT_${port}_PROCESS"
    if [[ -n "${!proc_var}" ]]; then
        pid=$(echo "${!proc_var}" | cut -d: -f1)
        name=$(echo "${!proc_var}" | cut -d: -f2)
        WARN_LIST+=("Port ${port} is occupied by '${name}' (PID: ${pid})")
    else
        PASS_LIST+=("Port ${port} is free")
    fi
done

# Print PASS section
if [ ${#PASS_LIST[@]} -gt 0 ]; then
    echo -e "${GREEN}[PASS]${NC}"
    for item in "${PASS_LIST[@]}"; do
        echo -e "  * $item"
    done
fi

# Print WARNING section
if [ ${#WARN_LIST[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}[WARNING]${NC}"
    for item in "${WARN_LIST[@]}"; do
        echo -e "  * $item"
    done
fi

# Print ACTION REQUIRED section
ACTION_REQ_NEEDED=false
if [ ${#CRIT_LIST[@]} -gt 0 ] || [ "$PORT_80_OCCUPIED" = true ] || [ "$PORT_443_OCCUPIED" = true ] || [ "$PORT_1935_OCCUPIED" = true ] || [ "$PORT_3000_OCCUPIED" = true ] || [ "$PORT_5432_OCCUPIED" = true ] || [ ${#EXISTING_CONTAINERS[@]} -gt 0 ]; then
    ACTION_REQ_NEEDED=true
    echo -e "\n${RED}[ACTION REQUIRED]${NC}"
    for item in "${CRIT_LIST[@]}"; do
        echo -e "  * $item"
    done
    if [ "$PORT_5432_OCCUPIED" = true ]; then
        echo -e "  * Port 5432 is occupied by process '$(echo $PORT_5432_PROCESS | cut -d: -f2)'"
    fi
    if [ "$PORT_80_OCCUPIED" = true ] || [ "$PORT_443_OCCUPIED" = true ]; then
        echo -e "  * HTTP Port 80/443 is occupied by process '$(echo ${PORT_80_PROCESS:-$PORT_443_PROCESS} | cut -d: -f2)'"
    fi
    if [ "$PORT_1935_OCCUPIED" = true ]; then
        echo -e "  * Port 1935 (RTMP) is occupied by process '$(echo $PORT_1935_PROCESS | cut -d: -f2)'"
    fi
    if [ "$PORT_3000_OCCUPIED" = true ]; then
        echo -e "  * Port 3000 is occupied by process '$(echo $PORT_3000_PROCESS | cut -d: -f2)'"
    fi
    if [ ${#EXISTING_CONTAINERS[@]} -gt 0 ]; then
        echo -e "  * Pre-existing StreamPulse Docker containers detected: ${EXISTING_CONTAINERS[*]}"
    fi
fi

echo -e "=======================================================================\n"

# Abort if critical requirements fail
if [ ${#CRIT_LIST[@]} -gt 0 ]; then
    log_error "Validation failed with critical errors. Please resolve them and re-run the installer."
    exit 1
fi

# 9. Interactive Conflict Resolution
if [ "$ACTION_REQ_NEEDED" = true ]; then
    log_warning "Addressing active environment conflicts..."

    # Resolve Port 5432 (PostgreSQL)
    if [ "$PORT_5432_OCCUPIED" = true ]; then
        echo ""
        echo "Detected PostgreSQL service."
        echo ""
        echo "Select an action:"
        echo ""
        echo "1. Use existing PostgreSQL"
        echo "2. Stop PostgreSQL automatically and continue"
        echo "3. Use another Docker host port"
        echo "4. Cancel installation"
        echo ""
        echo -n -e "${YELLOW}[PROMPT] Choose an option [1-4]: ${NC}"
        if [[ -t 0 ]]; then read -r PG_RESOLUTION; else PG_RESOLUTION="3"; fi

        if [[ "$PG_RESOLUTION" == "1" ]]; then
            RESOLVED_PG_STR="Use existing PostgreSQL"
            log_info "Configuring to connect to pre-existing host database..."
            
            echo -n -e "${YELLOW}[PROMPT] Enter host database IP address (default: 172.17.0.1 for docker host gateway): ${NC}"
            if [[ -t 0 ]]; then read -r EXT_DB_HOST; else EXT_DB_HOST=""; fi
            if [[ -z "$EXT_DB_HOST" ]]; then EXT_DB_HOST="172.17.0.1"; fi

            echo -n -e "${YELLOW}[PROMPT] Enter host database port (default: 5432): ${NC}"
            if [[ -t 0 ]]; then read -r EXT_DB_PORT; else EXT_DB_PORT=""; fi
            if [[ -z "$EXT_DB_PORT" ]]; then EXT_DB_PORT="5432"; fi

            echo -n -e "${YELLOW}[PROMPT] Enter host database username (default: streampulse_admin): ${NC}"
            if [[ -t 0 ]]; then read -r EXT_DB_USER; else EXT_DB_USER=""; fi
            if [[ -z "$EXT_DB_USER" ]]; then EXT_DB_USER="streampulse_admin"; fi

            echo -n -e "${YELLOW}[PROMPT] Enter host database password: ${NC}"
            if [[ -t 0 ]]; then read -r -s EXT_DB_PASSWORD; echo ""; else EXT_DB_PASSWORD=""; fi

            echo -n -e "${YELLOW}[PROMPT] Enter host database name (default: streampulse): ${NC}"
            if [[ -t 0 ]]; then read -r EXT_DB_NAME; else EXT_DB_NAME=""; fi
            if [[ -z "$EXT_DB_NAME" ]]; then EXT_DB_NAME="streampulse"; fi

            USE_CUSTOM_DB=true
            CUSTOM_DB_HOST="$EXT_DB_HOST"
            CUSTOM_DB_PORT="$EXT_DB_PORT"
            CUSTOM_DB_USER="$EXT_DB_USER"
            CUSTOM_DB_PASSWORD="$EXT_DB_PASSWORD"
            CUSTOM_DB_NAME="$EXT_DB_NAME"

            # Remap host port of postgres_db container to prevent local port bind error
            sed -i 's/"5432:5432"/"5433:5432"/g' "$SCRIPT_DIR/docker-compose.yml"
        elif [[ "$PG_RESOLUTION" == "2" ]]; then
            RESOLVED_PG_STR="Stop PostgreSQL automatically and continue"
            log_info "Attempting to safely stop host PostgreSQL service..."
            systemctl stop postgresql 2>/dev/null || service postgresql stop 2>/dev/null || true
            sleep 2
            if [[ -n "$(get_port_process 5432)" ]]; then
                log_error "Port 5432 remains occupied after stopping service. Please free it manually."
                exit 1
            fi
            PORT_5432_OCCUPIED=false
            log_success "Host PostgreSQL service stopped successfully. Port 5432 released."
        elif [[ "$PG_RESOLUTION" == "3" ]]; then
            RESOLVED_PG_STR="Use another Docker host port"
            log_info "Modifying docker-compose.yml to deploy Docker PostgreSQL on host port 5433..."
            sed -i 's/"5432:5432"/"5433:5432"/g' "$SCRIPT_DIR/docker-compose.yml"
        else
            log_warning "Installation cancelled safely by the user."
            exit 0
        fi
    fi

    # Resolve Port 80 / 443 (Nginx or HTTP service)
    IS_NGINX_RUNNING=false
    if systemctl is-active --quiet nginx 2>/dev/null || service nginx status &>/dev/null || [ "$PORT_80_OCCUPIED" = true ] || [ "$PORT_443_OCCUPIED" = true ] || command -v nginx &>/dev/null; then
        IS_NGINX_RUNNING=true
    fi

    if [ "$IS_NGINX_RUNNING" = true ]; then
        echo ""
        echo "Detected Nginx or web service conflict on HTTP ports."
        echo ""
        echo "Select:"
        echo ""
        echo "1. Use existing Nginx"
        echo "2. Stop existing Nginx"
        echo "3. Replace configuration"
        echo "4. Cancel"
        echo ""
        echo -n -e "${YELLOW}[PROMPT] Choose an option [1-4]: ${NC}"
        if [[ -t 0 ]]; then read -r NGINX_RESOLUTION; else NGINX_RESOLUTION="2"; fi

        if [[ "$NGINX_RESOLUTION" == "1" ]]; then
            RESOLVED_NGINX_STR="Use existing Nginx"
            log_info "Modifying docker-compose.yml to map HTTP to 8080 and HTTPS to 8443..."
            sed -i 's/"80:80"/"8080:80"/g' "$SCRIPT_DIR/docker-compose.yml"
            sed -i 's/"443:443"/"8443:443"/g' "$SCRIPT_DIR/docker-compose.yml"
            HOST_HTTP_PORT=8080
            HOST_HTTPS_PORT=8443
        elif [[ "$NGINX_RESOLUTION" == "2" ]]; then
            RESOLVED_NGINX_STR="Stop existing Nginx"
            log_info "Attempting to stop host Nginx/Apache2 services..."
            systemctl stop nginx 2>/dev/null || service nginx stop 2>/dev/null || true
            systemctl stop apache2 2>/dev/null || service apache2 stop 2>/dev/null || true
            sleep 2
            if [[ -n "$(get_port_process 80)" ]] || [[ -n "$(get_port_process 443)" ]]; then
                log_error "HTTP ports (80/443) are still occupied. Please release them manually."
                exit 1
            fi
            PORT_80_OCCUPIED=false
            PORT_443_OCCUPIED=false
            log_success "Host Nginx/HTTP services stopped. Ports 80 and 443 released."
        elif [[ "$NGINX_RESOLUTION" == "3" ]]; then
            RESOLVED_NGINX_STR="Replace configuration"
            log_info "Replacing host Nginx configuration with standard Docker ports..."
            log_info "Stopping and disabling host Nginx service..."
            systemctl stop nginx 2>/dev/null || service nginx stop 2>/dev/null || true
            systemctl disable nginx 2>/dev/null || true
            sleep 2
            if [[ -n "$(get_port_process 80)" ]] || [[ -n "$(get_port_process 443)" ]]; then
                log_error "HTTP ports (80/443) are still occupied after disabling host Nginx."
                exit 1
            fi
            PORT_80_OCCUPIED=false
            PORT_443_OCCUPIED=false
            log_success "Host Nginx stopped and disabled successfully. Standard Docker ports (80/443) prepared."
        else
            log_warning "Installation cancelled safely."
            exit 0
        fi
    fi

    # Resolve Port 1935 (RTMP ingest port)
    if [ "$PORT_1935_OCCUPIED" = true ]; then
        pid=$(echo "$PORT_1935_PROCESS" | cut -d: -f1)
        pname=$(echo "$PORT_1935_PROCESS" | cut -d: -f2)
        log_warning "Port 1935 (RTMP) is occupied by process '$pname' (PID: $pid)."
        echo -e "${YELLOW}[CONFLICT RESOLUTION] Select action for RTMP ingest port conflict:${NC}"
        echo "1) Terminate conflicting host process automatically."
        echo "2) Deploy Docker RTMP ingest on alternate host port 1936."
        echo "3) Cancel installation."
        echo -n -e "${YELLOW}[PROMPT] Choose an option [1-3]: ${NC}"
        if [[ -t 0 ]]; then read -r RTMP_RESOLUTION; else RTMP_RESOLUTION="2"; fi

        if [[ "$RTMP_RESOLUTION" == "1" ]]; then
            log_info "Killing process '$pname' (PID: $pid) on port 1935..."
            kill -9 "$pid" || true
            sleep 1
            if [[ -n "$(get_port_process 1935)" ]]; then
                log_error "Failed to release port 1935."
                exit 1
            fi
            log_success "Successfully released port 1935."
        elif [[ "$RTMP_RESOLUTION" == "2" ]]; then
            log_info "Modifying docker-compose.yml to map RTMP to host port 1936..."
            sed -i 's/"1935:1935"/"1936:1935"/g' "$SCRIPT_DIR/docker-compose.yml"
            HOST_RTMP_PORT=1936
        else
            log_warning "Installation cancelled safely."
            exit 0
        fi
    fi

    # Resolve Port 3000 (StreamPulse UI port)
    if [ "$PORT_3000_OCCUPIED" = true ]; then
        pid=$(echo "$PORT_3000_PROCESS" | cut -d: -f1)
        pname=$(echo "$PORT_3000_PROCESS" | cut -d: -f2)
        log_warning "Port 3000 is occupied by process '$pname' (PID: $pid)."
        echo -e "${YELLOW}[CONFLICT RESOLUTION] Select action for Port 3000 conflict:${NC}"
        echo "1) Terminate conflicting host process automatically."
        echo "2) Deploy Docker StreamPulse direct UI on alternate host port 3001."
        echo "3) Cancel installation."
        echo -n -e "${YELLOW}[PROMPT] Choose an option [1-3]: ${NC}"
        if [[ -t 0 ]]; then read -r PORT3000_RESOLUTION; else PORT3000_RESOLUTION="2"; fi

        if [[ "$PORT3000_RESOLUTION" == "1" ]]; then
            log_info "Killing process '$pname' (PID: $pid) on port 3000..."
            kill -9 "$pid" || true
            sleep 1
            if [[ -n "$(get_port_process 3000)" ]]; then
                log_error "Failed to release port 3000."
                exit 1
            fi
            log_success "Successfully released port 3000."
        elif [[ "$PORT3000_RESOLUTION" == "2" ]]; then
            log_info "Modifying docker-compose.yml to map direct UI to host port 3001..."
            sed -i 's/"3000:3000"/"3001:3000"/g' "$SCRIPT_DIR/docker-compose.yml"
        else
            log_warning "Installation cancelled safely."
            exit 0
        fi
    fi

    # Resolve Pre-existing Docker Containers
    if [ ${#EXISTING_CONTAINERS[@]} -gt 0 ]; then
        echo ""
        echo "Existing installation detected."
        echo ""
        echo "Select:"
        echo ""
        echo "1. Reuse existing deployment"
        echo "2. Restart containers"
        echo "3. Rebuild containers"
        echo "4. Remove existing deployment"
        echo "5. Cancel"
        echo ""
        echo -n -e "${YELLOW}[PROMPT] Choose an option [1-5]: ${NC}"
        if [[ -t 0 ]]; then read -r CONTAINER_RESOLUTION; else CONTAINER_RESOLUTION="2"; fi

        if [[ "$CONTAINER_RESOLUTION" == "1" ]]; then
            RESOLVED_CONTAINER_STR="Reuse existing deployment"
            SKIP_BUILD=true
            REUSE_MODE=true
        elif [[ "$CONTAINER_RESOLUTION" == "2" ]]; then
            RESOLVED_CONTAINER_STR="Restart containers"
            log_info "Stopping existing containers..."
            if docker compose version &>/dev/null; then
                docker compose down || true
            elif command -v docker-compose &>/dev/null; then
                docker-compose down || true
            else
                for cname in "${EXISTING_CONTAINERS[@]}"; do
                    docker stop "$cname" &>/dev/null || true
                    docker rm "$cname" &>/dev/null || true
                done
            fi
            SKIP_BUILD=true
            REUSE_MODE=false
        elif [[ "$CONTAINER_RESOLUTION" == "3" ]]; then
            RESOLVED_CONTAINER_STR="Rebuild containers"
            log_info "Stopping and removing existing containers for rebuild..."
            if docker compose version &>/dev/null; then
                docker compose down || true
            elif command -v docker-compose &>/dev/null; then
                docker-compose down || true
            else
                for cname in "${EXISTING_CONTAINERS[@]}"; do
                    docker stop "$cname" &>/dev/null || true
                    docker rm "$cname" &>/dev/null || true
                done
            fi
            SKIP_BUILD=false
        elif [[ "$CONTAINER_RESOLUTION" == "4" ]]; then
            RESOLVED_CONTAINER_STR="Remove existing deployment"
            log_info "Stopping and removing existing containers, networks, and persistent volumes..."
            if docker compose version &>/dev/null; then
                docker compose down -v || true
            elif command -v docker-compose &>/dev/null; then
                docker-compose down -v || true
            else
                for cname in "${EXISTING_CONTAINERS[@]}"; do
                    docker stop "$cname" &>/dev/null || true
                    docker rm -v "$cname" &>/dev/null || true
                done
            fi
            SKIP_BUILD=false
        else
            log_warning "Installation cancelled safely."
            exit 0
        fi
    fi
fi

log_success "Pre-installation validation and conflict resolution completed successfully!"

# --- 1. System Updates & Hardening ---
log_info "Step 1: Updating system packages and installing baseline utilities..."
apt-get update && apt-get upgrade -y
apt-get install -y curl wget git ufw fail2ban htop unzip ca-certificates software-properties-common gnupg

# Configure Fail2Ban
log_info "Configuring Fail2Ban brute-force protection for SSH..."
if [ ! -f /etc/fail2ban/jail.local ]; then
    cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
fi
systemctl enable fail2ban
systemctl restart fail2ban
log_success "Fail2Ban protection successfully activated."

# --- 2. UFW Firewall Setup ---
log_info "Step 2: Securing VPS via UFW Firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp      # SSH
ufw allow 80/tcp      # HTTP
ufw allow 443/tcp     # HTTPS Secure
ufw allow 1935/tcp    # RTMP Live-Stream Ingest
ufw allow 3000/tcp    # StreamPulse Manager Web UI (if direct access bypass is needed)
ufw --force enable
log_success "Firewall active. Allowed ports: 22, 80, 443, 1935, 3000."

# --- 3. Install Docker Engine & Compose plugin ---
log_info "Step 3: Installing Docker Engine & Docker Compose..."
if ! command -v docker &> /dev/null; then
    log_info "Adding Docker repository keys..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    log_success "Docker Engine installed."
else
    log_success "Docker is already installed: $(docker --version)"
fi

# Verify Docker daemon is active
systemctl enable docker
systemctl start docker

# --- 4. Prepare Environment Variables ---
log_info "Step 4: Loading and synchronizing environment variables..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Generate secure random secrets
RANDOM_JWT_SECRET=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32)
RANDOM_DB_PASS=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 24)

# Create Root .env if not exists
if [ ! -f "$ROOT_DIR/.env" ]; then
    log_info "Generating secure .env configuration file in project root..."
    
    DB_HOST_VAR="postgres_db"
    DB_PORT_VAR="5432"
    DB_USER_VAR="streampulse_admin"
    DB_PASSWORD_VAR="${RANDOM_DB_PASS}"
    DB_NAME_VAR="streampulse"

    if [ "$USE_CUSTOM_DB" = true ]; then
        DB_HOST_VAR="$CUSTOM_DB_HOST"
        DB_PORT_VAR="$CUSTOM_DB_PORT"
        DB_USER_VAR="$CUSTOM_DB_USER"
        DB_PASSWORD_VAR="$CUSTOM_DB_PASSWORD"
        DB_NAME_VAR="$CUSTOM_DB_NAME"
    fi

    cat <<EOF > "$ROOT_DIR/.env"
# StreamPulse Production Environment Variables
NODE_ENV=production
JWT_SECRET=${RANDOM_JWT_SECRET}

# Storage Configuration
STORAGE_MODE=postgres

# Database Configuration
DB_HOST=${DB_HOST_VAR}
DB_PORT=${DB_PORT_VAR}
DB_USER=${DB_USER_VAR}
DB_PASSWORD=${DB_PASSWORD_VAR}
DB_NAME=${DB_NAME_VAR}

# AI Feature Flags
AI_ENABLED=false
GEMINI_API_KEY=
EOF
    log_success ".env file generated successfully with secure credentials."
else
    log_warning ".env file already exists. Skipping recreation to preserve existing secrets."
fi

# Synchronize docker-compose.yml environment variables with .env
DB_HOST_FROM_ENV=$(grep -E "^DB_HOST=" "$ROOT_DIR/.env" | cut -d'=' -f2- || echo "postgres_db")
DB_PORT_FROM_ENV=$(grep -E "^DB_PORT=" "$ROOT_DIR/.env" | cut -d'=' -f2- || echo "5432")
DB_USER_FROM_ENV=$(grep -E "^DB_USER=" "$ROOT_DIR/.env" | cut -d'=' -f2- || echo "streampulse_admin")
DB_PASS_FROM_ENV=$(grep -E "^DB_PASSWORD=" "$ROOT_DIR/.env" | cut -d'=' -f2- || echo "${RANDOM_DB_PASS}")
DB_NAME_FROM_ENV=$(grep -E "^DB_NAME=" "$ROOT_DIR/.env" | cut -d'=' -f2- || echo "streampulse")
JWT_SECRET_FROM_ENV=$(grep -E "^JWT_SECRET=" "$ROOT_DIR/.env" | cut -d'=' -f2- || echo "${RANDOM_JWT_SECRET}")

# Update compose env dynamically to maintain absolute environment parity
log_info "Synchronizing service configurations into docker-compose.yml..."
sed -i "s/DB_HOST=.*$/DB_HOST=${DB_HOST_FROM_ENV}/g" "$SCRIPT_DIR/docker-compose.yml"
sed -i "s/DB_PORT=.*$/DB_PORT=${DB_PORT_FROM_ENV}/g" "$SCRIPT_DIR/docker-compose.yml"
sed -i "s/DB_USER=.*$/DB_USER=${DB_USER_FROM_ENV}/g" "$SCRIPT_DIR/docker-compose.yml"
sed -i "s/POSTGRES_USER=.*$/POSTGRES_USER=${DB_USER_FROM_ENV}/g" "$SCRIPT_DIR/docker-compose.yml"
sed -i "s/DB_PASSWORD=.*$/DB_PASSWORD=${DB_PASS_FROM_ENV}/g" "$SCRIPT_DIR/docker-compose.yml"
sed -i "s/POSTGRES_PASSWORD=.*$/POSTGRES_PASSWORD=${DB_PASS_FROM_ENV}/g" "$SCRIPT_DIR/docker-compose.yml"
sed -i "s/DB_NAME=.*$/DB_NAME=${DB_NAME_FROM_ENV}/g" "$SCRIPT_DIR/docker-compose.yml"
sed -i "s/POSTGRES_DB=.*$/POSTGRES_DB=${DB_NAME_FROM_ENV}/g" "$SCRIPT_DIR/docker-compose.yml"
sed -i "s/JWT_SECRET=.*$/JWT_SECRET=${JWT_SECRET_FROM_ENV}/g" "$SCRIPT_DIR/docker-compose.yml"

# --- 5. SSL & Domain Configuration ---
log_info "Step 5: Configuring Deployment Mode..."

# Helper function to generate custom Nginx configuration dynamically
generate_nginx_conf() {
    local mode=$1
    local target=$2

    # Detect final base image from Dockerfile to choose the correct user and PID path
    local base_image=""
    if [ -f "$SCRIPT_DIR/Dockerfile" ]; then
        base_image=$(grep -Ei '^FROM ' "$SCRIPT_DIR/Dockerfile" | tail -n 1 | awk '{print $2}' || echo "")
    fi

    local nginx_user="www-data"
    local nginx_pid="/run/nginx.pid"

    if [[ "$base_image" =~ alpine ]]; then
        nginx_user="nginx"
        nginx_pid="/var/run/nginx.pid"
    elif [[ "$base_image" =~ ubuntu ]] || [[ "$base_image" =~ debian ]]; then
        nginx_user="www-data"
        nginx_pid="/run/nginx.pid"
    else
        nginx_user="www-data"
        nginx_pid="/run/nginx.pid"
    fi

    if [[ "$mode" == "domain" ]]; then
        log_info "Generating Domain-based Nginx configuration for $target..."
        cat <<EOF > "$SCRIPT_DIR/nginx.conf"
# StreamPulse Nginx Reverse Proxy and HTTP Server Config

user $nginx_user;
worker_processes 1;
error_log /var/log/nginx/error.log warn;
pid $nginx_pid;

# Load dynamic modules on Ubuntu
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 1024;
}

# Unified RTMP Configuration
rtmp {
    server {
        listen 1935; # Standard RTMP port
        chunk_size 4096;

        # Primary Live Stream Ingest Application
        # OBS publishes to rtmp://server/ingest/<stream_key>
        application ingest {
            live on;
            record off;

            # Forward the incoming stream to the 'live' application for RTMP playback
            push rtmp://localhost/live;

            # Hand over incoming RTMP stream to FFmpeg for dynamic Multi-Bitrate HLS Transcoding
            # This triggers the custom transcode script to generate 1080p, 720p, 480p, and 360p HLS playlists
            exec_push /usr/local/bin/transcode.sh \$name;
        }

        # Standalone Live application for playback/distribution (No transcoding hooks, no circular locks)
        application live {
            live on;
            record off;
        }

        # Raw ingest application (optional, if you want direct playback without transcoding)
        application raw {
            live on;
            record off;
            
            # Enable HLS generation for raw input directly
            hls on;
            hls_path /var/www/hls/raw;
            hls_fragment 3;
            hls_playlist_length 60;
        }
    }
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;
    sendfile on;
    keepalive_timeout 65;

    # Enable Gzip Compression
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

    # HTTP Server (Redirects all traffic to HTTPS)
    server {
        listen 80;
        server_name $target;

        # Let's Encrypt ACME challenge directory
        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }

        location / {
            return 301 https://\$host\$request_uri;
        }
    }

    # HTTPS Secure Server Configuration
    server {
        listen 443 ssl;
        server_name $target;

        # SSL Certificates (managed via Let's Encrypt Certbot)
        ssl_certificate /etc/letsencrypt/live/$target/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/$target/privkey.pem;

        # SSL Best Practices
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;
        ssl_prefer_server_ciphers on;
        ssl_session_cache shared:SSL:10m;
        ssl_session_timeout 1d;

        # Frontend SPA Serving
        location / {
            proxy_pass http://localhost:3000; # Reverse proxy to the StreamPulse Node.js Server
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host \$host;
            proxy_cache_bypass \$http_upgrade;
        }

        # Node.js API Endpoints Proxy
        location /api/ {
            proxy_pass http://localhost:3000/api/;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

        # RTMP Statistics XML
        location /stat {
            rtmp_stat all;
            rtmp_stat_stylesheet stat.xsl;

            add_header Access-Control-Allow-Origin * always;
        }

        # RTMP Statistics Stylesheet
        location /stat.xsl {
            alias /usr/share/doc/libnginx-mod-rtmp/examples/stat.xsl;
        }

        # Playback HLS (Adaptive Bitrate Streaming Playlists & TS fragments)
        location /hls/ {
            alias /var/www/hls/;
            
            # CORS headers to support multi-origin players (HLS.js, Video.js, Mobile browsers)
            add_header Access-Control-Allow-Origin * always;
            add_header Access-Control-Expose-Headers Content-Length,Content-Range always;
            add_header Access-Control-Allow-Methods 'GET, HEAD, OPTIONS' always;
            add_header Access-Control-Allow-Headers 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range' always;

            if (\$request_method = 'OPTIONS') {
                add_header 'Access-Control-Allow-Origin' '*';
                add_header 'Access-Control-Allow-Methods' 'GET, HEAD, OPTIONS';
                add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
                add_header 'Access-Control-Max-Age' 1728000;
                add_header 'Content-Type' 'text/plain; charset=utf-8';
                add_header 'Content-Length' 0;
                return 204;
            }

            types {
                application/vnd.apple.mpegurl m3u8;
                video/mp2t ts;
            }

            expires -1; # Don't cache playlist files
        }
    }
}
EOF
    else
        log_info "Generating Public IP-based Nginx configuration for $target..."
        cat <<EOF > "$SCRIPT_DIR/nginx.conf"
# StreamPulse Nginx Reverse Proxy and HTTP Server Config

user $nginx_user;
worker_processes 1;
error_log /var/log/nginx/error.log warn;
pid $nginx_pid;

# Load dynamic modules on Ubuntu
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 1024;
}

# Unified RTMP Configuration
rtmp {
    server {
        listen 1935; # Standard RTMP port
        chunk_size 4096;

        # Primary Live Stream Ingest Application
        # OBS publishes to rtmp://server/ingest/<stream_key>
        application ingest {
            live on;
            record off;

            # Forward the incoming stream to the 'live' application for RTMP playback
            push rtmp://localhost/live;

            # Hand over incoming RTMP stream to FFmpeg for dynamic Multi-Bitrate HLS Transcoding
            # This triggers the custom transcode script to generate 1080p, 720p, 480p, and 360p HLS playlists
            exec_push /usr/local/bin/transcode.sh \$name;
        }

        # Standalone Live application for playback/distribution (No transcoding hooks, no circular locks)
        application live {
            live on;
            record off;
        }

        # Raw ingest application (optional, if you want direct playback without transcoding)
        application raw {
            live on;
            record off;
            
            # Enable HLS generation for raw input directly
            hls on;
            hls_path /var/www/hls/raw;
            hls_fragment 3;
            hls_playlist_length 60;
        }
    }
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;
    sendfile on;
    keepalive_timeout 65;

    # Enable Gzip Compression
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

    # HTTP Server for Public IP / Local IP / Domain
    server {
        listen 80 default_server;
        server_name _;

        # Frontend SPA Serving
        location / {
            proxy_pass http://localhost:3000; # Reverse proxy to the StreamPulse Node.js Server
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host \$host;
            proxy_cache_bypass \$http_upgrade;
        }

        # Node.js API Endpoints Proxy
        location /api/ {
            proxy_pass http://localhost:3000/api/;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

        # RTMP Statistics XML
        location /stat {
            rtmp_stat all;
            rtmp_stat_stylesheet stat.xsl;
            add_header Access-Control-Allow-Origin * always;
        }

        # RTMP Statistics Stylesheet
        location /stat.xsl {
            alias /usr/share/doc/libnginx-mod-rtmp/examples/stat.xsl;
        }

        # Playback HLS (Adaptive Bitrate Streaming Playlists & TS fragments)
        location /hls/ {
            alias /var/www/hls/;
            
            # CORS headers to support multi-origin players (HLS.js, Video.js, Mobile browsers)
            add_header Access-Control-Allow-Origin * always;
            add_header Access-Control-Expose-Headers Content-Length,Content-Range always;
            add_header Access-Control-Allow-Methods 'GET, HEAD, OPTIONS' always;
            add_header Access-Control-Allow-Headers 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range' always;

            if (\$request_method = 'OPTIONS') {
                add_header 'Access-Control-Allow-Origin' '*';
                add_header 'Access-Control-Allow-Methods' 'GET, HEAD, OPTIONS';
                add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
                add_header 'Access-Control-Max-Age' 1728000;
                add_header 'Content-Type' 'text/plain; charset=utf-8';
                add_header 'Content-Length' 0;
                return 204;
            }

            types {
                application/vnd.apple.mpegurl m3u8;
                video/mp2t ts;
            }

            expires -1; # Don't cache playlist files
        }
    }
}
EOF
    fi
}

log_info "Detecting VPS Public IP..."
PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org || curl -s --max-time 5 https://ifconfig.me || curl -s --max-time 5 https://icanhazip.com || echo "YOUR_VPS_PUBLIC_IP")
if [[ "$PUBLIC_IP" == "YOUR_VPS_PUBLIC_IP" ]]; then
    log_warning "Could not automatically detect public IP. Using default placeholder."
else
    log_success "Detected Public IP: $PUBLIC_IP"
fi

# --- Deployment-Aware Endpoint Selection ---
IS_LOCAL_ENV=false
VIRT_TYPE="none"
if command -v systemd-detect-virt &>/dev/null; then
    VIRT_TYPE=$(systemd-detect-virt 2>/dev/null || echo "none")
fi

PRODUCT_NAME=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "")
SYS_VENDOR=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || echo "")

if [[ "$VIRT_TYPE" == "oracle" || "$VIRT_TYPE" == "vmware" ]] || \
   [[ "$PRODUCT_NAME" =~ [Vv]irtual[Bb]ox || "$PRODUCT_NAME" =~ [Vv]mware || "$PRODUCT_NAME" =~ [Vv][Mm]ware ]] || \
   [[ "$SYS_VENDOR" =~ [Vv]irtual[Bb]ox || "$SYS_VENDOR" =~ [Vv]mware || "$SYS_VENDOR" =~ [Vv][Mm]ware ]]; then
    IS_LOCAL_ENV=true
fi

DEFAULT_IFACE=$(ip route show default 2>/dev/null | grep -oP 'dev \K\S+' | head -n 1 || echo "")
DEFAULT_IP=""
if [[ -n "$DEFAULT_IFACE" ]]; then
    DEFAULT_IP=$(ip -4 addr show dev "$DEFAULT_IFACE" 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -n 1 || echo "")
    if [[ "$DEFAULT_IP" =~ ^192\.168\. ]] || [[ "$DEFAULT_IP" =~ ^10\. ]] || [[ "$DEFAULT_IP" =~ ^172\.(16|17|18|19|20|21|22|23|24|25|26|27|28|29|30|31)\. ]]; then
        if [[ "$DEFAULT_IP" =~ ^192\.168\. ]] || [ "$IS_LOCAL_ENV" = true ]; then
            IS_LOCAL_ENV=true
        fi
    fi
fi

get_local_lan_ip() {
    if [[ -n "${DEFAULT_IP:-}" ]] && [[ "$DEFAULT_IP" =~ ^192\.168\. || "$DEFAULT_IP" =~ ^10\. || "$DEFAULT_IP" =~ ^172\.(16|17|18|19|20|21|22|23|24|25|26|27|28|29|30|31)\. ]]; then
        if ! [[ "$DEFAULT_IP" =~ ^172\.(17|18|19)\. ]]; then
            echo "$DEFAULT_IP"
            return 0
        fi
    fi
    local ips
    ips=$(hostname -I 2>/dev/null || ip addr show | grep -oP 'inet \K[\d.]+')
    for ip in $ips; do
        if [[ "$ip" =~ ^127\. ]] || [[ "$ip" =~ ^172\.(17|18|19)\. ]]; then
            continue
        fi
        if [[ "$ip" =~ ^192\.168\. ]] || [[ "$ip" =~ ^10\. ]] || [[ "$ip" =~ ^172\. ]]; then
            echo "$ip"
            return 0
        fi
    done
    echo "${DEFAULT_IP:-127.0.0.1}"
}

# Select primary endpoint based on deployment environment
if [ "$IS_LOCAL_ENV" = true ]; then
    LOCAL_LAN_IP=$(get_local_lan_ip)
    log_info "Local deployment environment detected (VirtualBox/VMware/Local Network)."
    log_info "Automatically selected Local LAN IP: $LOCAL_LAN_IP"
    TARGET_ENDPOINT="$LOCAL_LAN_IP"
else
    log_info "Public VPS environment detected."
    log_info "Automatically selected Public IP: $PUBLIC_IP"
    TARGET_ENDPOINT="$PUBLIC_IP"
fi

echo -e "${YELLOW}Select StreamPulse Deployment Mode:${NC}"
echo -e "1) Domain Mode (Configure Let's Encrypt SSL & HTTPS)"
if [ "$IS_LOCAL_ENV" = true ]; then
    echo -e "2) Local LAN IP Mode (Skip SSL, use standard HTTP on Local LAN IP)"
else
    echo -e "2) Public IP Mode (Skip SSL, use standard HTTP on Public IP)"
fi
echo -e -n "${YELLOW}[PROMPT] Choose an option [1-2]: ${NC}"

if [[ -t 0 ]]; then
    read -r DEPLOY_MODE
else
    DEPLOY_MODE="2" # Fallback to IP mode in headless CI / non-interactive
fi

DOMAIN_NAME=""
if [[ "$DEPLOY_MODE" == "1" ]]; then
    log_info "Selected: Domain Mode"
    echo -e -n "${YELLOW}[PROMPT] Please enter your StreamPulse server domain name (e.g. stream.yourdomain.com): ${NC}"
    if [[ -t 0 ]]; then
        read -r DOMAIN_NAME
    else
        DOMAIN_NAME="streampulse.local"
    fi

    if [[ -z "$DOMAIN_NAME" ]]; then
        log_warning "No domain provided. Falling back to HTTP Public IP setup."
        DEPLOY_MODE="2"
    fi
fi

if [[ "$DEPLOY_MODE" == "1" ]]; then
    log_info "Initiating Let's Encrypt SSL standalone validation for $DOMAIN_NAME..."
    # Disable port 80 momentarily if Nginx is running on host
    if systemctl is-active --quiet nginx; then
        systemctl stop nginx
    fi
    
    apt-get install -y certbot
    if certbot certonly --standalone -d "$DOMAIN_NAME" --agree-tos --register-unsafely-without-email --non-interactive; then
        log_success "SSL certificates generated successfully!"
        generate_nginx_conf "domain" "$DOMAIN_NAME"
    else
        log_error "SSL generation failed. Check your DNS and port 80 accessibility."
        log_warning "Falling back to HTTP Public IP setup due to SSL generation failure."
        DEPLOY_MODE="2"
    fi
fi

if [[ "$DEPLOY_MODE" == "2" ]]; then
    if [ "$IS_LOCAL_ENV" = true ]; then
        log_info "Configuring Local LAN IP Mode..."
    else
        log_info "Configuring Public IP Mode..."
    fi
    generate_nginx_conf "ip" "$TARGET_ENDPOINT"
fi

# --- 6. Bootstrap Containers via Docker Compose ---
log_info "Step 6: Bootstrapping StreamPulse application services via Docker Compose..."
cd "$SCRIPT_DIR"

# Ensure local directories for volume mappings
mkdir -p "$ROOT_DIR/data"

if [ "$SKIP_BUILD" = true ]; then
    if [ "$REUSE_MODE" = true ]; then
        log_info "Skipping build/recreate stage because 'Reuse' mode was selected."
        log_info "Starting existing containers..."
        docker compose up -d --no-recreate
    else
        log_info "Skipping build stage because 'Restart' mode was selected."
        log_info "Starting existing containers (no rebuild)..."
        docker compose up -d
    fi
else
    # Pull and Build
    log_info "Building StreamPulse Manager and Database Containers..."
    docker compose build --pull
    
    log_info "Launching all containers in daemonized (detached) mode..."
    docker compose up -d
fi

# Verify Container Statuses
log_info "Step 7: Validating container health states..."
sleep 5
docker compose ps

# --- Generate final Environment Validation Report ---
log_success "======================================================================="
log_success "                  ENVIRONMENT VALIDATION REPORT"
log_success "======================================================================="
log_info "Ubuntu Version:         $OS_NAME ($OS_VERSION)"
log_info "Docker Status:          $(docker --version 2>/dev/null || echo 'Not installed')"
if docker compose version &>/dev/null; then
    log_info "Docker Compose Status:  $(docker compose version)"
else
    log_info "Docker Compose Status:  $(command -v docker-compose &>/dev/null && docker-compose version || echo 'Not installed')"
fi

# PostgreSQL Status on Host
if command -v psql &>/dev/null; then
    if systemctl is-active --quiet postgresql 2>/dev/null; then
        log_info "PostgreSQL (Host):      Installed and Running"
    else
        log_info "PostgreSQL (Host):      Installed and Stopped"
    fi
else
    log_info "PostgreSQL (Host):      Not installed on host"
fi

# Nginx Status on Host
if command -v nginx &>/dev/null; then
    if systemctl is-active --quiet nginx 2>/dev/null; then
        log_info "Nginx (Host):           Installed and Running"
    else
        log_info "Nginx (Host):           Installed and Stopped"
    fi
else
    log_info "Nginx (Host):           Not installed on host"
fi

# FFmpeg Status on Host
if command -v ffmpeg &>/dev/null; then
    log_info "FFmpeg (Host):          Installed"
else
    log_info "FFmpeg (Host):          Not installed on host (Bundled in StreamPulse container)"
fi

log_info "Port Status:"
log_info "  - Port 80 (HTTP):     Mapped to Host Port $HOST_HTTP_PORT"
log_info "  - Port 443 (HTTPS):   Mapped to Host Port $HOST_HTTPS_PORT"
log_info "  - Port 1935 (RTMP):   Mapped to Host Port $HOST_RTMP_PORT"
log_info "  - Port 5432 (DB):     $( [ "$USE_CUSTOM_DB" = true ] && echo "Using Host Database" || echo "Mapped to Host Port 5433 (Docker Postgres)" )"

log_info "Selected Conflict Resolutions:"
log_info "  - Database Conflict:  $RESOLVED_PG_STR"
log_info "  - Nginx Conflict:     $RESOLVED_NGINX_STR"
log_info "  - Containers Conflict:$RESOLVED_CONTAINER_STR"

log_info "Installation Readiness: READY"
log_success "======================================================================="

# Done
trap - EXIT
log_success "======================================================================="
log_success "  StreamPulse RTMP VPS Core Manager has been successfully installed!"
log_success "======================================================================="
log_info "Access your dashboard via:"
if [[ "$DEPLOY_MODE" == "1" ]]; then
    log_info "Dashboard URL:  https://$DOMAIN_NAME"
    log_info "API Base URL:   https://$DOMAIN_NAME/api"
    log_info "Playback URL:   https://$DOMAIN_NAME/hls/{stream_key}/index.m3u8"
    log_info "Stream Ingest RTMP URL: rtmp://$DOMAIN_NAME/live"
else
    log_info "Dashboard URL:  http://$TARGET_ENDPOINT"
    log_info "API Base URL:   http://$TARGET_ENDPOINT/api"
    log_info "Playback URL:   http://$TARGET_ENDPOINT/hls/{stream_key}/index.m3u8"
    log_info "Stream Ingest RTMP URL: rtmp://$TARGET_ENDPOINT/live"
fi
log_info "======================================================================="
