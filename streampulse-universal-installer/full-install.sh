#!/usr/bin/env bash
# ==============================================================================
# StreamPulse Universal Master Installer for Raspberry Pi
# Supports: New Pi & Existing Pi / Debian 13 (Trixie) ARM64 / Labwc Desktop
# Auto-detects Linux user (himakara, pi, operator, admin, etc.)
# ==============================================================================

set -uo pipefail

# ------------------------------------------------------------------------------
# Default Parameters & Flags
# ------------------------------------------------------------------------------
CHANNEL_NAME="channel1"
STREAM_KEY="live_stream"
DASHBOARD_URL="http://187.127.210.81/"
SERVER_URL="http://187.127.210.81"
OVERRIDE_USER=""
RUN_VALIDATION=1
SKIP_BACKUP=0

# Helper to mask secret keys in terminal output
mask_secret() {
  local secret="${1:-}"
  local len=${#secret}
  if (( len <= 4 )); then
    echo "****"
  elif (( len <= 8 )); then
    echo "${secret:0:2}****${secret: -2}"
  else
    echo "${secret:0:3}******${secret: -3}"
  fi
}

# ------------------------------------------------------------------------------
# Parse Command-Line Options
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--channel)
      CHANNEL_NAME="$2"
      shift 2
      ;;
    -k|--stream-key)
      STREAM_KEY="$2"
      shift 2
      ;;
    -u|--dashboard-url)
      DASHBOARD_URL="$2"
      shift 2
      ;;
    -s|--server-url)
      SERVER_URL="$2"
      shift 2
      ;;
    -U|--user)
      OVERRIDE_USER="$2"
      shift 2
      ;;
    --no-validate)
      RUN_VALIDATION=0
      shift
      ;;
    --no-backup)
      SKIP_BACKUP=1
      shift
      ;;
    -h|--help)
      echo "StreamPulse Universal Master Installer for Raspberry Pi"
      echo ""
      echo "Usage:"
      echo "  sudo bash full-install.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  -c, --channel CHANNEL       Assigned Pi Streaming Channel (default: \"channel1\")"
      echo "  -k, --stream-key KEY        Stream key for StreamPulse Player (default: \"live_stream\")"
      echo "  -u, --dashboard-url URL     Target URL for Fullscreen Kiosk (default: \"http://187.127.210.81/\")"
      echo "  -s, --server-url URL        Central StreamPulse Server (default: inferred from dashboard)"
      echo "  -U, --user USERNAME         Target Linux user (auto-detected if omitted)"
      echo "  --no-validate               Skip post-installation 18-point verification"
      echo "  --no-backup                 Skip pre-installation backup snapshot"
      echo "  -h, --help                  Show this help message and exit"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Run with --help for usage details." >&2
      exit 1
      ;;
  esac
done

# ------------------------------------------------------------------------------
# 1. Root Privilege Enforcement
# ------------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  echo -e "\e[31m[ERROR] This installer must be run with root privileges (sudo).\e[0m" >&2
  echo "Please rerun: sudo bash full-install.sh --channel \"${CHANNEL_NAME}\" --stream-key \"${STREAM_KEY}\"" >&2
  exit 1
fi

echo "======================================================================"
echo "          StreamPulse Universal Master Installer"
echo "======================================================================"
echo "Timestamp:        $(date '+%Y-%m-%d %H:%M:%S')"
echo "Target Channel:   ${CHANNEL_NAME}"
echo "Stream Key:       $(mask_secret "${STREAM_KEY}")"
echo "Dashboard URL:    ${DASHBOARD_URL}"
echo "Central Server:   ${SERVER_URL}"
echo "----------------------------------------------------------------------"

# ------------------------------------------------------------------------------
# 2. Dynamic Desktop User Detection (No Hardcoding)
# ------------------------------------------------------------------------------
TARGET_USER=""

if [[ -n "${OVERRIDE_USER}" ]]; then
  TARGET_USER="${OVERRIDE_USER}"
  echo "[+] Using user override: ${TARGET_USER}"
elif [[ -n "${SUDO_USER:-}" ]] && [[ "${SUDO_USER}" != "root" ]]; then
  TARGET_USER="${SUDO_USER}"
  echo "[+] Detected invoking sudo user: ${TARGET_USER}"
else
  # Try loginctl active graphical user
  LOGIN_USERS=($(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $3}' | grep -v '^root$' | sort -u || true))
  if [[ ${#LOGIN_USERS[@]} -eq 1 ]]; then
    TARGET_USER="${LOGIN_USERS[0]}"
    echo "[+] Detected active loginctl session user: ${TARGET_USER}"
  elif [[ ${#LOGIN_USERS[@]} -gt 1 ]]; then
    # Pick first non-root graphical user
    TARGET_USER="${LOGIN_USERS[0]}"
    echo "[!] Multiple session users found (${LOGIN_USERS[*]}). Selected: ${TARGET_USER}"
  else
    # Fallback to standard UID 1000 user in /etc/passwd
    UID_1000_USER="$(awk -F: '$3 == 1000 {print $1}' /etc/passwd 2>/dev/null || echo '')"
    if [[ -n "${UID_1000_USER}" ]]; then
      TARGET_USER="${UID_1000_USER}"
      echo "[+] Detected default system user (UID 1000): ${TARGET_USER}"
    else
      # Check /home/* directories
      HOME_CANDIDATES=($(ls -d /home/* 2>/dev/null | xargs -n1 basename | grep -v 'lost+found' || true))
      if [[ ${#HOME_CANDIDATES[@]} -ge 1 ]]; then
        TARGET_USER="${HOME_CANDIDATES[0]}"
        echo "[+] Detected user from /home directory: ${TARGET_USER}"
      else
        TARGET_USER="himakara"
        echo "[!] No user detected automatically. Defaulting to: ${TARGET_USER}"
      fi
    fi
  fi
fi

# Verify User Exists
if ! id -u "${TARGET_USER}" >/dev/null 2>&1; then
  echo "[!] Warning: User '${TARGET_USER}' does not exist yet. Creating user..."
  useradd -m -s /bin/bash "${TARGET_USER}" || true
fi

TARGET_UID="$(id -u "${TARGET_USER}")"
TARGET_GID="$(id -g "${TARGET_USER}")"
USER_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
if [[ -z "${USER_HOME}" ]] || [[ ! -d "${USER_HOME}" ]]; then
  USER_HOME="/home/${TARGET_USER}"
fi

echo "  -> Target User: ${TARGET_USER} (UID: ${TARGET_UID}, GID: ${TARGET_GID})"
echo "  -> User Home:   ${USER_HOME}"
echo "----------------------------------------------------------------------"

# ------------------------------------------------------------------------------
# 3. Detect Existing Installation vs New Pi State
# ------------------------------------------------------------------------------
EXISTING_INSTALLATION=0
if [[ -d "/opt/streampulse" ]] || [[ -f "/etc/systemd/system/streampulse-dashboard.service" ]] || [[ -f "/etc/systemd/system/streampulse-rpi-player.service" ]]; then
  EXISTING_INSTALLATION=1
  echo "[i] DETECTED: Existing StreamPulse / Player setup on this Raspberry Pi."
  echo "    Mode: In-place idempotent update (preserving media, logo, & player configuration)."
else
  echo "[i] DETECTED: Fresh / New Raspberry Pi."
  echo "    Mode: Full universal provisioning."
fi

# ------------------------------------------------------------------------------
# 4. Pre-Flight Backup Snapshot (Existing Pi Safeguard)
# ------------------------------------------------------------------------------
if (( SKIP_BACKUP == 0 )) && (( EXISTING_INSTALLATION == 1 )); then
  echo "[+] Creating pre-installation backup snapshot in ${USER_HOME}/streampulse-backups/..."
  TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
  BACKUP_DIR="${USER_HOME}/streampulse-backups/${TIMESTAMP}"
  mkdir -p "${BACKUP_DIR}/systemd" "${BACKUP_DIR}/config"

  # Backup systemd units
  for srv in streampulse-dashboard.service streampulse-rpi-player.service streampulse-kiosk.service; do
    if [[ -f "/etc/systemd/system/${srv}" ]]; then
      cp -p "/etc/systemd/system/${srv}" "${BACKUP_DIR}/systemd/" 2>/dev/null || true
    fi
  done

  # Backup configs
  if [[ -d "/opt/streampulse/config" ]]; then
    cp -rp "/opt/streampulse/config" "${BACKUP_DIR}/" 2>/dev/null || true
  fi

  # Backup user autostart
  if [[ -f "${USER_HOME}/.config/labwc/autostart" ]]; then
    mkdir -p "${BACKUP_DIR}/labwc"
    cp -p "${USER_HOME}/.config/labwc/autostart" "${BACKUP_DIR}/labwc/" 2>/dev/null || true
  fi

  chown -R "${TARGET_USER}:${TARGET_USER}" "${USER_HOME}/streampulse-backups" 2>/dev/null || true
  ln -sfn "${BACKUP_DIR}" "${USER_HOME}/streampulse-backups/latest" 2>/dev/null || true
  echo "  -> Snapshot saved: ${BACKUP_DIR}"
fi

# ------------------------------------------------------------------------------
# 5. Core Directory Structure Setup
# ------------------------------------------------------------------------------
echo "[+] Establishing authoritative directory structure (/opt/streampulse)..."
mkdir -p /opt/streampulse/bin \
         /opt/streampulse/config \
         /opt/streampulse/logo \
         /opt/streampulse/chromium-profile

# ------------------------------------------------------------------------------
# 6. Common Logo Assets Handling (Common to ALL Pis - Never Deleted)
# ------------------------------------------------------------------------------
echo "[+] Configuring Common Logo directory (/opt/streampulse/logo)..."
# Check if logo files already exist
if [[ ! -f "/opt/streampulse/logo/motion-logo.mp4" ]]; then
  echo "  -> Downloading default StreamPulse offline motion logo video..."
  curl -s -f -m 15 "${SERVER_URL}/api/rpi-player/motion-logo" -o /opt/streampulse/logo/motion-logo.mp4 2>/dev/null || true
fi

# Create HTML fallback if not present
if [[ ! -f "/opt/streampulse/logo/logo-fallback.html" ]]; then
  cat <<HTML > /opt/streampulse/logo/logo-fallback.html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>StreamPulse Offline Logo</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      background: #090d16;
      color: #f8fafc;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      overflow: hidden;
    }
    .pulse-ring {
      width: 140px;
      height: 140px;
      border-radius: 50%;
      border: 3px solid #6366f1;
      display: flex;
      align-items: center;
      justify-content: center;
      animation: pulse 2.5s infinite ease-in-out;
      margin-bottom: 24px;
    }
    .pulse-core {
      width: 100px;
      height: 100px;
      border-radius: 50%;
      background: linear-gradient(135deg, #4f46e5, #06b6d4);
      display: flex;
      align-items: center;
      justify-content: center;
    }
    .brand { font-size: 32px; font-weight: 800; letter-spacing: -0.5px; }
    .channel { color: #818cf8; font-size: 16px; margin-top: 8px; font-family: monospace; }
    .status { color: #94a3b8; font-size: 14px; margin-top: 16px; }
    @keyframes pulse {
      0%, 100% { transform: scale(1); opacity: 0.8; }
      50% { transform: scale(1.08); opacity: 1; border-color: #06b6d4; }
    }
  </style>
</head>
<body>
  <div class="pulse-ring">
    <div class="pulse-core">
      <svg width="44" height="44" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2.5">
        <polygon points="5 3 19 12 5 21 5 3"></polygon>
      </svg>
    </div>
  </div>
  <div class="brand">StreamPulse Node</div>
  <div class="channel">Channel: ${CHANNEL_NAME}</div>
  <div class="status">Connecting to live broadcast stream...</div>
</body>
</html>
HTML
fi

# ------------------------------------------------------------------------------
# 7. Persistent Per-Pi Channel & Player Configuration
# ------------------------------------------------------------------------------
echo "[+] Writing Per-Pi Player configuration (/opt/streampulse/config/player.conf)..."
PLAYER_CONF="/opt/streampulse/config/player.conf"

# Preserve existing stream key if installer ran without custom stream key on an existing Pi
if [[ "${STREAM_KEY}" == "live_stream" ]] && [[ -f "${PLAYER_CONF}" ]]; then
  EXISTING_KEY="$(grep '^STREAM_KEY=' "${PLAYER_CONF}" | cut -d= -f2 | tr -d '"' || echo '')"
  if [[ -n "${EXISTING_KEY}" ]]; then
    STREAM_KEY="${EXISTING_KEY}"
  fi
fi

cat <<CONF > "${PLAYER_CONF}"
# StreamPulse Player & Channel Configuration
# Managed by StreamPulse Universal Installer
# Path: /opt/streampulse/config/player.conf

# Assigned Pi Streaming Channel (Specific to this Pi)
CHANNEL_NAME="${CHANNEL_NAME}"

# Stream Key (Secrets kept local and masked in diagnostics)
STREAM_KEY="${STREAM_KEY}"

# StreamPulse Central Ingest / API Server URL
SERVER_URL="${SERVER_URL}"

# Common Logo & Media Assets Directory (Permanent across all Pis)
LOGO_DIR="/opt/streampulse/logo"
OFFLINE_LOGO_MEDIA="/opt/streampulse/logo/motion-logo.mp4"
OFFLINE_FALLBACK_HTML="/opt/streampulse/logo/logo-fallback.html"

# Playback Mode (auto / stream_priority / logo_priority)
PLAYBACK_MODE="auto"

# Hardware Video Acceleration
ENABLE_HW_ACCEL=1

# Audio Output Device (default / hdmi / pipewire)
AUDIO_OUTPUT="default"

# Last Updated Timestamp
LAST_UPDATED="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
CONF

chmod 644 "${PLAYER_CONF}"

# ------------------------------------------------------------------------------
# 8. Kiosk Configuration
# ------------------------------------------------------------------------------
echo "[+] Writing Kiosk configuration (/opt/streampulse/config/kiosk.conf)..."
cat <<CONF > /opt/streampulse/config/kiosk.conf
# StreamPulse Kiosk Configuration
# Path: /opt/streampulse/config/kiosk.conf

DASHBOARD_URL="${DASHBOARD_URL}"
KIOSK_USER="${TARGET_USER}"
BROWSER_PROFILE_DIR="/opt/streampulse/chromium-profile"
BROWSER_ENGINE="auto"
SCREEN_WIDTH=1920
SCREEN_HEIGHT=1080
HIDE_CURSOR=1
DISABLE_SCREEN_BLANKING=1
WAIT_NETWORK_TIMEOUT=30
RESTART_DELAY_SEC=3

CHROMIUM_EXTRA_FLAGS=(
  "--password-store=basic"
  "--noerrdialogs"
  "--disable-infobars"
  "--kiosk"
  "--start-fullscreen"
  "--fullscreen"
  "--no-first-run"
  "--disable-restore-session-state"
  "--disable-session-crashed-bubble"
  "--autoplay-policy=no-user-gesture-required"
  "--check-for-update-interval=31536000"
  "--disable-component-update"
  "--disable-features=TranslateUI"
  "--disable-save-password-bubble"
  "--allow-file-access-from-files"
  "--disable-web-security"
  "--window-position=0,0"
  "--window-size=1920,1080"
)
CONF

chmod 644 /opt/streampulse/config/kiosk.conf

# ------------------------------------------------------------------------------
# 9. Authoritative Scripts Installation
# ------------------------------------------------------------------------------
echo "[+] Installing Authoritative Management Binaries in /opt/streampulse/bin/..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Copy scripts from local installer repository if present, otherwise write inline
if [[ -d "${SCRIPT_DIR}/bin" ]]; then
  cp -p "${SCRIPT_DIR}/bin/"*.sh /opt/streampulse/bin/ 2>/dev/null || true
fi

# Ensure set-channel.sh exists and is executable
if [[ ! -f "/opt/streampulse/bin/set-channel.sh" ]]; then
  if [[ -f "${SCRIPT_DIR}/bin/set-channel.sh" ]]; then
    cp "${SCRIPT_DIR}/bin/set-channel.sh" /opt/streampulse/bin/
  fi
fi

# Ensure dashboard-kiosk.sh exists and is executable
if [[ ! -f "/opt/streampulse/bin/dashboard-kiosk.sh" ]]; then
  if [[ -f "${SCRIPT_DIR}/bin/dashboard-kiosk.sh" ]]; then
    cp "${SCRIPT_DIR}/bin/dashboard-kiosk.sh" /opt/streampulse/bin/
  fi
fi

# Ensure backup.sh, restore.sh, diagnose.sh, validate.sh exist
for b in backup restore diagnose validate set-channel dashboard-kiosk; do
  if [[ -f "${SCRIPT_DIR}/bin/${b}.sh" ]] && [[ ! -f "/opt/streampulse/bin/${b}.sh" ]]; then
    cp "${SCRIPT_DIR}/bin/${b}.sh" /opt/streampulse/bin/
  fi
done

chmod +x /opt/streampulse/bin/*.sh 2>/dev/null || true

# ------------------------------------------------------------------------------
# 10. Duplicate Autostart Cleanup (Safely Backed Up)
# ------------------------------------------------------------------------------
echo "[+] Cleaning competing/duplicate autostart launchers..."
LABWC_AUTOSTART="${USER_HOME}/.config/labwc/autostart"
if [[ -f "${LABWC_AUTOSTART}" ]]; then
  # Comment out old unmanaged chromium kiosk lines
  if grep -E "chromium.*kiosk|dashboard-kiosk" "${LABWC_AUTOSTART}" >/dev/null 2>&1; then
    echo "  -> Disabling legacy browser lines in Labwc autostart (systemd is now authoritative)..."
    sed -i -E 's/^([^#]*chromium.*kiosk.*)/# [StreamPulse Managed] \1/' "${LABWC_AUTOSTART}"
    sed -i -E 's/^([^#]*.*dashboard-kiosk.*)/# [StreamPulse Managed] \1/' "${LABWC_AUTOSTART}"
  fi
fi

# ------------------------------------------------------------------------------
# 11. Authoritative Systemd Dashboard Service
# ------------------------------------------------------------------------------
echo "[+] Provisioning Authoritative systemd service (streampulse-dashboard.service)..."
cat <<UNIT > /etc/systemd/system/streampulse-dashboard.service
[Unit]
Description=StreamPulse Dashboard Kiosk Service (Universal)
Documentation=https://streampulse.io
After=network-online.target sound.target graphical-session.target graphical.target
Wants=network-online.target

[Service]
Type=simple
User=${TARGET_USER}
Group=${TARGET_GID}
WorkingDirectory=/opt/streampulse
Environment=DISPLAY=:0
Environment=WAYLAND_DISPLAY=wayland-0
Environment=XDG_RUNTIME_DIR=/run/user/${TARGET_UID}
Environment=HOME=${USER_HOME}
ExecStartPre=/bin/sleep 2
ExecStart=/opt/streampulse/bin/dashboard-kiosk.sh
Restart=always
RestartSec=3
KillMode=mixed
TimeoutStopSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=graphical.target default.target
UNIT

chmod 644 /etc/systemd/system/streampulse-dashboard.service
systemctl daemon-reload
systemctl enable streampulse-dashboard.service

# ------------------------------------------------------------------------------
# 12. Fix Directory Permissions for Detected User
# ------------------------------------------------------------------------------
echo "[+] Setting filesystem permissions for user '${TARGET_USER}'..."
chown -R "${TARGET_USER}:${TARGET_GID}" /opt/streampulse/chromium-profile \
                                       /opt/streampulse/logo \
                                       /opt/streampulse/config 2>/dev/null || true

# ------------------------------------------------------------------------------
# 13. Restart / Start Services
# ------------------------------------------------------------------------------
echo "[+] Starting streampulse-dashboard.service..."
systemctl restart streampulse-dashboard.service 2>/dev/null || true

# ------------------------------------------------------------------------------
# 14. 18-Point Automated Validation Matrix
# ------------------------------------------------------------------------------
if (( RUN_VALIDATION == 1 )) && [[ -x "/opt/streampulse/bin/validate.sh" ]]; then
  echo ""
  echo "----------------------------------------------------------------------"
  echo "Running 18-Point StreamPulse Universal Validation Suite..."
  echo "----------------------------------------------------------------------"
  /opt/streampulse/bin/validate.sh || true
fi

echo ""
echo "======================================================================"
echo "      STREAM_PULSE UNIVERSAL INSTALLATION COMPLETE!"
echo "======================================================================"
echo "Assigned Channel:   ${CHANNEL_NAME}"
echo "Stream Key:         $(mask_secret "${STREAM_KEY}")"
echo "Target User:        ${TARGET_USER} (UID: ${TARGET_UID})"
echo "Common Logo Folder: /opt/streampulse/logo/"
echo "Dashboard Kiosk:    ${DASHBOARD_URL}"
echo "Authoritative Svc:  streampulse-dashboard.service (ENABLED)"
echo ""
echo "Helpful Commands:"
echo "  - Change Channel:   sudo /opt/streampulse/bin/set-channel.sh <new_channel>"
echo "  - Run Diagnostics:  sudo /opt/streampulse/bin/diagnose.sh"
echo "  - Run Validation:   sudo /opt/streampulse/bin/validate.sh"
echo "  - Create Backup:    sudo /opt/streampulse/bin/backup.sh"
echo "  - Restore Backup:   sudo /opt/streampulse/bin/restore.sh"
echo "  - Live Kiosk Logs:  sudo journalctl -u streampulse-dashboard.service -f"
echo "======================================================================"
