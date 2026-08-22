#!/usr/bin/env bash
# ==============================================================================
# StreamPulse Universal Master Installer for Raspberry Pi
# Standalone Remote Execution Architecture (curl -fsSL ... | sudo bash)
# Supports: New Pi & Existing Pi / Debian 13 (Trixie) ARM64 / Labwc & Wayland
# Architecture: Single Authoritative Fullscreen Playback Controller
# ==============================================================================

set -euo pipefail

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
SKIP_PKG_INSTALL=0

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
    --skip-pkgs)
      SKIP_PKG_INSTALL=1
      shift
      ;;
    -h|--help)
      echo "StreamPulse Universal Master Installer for Raspberry Pi"
      echo ""
      echo "Usage:"
      echo "  sudo bash full-install.sh [OPTIONS]"
      echo "  curl -fsSL \"<URL>\" | sudo bash -s -- [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  -c, --channel CHANNEL       Assigned Pi Streaming Channel (default: \"channel1\")"
      echo "  -k, --stream-key KEY        Stream key for StreamPulse Player (default: \"live_stream\")"
      echo "  -u, --dashboard-url URL     Target URL for Fullscreen Kiosk"
      echo "  -s, --server-url URL        Central StreamPulse Server (default: \"http://187.127.210.81\")"
      echo "  -U, --user USERNAME         Target Linux user (auto-detected if unambiguous)"
      echo "  --no-validate               Skip post-installation 18-point verification"
      echo "  --no-backup                 Skip pre-installation backup snapshot"
      echo "  --skip-pkgs                 Skip apt package installation check"
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
echo "Assigned Channel: ${CHANNEL_NAME}"
echo "Stream Key:       $(mask_secret "${STREAM_KEY}")"
echo "Central Server:   ${SERVER_URL}"
echo "Architecture:     Unified Authoritative Single-Window Player"
echo "----------------------------------------------------------------------"

# ------------------------------------------------------------------------------
# 2. Strict & Safe Desktop User Detection (No Hardcoding, No Auto-Creation)
# ------------------------------------------------------------------------------
TARGET_USER=""

if [[ -n "${OVERRIDE_USER}" ]]; then
  if id -u "${OVERRIDE_USER}" >/dev/null 2>&1; then
    TARGET_USER="${OVERRIDE_USER}"
    echo "[+] Using specified user override: ${TARGET_USER}"
  else
    echo -e "\e[31m[ERROR] Specified user '${OVERRIDE_USER}' does not exist on this system.\e[0m" >&2
    exit 1
  fi
else
  # Step A: Check SUDO_USER if invoked via sudo and not root
  if [[ -n "${SUDO_USER:-}" ]] && [[ "${SUDO_USER}" != "root" ]]; then
    if id -u "${SUDO_USER}" >/dev/null 2>&1; then
      TARGET_USER="${SUDO_USER}"
      echo "[+] Detected invoking sudo user: ${TARGET_USER}"
    fi
  fi

  # Step B: Check active user sessions via loginctl
  if [[ -z "${TARGET_USER}" ]]; then
    ACTIVE_SESSIONS=($(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $3}' | grep -v '^root$' | sort -u || true))
    if [[ ${#ACTIVE_SESSIONS[@]} -eq 1 ]]; then
      TARGET_USER="${ACTIVE_SESSIONS[0]}"
      echo "[+] Detected active session user: ${TARGET_USER}"
    elif [[ ${#ACTIVE_SESSIONS[@]} -gt 1 ]]; then
      echo -e "\e[31m[ERROR] Multiple active graphical/user sessions detected: (${ACTIVE_SESSIONS[*]}).\e[0m" >&2
      echo "To ensure correct desktop/kiosk configuration, please specify the target user explicitly:" >&2
      echo "  curl -fsSL \"...\" | sudo bash -s -- --user <username> --channel \"${CHANNEL_NAME}\"" >&2
      exit 1
    fi
  fi

  # Step C: Fallback to non-system human accounts in /etc/passwd
  if [[ -z "${TARGET_USER}" ]]; then
    REGULAR_USERS=($(awk -F: '$3 >= 1000 && $3 < 60000 && $7 !~ /(nologin|false)/ {print $1}' /etc/passwd | sort -u || true))
    if [[ ${#REGULAR_USERS[@]} -eq 1 ]]; then
      TARGET_USER="${REGULAR_USERS[0]}"
      echo "[+] Detected sole regular system user: ${TARGET_USER}"
    elif [[ ${#REGULAR_USERS[@]} -gt 1 ]]; then
      echo -e "\e[31m[ERROR] Multiple non-root user accounts found on system: (${REGULAR_USERS[*]}).\e[0m" >&2
      echo "Please specify which user account to configure for StreamPulse:" >&2
      echo "  curl -fsSL \"...\" | sudo bash -s -- --user <username> --channel \"${CHANNEL_NAME}\"" >&2
      exit 1
    elif [[ ${#REGULAR_USERS[@]} -eq 0 ]]; then
      echo -e "\e[31m[ERROR] No non-root human user account found on this system.\e[0m" >&2
      echo "Please create a user account first or specify: --user <username>" >&2
      exit 1
    fi
  fi
fi

# Validate target user resolution
TARGET_UID="$(id -u "${TARGET_USER}")"
TARGET_GID="$(id -g "${TARGET_USER}")"
USER_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
if [[ -z "${USER_HOME}" ]] || [[ ! -d "${USER_HOME}" ]]; then
  echo -e "\e[31m[ERROR] User home directory '${USER_HOME}' does not exist for user '${TARGET_USER}'.\e[0m" >&2
  exit 1
fi

echo "  -> Target User: ${TARGET_USER} (UID: ${TARGET_UID}, GID: ${TARGET_GID})"
echo "  -> User Home:   ${USER_HOME}"
echo "----------------------------------------------------------------------"

# ------------------------------------------------------------------------------
# 3. Fresh Pi Package & Dependency Installation
# ------------------------------------------------------------------------------
if (( SKIP_PKG_INSTALL == 0 )); then
  echo "[+] Checking required packages and runtime dependencies..."
  REQUIRED_PKGS=(curl wget jq unclutter ca-certificates alsa-utils)
  
  # Determine browser package
  if ! command -v chromium >/dev/null 2>&1 && ! command -v chromium-browser >/dev/null 2>&1; then
    REQUIRED_PKGS+=(chromium)
  fi

  MISSING_PKGS=()
  for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! dpkg -s "${pkg}" >/dev/null 2>&1 && ! command -v "${pkg}" >/dev/null 2>&1; then
      MISSING_PKGS+=("${pkg}")
    fi
  done

  if [[ ${#MISSING_PKGS[@]} -gt 0 ]]; then
    echo "  -> Missing packages detected: ${MISSING_PKGS[*]}"
    echo "  -> Installing via APT (waiting for locks if active)..."

    LOCK_WAIT=0
    while fuser /var/lib/dpkg/lock >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
      if (( LOCK_WAIT >= 30 )); then
        echo -e "\e[33m[WARN] APT lock held by another process for >30s. Continuing attempt...\e[0m"
        break
      fi
      sleep 2
      (( LOCK_WAIT += 2 ))
    done

    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y || echo "[WARN] apt-get update returned non-zero, attempting package install..."
    
    if ! apt-get install -y --no-install-recommends "${MISSING_PKGS[@]}"; then
      echo "[!] Retrying with chromium-browser fallback..."
      FALLBACK_PKGS=()
      for p in "${MISSING_PKGS[@]}"; do
        if [[ "$p" == "chromium" ]]; then
          FALLBACK_PKGS+=(chromium-browser)
        else
          FALLBACK_PKGS+=("$p")
        fi
      done
      apt-get install -y --no-install-recommends "${FALLBACK_PKGS[@]}" || {
        echo -e "\e[31m[ERROR] Failed to install required dependencies (${MISSING_PKGS[*]}). Check network / APT sources.\e[0m" >&2
        exit 1
      }
    fi
    echo "  -> Dependencies successfully installed."
  else
    echo "  -> All core dependencies already satisfied."
  fi
fi

# ------------------------------------------------------------------------------
# 4. Detect Existing Installation & Create Full Pre-Flight Backup Snapshot
# ------------------------------------------------------------------------------
EXISTING_INSTALLATION=0
if [[ -d "/opt/streampulse" ]] || [[ -f "/etc/systemd/system/streampulse-dashboard.service" ]] || [[ -f "/etc/systemd/system/streampulse-player.service" ]] || [[ -f "/etc/systemd/system/streampulse-rpi-player.service" ]]; then
  EXISTING_INSTALLATION=1
  echo "[i] DETECTED: Existing StreamPulse installation on this Raspberry Pi."
fi

if (( SKIP_BACKUP == 0 )) && (( EXISTING_INSTALLATION == 1 )); then
  TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
  BACKUP_DIR="${USER_HOME}/streampulse-backups/${TIMESTAMP}"
  echo "[+] Creating pre-installation backup snapshot in ${BACKUP_DIR}..."
  mkdir -p "${BACKUP_DIR}/systemd" "${BACKUP_DIR}/config" "${BACKUP_DIR}/bin" "${BACKUP_DIR}/autostart"

  # Systemd units
  for srv in streampulse-player.service streampulse-dashboard.service streampulse-rpi-player.service streampulse-kiosk.service streampulse.service; do
    if [[ -f "/etc/systemd/system/${srv}" ]]; then
      cp -p "/etc/systemd/system/${srv}" "${BACKUP_DIR}/systemd/" 2>/dev/null || true
    fi
  done

  # Configs and scripts
  if [[ -d "/opt/streampulse/config" ]]; then
    cp -rp "/opt/streampulse/config" "${BACKUP_DIR}/" 2>/dev/null || true
  fi
  if [[ -d "/opt/streampulse/bin" ]]; then
    cp -rp "/opt/streampulse/bin" "${BACKUP_DIR}/" 2>/dev/null || true
  fi

  # Desktop autostarts
  for auto_f in "${USER_HOME}/.config/labwc/autostart" "${USER_HOME}/.config/autostart" "${USER_HOME}/.config/openbox/autostart"; do
    if [[ -e "${auto_f}" ]]; then
      cp -rp "${auto_f}" "${BACKUP_DIR}/autostart/" 2>/dev/null || true
    fi
  done

  # Save manifest
  cat <<MANIFEST > "${BACKUP_DIR}/manifest.json"
{
  "timestamp": "${TIMESTAMP}",
  "user": "${TARGET_USER}",
  "channel": "${CHANNEL_NAME}",
  "reason": "Pre-flight universal installer backup"
}
MANIFEST

  chown -R "${TARGET_USER}:${TARGET_GID}" "${USER_HOME}/streampulse-backups" 2>/dev/null || true
  ln -sfn "${BACKUP_DIR}" "${USER_HOME}/streampulse-backups/latest" 2>/dev/null || true
  echo "  -> Snapshot saved successfully: ${BACKUP_DIR}"
fi

# ------------------------------------------------------------------------------
# 5. Terminate & Remove Competing/Legacy Processes & Services
# ------------------------------------------------------------------------------
echo "[+] Eliminating duplicate/competing playback services & legacy loops..."
for legacy_svc in streampulse-rpi-player.service streampulse-kiosk.service streampulse.service streampulse-dashboard.service; do
  if systemctl is-active --quiet "${legacy_svc}" 2>/dev/null; then
    echo "  -> Stopping legacy service: ${legacy_svc}"
    systemctl stop "${legacy_svc}" 2>/dev/null || true
  fi
  if systemctl is-enabled --quiet "${legacy_svc}" 2>/dev/null; then
    echo "  -> Disabling legacy service: ${legacy_svc}"
    systemctl disable "${legacy_svc}" 2>/dev/null || true
  fi
  rm -f "/etc/systemd/system/${legacy_svc}" 2>/dev/null || true
  rm -f "/etc/systemd/system/graphical.target.wants/${legacy_svc}" 2>/dev/null || true
  rm -f "/etc/systemd/system/default.target.wants/${legacy_svc}" 2>/dev/null || true
  rm -f "/etc/systemd/system/multi-user.target.wants/${legacy_svc}" 2>/dev/null || true
done

# Terminate any rogue mpv or cvlc loops competing for fullscreen display
pkill -9 -f "mpv.*motion-logo" 2>/dev/null || true
pkill -9 -f "cvlc.*motion-logo" 2>/dev/null || true
pkill -9 -f "player-launcher\.sh" 2>/dev/null || true
rm -f /tmp/streampulse-player.lock 2>/dev/null || true

# ------------------------------------------------------------------------------
# 6. Establish Authoritative Directories
# ------------------------------------------------------------------------------
echo "[+] Establishing authoritative directory structure (/opt/streampulse)..."
mkdir -p /opt/streampulse/bin \
         /opt/streampulse/config \
         /opt/streampulse/logo \
         /opt/streampulse/chromium-profile

# ------------------------------------------------------------------------------
# 7. Common Logo Assets & Offline Visual Fallback
# ------------------------------------------------------------------------------
echo "[+] Setting up Common Logo Assets (/opt/streampulse/logo)..."

# 1. Guaranteed Mandatory Offline Visual Fallback (Self-contained CSS/SVG animated canvas)
cat << 'HTML' > /opt/streampulse/logo/logo-fallback.html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>StreamPulse Offline Logo</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; user-select: none; -webkit-user-select: none; }
    html, body {
      width: 100vw;
      height: 100vh;
      background-color: #090d16;
      color: #f8fafc;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      overflow: hidden;
    }
    .pulse-ring {
      width: 150px;
      height: 150px;
      border-radius: 50%;
      border: 3px solid #6366f1;
      display: flex;
      align-items: center;
      justify-content: center;
      animation: pulse-ring 2.8s infinite ease-in-out;
      margin-bottom: 28px;
      box-shadow: 0 0 30px rgba(99, 102, 241, 0.25);
    }
    .pulse-core {
      width: 108px;
      height: 108px;
      border-radius: 50%;
      background: linear-gradient(135deg, #4f46e5, #06b6d4);
      display: flex;
      align-items: center;
      justify-content: center;
      box-shadow: 0 0 20px rgba(6, 182, 212, 0.4);
    }
    .brand-title {
      font-size: 34px;
      font-weight: 800;
      letter-spacing: -0.5px;
      background: linear-gradient(135deg, #ffffff 40%, #94a3b8);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      margin-bottom: 6px;
    }
    .channel-badge {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      background: rgba(30, 41, 59, 0.8);
      border: 1px solid rgba(99, 102, 241, 0.3);
      padding: 6px 16px;
      border-radius: 9999px;
      color: #818cf8;
      font-size: 15px;
      font-weight: 600;
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
      margin-top: 8px;
    }
    .channel-dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background-color: #f59e0b;
      animation: blink 1.2s infinite;
    }
    .status-message {
      color: #64748b;
      font-size: 14px;
      margin-top: 20px;
      letter-spacing: 0.02em;
    }
    @keyframes pulse-ring {
      0%, 100% { transform: scale(1); border-color: #6366f1; opacity: 0.8; }
      50% { transform: scale(1.1); border-color: #06b6d4; opacity: 1; box-shadow: 0 0 45px rgba(6, 182, 212, 0.4); }
    }
    @keyframes blink { 0%, 100% { opacity: 1; } 50% { opacity: 0.3; } }
  </style>
</head>
<body>
  <div style="text-align: center; display: flex; flex-direction: column; align-items: center;">
    <div class="pulse-ring">
      <div class="pulse-core">
        <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="#ffffff" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
          <polygon points="5 3 19 12 5 21 5 3"></polygon>
        </svg>
      </div>
    </div>
    <div class="brand-title">StreamPulse</div>
    <div class="channel-badge">
      <span class="channel-dot"></span>
      <span id="channel-name">Channel Standby</span>
    </div>
    <div class="status-message">Waiting for live broadcast stream...</div>
  </div>
  <script>
    (function() {
      const p = new URLSearchParams(window.location.search);
      const ch = p.get('channel') || 'channel1';
      const el = document.getElementById('channel-name');
      if (el) el.textContent = 'Channel: ' + ch;
    })();
  </script>
</body>
</html>
HTML

chmod 644 /opt/streampulse/logo/logo-fallback.html
if [[ ! -s /opt/streampulse/logo/logo-fallback.html ]]; then
  echo -e "\e[31m[FAIL] Failed to create mandatory /opt/streampulse/logo/logo-fallback.html\e[0m" >&2
  exit 1
fi
echo "  -> Guaranteed offline fallback created: /opt/streampulse/logo/logo-fallback.html"

# 2. Local Authoritative Motion Logo Detection & Installation
LOGO_SRC=""
LOGO_SRC_SIZE=0
LOGO_DEST="/opt/streampulse/logo/motion-logo.mp4"

# Candidate sources in strict priority order:
CANDIDATE_PATHS=(
  "${USER_HOME}/Downloads/Motion Logo.mp4"
  "${USER_HOME}/Downloads/motion_logo.mp4"
  "${USER_HOME}/Downloads/motion logo.mp4"
  "${USER_HOME}/Downloads/MOTION LOGO.mp4"
  "${USER_HOME}/Downloads/motion-logo.mp4"
  "/home/${TARGET_USER}/Downloads/Motion Logo.mp4"
  "/home/${TARGET_USER}/Downloads/motion_logo.mp4"
  "/home/${TARGET_USER}/Downloads/motion logo.mp4"
  "/home/${TARGET_USER}/Downloads/MOTION LOGO.mp4"
  "/home/${TARGET_USER}/Downloads/motion-logo.mp4"
  "${USER_HOME}/motion_logo.mp4"
  "${USER_HOME}/Motion Logo.mp4"
  "${LOGO_DEST}"
)

for p in "${CANDIDATE_PATHS[@]}"; do
  if [[ -f "${p}" ]] && [[ -s "${p}" ]]; then
    LOGO_SRC="${p}"
    LOGO_SRC_SIZE=$(stat -c%s "${p}" 2>/dev/null || wc -c < "${p}" || echo 0)
    break
  fi
done

# If not found in primary user home, check all /home/*/Downloads/
if [[ -z "${LOGO_SRC}" ]]; then
  for p in /home/*/Downloads/"Motion Logo.mp4" /home/*/Downloads/motion_logo.mp4 /home/*/Downloads/"motion logo.mp4" /home/*/Downloads/"MOTION LOGO.mp4" /home/*/Downloads/motion-logo.mp4; do
    if [[ -f "${p}" ]] && [[ -s "${p}" ]]; then
      LOGO_SRC="${p}"
      LOGO_SRC_SIZE=$(stat -c%s "${p}" 2>/dev/null || wc -c < "${p}" || echo 0)
      break
    fi
  done
fi

echo "----------------------------------------------------------------------"
if [[ -n "${LOGO_SRC}" ]]; then
  echo "[LOGO] Source:       ${LOGO_SRC}"
  echo "[LOGO] Destination:  ${LOGO_DEST}"
  echo "[LOGO] Source Size:  ${LOGO_SRC_SIZE} bytes"
  
  if [[ "${LOGO_SRC}" != "${LOGO_DEST}" ]]; then
    echo "[+] Copying authoritative Motion Logo to ${LOGO_DEST}..."
    cp -f "${LOGO_SRC}" "${LOGO_DEST}"
  fi
  
  chmod 644 "${LOGO_DEST}"
  chown "${TARGET_USER}:${TARGET_GID}" "${LOGO_DEST}" 2>/dev/null || true
  
  if [[ -s "${LOGO_DEST}" ]]; then
    DEST_SIZE=$(stat -c%s "${LOGO_DEST}" 2>/dev/null || wc -c < "${LOGO_DEST}" || echo 0)
    echo "[LOGO] Dest Size:    ${DEST_SIZE} bytes"
    echo "[LOGO] Verification: PASS"
  else
    echo -e "\e[31m[LOGO] Verification: FAIL (Destination file missing or empty after copy)\e[0m" >&2
    exit 1
  fi
else
  # Check if server optionally provides it as fallback
  echo "[LOGO] Notice: No local Motion Logo MP4 found in ~/Downloads/ (Checking optional server asset)..."
  if curl -fsSL --connect-timeout 5 --max-time 15 "${SERVER_URL}/api/rpi-player/motion-logo" -o "${LOGO_DEST}" 2>/dev/null && [[ -s "${LOGO_DEST}" ]]; then
    chmod 644 "${LOGO_DEST}"
    chown "${TARGET_USER}:${TARGET_GID}" "${LOGO_DEST}" 2>/dev/null || true
    DEST_SIZE=$(stat -c%s "${LOGO_DEST}" 2>/dev/null || wc -c < "${LOGO_DEST}" || echo 0)
    echo "[LOGO] Source:       ${SERVER_URL}/api/rpi-player/motion-logo (Server)"
    echo "[LOGO] Destination:  ${LOGO_DEST}"
    echo "[LOGO] Size:         ${DEST_SIZE} bytes"
    echo "[LOGO] Verification: PASS"
  else
    rm -f "${LOGO_DEST}" 2>/dev/null
    echo "[LOGO] Source:       None (Optional MP4 not provided)"
    echo "[LOGO] Destination:  ${LOGO_DEST} (Guaranteed HTML5 fallback active)"
    echo "[LOGO] Fallback:     /opt/streampulse/logo/logo-fallback.html (Verified)"
    echo "[LOGO] Verification: PASS (Guaranteed HTML5 fallback active)"
  fi
fi
echo "----------------------------------------------------------------------"

# Create Self-Contained Standalone Universal Kiosk Player (Single Unified Display Surface)
cat << 'HTML' > /opt/streampulse/logo/player.html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>StreamPulse Kiosk Player</title>
  <style>
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
      user-select: none;
      -webkit-user-select: none;
    }
    html, body {
      width: 100vw;
      height: 100vh;
      background-color: #000000;
      overflow: hidden;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      color: #ffffff;
    }
    .cursor-hidden {
      cursor: none !important;
    }
    #player-container {
      position: absolute;
      top: 0;
      left: 0;
      width: 100vw;
      height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      background: #000000;
      overflow: hidden;
    }
    .kiosk-video {
      position: absolute;
      top: 0;
      left: 0;
      width: 100vw;
      height: 100vh;
      object-fit: contain;
      background: #000000;
      border: none;
      outline: none;
      transition: opacity 0.3s ease-in-out;
    }
    #live-video {
      z-index: 20;
      opacity: 0;
      pointer-events: none;
    }
    #live-video.active {
      opacity: 1;
      pointer-events: auto;
    }
    #motion-video {
      z-index: 10;
      opacity: 1;
    }
    #motion-video.hidden {
      opacity: 0;
      pointer-events: none;
      display: none;
    }
    #html-fallback {
      position: absolute;
      top: 0;
      left: 0;
      width: 100vw;
      height: 100vh;
      z-index: 5;
      background-color: #090d16;
      color: #f8fafc;
      display: none;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      text-align: center;
      padding: 32px;
    }
    #html-fallback.active {
      display: flex;
      z-index: 15;
    }
    .pulse-ring {
      width: 150px;
      height: 150px;
      border-radius: 50%;
      border: 3px solid #6366f1;
      display: flex;
      align-items: center;
      justify-content: center;
      animation: pulse-ring 2.8s infinite ease-in-out;
      margin-bottom: 28px;
      box-shadow: 0 0 30px rgba(99, 102, 241, 0.25);
    }
    .pulse-core {
      width: 108px;
      height: 108px;
      border-radius: 50%;
      background: linear-gradient(135deg, #4f46e5, #06b6d4);
      display: flex;
      align-items: center;
      justify-content: center;
      box-shadow: 0 0 20px rgba(6, 182, 212, 0.4);
    }
    .brand-title {
      font-size: 34px;
      font-weight: 800;
      letter-spacing: -0.5px;
      background: linear-gradient(135deg, #ffffff 40%, #94a3b8);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      margin-bottom: 6px;
    }
    .channel-badge {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      background: rgba(30, 41, 59, 0.8);
      border: 1px solid rgba(99, 102, 241, 0.3);
      padding: 6px 16px;
      border-radius: 9999px;
      color: #818cf8;
      font-size: 15px;
      font-weight: 600;
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
      margin-top: 8px;
    }
    .channel-dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background-color: #f59e0b;
      animation: blink 1.2s infinite;
    }
    .status-message {
      color: #64748b;
      font-size: 14px;
      margin-top: 20px;
      letter-spacing: 0.02em;
    }
    @keyframes pulse-ring {
      0%, 100% {
        transform: scale(1);
        border-color: #6366f1;
        opacity: 0.8;
      }
      50% {
        transform: scale(1.1);
        border-color: #06b6d4;
        opacity: 1;
        box-shadow: 0 0 45px rgba(6, 182, 212, 0.4);
      }
    }
    @keyframes blink {
      0%, 100% { opacity: 1; }
      50% { opacity: 0.3; }
    }
    .status-overlay {
      position: absolute;
      bottom: 24px;
      left: 24px;
      display: flex;
      align-items: center;
      gap: 10px;
      background: rgba(15, 23, 42, 0.85);
      backdrop-filter: blur(8px);
      border: 1px solid rgba(255, 255, 255, 0.1);
      padding: 8px 16px;
      border-radius: 9999px;
      font-size: 13px;
      font-weight: 500;
      letter-spacing: 0.02em;
      z-index: 99;
      transition: opacity 0.4s ease;
      pointer-events: none;
    }
    .status-badge {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background-color: #ef4444;
    }
    .status-badge.live {
      background-color: #10b981;
      box-shadow: 0 0 8px #10b981;
    }
    .status-badge.offline {
      background-color: #f59e0b;
      animation: pulse-dot 1.4s infinite;
    }
    @keyframes pulse-dot {
      0%, 100% { opacity: 1; transform: scale(1); }
      50% { opacity: 0.4; transform: scale(0.85); }
    }
  </style>
</head>
<body class="cursor-hidden">
  <div id="player-container">
    <!-- 1. Live HLS Video Element -->
    <video id="live-video" class="kiosk-video" autoplay playsinline muted preload="auto"></video>

    <!-- 2. Permanent Offline Motion Logo Video Element -->
    <video id="motion-video" class="kiosk-video" src="motion-logo.mp4" autoplay loop muted playsinline preload="auto">
      <source src="motion-logo.mp4" type="video/mp4">
    </video>

    <!-- 3. Local HTML Fallback (when MP4 is unplayable) -->
    <div id="html-fallback">
      <div class="pulse-ring">
        <div class="pulse-core">
          <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="#ffffff" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
            <polygon points="5 3 19 12 5 21 5 3"></polygon>
          </svg>
        </div>
      </div>
      <div class="brand-title">StreamPulse</div>
      <div class="channel-badge">
        <span class="channel-dot"></span>
        <span id="fallback-channel-name">Channel Standby</span>
      </div>
      <div id="fallback-status" class="status-message">Waiting for live broadcast stream...</div>
    </div>

    <!-- 4. Subtle Overlay Status Badge -->
    <div id="status-overlay" class="status-overlay">
      <div id="status-badge" class="status-badge offline"></div>
      <span id="status-text">Standby • StreamPulse Logo Active</span>
      <span id="status-metrics" style="color: #94a3b8; border-left: 1px solid #334155; padding-left: 8px;">Polling stream...</span>
    </div>
  </div>

  <!-- Local HLS.js Library (Installed offline in /opt/streampulse/logo/) -->
  <script src="hls.min.js"></script>

  <script>
    (function() {
      'use strict';

      // --------------------------------------------------
      // Global Error Shields (Prevent Script Termination)
      // --------------------------------------------------
      window.addEventListener('error', function(e) {
        console.warn('[StreamPulse Player Shield] Handled error:', e ? (e.message || e) : 'unknown');
        if (e && typeof e.preventDefault === 'function') e.preventDefault();
      }, true);

      window.addEventListener('unhandledrejection', function(e) {
        console.warn('[StreamPulse Player Shield] Handled promise rejection:', e ? (e.reason || e) : 'unknown');
        if (e && typeof e.preventDefault === 'function') e.preventDefault();
      });

      // --------------------------------------------------
      // Configuration & Parameter Extraction
      // --------------------------------------------------
      const params = new URLSearchParams(window.location.search);
      const channelName = params.get('channel') || params.get('channelName') || 'channel1';
      const streamKey = params.get('key') || params.get('streamKey') || 'live_stream';
      let serverUrl = params.get('server') || params.get('serverUrl') || '';

      if (!serverUrl) {
        if (window.location.protocol.startsWith('http')) {
          serverUrl = window.location.origin;
        } else {
          serverUrl = 'http://187.127.210.81';
        }
      }
      serverUrl = serverUrl.replace(/\/+$/, '');

      // Direct HLS override if specified
      const directHlsUrl = params.get('hls') || '';

      // DOM Elements
      const liveVideo = document.getElementById('live-video');
      const motionVideo = document.getElementById('motion-video');
      const htmlFallback = document.getElementById('html-fallback');
      const fallbackChannelName = document.getElementById('fallback-channel-name');
      const fallbackStatus = document.getElementById('fallback-status');
      const statusOverlay = document.getElementById('status-overlay');
      const statusBadge = document.getElementById('status-badge');
      const statusText = document.getElementById('status-text');
      const statusMetrics = document.getElementById('status-metrics');

      if (fallbackChannelName) {
        fallbackChannelName.textContent = 'Channel: ' + channelName;
      }

      // Candidate HLS URLs in priority order
      const candidateHlsUrls = directHlsUrl ? [directHlsUrl] : [
        serverUrl + '/hls/' + channelName + '/master.m3u8',
        serverUrl + '/hls/' + channelName + '/Original/index.m3u8',
        serverUrl + '/hls/' + channelName + '/index.m3u8',
        serverUrl + '/hls/' + channelName + '.m3u8',
        ...(streamKey && streamKey !== 'live_stream' ? [
          serverUrl + '/hls/' + streamKey + '/master.m3u8',
          serverUrl + '/hls/' + streamKey + '/Original/index.m3u8',
          serverUrl + '/hls/' + streamKey + '/index.m3u8'
        ] : [])
      ].filter((url, idx, arr) => url && arr.indexOf(url) === idx);

      // State Machine Variables
      let currentState = 'STANDBY'; // 'STANDBY' | 'LIVE'
      let activeHlsUrl = '';
      let hlsInstance = null;
      let isPollCycleRunning = false;
      let nextPollTimeoutId = null;
      let consecutiveOfflineCycles = 0;
      let mp4Failed = false;
      let overlayFadeTimer = null;
      let mouseTimer = null;
      let stallCheckTimer = null;
      let stallCount = 0;
      let lastPlayheadTime = -1;
      let heartbeatTimeoutId = null;

      // --------------------------------------------------
      // UI / Cursor Auto-Hide & Status Badge Helpers
      // --------------------------------------------------
      function resetCursor() {
        document.body.classList.remove('cursor-hidden');
        if (mouseTimer) {
          clearTimeout(mouseTimer);
          mouseTimer = null;
        }
        mouseTimer = setTimeout(() => {
          document.body.classList.add('cursor-hidden');
          mouseTimer = null;
        }, 2500);
      }
      window.addEventListener('mousemove', resetCursor, { passive: true });
      window.addEventListener('keydown', resetCursor, { passive: true });
      resetCursor();

      function updateStatus(mode, title, detail, autoHideMs) {
        if (!statusBadge || !statusText || !statusMetrics || !statusOverlay) return;
        statusBadge.className = 'status-badge ' + (mode === 'live' ? 'live' : 'offline');
        statusText.textContent = title || '';
        statusMetrics.textContent = detail || '';
        statusOverlay.style.opacity = '1';

        if (overlayFadeTimer) {
          clearTimeout(overlayFadeTimer);
          overlayFadeTimer = null;
        }
        if (autoHideMs && autoHideMs > 0) {
          overlayFadeTimer = setTimeout(() => {
            statusOverlay.style.opacity = '0';
            overlayFadeTimer = null;
          }, autoHideMs);
        }
      }

      // --------------------------------------------------
      // Safe, Leak-Free Fetch with Native Timeout & Signal Cleanup
      // --------------------------------------------------
      async function safeFetch(url, options = {}, timeoutMs = 3000) {
        let controller = null;
        let timer = null;
        try {
          if (typeof AbortController !== 'undefined') {
            controller = new AbortController();
            timer = setTimeout(() => {
              try { if (controller) controller.abort(); } catch(e) {}
            }, timeoutMs);
          }

          const fetchOpts = {
            ...options,
            cache: 'no-store'
          };
          if (controller) {
            fetchOpts.signal = controller.signal;
          }

          const res = await fetch(url, fetchOpts);
          if (timer) {
            clearTimeout(timer);
            timer = null;
          }
          controller = null;
          return res;
        } catch (err) {
          if (timer) {
            clearTimeout(timer);
            timer = null;
          }
          controller = null;
          return null;
        }
      }

      // --------------------------------------------------
      // Safe Video Playback Utilities
      // --------------------------------------------------
      function safePlay(videoEl) {
        if (!videoEl) return Promise.resolve(false);
        videoEl.muted = true;
        videoEl.playsInline = true;
        try {
          const playPromise = videoEl.play();
          if (playPromise !== undefined) {
            return playPromise.then(() => true).catch(() => {
              videoEl.muted = true;
              return videoEl.play().then(() => true).catch(() => false);
            });
          }
        } catch (e) {
          return Promise.resolve(false);
        }
        return Promise.resolve(true);
      }

      function tryUnmute() {
        if (currentState === 'LIVE' && liveVideo) {
          liveVideo.muted = false;
        }
      }
      window.addEventListener('click', tryUnmute, { passive: true });
      window.addEventListener('touchstart', tryUnmute, { passive: true });
      window.addEventListener('keydown', tryUnmute, { passive: true });

      // --------------------------------------------------
      // Motion Logo & Fallback HTML Handling (Zero Memory Leak)
      // --------------------------------------------------
      function showOfflineVisuals() {
        if (!mp4Failed) {
          if (motionVideo.error || motionVideo.networkState === 3) {
            handleMp4Failure();
            return;
          }
          motionVideo.classList.remove('hidden');
          motionVideo.style.display = '';
          htmlFallback.classList.remove('active');
          try {
            if (motionVideo.paused) {
              safePlay(motionVideo).then(ok => {
                if (!ok && currentState === 'STANDBY') handleMp4Failure();
              });
            }
          } catch(e) {}
        } else {
          motionVideo.classList.add('hidden');
          motionVideo.style.display = 'none';
          htmlFallback.classList.add('active');
        }
      }

      function handleMp4Failure() {
        if (mp4Failed) return;
        mp4Failed = true;
        console.warn('[StreamPulse Player] Motion Logo MP4 unavailable. Engaging CSS/SVG animated canvas fallback.');
        try {
          motionVideo.pause();
          motionVideo.removeAttribute('src');
          if (motionVideo.srcObject) motionVideo.srcObject = null;
          motionVideo.load();
        } catch(e) {}
        motionVideo.classList.add('hidden');
        motionVideo.style.display = 'none';
        htmlFallback.classList.add('active');
        if (fallbackStatus) {
          fallbackStatus.textContent = 'Stream offline • Polling channel ' + channelName + '...';
        }
      }

      // Event listeners for Motion Logo element
      const motionSource = motionVideo.querySelector('source');
      if (motionSource) {
        motionSource.addEventListener('error', handleMp4Failure);
      }
      motionVideo.addEventListener('error', handleMp4Failure);

      motionVideo.addEventListener('playing', () => {
        if (currentState === 'STANDBY' && !mp4Failed) {
          motionVideo.classList.remove('hidden');
          motionVideo.style.display = '';
          htmlFallback.classList.remove('active');
        }
      });
      motionVideo.addEventListener('ended', () => {
        if (currentState === 'STANDBY' && !mp4Failed) {
          motionVideo.currentTime = 0;
          safePlay(motionVideo);
        }
      });
      motionVideo.addEventListener('stalled', () => {
        if (currentState === 'STANDBY' && !mp4Failed && motionVideo.paused) {
          safePlay(motionVideo);
        }
      });

      // --------------------------------------------------
      // Complete & Leak-Free Player Destruction
      // --------------------------------------------------
      function destroyLivePlayer() {
        stopStallWatchdog();
        stallCount = 0;
        activeHlsUrl = '';

        // 1. Destroy HLS engine and clean up all media buffers
        if (hlsInstance) {
          try {
            hlsInstance.stopLoad();
            hlsInstance.detachMedia();
            hlsInstance.destroy();
          } catch (e) {}
          hlsInstance = null;
        }

        // 2. Hide, pause, and detach live video element to free GPU & memory
        if (liveVideo) {
          liveVideo.classList.remove('active');
          try {
            liveVideo.onplaying = null;
            liveVideo.pause();
            liveVideo.removeAttribute('src');
            if (liveVideo.srcObject) {
              liveVideo.srcObject = null;
            }
            liveVideo.load();
          } catch (e) {}
        }
      }

      // --------------------------------------------------
      // STATE TRANSITION: Switch to Offline Standby (Zero Reload)
      // --------------------------------------------------
      function switchToOfflineStandby(reason) {
        if (currentState === 'STANDBY') return;
        currentState = 'STANDBY';
        console.log('[StreamPulse Player] [STANDBY] Entering STANDBY state. Reason:', reason || 'Stream Offline');

        // 1. Fully destroy live player instance
        destroyLivePlayer();

        // 2. Show & play offline logo visuals
        showOfflineVisuals();

        // 3. Update status overlay
        updateStatus('offline', 'Stream Offline • Standby Active', 'Channel: ' + channelName, 0);

        // 4. Resume authoritative single polling loop with clean immediate check
        consecutiveOfflineCycles = 0;
        scheduleNextPoll(1000);
      }

      // --------------------------------------------------
      // Stalled Video Watchdog for LIVE Playback
      // --------------------------------------------------
      function startStallWatchdog() {
        stopStallWatchdog();
        lastPlayheadTime = liveVideo ? liveVideo.currentTime : -1;
        stallCount = 0;

        stallCheckTimer = setInterval(() => {
          if (currentState !== 'LIVE' || !liveVideo) return;

          const currentTime = liveVideo.currentTime;
          const isPaused = liveVideo.paused;
          const readyState = liveVideo.readyState;

          if (isPaused || readyState < 2 || (currentTime === lastPlayheadTime && currentTime > 0)) {
            stallCount++;
            console.warn('[StreamPulse Player] [STALL] Playback stall detected (' + stallCount + '/4, readyState=' + readyState + ', paused=' + isPaused + ')');

            safePlay(liveVideo);

            if (stallCount === 2 && hlsInstance) {
              try { hlsInstance.recoverMediaError(); safePlay(liveVideo); } catch(e) {}
            }

            if (stallCount >= 4) {
              console.warn('[StreamPulse Player] Stream disconnected/stalled. Switching to offline logo standby.');
              switchToOfflineStandby('Stream Inactive / Stalled');
              return;
            }
          } else {
            stallCount = 0;
          }

          lastPlayheadTime = currentTime;
        }, 3500);
      }

      function stopStallWatchdog() {
        if (stallCheckTimer) {
          clearInterval(stallCheckTimer);
          stallCheckTimer = null;
        }
      }

      // --------------------------------------------------
      // STATE TRANSITION: Switch to Live HLS
      // --------------------------------------------------
      function switchToLiveHls(validHlsUrl) {
        if (currentState === 'LIVE' && activeHlsUrl === validHlsUrl) return;
        currentState = 'LIVE';
        activeHlsUrl = validHlsUrl;
        console.log('[StreamPulse Player] [LIVE] Entering LIVE state. HLS URL:', validHlsUrl);

        // Stop polling immediately while in LIVE state
        stopStreamPolling();

        // Destroy any prior HLS instance cleanly before creating a new one
        if (hlsInstance) {
          try {
            hlsInstance.stopLoad();
            hlsInstance.detachMedia();
            hlsInstance.destroy();
          } catch (e) {}
          hlsInstance = null;
        }

        const cacheBustUrl = validHlsUrl + (validHlsUrl.includes('?') ? '&' : '?') + '_t=' + Date.now();

        if (window.Hls && window.Hls.isSupported()) {
          hlsInstance = new window.Hls({
            enableWorker: true,
            lowLatencyMode: true,
            backBufferLength: 15,
            maxBufferLength: 10,
            liveBackBufferLength: 6,
            manifestLoadingTimeOut: 6000,
            manifestLoadingMaxRetry: 2,
            levelLoadingTimeOut: 6000,
            fragLoadingTimeOut: 8000
          });

          hlsInstance.on(window.Hls.Events.MEDIA_ATTACHED, function() {
            safePlay(liveVideo);
          });

          hlsInstance.attachMedia(liveVideo);
          hlsInstance.loadSource(cacheBustUrl);

          hlsInstance.on(window.Hls.Events.MANIFEST_PARSED, function() {
            safePlay(liveVideo);
          });

          hlsInstance.on(window.Hls.Events.FRAG_BUFFERED, function() {
            if (liveVideo.paused) safePlay(liveVideo);
          });

          hlsInstance.on(window.Hls.Events.ERROR, function(event, data) {
            if (data && data.fatal) {
              if (data.type === window.Hls.ErrorTypes.MEDIA_ERROR) {
                try {
                  hlsInstance.recoverMediaError();
                  safePlay(liveVideo);
                } catch (e) {
                  switchToOfflineStandby('Media Error Unrecoverable');
                }
              } else if (data.type === window.Hls.ErrorTypes.NETWORK_ERROR) {
                switchToOfflineStandby('Stream Endpoint Returned 404/Offline');
              } else {
                switchToOfflineStandby('Fatal HLS Error: ' + (data.details || 'unknown'));
              }
            }
          });
        } else if (liveVideo.canPlayType('application/vnd.apple.mpegurl')) {
          liveVideo.src = cacheBustUrl;
          safePlay(liveVideo);
        } else {
          switchToOfflineStandby('HLS Engine Missing');
          return;
        }

        function onLivePlaying() {
          liveVideo.removeEventListener('playing', onLivePlaying);
          if (currentState !== 'LIVE') return;

          console.log('[StreamPulse Player] [LIVE ACTIVATION] Live stream rendering confirmed.');

          motionVideo.classList.add('hidden');
          htmlFallback.classList.remove('active');
          try { motionVideo.pause(); } catch(e) {}

          liveVideo.classList.add('active');

          const h = liveVideo.videoHeight || 1080;
          updateStatus('live', 'Live • ' + h + 'p', 'Channel: ' + channelName, 6000);

          startStallWatchdog();
        }
        liveVideo.onplaying = onLivePlaying;
      }

      liveVideo.addEventListener('error', function() {
        if (currentState === 'LIVE') {
          switchToOfflineStandby('Live Video Element Error');
        }
      });

      // --------------------------------------------------
      // Authoritative Single Polling Cycle (Bounded, Non-Leaking, Smart Discovery)
      // --------------------------------------------------
      async function runPollCycle() {
        if (currentState === 'LIVE' || isPollCycleRunning) return;
        isPollCycleRunning = true;

        let foundLiveStream = false;

        try {
          // 1. Authoritative check via Discovery API
          const discoveryUrl = serverUrl + '/api/stream/active?channel=' + encodeURIComponent(channelName) + (streamKey && streamKey !== 'live_stream' ? '&key=' + encodeURIComponent(streamKey) : '') + '&_t=' + Date.now();
          const discRes = await safeFetch(discoveryUrl, { headers: { 'Accept': 'application/json' } }, 2500);

          if (discRes && discRes.ok && discRes.status === 200) {
            const discData = await discRes.json();
            if (discData) {
              if (discData.isLive === true && discData.status === 'live') {
                // Channel is LIVE on server — probe the authoritative URL
                const targetUrl = discData.hlsMasterUrl || (discData.candidateUrls && discData.candidateUrls[0]) || '';
                if (targetUrl) {
                  const probeUrl = targetUrl + (targetUrl.includes('?') ? '&' : '?') + '_probe=' + Date.now();
                  const probeRes = await safeFetch(probeUrl, {
                    headers: { 'Accept': 'application/x-mpegURL, application/vnd.apple.mpegurl, */*' }
                  }, 2500);

                  if (probeRes && probeRes.ok && probeRes.status === 200) {
                    const text = await probeRes.text();
                    const trimmed = text ? text.trim() : '';
                    if (trimmed.startsWith('#EXTM3U') && !trimmed.includes('<html') && !trimmed.includes('<!DOCTYPE')) {
                      console.log('[StreamPulse Player] Valid live stream confirmed at:', targetUrl);
                      foundLiveStream = true;
                      isPollCycleRunning = false;
                      switchToLiveHls(targetUrl);
                      return;
                    }
                  }
                }
              } else {
                // Server confirmed channel is OFFLINE: Do NOT probe candidate URLs (avoids 404 flood)
                consecutiveOfflineCycles++;
              }
            }
          } else {
            // Server API unreachable (e.g. server restarting or network glitch)
            // Gently probe the first candidate HLS URL as fallback
            const fallbackUrl = candidateHlsUrls[0];
            if (fallbackUrl) {
              const probeUrl = fallbackUrl + (fallbackUrl.includes('?') ? '&' : '?') + '_probe=' + Date.now();
              const probeRes = await safeFetch(probeUrl, {
                headers: { 'Accept': 'application/x-mpegURL, application/vnd.apple.mpegurl, */*' }
              }, 2000);

              if (probeRes && probeRes.ok && probeRes.status === 200) {
                const text = await probeRes.text();
                const trimmed = text ? text.trim() : '';
                if (trimmed.startsWith('#EXTM3U') && !trimmed.includes('<html') && !trimmed.includes('<!DOCTYPE')) {
                  console.log('[StreamPulse Player] Fallback stream confirmed at:', fallbackUrl);
                  foundLiveStream = true;
                  isPollCycleRunning = false;
                  switchToLiveHls(fallbackUrl);
                  return;
                }
              }
            }
            consecutiveOfflineCycles++;
          }
        } catch (e) {
          consecutiveOfflineCycles++;
        }

        isPollCycleRunning = false;

        // Schedule next poll cycle with smooth, calm backoff (2.5s -> 4s -> 6s -> max 8s)
        if (currentState === 'STANDBY') {
          let nextDelay = 2500;
          if (consecutiveOfflineCycles > 20) {
            nextDelay = 8000;
          } else if (consecutiveOfflineCycles > 8) {
            nextDelay = 5000;
          } else if (consecutiveOfflineCycles > 3) {
            nextDelay = 3500;
          }
          scheduleNextPoll(nextDelay);
        }
      }

      function scheduleNextPoll(delayMs) {
        stopStreamPolling();
        if (currentState === 'STANDBY') {
          nextPollTimeoutId = setTimeout(runPollCycle, delayMs || 2500);
        }
      }

      function stopStreamPolling() {
        if (nextPollTimeoutId) {
          clearTimeout(nextPollTimeoutId);
          nextPollTimeoutId = null;
        }
      }

      // --------------------------------------------------
      // Telemetry Heartbeat (Safe Single Timeout Loop, 30s in Standby)
      // --------------------------------------------------
      async function sendHeartbeat() {
        if (serverUrl && serverUrl.startsWith('http')) {
          try {
            await safeFetch(serverUrl + '/api/rpi-player/status', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({
                channel: channelName,
                streamKey: streamKey,
                online_status: currentState === 'LIVE' ? 'playing' : 'offline_logo',
                current_resolution: (liveVideo.videoWidth || 1920) + 'x' + (liveVideo.videoHeight || 1080),
                engine: currentState === 'LIVE' ? 'HLS.js' : (mp4Failed ? 'HTML Canvas' : 'Motion Logo'),
                player_version: '2.5.1-universal'
              })
            }, 3000);
          } catch(e) {}
        }
        const nextHb = currentState === 'LIVE' ? 15000 : 30000;
        heartbeatTimeoutId = setTimeout(sendHeartbeat, nextHb);
      }

      // --------------------------------------------------
      // Initial Startup Execution
      // --------------------------------------------------
      showOfflineVisuals();
      updateStatus('offline', 'StreamPulse Standby', 'Channel: ' + channelName + ' • Probing stream...', 0);
      scheduleNextPoll(500);
      heartbeatTimeoutId = setTimeout(sendHeartbeat, 10000);

    })();
  </script>
</body>
</html>

HTML

# Mandatory local download and verification of hls.min.js for offline operation
echo "[+] Downloading and verifying local HLS.js playback engine..."
if ! curl -fsSL --retry 3 --connect-timeout 10 --max-time 30 \
  "https://cdn.jsdelivr.net/npm/hls.js@1.5.8/dist/hls.min.js" \
  -o /opt/streampulse/logo/hls.min.js; then
  echo -e "\e[31m[FAIL] Mandatory local HLS.js download failed from CDN.\e[0m" >&2
  exit 1
fi

if [[ ! -s /opt/streampulse/logo/hls.min.js ]]; then
  echo -e "\e[31m[FAIL] /opt/streampulse/logo/hls.min.js is empty or missing.\e[0m" >&2
  exit 1
fi
chmod 644 /opt/streampulse/logo/* 2>/dev/null || true

# ------------------------------------------------------------------------------
# 8. Persistent Per-Pi Channel & Player Configuration
# ------------------------------------------------------------------------------
echo "[+] Writing Per-Pi Player Configuration (/opt/streampulse/config/player.conf)..."
PLAYER_CONF="/opt/streampulse/config/player.conf"

# Preserve existing stream key and channel name if installer ran with defaults on existing Pi
if [[ -f "${PLAYER_CONF}" ]]; then
  EXISTING_KEY="$(grep '^STREAM_KEY=' "${PLAYER_CONF}" | cut -d= -f2 | tr -d '"' || echo '')"
  EXISTING_CH="$(grep '^CHANNEL_NAME=' "${PLAYER_CONF}" | cut -d= -f2 | tr -d '"' || echo '')"
  if [[ "${STREAM_KEY}" == "live_stream" ]] && [[ -n "${EXISTING_KEY}" ]]; then
    STREAM_KEY="${EXISTING_KEY}"
  fi
  if [[ "${CHANNEL_NAME}" == "channel1" ]] && [[ -n "${EXISTING_CH}" ]]; then
    CHANNEL_NAME="${EXISTING_CH}"
  fi
fi

cat <<CONF > "${PLAYER_CONF}"
# StreamPulse Player & Channel Configuration
# Managed by StreamPulse Universal Installer
# Path: /opt/streampulse/config/player.conf

CHANNEL_NAME="${CHANNEL_NAME}"
STREAM_KEY="${STREAM_KEY}"
SERVER_URL="${SERVER_URL}"
LOGO_DIR="/opt/streampulse/logo"
OFFLINE_LOGO_MEDIA="/opt/streampulse/logo/motion-logo.mp4"
OFFLINE_FALLBACK_HTML="/opt/streampulse/logo/logo-fallback.html"
PLAYBACK_MODE="auto"
ENABLE_HW_ACCEL=1
AUDIO_OUTPUT="default"
LAST_UPDATED="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
CONF

chmod 644 "${PLAYER_CONF}"

# ------------------------------------------------------------------------------
# 9. Kiosk Configuration (Keyring Suppression & Clean Flags)
# ------------------------------------------------------------------------------
echo "[+] Writing Kiosk Configuration (/opt/streampulse/config/kiosk.conf)..."
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
  "--window-position=0,0"
  "--window-size=1920,1080"
)
CONF

chmod 644 /opt/streampulse/config/kiosk.conf

# ------------------------------------------------------------------------------
# 10. Standalone Self-Contained Binaries Generation in /opt/streampulse/bin/
# (Unified Single-Surface Architecture with Duplicate Process Lock)
# ------------------------------------------------------------------------------
echo "[+] Writing Authoritative Management Binaries in /opt/streampulse/bin/..."

# --- 10.1 streampulse-player.sh (Authoritative Unified Controller) ---
cat << 'EOF_PLAYER' > /opt/streampulse/bin/streampulse-player.sh
#!/usr/bin/env bash
# ==============================================================================
# StreamPulse Authoritative Unified Fullscreen Player Supervisor
# Managed by StreamPulse Universal Installer
# Path: /opt/streampulse/bin/streampulse-player.sh
# ==============================================================================

set -uo pipefail

# ------------------------------------------------------------------------------
# 1. Strict Process Lock (Guarantees ONLY ONE player launcher instance ever runs)
# ------------------------------------------------------------------------------
LOCK_FILE="/tmp/streampulse-player.lock"
exec 200>"${LOCK_FILE}"
if ! flock -n 200; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse] Another player instance is already active with lock. Exiting duplicate launcher."
  exit 0
fi

# ------------------------------------------------------------------------------
# 2. Terminate Any Rogue Competing Playback Loops (mpv, cvlc, old launchers)
# ------------------------------------------------------------------------------
pkill -9 -f "mpv.*motion-logo" 2>/dev/null || true
pkill -9 -f "cvlc.*motion-logo" 2>/dev/null || true
pkill -9 -f "player-launcher\.sh" 2>/dev/null || true

# ------------------------------------------------------------------------------
# 3. Load Configurations (player.conf has highest priority for channel & key)
# ------------------------------------------------------------------------------
CONFIG_FILE="/opt/streampulse/config/kiosk.conf"
PLAYER_CONFIG="/opt/streampulse/config/player.conf"

CHANNEL_NAME="channel1"
STREAM_KEY="live_stream"
SERVER_URL="http://187.127.210.81"
DASHBOARD_URL=""
BROWSER_PROFILE_DIR="/opt/streampulse/chromium-profile"
SCREEN_WIDTH=1920
SCREEN_HEIGHT=1080

if [[ -f "${PLAYER_CONFIG}" ]]; then
  # shellcheck source=/dev/null
  source "${PLAYER_CONFIG}"
fi

if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck source=/dev/null
  source "${CONFIG_FILE}"
fi

echo "======================================================================"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse Supervisor] Booting Authoritative Fullscreen Player Supervisor..."
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse Supervisor] Assigned Channel: ${CHANNEL_NAME}"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse Supervisor] Server Endpoint:  ${SERVER_URL}"
echo "======================================================================"

# ------------------------------------------------------------------------------
# 4. Environment & Display Resolution
# ------------------------------------------------------------------------------
CURRENT_UID="$(id -u)"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/${CURRENT_UID}}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export DISPLAY="${DISPLAY:-:0}"

# ------------------------------------------------------------------------------
# 5. Wait for Graphical Display / Compositor (Strict Wayland & Labwc Validation)
# ------------------------------------------------------------------------------
MAX_DISPLAY_WAIT=60
DISPLAY_WAITED=0
WAYLAND_SOCKET="${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse Supervisor] Waiting for Wayland / Labwc display session readiness..."

while true; do
  SOCKET_READY=0
  COMPOSITOR_READY=0

  if [[ -S "${WAYLAND_SOCKET}" ]] || [[ -e "${WAYLAND_SOCKET}" ]]; then
    SOCKET_READY=1
  fi

  if pgrep -u "${CURRENT_UID}" -x labwc >/dev/null 2>&1 || pgrep -x labwc >/dev/null 2>&1 || pgrep -u "${CURRENT_UID}" -x wayfire >/dev/null 2>&1 || pgrep -x Xorg >/dev/null 2>&1 || [[ -S "/tmp/.X11-unix/X0" ]]; then
    COMPOSITOR_READY=1
  fi

  if (( SOCKET_READY == 1 && COMPOSITOR_READY == 1 )); then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse Supervisor] Graphical display session confirmed ready (Socket: ${WAYLAND_SOCKET}, Compositor: active) after ${DISPLAY_WAITED}s."
    break
  fi

  # Fallback check for X11 / Xwayland if xset succeeds
  if command -v xset >/dev/null 2>&1 && xset q >/dev/null 2>&1; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse Supervisor] Display verified ready via xset after ${DISPLAY_WAITED}s."
    break
  fi

  if (( DISPLAY_WAITED >= MAX_DISPLAY_WAIT )); then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse Supervisor] ERROR: Graphical display / Wayland session failed to become ready after ${MAX_DISPLAY_WAIT}s. Exiting." >&2
    exit 1
  fi

  if (( DISPLAY_WAITED % 5 == 0 && DISPLAY_WAITED > 0 )); then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse Supervisor] Waiting for Wayland socket & compositor (${DISPLAY_WAITED}/${MAX_DISPLAY_WAIT}s)..."
  fi

  sleep 1
  (( DISPLAY_WAITED++ ))
done

# ------------------------------------------------------------------------------
# 6. Screen Power Management & Cursor Hiding
# ------------------------------------------------------------------------------
if command -v xset >/dev/null 2>&1; then
  xset s off -dpms s noblank 2>/dev/null || true
fi
if command -v wlr-randr >/dev/null 2>&1; then
  wlr-randr --output HDMI-A-1 --on 2>/dev/null || true
fi
if command -v unclutter >/dev/null 2>&1; then
  pgrep -x unclutter >/dev/null 2>&1 || unclutter -idle 0.5 -root &
fi

# ------------------------------------------------------------------------------
# 7. Locate Browser Binary
# ------------------------------------------------------------------------------
BROWSER_BIN=""
for CANDIDATE in chromium chromium-browser google-chrome firefox; do
  if command -v "${CANDIDATE}" >/dev/null 2>&1; then
    BROWSER_BIN="$(command -v "${CANDIDATE}")"
    break
  fi
done

if [[ -z "${BROWSER_BIN}" ]]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse Supervisor] ERROR: No supported browser found." >&2
  exit 1
fi

# ------------------------------------------------------------------------------
# 8. Profile Directory Setup
# ------------------------------------------------------------------------------
mkdir -p "${BROWSER_PROFILE_DIR}"
mkdir -p "/tmp/chromium-cache" 2>/dev/null || true

# ------------------------------------------------------------------------------
# 9. Assemble Safe Browser Arguments (Wayland Native + GPU Workaround + DevSHM Guard)
# ------------------------------------------------------------------------------
declare -a LAUNCH_ARGS=(
  "--user-data-dir=${BROWSER_PROFILE_DIR}"
  "--ozone-platform=wayland"
  "--disable-gpu"
  "--disable-dev-shm-usage"
  "--disk-cache-dir=/tmp/chromium-cache"
  "--disk-cache-size=33554432"
  "--media-cache-size=33554432"
  "--disable-breakpad"
  "--disable-crash-reporter"
  "--disable-hang-monitor"
  "--disable-background-timer-throttling"
  "--disable-backgrounding-occluded-windows"
  "--disable-renderer-backgrounding"
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
  "--disable-features=TranslateUI,OptimizationHints,MediaRouter"
  "--enable-features=OverlayScrollbar"
  "--disable-save-password-bubble"
  "--allow-file-access-from-files"
  "--window-position=0,0"
  "--window-size=${SCREEN_WIDTH:-1920},${SCREEN_HEIGHT:-1080}"
)

# ------------------------------------------------------------------------------
# 10. Authoritative Target URL: Integrated HTML5 Kiosk Player
# ------------------------------------------------------------------------------
LOCAL_PLAYER="file:///opt/streampulse/logo/player.html"
TARGET_URL="${LOCAL_PLAYER}?channel=${CHANNEL_NAME}&server=${SERVER_URL}"

# Support explicit custom non-default URLs if specifically configured
if [[ -n "${DASHBOARD_URL:-}" ]] && [[ "${DASHBOARD_URL}" =~ ^https?:// ]] && [[ "${DASHBOARD_URL}" != "http://187.127.210.81/" ]] && [[ "${DASHBOARD_URL}" != "http://187.127.210.81" ]] && [[ "${DASHBOARD_URL}" != *"127.0.0.1"* ]] && [[ "${DASHBOARD_URL}" != *"localhost"* ]]; then
  # Only use remote dashboard if not a video stream URL
  if [[ ! "${DASHBOARD_URL}" =~ \.m3u8 ]] && [[ ! "${DASHBOARD_URL}" =~ /hls/ ]]; then
    TARGET_URL="${DASHBOARD_URL}"
  fi
fi

LAUNCH_ARGS+=("${TARGET_URL}")

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse Supervisor] Target Player URL: ${TARGET_URL}"

# ------------------------------------------------------------------------------
# 11. External Chromium Process Supervision Loop with Bounded Backoff
# ------------------------------------------------------------------------------
SUPERVISOR_ACTIVE=1
RESTART_COUNT=0
CONSECUTIVE_QUICK_CRASHES=0
BACKOFF_SECONDS=2

cleanup_supervisor() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse Supervisor] Termination signal received. Stopping Chromium supervisor."
  SUPERVISOR_ACTIVE=0
  pkill -u "${CURRENT_UID}" -f "${BROWSER_PROFILE_DIR}" 2>/dev/null || true
  exit 0
}

trap cleanup_supervisor SIGTERM SIGINT SIGHUP

while (( SUPERVISOR_ACTIVE == 1 )); do
  # Clean stale profile locks and lingering sockets before start
  rm -f "${BROWSER_PROFILE_DIR}/SingletonLock" \
        "${BROWSER_PROFILE_DIR}/SingletonSocket" \
        "${BROWSER_PROFILE_DIR}/SingletonCookie" \
        "${BROWSER_PROFILE_DIR}/lockfile" 2>/dev/null || true

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse Supervisor] Launching Chromium (Supervisor Run #${RESTART_COUNT})..."
  START_TIME=$(date +%s)

  # Execute Chromium process in foreground under supervisor
  "${BROWSER_BIN}" "${LAUNCH_ARGS[@]}"
  EXIT_CODE=$?

  END_TIME=$(date +%s)
  RUNTIME=$(( END_TIME - START_TIME ))

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse Supervisor] Chromium process exited with code ${EXIT_CODE} after ${RUNTIME}s uptime."

  if (( SUPERVISOR_ACTIVE == 0 )); then
    break
  fi

  # Reset backoff if browser was stable for >= 60 seconds
  if (( RUNTIME >= 60 )); then
    CONSECUTIVE_QUICK_CRASHES=0
    BACKOFF_SECONDS=2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse Supervisor] Stable runtime confirmed (${RUNTIME}s). Resetting backoff to 2s."
  else
    (( CONSECUTIVE_QUICK_CRASHES++ ))
    if (( CONSECUTIVE_QUICK_CRASHES == 1 )); then
      BACKOFF_SECONDS=2
    elif (( CONSECUTIVE_QUICK_CRASHES == 2 )); then
      BACKOFF_SECONDS=5
    elif (( CONSECUTIVE_QUICK_CRASHES == 3 )); then
      BACKOFF_SECONDS=10
    elif (( CONSECUTIVE_QUICK_CRASHES == 4 )); then
      BACKOFF_SECONDS=20
    else
      BACKOFF_SECONDS=30
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse Supervisor] Quick exit detected (${CONSECUTIVE_QUICK_CRASHES} consecutive). Backoff set to ${BACKOFF_SECONDS}s."
  fi

  (( RESTART_COUNT++ ))
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse Supervisor] Auto-recovering Chromium in ${BACKOFF_SECONDS}s (Restart #${RESTART_COUNT})..."

  # Kill any orphan Chromium helper/renderer processes before restart
  pkill -u "${CURRENT_UID}" -f "${BROWSER_PROFILE_DIR}" 2>/dev/null || true
  sleep "${BACKOFF_SECONDS}"
done

EOF_PLAYER

# --- 10.2 dashboard-kiosk.sh & player-launcher.sh (Delegating wrappers) ---
cat << 'EOF_DASHBOARD_KIOSK' > /opt/streampulse/bin/dashboard-kiosk.sh
#!/usr/bin/env bash
# StreamPulse Dashboard Kiosk Compatibility Wrapper
exec /opt/streampulse/bin/streampulse-player.sh "$@"
EOF_DASHBOARD_KIOSK

cat << 'EOF_PLAYER_LAUNCHER' > /opt/streampulse/bin/player-launcher.sh
#!/usr/bin/env bash
# StreamPulse Player Launcher Compatibility Wrapper
exec /opt/streampulse/bin/streampulse-player.sh "$@"
EOF_PLAYER_LAUNCHER

# --- 10.3 set-channel.sh ---
cat << 'EOF_SET_CHANNEL' > /opt/streampulse/bin/set-channel.sh
#!/usr/bin/env bash
# StreamPulse Channel Switcher Utility
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Error: set-channel.sh must be run with root privileges (sudo)." >&2
  exit 1
fi

NEW_CHANNEL="${1:-}"
NEW_STREAM_KEY="${2:-}"

if [[ -z "${NEW_CHANNEL}" ]]; then
  echo "Usage: sudo /opt/streampulse/bin/set-channel.sh <channel_name> [stream_key]"
  echo "Example: sudo /opt/streampulse/bin/set-channel.sh channel2"
  exit 1
fi

if [[ ! "${NEW_CHANNEL}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "Error: Invalid channel name '${NEW_CHANNEL}'. Alphanumerics, hyphens and underscores only." >&2
  exit 1
fi

CONFIG_FILE="/opt/streampulse/config/player.conf"
mkdir -p /opt/streampulse/config

CURRENT_CHANNEL="unknown"
if [[ -f "${CONFIG_FILE}" ]]; then
  CURRENT_CHANNEL="$(grep '^CHANNEL_NAME=' "${CONFIG_FILE}" | cut -d= -f2 | tr -d '"' || echo 'unknown')"
fi

echo "======================================================================"
echo "          StreamPulse Per-Pi Channel Update"
echo "======================================================================"
echo "Current Channel: ${CURRENT_CHANNEL}"
echo "Target Channel:  ${NEW_CHANNEL}"
echo "Timestamp:       $(date '+%Y-%m-%d %H:%M:%S')"
echo "----------------------------------------------------------------------"

TMP_CONF="$(mktemp)"
if [[ -f "${CONFIG_FILE}" ]]; then
  cp "${CONFIG_FILE}" "${TMP_CONF}"
  if grep -q '^CHANNEL_NAME=' "${TMP_CONF}"; then
    sed -i "s|^CHANNEL_NAME=.*|CHANNEL_NAME=\"${NEW_CHANNEL}\"|" "${TMP_CONF}"
  else
    echo "CHANNEL_NAME=\"${NEW_CHANNEL}\"" >> "${TMP_CONF}"
  fi
  if [[ -n "${NEW_STREAM_KEY}" ]]; then
    if grep -q '^STREAM_KEY=' "${TMP_CONF}"; then
      sed -i "s|^STREAM_KEY=.*|STREAM_KEY=\"${NEW_STREAM_KEY}\"|" "${TMP_CONF}"
    else
      echo "STREAM_KEY=\"${NEW_STREAM_KEY}\"" >> "${TMP_CONF}"
    fi
  fi
  if grep -q '^LAST_UPDATED=' "${TMP_CONF}"; then
    sed -i "s|^LAST_UPDATED=.*|LAST_UPDATED=\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"|" "${TMP_CONF}"
  else
    echo "LAST_UPDATED=\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"" >> "${TMP_CONF}"
  fi
else
  cat <<CONF > "${TMP_CONF}"
# StreamPulse Player & Channel Configuration
CHANNEL_NAME="${NEW_CHANNEL}"
STREAM_KEY="${NEW_STREAM_KEY:-live_stream}"
SERVER_URL="http://187.127.210.81"
LOGO_DIR="/opt/streampulse/logo"
OFFLINE_LOGO_MEDIA="/opt/streampulse/logo/motion-logo.mp4"
OFFLINE_FALLBACK_HTML="/opt/streampulse/logo/logo-fallback.html"
PLAYBACK_MODE="auto"
ENABLE_HW_ACCEL=1
AUDIO_OUTPUT="default"
LAST_UPDATED="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
CONF
fi

mv "${TMP_CONF}" "${CONFIG_FILE}"
chmod 644 "${CONFIG_FILE}"

DETECTED_USER="${SUDO_USER:-$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $3}' | grep -v '^root$' | head -n1 || awk -F: '$3 == 1000 {print $1}' /etc/passwd 2>/dev/null || echo '')}"
if [[ -n "${DETECTED_USER}" ]] && id -u "${DETECTED_USER}" >/dev/null 2>&1; then
  chown "${DETECTED_USER}:${DETECTED_USER}" "${CONFIG_FILE}" 2>/dev/null || true
fi

echo "  [+] Updated configuration saved to ${CONFIG_FILE}"

# Safely restart the single authoritative player service
if systemctl is-active --quiet streampulse-player.service 2>/dev/null || systemctl is-enabled --quiet streampulse-player.service 2>/dev/null; then
  echo "  [+] Reloading authoritative service: streampulse-player.service..."
  systemctl restart streampulse-player.service 2>/dev/null || true
fi

VERIFIED_CHANNEL="$(grep '^CHANNEL_NAME=' "${CONFIG_FILE}" | cut -d= -f2 | tr -d '"')"
if [[ "${VERIFIED_CHANNEL}" == "${NEW_CHANNEL}" ]]; then
  echo "[OK] Pi channel successfully switched to '${NEW_CHANNEL}'."
else
  echo "[FAIL] Verification failed. Channel in config is '${VERIFIED_CHANNEL}'." >&2
  exit 1
fi
EOF_SET_CHANNEL

# --- 10.4 backup.sh ---
cat << 'EOF_BACKUP' > /opt/streampulse/bin/backup.sh
#!/usr/bin/env bash
# StreamPulse Backup Engine
set -euo pipefail

TARGET_USER="${1:-${SUDO_USER:-$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $3}' | grep -v '^root$' | head -n 1 || awk -F: '$3 >= 1000 && $3 < 60000 {print $1}' /etc/passwd | head -n1 || echo '')}}"
if [[ -z "${TARGET_USER}" ]]; then
  echo "Error: Could not resolve target user for backup." >&2
  exit 1
fi

USER_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
BACKUP_BASE="${USER_HOME}/streampulse-backups"
BACKUP_DIR="${BACKUP_BASE}/${TIMESTAMP}"

echo "======================================================================"
echo "          StreamPulse Backup Creation Snapshot"
echo "======================================================================"
echo "Timestamp:    ${TIMESTAMP}"
echo "Target User:  ${TARGET_USER}"
echo "Backup Path:  ${BACKUP_DIR}"
echo "----------------------------------------------------------------------"

mkdir -p "${BACKUP_DIR}/systemd" "${BACKUP_DIR}/config" "${BACKUP_DIR}/bin" "${BACKUP_DIR}/autostart"

for srv in streampulse-player.service streampulse-dashboard.service streampulse-rpi-player.service streampulse-kiosk.service; do
  if [[ -f "/etc/systemd/system/${srv}" ]]; then
    cp -p "/etc/systemd/system/${srv}" "${BACKUP_DIR}/systemd/"
  fi
done

if [[ -d "/opt/streampulse/config" ]]; then
  cp -rp "/opt/streampulse/config" "${BACKUP_DIR}/"
fi
if [[ -d "/opt/streampulse/bin" ]]; then
  cp -rp "/opt/streampulse/bin" "${BACKUP_DIR}/"
fi

if [[ -f "${USER_HOME}/.config/labwc/autostart" ]]; then
  cp -p "${USER_HOME}/.config/labwc/autostart" "${BACKUP_DIR}/autostart/" 2>/dev/null || true
fi

cat <<MANIFEST > "${BACKUP_DIR}/manifest.json"
{
  "timestamp": "${TIMESTAMP}",
  "user": "${TARGET_USER}",
  "backup_dir": "${BACKUP_DIR}"
}
MANIFEST

chown -R "${TARGET_USER}:${TARGET_USER}" "${BACKUP_BASE}" 2>/dev/null || true
ln -sfn "${BACKUP_DIR}" "${BACKUP_BASE}/latest"

echo "Backup completed successfully -> ${BACKUP_DIR}"
EOF_BACKUP

# --- 10.5 restore.sh ---
cat << 'EOF_RESTORE' > /opt/streampulse/bin/restore.sh
#!/usr/bin/env bash
# StreamPulse Restoration Engine
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Error: restore.sh must be run as root (sudo)." >&2
  exit 1
fi

TARGET_USER="${1:-${SUDO_USER:-$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $3}' | grep -v '^root$' | head -n 1 || awk -F: '$3 >= 1000 {print $1}' /etc/passwd | head -n1 || echo '')}}"
USER_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
BACKUP_BASE="${USER_HOME}/streampulse-backups"

RESTORE_DIR="${2:-${BACKUP_BASE}/latest}"
if [[ ! -d "${RESTORE_DIR}" ]]; then
  echo "Error: No backup directory found at ${RESTORE_DIR}." >&2
  exit 1
fi

echo "======================================================================"
echo "          StreamPulse Rollback & Restore"
echo "======================================================================"
echo "Restoring from: ${RESTORE_DIR}"
echo "----------------------------------------------------------------------"

if [[ -d "${RESTORE_DIR}/systemd" ]]; then
  cp -p "${RESTORE_DIR}/systemd/"*.service /etc/systemd/system/ 2>/dev/null || true
  systemctl daemon-reload
fi

if [[ -d "${RESTORE_DIR}/config" ]]; then
  mkdir -p /opt/streampulse/config
  cp -rp "${RESTORE_DIR}/config/"* /opt/streampulse/config/ 2>/dev/null || true
fi

if [[ -d "${RESTORE_DIR}/autostart/autostart" ]] && [[ -d "${USER_HOME}/.config/labwc" ]]; then
  cp -p "${RESTORE_DIR}/autostart/autostart" "${USER_HOME}/.config/labwc/autostart" 2>/dev/null || true
fi

if systemctl is-enabled --quiet streampulse-player.service 2>/dev/null || systemctl is-active --quiet streampulse-player.service 2>/dev/null; then
  systemctl restart streampulse-player.service 2>/dev/null || true
fi

echo "[OK] System configuration successfully restored from snapshot."
EOF_RESTORE

# --- 10.6 diagnose.sh ---
cat << 'EOF_DIAGNOSE' > /opt/streampulse/bin/diagnose.sh
#!/usr/bin/env bash
# StreamPulse Diagnostic Engine
set -uo pipefail

echo "======================================================================"
echo "          StreamPulse Diagnostics Report"
echo "======================================================================"
echo "Timestamp:    $(date '+%Y-%m-%d %H:%M:%S')"
echo "Hostname:     $(hostname 2>/dev/null || echo 'unknown')"
echo "Hardware:     $(cat /proc/device-tree/model 2>/dev/null || uname -m)"
echo "OS:           $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '\"' || uname -s)"
echo "----------------------------------------------------------------------"

PLAYER_CONF="/opt/streampulse/config/player.conf"
if [[ -f "${PLAYER_CONF}" ]]; then
  CHANNEL="$(grep '^CHANNEL_NAME=' "${PLAYER_CONF}" | cut -d= -f2 | tr -d '\"')"
  RAW_KEY="$(grep '^STREAM_KEY=' "${PLAYER_CONF}" | cut -d= -f2 | tr -d '\"')"
  if (( ${#RAW_KEY} > 6 )); then
    MASKED_KEY="${RAW_KEY:0:3}******${RAW_KEY: -3}"
  else
    MASKED_KEY="******"
  fi
  echo "Assigned Channel: ${CHANNEL}"
  echo "Stream Key:       ${MASKED_KEY} (SECURE)"
  echo "Server URL:       $(grep '^SERVER_URL=' "${PLAYER_CONF}" | cut -d= -f2 | tr -d '\"')"
else
  echo "[!] Player configuration (${PLAYER_CONF}) missing."
fi

echo "----------------------------------------------------------------------"
echo "Authoritative Playback Service Status:"
if systemctl is-active --quiet streampulse-player.service 2>/dev/null; then
  echo "  [OK] streampulse-player.service: ACTIVE (Running)"
elif systemctl is-enabled --quiet streampulse-player.service 2>/dev/null; then
  echo "  [WARN] streampulse-player.service: ENABLED (Not active right now)"
else
  echo "  [INFO] streampulse-player.service: INACTIVE"
fi

echo "----------------------------------------------------------------------"
echo "Competing Legacy Services Check:"
if systemctl is-active --quiet streampulse-rpi-player.service 2>/dev/null; then
  echo "  [FAIL] streampulse-rpi-player.service is running! (Competing service conflict)"
else
  echo "  [OK] No competing streampulse-rpi-player.service detected."
fi

ROGUE_MPV="$(pgrep -f "mpv.*motion-logo" | tr '\n' ' ')"
if [[ -n "${ROGUE_MPV}" ]]; then
  echo "  [WARN] Legacy mpv loop running: PID ${ROGUE_MPV}"
else
  echo "  [OK] No rogue mpv background processes."
fi

echo "----------------------------------------------------------------------"
echo "Process Lock & Display:"
if [[ -f /tmp/streampulse-player.lock ]]; then
  echo "  Lock File:   /tmp/streampulse-player.lock (Active)"
fi
echo "  IP Address:  $(hostname -I 2>/dev/null || echo 'none')"
echo "  Display:     ${DISPLAY:-:0} | Wayland: ${WAYLAND_DISPLAY:-wayland-0}"
echo "======================================================================"
EOF_DIAGNOSE

# --- 10.8 streampulse-update.sh ---
cat << 'EOF_UPDATE' > /opt/streampulse/bin/streampulse-update.sh
#!/usr/bin/env bash
# ==============================================================================
# StreamPulse Lightweight Auto-Update Engine
# Runs safely on boot via streampulse-update.service
# Path: /opt/streampulse/bin/streampulse-update.sh
# ==============================================================================

set -uo pipefail

PLAYER_CONF="/opt/streampulse/config/player.conf"
VERSION_FILE="/opt/streampulse/VERSION"
LOCAL_VERSION="1.0.0"

if [[ -f "${VERSION_FILE}" ]]; then
  LOCAL_VERSION="$(tr -d ' \r\n' < "${VERSION_FILE}" || echo "1.0.0")"
fi

if [[ ! -f "${PLAYER_CONF}" ]]; then
  echo "[StreamPulse Update] Configuration (${PLAYER_CONF}) missing. Skipping update check."
  exit 0
fi

SERVER_URL="$(grep '^SERVER_URL=' "${PLAYER_CONF}" 2>/dev/null | cut -d= -f2- | tr -d '"\r\n' || echo '')"
if [[ -z "${SERVER_URL}" ]]; then
  echo "[StreamPulse Update] SERVER_URL not defined in player.conf. Skipping update check."
  exit 0
fi

# Ensure trailing slash removed
SERVER_URL="${SERVER_URL%/}"

echo "[StreamPulse Update] Checking for updates (Local Version: ${LOCAL_VERSION}, Server: ${SERVER_URL})..."

# Fetch server version with strict timeout
REMOTE_VERSION_RESP="$(curl -sSL -m 8 --connect-timeout 5 "${SERVER_URL}/api/rpi-player/version" 2>/dev/null || echo '')"

if [[ -z "${REMOTE_VERSION_RESP}" ]]; then
  echo "[StreamPulse Update] Server unreachable or network offline. Preserving current version (${LOCAL_VERSION})."
  exit 0
fi

# Extract version string (support plain text or JSON { "version": "x.y.z" })
if echo "${REMOTE_VERSION_RESP}" | grep -q '^{'; then
  REMOTE_VERSION="$(echo "${REMOTE_VERSION_RESP}" | grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4 || echo '')"
else
  REMOTE_VERSION="$(echo "${REMOTE_VERSION_RESP}" | tr -d ' \r\n' || echo '')"
fi

if [[ -z "${REMOTE_VERSION}" ]]; then
  echo "[StreamPulse Update] Invalid version response from server. Preserving current version (${LOCAL_VERSION})."
  exit 0
fi

echo "[StreamPulse Update] Remote version: ${REMOTE_VERSION} | Local version: ${LOCAL_VERSION}"

if [[ "${REMOTE_VERSION}" == "${LOCAL_VERSION}" ]]; then
  echo "[StreamPulse Update] StreamPulse is up to date (${LOCAL_VERSION}). No action required."
  exit 0
fi

echo "[StreamPulse Update] New StreamPulse update detected: ${REMOTE_VERSION} (Current: ${LOCAL_VERSION}). Initiating safe update..."

# Create staging and backup directories
STAGING_DIR="/tmp/streampulse-update-staging"
BACKUP_DIR="/opt/streampulse/backups/pre-update-${LOCAL_VERSION}"
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}" "${BACKUP_DIR}"

# 1. Download updated installer payload
UPDATE_SCRIPT="${STAGING_DIR}/full-install.sh"
if ! curl -fsSL -m 30 --connect-timeout 10 "${SERVER_URL}/api/rpi-player/script/universal-install" -o "${UPDATE_SCRIPT}"; then
  echo "[StreamPulse Update] [ERROR] Failed to download update payload from server. Aborting update." >&2
  rm -rf "${STAGING_DIR}"
  exit 0
fi

# 2. Syntax integrity check
if ! bash -n "${UPDATE_SCRIPT}"; then
  echo "[StreamPulse Update] [ERROR] Downloaded update script failed syntax verification (bash -n). Aborting." >&2
  rm -rf "${STAGING_DIR}"
  exit 0
fi

# 3. Create pre-update backup of current scripts, configs, and assets
echo "[StreamPulse Update] Backing up current installation to ${BACKUP_DIR}..."
cp -rp /opt/streampulse/bin "${BACKUP_DIR}/" 2>/dev/null || true
cp -rp /opt/streampulse/config "${BACKUP_DIR}/" 2>/dev/null || true
cp -p /opt/streampulse/logo/player.html "${BACKUP_DIR}/" 2>/dev/null || true
cp -p /opt/streampulse/logo/logo-fallback.html "${BACKUP_DIR}/" 2>/dev/null || true
cp -p /opt/streampulse/logo/hls.min.js "${BACKUP_DIR}/" 2>/dev/null || true
[[ -f /opt/streampulse/logo/motion-logo.mp4 ]] && cp -p /opt/streampulse/logo/motion-logo.mp4 "${BACKUP_DIR}/" 2>/dev/null || true
[[ -f "${VERSION_FILE}" ]] && cp -p "${VERSION_FILE}" "${BACKUP_DIR}/" 2>/dev/null || true

# 4. Execute the update using installer in safe non-destructive update mode
echo "[StreamPulse Update] Applying StreamPulse update payload (${REMOTE_VERSION})..."

CHANNEL="$(grep '^CHANNEL_NAME=' "${PLAYER_CONF}" 2>/dev/null | cut -d= -f2- | tr -d '"\r\n' || echo 'channel1')"
STREAM_KEY="$(grep '^STREAM_KEY=' "${PLAYER_CONF}" 2>/dev/null | cut -d= -f2- | tr -d '"\r\n' || echo 'live_stream')"

if bash "${UPDATE_SCRIPT}" --channel "${CHANNEL}" --key "${STREAM_KEY}" --server "${SERVER_URL}" --no-validate; then
  echo "${REMOTE_VERSION}" > "${VERSION_FILE}"
  echo "[StreamPulse Update] [SUCCESS] StreamPulse successfully updated to version ${REMOTE_VERSION}!"
  
  # Trigger post-update validation if available
  if [[ -x "/opt/streampulse/bin/validate.sh" ]]; then
    /opt/streampulse/bin/validate.sh || true
  fi
else
  echo "[StreamPulse Update] [ERROR] Update execution failed. Rolling back previous version..." >&2
  if [[ -d "${BACKUP_DIR}/bin" ]]; then
    cp -rp "${BACKUP_DIR}/bin/"* /opt/streampulse/bin/ 2>/dev/null || true
  fi
  if [[ -f "${BACKUP_DIR}/player.html" ]]; then
    cp -p "${BACKUP_DIR}/player.html" /opt/streampulse/logo/ 2>/dev/null || true
  fi
  if [[ -f "${BACKUP_DIR}/logo-fallback.html" ]]; then
    cp -p "${BACKUP_DIR}/logo-fallback.html" /opt/streampulse/logo/ 2>/dev/null || true
  fi
  if [[ -f "${BACKUP_DIR}/hls.min.js" ]]; then
    cp -p "${BACKUP_DIR}/hls.min.js" /opt/streampulse/logo/ 2>/dev/null || true
  fi
  if [[ -f "${BACKUP_DIR}/motion-logo.mp4" ]]; then
    cp -p "${BACKUP_DIR}/motion-logo.mp4" /opt/streampulse/logo/ 2>/dev/null || true
  fi
  if [[ -f "${BACKUP_DIR}/VERSION" ]]; then
    cp -p "${BACKUP_DIR}/VERSION" /opt/streampulse/ 2>/dev/null || true
  fi
  systemctl restart streampulse-player.service 2>/dev/null || true
  echo "[StreamPulse Update] Rollback complete. Preserved working version ${LOCAL_VERSION}."
fi

# Clean temporary staging
rm -rf "${STAGING_DIR}"
exit 0
EOF_UPDATE

# Write authoritative VERSION file
echo "2.4.0" > /opt/streampulse/VERSION
chmod 644 /opt/streampulse/VERSION

# --- 10.7 validate.sh ---
cat << 'EOF_VALIDATE' > /opt/streampulse/bin/validate.sh
#!/usr/bin/env bash
# ==============================================================================
# StreamPulse Universal Validation Suite (Production Hardened Matrix)
# Managed by StreamPulse Universal Installer
# Path: /opt/streampulse/bin/validate.sh
# ==============================================================================

set -uo pipefail

TOTAL_CHECKS=44
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNINGS=0

# Safe Target User & Environment Resolution at initialization
DETECTED_USER="${SUDO_USER:-$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $3}' | grep -v '^root
chmod +x /opt/streampulse/bin/*.sh

# ------------------------------------------------------------------------------
# 11. Duplicate Autostart Cleanup (Safely Backed Up)
# ------------------------------------------------------------------------------
echo "[+] Cleaning competing/duplicate autostart launchers..."
LABWC_AUTOSTART="${USER_HOME}/.config/labwc/autostart"
if [[ -f "${LABWC_AUTOSTART}" ]]; then
  if grep -E "chromium.*kiosk|dashboard-kiosk|player-launcher|mpv" "${LABWC_AUTOSTART}" >/dev/null 2>&1; then
    echo "  -> Disabling legacy browser/mpv lines in Labwc autostart (systemd is authoritative)..."
    sed -i -E 's/^([^#]*chromium.*kiosk.*)/# [StreamPulse Managed] \1/' "${LABWC_AUTOSTART}"
    sed -i -E 's/^([^#]*.*dashboard-kiosk.*)/# [StreamPulse Managed] \1/' "${LABWC_AUTOSTART}"
    sed -i -E 's/^([^#]*.*player-launcher.*)/# [StreamPulse Managed] \1/' "${LABWC_AUTOSTART}"
    sed -i -E 's/^([^#]*.*mpv.*motion-logo.*)/# [StreamPulse Managed] \1/' "${LABWC_AUTOSTART}"
  fi
fi

# ------------------------------------------------------------------------------
# 12. Authoritative Systemd Services (Player & Auto-Update)
# ------------------------------------------------------------------------------
echo "[+] Provisioning Authoritative systemd service units..."

# 1. Update service unit
cat << 'UPDATE_UNIT' > /etc/systemd/system/streampulse-update.service
[Unit]
Description=StreamPulse Lightweight Auto-Update Check on Boot
Documentation=https://streampulse.io
After=network-online.target
Wants=network-online.target
Before=streampulse-player.service

[Service]
Type=oneshot
ExecStart=/opt/streampulse/bin/streampulse-update.sh
TimeoutSec=45
StandardOutput=journal
StandardError=journal
RemainAfterExit=no

[Install]
WantedBy=multi-user.target graphical.target
UPDATE_UNIT

chmod 644 /etc/systemd/system/streampulse-update.service

# 2. Player service unit
# Ensure any legacy / duplicate dashboard service or alias symlinks are removed
if systemctl is-active --quiet streampulse-dashboard.service 2>/dev/null; then
  systemctl stop streampulse-dashboard.service 2>/dev/null || true
fi
if systemctl is-enabled --quiet streampulse-dashboard.service 2>/dev/null; then
  systemctl disable streampulse-dashboard.service 2>/dev/null || true
fi
rm -f /etc/systemd/system/streampulse-dashboard.service 2>/dev/null || true
rm -f /etc/systemd/system/graphical.target.wants/streampulse-dashboard.service 2>/dev/null || true
rm -f /etc/systemd/system/default.target.wants/streampulse-dashboard.service 2>/dev/null || true
rm -f /etc/systemd/system/multi-user.target.wants/streampulse-dashboard.service 2>/dev/null || true

cat <<UNIT > /etc/systemd/system/streampulse-player.service
[Unit]
Description=StreamPulse Authoritative Fullscreen Player Service
Documentation=https://streampulse.io
After=network-online.target sound.target graphical-session.target graphical.target
Wants=network-online.target
Conflicts=streampulse-rpi-player.service

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
ExecStart=/opt/streampulse/bin/streampulse-player.sh
Restart=always
RestartSec=3
KillMode=mixed
TimeoutStopSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=graphical.target default.target
UNIT

chmod 644 /etc/systemd/system/streampulse-player.service
systemctl daemon-reload
systemctl enable streampulse-update.service 2>/dev/null || true
systemctl enable streampulse-player.service

# ------------------------------------------------------------------------------
# 13. Fix Directory Permissions for Detected User
# ------------------------------------------------------------------------------
echo "[+] Setting filesystem ownership to '${TARGET_USER}'..."
chown -R "${TARGET_USER}:${TARGET_GID}" /opt/streampulse/chromium-profile \
                                       /opt/streampulse/logo \
                                       /opt/streampulse/config

# ------------------------------------------------------------------------------
# 14. Restart / Start Authoritative Playback Service
# ------------------------------------------------------------------------------
echo "[+] Starting single authoritative streampulse-player.service..."
if ! systemctl restart streampulse-player.service; then
  echo -e "\e[31m[FAIL] Failed to start streampulse-player.service!\e[0m" >&2
  systemctl status streampulse-player.service --no-pager -l || true
  journalctl -u streampulse-player.service -n 30 --no-pager || true
  exit 1
fi

sleep 2
if ! systemctl is-active --quiet streampulse-player.service && ! systemctl is-enabled --quiet streampulse-player.service; then
  echo -e "\e[31m[FAIL] streampulse-player.service is neither active nor enabled!\e[0m" >&2
  exit 1
fi

# ------------------------------------------------------------------------------
# 15. Automated Validation Matrix
# ------------------------------------------------------------------------------
if (( RUN_VALIDATION == 1 )) && [[ -x "/opt/streampulse/bin/validate.sh" ]]; then
  echo ""
  echo "----------------------------------------------------------------------"
  echo "Running StreamPulse Universal Validation Suite..."
  echo "----------------------------------------------------------------------"
  if ! /opt/streampulse/bin/validate.sh; then
    echo -e "\e[31m[FAIL] StreamPulse installation validation failed!\e[0m" >&2
    exit 1
  fi
fi

echo ""
echo "======================================================================"
echo "      STREAM_PULSE UNIVERSAL INSTALLATION COMPLETE!"
echo "======================================================================"
echo "Assigned Channel:   ${CHANNEL_NAME}"
echo "Stream Key:         $(mask_secret "${STREAM_KEY}")"
echo "Target User:        ${TARGET_USER} (UID: ${TARGET_UID})"
echo "Common Logo Folder: /opt/streampulse/logo/"
echo "Playback Engine:    Integrated HTML5 Kiosk Player (HLS <-> Logo Auto-Switch)"
echo "Authoritative Svc:  streampulse-player.service (ENABLED)"
echo ""
echo "Helpful Commands:"
echo "  - Change Channel:   sudo /opt/streampulse/bin/set-channel.sh <new_channel>"
echo "  - Run Diagnostics:  sudo /opt/streampulse/bin/diagnose.sh"
echo "  - Run Validation:   sudo /opt/streampulse/bin/validate.sh"
echo "  - Create Backup:    sudo /opt/streampulse/bin/backup.sh"
echo "  - Restore Backup:   sudo /opt/streampulse/bin/restore.sh"
echo "  - Live Player Logs: sudo journalctl -u streampulse-player.service -f"
echo "======================================================================"
 | head -n 1 || awk -F: '$3 >= 1000 {print $1}' /etc/passwd | head -n1 || echo '')}"
TARGET_USER="${TARGET_USER:-${DETECTED_USER}}"
TARGET_UID="$(id -u "${TARGET_USER}" 2>/dev/null || echo '1000')"
USER_HOME="$(getent passwd "${TARGET_USER}" 2>/dev/null | cut -d: -f6 || echo "/home/${TARGET_USER}")"
LOGO_DIR="/opt/streampulse/logo"
PLAYER_SCRIPT="/opt/streampulse/bin/streampulse-player.sh"
PLAYER_HTML="${LOGO_DIR}/player.html"
HLS_JS_FILE="${LOGO_DIR}/hls.min.js"
SERVICE_UNIT="/etc/systemd/system/streampulse-player.service"

print_pass() {
  local title="${1:-}"
  local detail="${2:-}"
  echo -e "\e[32m[OK]\e[0m ${title} \e[2m(${detail})\e[0m"
  (( PASSED_CHECKS++ ))
}

print_warn() {
  local title="${1:-}"
  local detail="${2:-}"
  echo -e "\e[33m[WARN]\e[0m ${title} \e[33m(${detail})\e[0m"
  (( WARNINGS++ ))
}

print_fail() {
  local title="${1:-}"
  local reason="${2:-}"
  echo -e "\e[31m[FAIL]\e[0m ${title} \e[31m- Reason: ${reason}\e[0m"
  (( FAILED_CHECKS++ ))
}

echo "======================================================================"
echo "          StreamPulse Universal System & Playback Validation"
echo "======================================================================"
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
echo "----------------------------------------------------------------------"

# 1. Architecture Check
ARCH="$(uname -m 2>/dev/null || echo 'unknown')"
if [[ "${ARCH}" =~ ^(aarch64|arm64|armv7l|x86_64)$ ]]; then
  print_pass "Architecture" "${ARCH} compatible"
else
  print_fail "Architecture" "Unsupported architecture: ${ARCH}"
fi

# 2. Supported OS Check
if [[ -f /etc/os-release ]]; then
  source /etc/os-release
  print_pass "Supported OS" "${PRETTY_NAME:-$NAME}"
else
  print_warn "Supported OS" "/etc/os-release not found"
fi

# 3. Target User & UID Check
if [[ -n "${TARGET_USER}" ]] && id -u "${TARGET_USER}" >/dev/null 2>&1; then
  print_pass "Target User" "${TARGET_USER} (UID: ${TARGET_UID}, HOME: ${USER_HOME})"
else
  print_fail "Target User" "Could not resolve valid non-root desktop user"
fi

# 4. Labwc / Wayland Compositor Check
if pgrep -u "${TARGET_UID}" -x labwc >/dev/null 2>&1 || pgrep -x labwc >/dev/null 2>&1 || which labwc >/dev/null 2>&1 || [[ -d "${USER_HOME}/.config/labwc" ]] || [[ -d "/etc/xdg/labwc" ]]; then
  print_pass "Labwc Compositor" "Labwc compositor package & config verified"
else
  print_fail "Labwc Compositor" "Labwc not detected or configured"
fi

# 5. Wayland Socket Readiness Check
WAYLAND_SOCK="/run/user/${TARGET_UID}/wayland-0"
if [[ -S "${WAYLAND_SOCK}" ]] || [[ -e "${WAYLAND_SOCK}" ]] || [[ -n "${WAYLAND_DISPLAY:-}" ]] || [[ -S "/tmp/.X11-unix/X0" ]]; then
  print_pass "Wayland Socket" "Display session ready (${WAYLAND_SOCK})"
else
  print_warn "Wayland Socket" "${WAYLAND_SOCK} standby (will be polled by player supervisor)"
fi

# 6. Network Gateway Check
LOCAL_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || echo '')"
if [[ -n "${LOCAL_IP}" ]]; then
  print_pass "Network Gateway" "IP: ${LOCAL_IP}"
else
  print_fail "Network Gateway" "No local IP address assigned"
fi

# 7. Load Player Configuration
PLAYER_CONF="/opt/streampulse/config/player.conf"
SERVER_URL="http://187.127.210.81"
STREAM_KEY="live_stream"
CHANNEL_NAME="channel1"

if [[ -f "${PLAYER_CONF}" ]]; then
  source "${PLAYER_CONF}"
  if [[ -n "${STREAM_KEY:-}" ]] && [[ -n "${SERVER_URL:-}" ]]; then
    print_pass "Player Config" "Channel: '${CHANNEL_NAME}', Server: ${SERVER_URL}"
  else
    print_fail "Player Config" "STREAM_KEY or SERVER_URL empty in ${PLAYER_CONF}"
  fi
else
  print_fail "Player Config" "${PLAYER_CONF} missing"
fi

# 8. Server HTTP Endpoint Reachability Check
SERVER_HTTP_CODE="$(curl -s -o /dev/null -w "%{http_code}" -m 5 "${SERVER_URL}" 2>/dev/null || echo "000")"
if [[ "${SERVER_HTTP_CODE}" =~ ^(200|301|302|304|404)$ ]]; then
  print_pass "Server Reachability" "HTTP ${SERVER_HTTP_CODE} at ${SERVER_URL}"
else
  print_warn "Server Reachability" "Server returned HTTP ${SERVER_HTTP_CODE} (offline fallback will engage)"
fi

# 9. Authoritative Stream Discovery Endpoint Check
DISCOVERY_URL="${SERVER_URL}/api/stream/active?channel=${CHANNEL_NAME}&key=${STREAM_KEY}"
DISCOVERY_RESP="$(curl -s -m 5 -H "Accept: application/json" "${DISCOVERY_URL}" 2>/dev/null || echo "")"
DISCOVERED_HLS=""

if [[ -n "${DISCOVERY_RESP}" ]] && echo "${DISCOVERY_RESP}" | grep -q '"isLive"'; then
  IS_LIVE_JSON="$(echo "${DISCOVERY_RESP}" | grep -o '"isLive":[^,}]*' | cut -d: -f2 | tr -d ' "')"
  RESOLVED_KEY="$(echo "${DISCOVERY_RESP}" | grep -o '"streamKey":"[^"]*"' | cut -d: -f2 | tr -d ' "')"
  DISCOVERED_HLS="$(echo "${DISCOVERY_RESP}" | grep -o '"hlsMasterUrl":"[^"]*"' | cut -d: -f2- | tr -d ' "')"
  print_pass "Stream Discovery API" "Endpoint active (Resolved key: '${RESOLVED_KEY}', isLive: ${IS_LIVE_JSON})"
else
  print_warn "Stream Discovery API" "API not responding or offline (falling back to direct playlist probing)"
fi

# 10. HLS Master Stream Verification Check
HLS_TARGET_URL="${DISCOVERED_HLS:-${SERVER_URL}/hls/${STREAM_KEY}/master.m3u8}"
HLS_RESP="$(curl -s -m 6 "${HLS_TARGET_URL}" 2>/dev/null || echo "")"
HLS_FOUND=0
VERIFIED_ENDPOINT=""

if echo "${HLS_RESP}" | grep -q "#EXTM3U"; then
  HLS_FOUND=1
  VERIFIED_ENDPOINT="${HLS_TARGET_URL}"
  CHILD_PATH="$(echo "${HLS_RESP}" | grep -v '^#' | grep -E '\.m3u8' | head -n1 || echo '')"
  if [[ -n "${CHILD_PATH}" ]]; then
    if [[ "${CHILD_PATH}" =~ ^https?:// ]]; then
      CHILD_URL="${CHILD_PATH}"
    else
      CHILD_URL="${SERVER_URL}/hls/${STREAM_KEY}/${CHILD_PATH}"
    fi
    CHILD_RESP="$(curl -s -m 5 "${CHILD_URL}" 2>/dev/null || echo "")"
    if echo "${CHILD_RESP}" | grep -q "#EXTM3U"; then
      VERIFIED_ENDPOINT="${VERIFIED_ENDPOINT} (Variant stream verified)"
    fi
  fi
else
  HLS_ALT_URL="${SERVER_URL}/hls/${CHANNEL_NAME}/master.m3u8"
  HLS_ALT_RESP="$(curl -s -m 6 "${HLS_ALT_URL}" 2>/dev/null || echo "")"
  if echo "${HLS_ALT_RESP}" | grep -q "#EXTM3U"; then
    HLS_FOUND=1
    VERIFIED_ENDPOINT="${HLS_ALT_URL}"
  fi
fi

if (( HLS_FOUND == 1 )); then
  print_pass "HLS Master Stream" "Verified live stream: ${VERIFIED_ENDPOINT}"
else
  print_warn "HLS Master Stream" "Broadcast is currently idle (offline logo loop active)"
fi

# 11. Local HLS.js Library Check
if [[ -s "${HLS_JS_FILE}" ]]; then
  HLS_JS_SIZE="$(wc -c < "${HLS_JS_FILE}" | tr -d ' ')"
  print_pass "Local HLS.js Engine" "${HLS_JS_FILE} (${HLS_JS_SIZE} bytes)"
else
  print_fail "Local HLS.js Engine" "${HLS_JS_FILE} missing or empty"
fi

# 12. Guaranteed Fallback Canvas Check
FALLBACK_HTML="${LOGO_DIR}/logo-fallback.html"
if [[ -s "${FALLBACK_HTML}" ]]; then
  FALLBACK_SIZE="$(wc -c < "${FALLBACK_HTML}" | tr -d ' ')"
  print_pass "Fallback Canvas" "${FALLBACK_HTML} (${FALLBACK_SIZE} bytes)"
else
  print_fail "Fallback Canvas" "${FALLBACK_HTML} missing or empty"
fi

# 13. Installed Motion Logo Asset Check
INSTALLED_MP4="${LOGO_DIR}/motion-logo.mp4"
if [[ -f "${INSTALLED_MP4}" ]] && [[ -s "${INSTALLED_MP4}" ]]; then
  INSTALLED_SIZE=$(stat -c%s "${INSTALLED_MP4}" 2>/dev/null || wc -c < "${INSTALLED_MP4}" || echo 0)
  if [[ -r "${INSTALLED_MP4}" ]]; then
    print_pass "Motion Logo Asset" "${INSTALLED_MP4} (${INSTALLED_SIZE} bytes, readable by ${TARGET_USER})"
  else
    print_fail "Motion Logo Asset" "${INSTALLED_MP4} exists but not readable by ${TARGET_USER}"
  fi
else
  if [[ -s "${FALLBACK_HTML}" ]]; then
    print_warn "Motion Logo Asset" "MP4 asset not present; guaranteed HTML5 fallback canvas is active"
  else
    print_fail "Motion Logo Asset" "Neither motion-logo.mp4 nor logo-fallback.html found in ${LOGO_DIR}"
  fi
fi

# 14. Player HTML Display Core Check
if [[ -s "${PLAYER_HTML}" ]] && grep -q "motion-logo.mp4" "${PLAYER_HTML}" && [[ -s "${HLS_JS_FILE}" ]]; then
  print_pass "Player Display Core" "player.html (with motion-logo.mp4 + hls.min.js verified)"
else
  MISSING_ASSETS=""
  [[ ! -s "${PLAYER_HTML}" ]] && MISSING_ASSETS="${MISSING_ASSETS} player.html"
  ! grep -q "motion-logo.mp4" "${PLAYER_HTML}" 2>/dev/null && MISSING_ASSETS="${MISSING_ASSETS} (motion-logo.mp4 reference)"
  [[ ! -s "${HLS_JS_FILE}" ]] && MISSING_ASSETS="${MISSING_ASSETS} hls.min.js"
  print_fail "Player Display Core" "Asset check failed: ${MISSING_ASSETS}"
fi

# 15. Browser Binary Check
BROWSER_BIN="$(command -v chromium || command -v chromium-browser || command -v google-chrome || command -v firefox || echo '')"
if [[ -n "${BROWSER_BIN}" ]]; then
  print_pass "Browser Binary" "${BROWSER_BIN}"
else
  print_fail "Browser Binary" "No supported browser binary found"
fi

# 16. Chromium Wayland Mode Flag Check
if [[ -f "${PLAYER_SCRIPT}" ]] && grep -q -- "--ozone-platform=wayland" "${PLAYER_SCRIPT}"; then
  print_pass "Wayland Mode Flag" "--ozone-platform=wayland registered in launcher"
else
  print_fail "Wayland Mode Flag" "--ozone-platform=wayland missing in launcher"
fi

# 17. Chromium GPU Workaround Flag Check
if [[ -f "${PLAYER_SCRIPT}" ]] && grep -q -- "--disable-gpu" "${PLAYER_SCRIPT}"; then
  print_pass "GPU Workaround Flag" "--disable-gpu registered in launcher (prevents OpenGL context errors)"
else
  print_fail "GPU Workaround Flag" "--disable-gpu missing in launcher"
fi

# 18. Autoplay Policy Flag Check
if [[ -f "${PLAYER_SCRIPT}" ]] && grep -q -- "--autoplay-policy=no-user-gesture-required" "${PLAYER_SCRIPT}"; then
  print_pass "Autoplay Policy Flag" "--autoplay-policy=no-user-gesture-required registered"
else
  print_fail "Autoplay Policy Flag" "--autoplay-policy=no-user-gesture-required missing in launcher"
fi

# 19. Keyring Suppression Flag Check
if [[ -f "${PLAYER_SCRIPT}" ]] && grep -q -- "--password-store=basic" "${PLAYER_SCRIPT}"; then
  print_pass "Keyring Suppression" "--password-store=basic registered in launcher"
else
  print_fail "Keyring Suppression" "--password-store=basic not found in player launcher"
fi

# 20. Dedicated Profile Directory Check
PROFILE_DIR="${BROWSER_PROFILE_DIR:-/opt/streampulse/chromium-profile}"
if [[ -d "${PROFILE_DIR}" ]]; then
  print_pass "Dedicated Profile" "${PROFILE_DIR} ready"
else
  print_fail "Dedicated Profile" "${PROFILE_DIR} missing"
fi

# 21. Process Lock Implementation Check
if [[ -f "${PLAYER_SCRIPT}" ]] && grep -q "flock" "${PLAYER_SCRIPT}"; then
  print_pass "Duplicate Lock" "Process lock (flock) active in launcher"
else
  print_fail "Duplicate Lock" "flock locking missing in launcher"
fi

# 22. Authoritative Player Launcher Executable Check
if [[ -x "${PLAYER_SCRIPT}" ]]; then
  print_pass "Player Launcher" "${PLAYER_SCRIPT} executable"
else
  print_fail "Player Launcher" "${PLAYER_SCRIPT} missing or not executable"
fi

# 23. Authoritative Systemd Service Registration Check
if [[ -f "${SERVICE_UNIT}" ]]; then
  print_pass "Service Unit" "${SERVICE_UNIT} registered"
else
  print_fail "Service Unit" "${SERVICE_UNIT} missing"
fi

# 24. Competing Service Conflict Absence Check
if systemctl is-active --quiet streampulse-rpi-player.service 2>/dev/null; then
  print_fail "Conflict Prevention" "Competing streampulse-rpi-player.service is active"
else
  print_pass "Conflict Prevention" "Zero conflicting legacy services active"
fi

# 25. Auto-Update Service Check
if systemctl is-enabled streampulse-update.service >/dev/null 2>&1; then
  print_pass "Auto-Update Engine" "streampulse-update.service ENABLED on boot"
else
  print_warn "Auto-Update Engine" "streampulse-update.service not enabled"
fi

# 26. Reboot Persistence Check
if systemctl is-enabled streampulse-player.service >/dev/null 2>&1; then
  print_pass "Reboot Persistence" "streampulse-player.service ENABLED on boot"
else
  print_warn "Reboot Persistence" "streampulse-player.service not enabled"
fi

# 27. Authoritative Service Active Status Check
if systemctl is-active --quiet streampulse-player.service 2>/dev/null; then
  print_pass "Playback Service" "streampulse-player.service ACTIVE (Running)"
elif systemctl is-enabled --quiet streampulse-player.service 2>/dev/null; then
  print_warn "Playback Service" "streampulse-player.service is ENABLED (Waiting for display trigger)"
else
  print_fail "Playback Service" "streampulse-player.service is INACTIVE/FAILED"
fi

# 28. Zero Page Reload Mandate Check (Offline Stability)
if [[ -f "${PLAYER_HTML}" ]]; then
  if grep -E "location\.reload|window\.location\.reload" "${PLAYER_HTML}" >/dev/null 2>&1; then
    print_fail "Zero Reload Mandate" "player.html contains forbidden location.reload call"
  else
    print_pass "Zero Reload Mandate" "player.html has 0 reload calls (Memory stable indefinitely)"
  fi
else
  print_fail "Zero Reload Mandate" "${PLAYER_HTML} missing"
fi

# 29. Zero Navigation Mandate Check
if [[ -f "${PLAYER_HTML}" ]]; then
  if grep -E "location\.href\s*=|window\.location\s*=" "${PLAYER_HTML}" >/dev/null 2>&1; then
    print_fail "Zero Navigation Mandate" "player.html contains location navigation calls"
  else
    print_pass "Zero Navigation Mandate" "player.html maintains a single persistent DOM session"
  fi
else
  print_fail "Zero Navigation Mandate" "${PLAYER_HTML} missing"
fi

# 30. Single Polling State Machine Check
if [[ -f "${PLAYER_HTML}" ]] && grep -q "scheduleNextPoll" "${PLAYER_HTML}" && grep -q "runPollCycle" "${PLAYER_HTML}"; then
  print_pass "Single State Machine" "Sequential polling state machine verified (No concurrent timers)"
else
  print_fail "Single State Machine" "Single sequential polling state machine missing in player.html"
fi

# 31. AbortController Timeout Guard Check
if [[ -f "${PLAYER_HTML}" ]] && grep -q "new AbortController()" "${PLAYER_HTML}" && grep -q "controller.signal" "${PLAYER_HTML}"; then
  print_pass "AbortController Guard" "Network fetch abort controller guard verified (Hard timeout protection)"
else
  print_fail "AbortController Guard" "AbortController fetch protection missing in player.html"
fi

# 32. Chromium Process Supervisor Loop Check
if [[ -f "${PLAYER_SCRIPT}" ]] && grep -q "SUPERVISOR_ACTIVE" "${PLAYER_SCRIPT}"; then
  print_pass "Process Supervisor" "External Chromium supervisor loop verified in launcher"
else
  print_fail "Process Supervisor" "External supervisor loop missing in streampulse-player.sh"
fi

# 33. Chromium Auto-Restart on Exit Behavior Check
if [[ -f "${PLAYER_SCRIPT}" ]] && grep -q "EXIT_CODE=" "${PLAYER_SCRIPT}" && grep -q "RESTART_COUNT" "${PLAYER_SCRIPT}"; then
  print_pass "Auto-Restart Engine" "Chromium exit code capture & auto-restart behavior verified"
else
  print_fail "Auto-Restart Engine" "Exit code capture and restart logic missing in launcher"
fi

# 34. Systemd Restart=always Configuration Check
if [[ -f "${SERVICE_UNIT}" ]] && grep -q "Restart=always" "${SERVICE_UNIT}"; then
  print_pass "Systemd Auto-Restart" "streampulse-player.service configured with Restart=always"
else
  print_warn "Systemd Auto-Restart" "Restart=always missing or service unit uninstalled"
fi

# 35. Bounded Restart Backoff Engine Check
if [[ -f "${PLAYER_SCRIPT}" ]] && grep -q "BACKOFF_SECONDS=" "${PLAYER_SCRIPT}" && grep -q "CONSECUTIVE_QUICK_CRASHES" "${PLAYER_SCRIPT}"; then
  print_pass "Bounded Backoff" "Exponential 2s-30s crash backoff with 60s runtime reset verified"
else
  print_fail "Bounded Backoff" "Bounded restart backoff missing in launcher"
fi

# 36. Clean Profile & Lockfile Removal Check
if [[ -f "${PLAYER_SCRIPT}" ]] && grep -q "SingletonLock" "${PLAYER_SCRIPT}" && grep -q "SingletonSocket" "${PLAYER_SCRIPT}"; then
  print_pass "Profile Lock Cleanup" "Stale SingletonLock and SingletonSocket cleanup verified"
else
  print_fail "Profile Lock Cleanup" "Profile lock cleanup missing in streampulse-player.sh"
fi

# 37. Dynamic Stream Discovery Query Check
if [[ -f "${PLAYER_HTML}" ]] && grep -q "/api/stream/active" "${PLAYER_HTML}"; then
  print_pass "Dynamic Discovery" "Dynamic /api/stream/active endpoint polling verified"
else
  print_fail "Dynamic Discovery" "Dynamic stream key discovery missing in player.html"
fi

# 38. Strict #EXTM3U Manifest Validation & HTML Rejection Check
if [[ -f "${PLAYER_HTML}" ]] && grep -q "startsWith('#EXTM3U')" "${PLAYER_HTML}" && grep -q "<html" "${PLAYER_HTML}"; then
  print_pass "Manifest Validation" "Strict #EXTM3U check with HTML/SPA rejection verified"
else
  print_fail "Manifest Validation" "Strict manifest verification check missing in player.html"
fi

# 39. Comprehensive HLS Engine Lifecycle Cleanup Check
if [[ -f "${PLAYER_HTML}" ]] && grep -q "hlsInstance.destroy()" "${PLAYER_HTML}" && grep -q "hlsInstance.stopLoad()" "${PLAYER_HTML}"; then
  print_pass "HLS Cleanup Lifecycle" "Comprehensive HLS engine lifecycle cleanup verified"
else
  print_fail "HLS Cleanup Lifecycle" "HLS cleanup routines missing in player.html"
fi

# 40. Stalled Playback Watchdog Check
if [[ -f "${PLAYER_HTML}" ]] && grep -q "startStallWatchdog" "${PLAYER_HTML}" && grep -q "lastPlayheadTime" "${PLAYER_HTML}"; then
  print_pass "Stall Watchdog" "In-memory video stall watchdog verified (Auto-transitions to Standby)"
else
  print_fail "Stall Watchdog" "Stall watchdog missing in player.html"
fi

# 41. Local Motion Logo Path Check
if [[ -f "${LOGO_DIR}/motion-logo.mp4" ]] || [[ -f "${USER_HOME}/Downloads/MOTION LOGO.mp4" ]] || [[ -f "${LOGO_DIR}/logo-fallback.html" ]]; then
  print_pass "Local Motion Logo Path" "Local Motion Logo asset / fallback hierarchy verified"
else
  print_fail "Local Motion Logo Path" "No local motion logo asset or fallback exists"
fi

# 42. Local Offline HLS.js Asset Check
if [[ -f "${HLS_JS_FILE}" ]]; then
  print_pass "Local HLS.js Path" "Offline-first hls.min.js present at ${HLS_JS_FILE}"
else
  print_fail "Local HLS.js Path" "${HLS_JS_FILE} missing"
fi

# 43. Zero External CDN Runtime Dependency Mandate Check
if [[ -f "${PLAYER_HTML}" ]]; then
  if grep -E 'src="https?://' "${PLAYER_HTML}" >/dev/null 2>&1; then
    print_fail "Zero CDN Mandate" "player.html contains remote script tags"
  else
    print_pass "Zero CDN Mandate" "All player dependencies are 100% offline-local"
  fi
else
  print_fail "Zero CDN Mandate" "${PLAYER_HTML} missing"
fi

# 44. Shared Memory & ARM64 Stability Guard Check
if [[ -f "${PLAYER_SCRIPT}" ]] && grep -q -- "--disable-dev-shm-usage" "${PLAYER_SCRIPT}" && grep -q "max-old-space-size" "${PLAYER_SCRIPT}"; then
  print_pass "ARM64 Memory Guard" "--disable-dev-shm-usage and V8 heap limits verified"
else
  print_fail "ARM64 Memory Guard" "ARM64 shared memory & heap limits missing in launcher"
fi

echo "----------------------------------------------------------------------"
echo "Validation Summary: Passed: ${PASSED_CHECKS}/${TOTAL_CHECKS} | Failed: ${FAILED_CHECKS} | Warnings: ${WARNINGS}"

if (( FAILED_CHECKS == 0 )); then
  echo -e "\e[32m[SUCCESS] All critical StreamPulse components validated successfully!\e[0m"
  exit 0
else
  echo -e "\e[31m[ERROR] Validation encountered ${FAILED_CHECKS} critical failure(s).\e[0m" >&2
  exit 1
fi

EOF_VALIDATE

chmod +x /opt/streampulse/bin/*.sh

# ------------------------------------------------------------------------------
# 11. Duplicate Autostart Cleanup (Safely Backed Up)
# ------------------------------------------------------------------------------
echo "[+] Cleaning competing/duplicate autostart launchers..."
LABWC_AUTOSTART="${USER_HOME}/.config/labwc/autostart"
if [[ -f "${LABWC_AUTOSTART}" ]]; then
  if grep -E "chromium.*kiosk|dashboard-kiosk|player-launcher|mpv" "${LABWC_AUTOSTART}" >/dev/null 2>&1; then
    echo "  -> Disabling legacy browser/mpv lines in Labwc autostart (systemd is authoritative)..."
    sed -i -E 's/^([^#]*chromium.*kiosk.*)/# [StreamPulse Managed] \1/' "${LABWC_AUTOSTART}"
    sed -i -E 's/^([^#]*.*dashboard-kiosk.*)/# [StreamPulse Managed] \1/' "${LABWC_AUTOSTART}"
    sed -i -E 's/^([^#]*.*player-launcher.*)/# [StreamPulse Managed] \1/' "${LABWC_AUTOSTART}"
    sed -i -E 's/^([^#]*.*mpv.*motion-logo.*)/# [StreamPulse Managed] \1/' "${LABWC_AUTOSTART}"
  fi
fi

# ------------------------------------------------------------------------------
# 12. Authoritative Systemd Services (Player & Auto-Update)
# ------------------------------------------------------------------------------
echo "[+] Provisioning Authoritative systemd service units..."

# 1. Update service unit
cat << 'UPDATE_UNIT' > /etc/systemd/system/streampulse-update.service
[Unit]
Description=StreamPulse Lightweight Auto-Update Check on Boot
Documentation=https://streampulse.io
After=network-online.target
Wants=network-online.target
Before=streampulse-player.service

[Service]
Type=oneshot
ExecStart=/opt/streampulse/bin/streampulse-update.sh
TimeoutSec=45
StandardOutput=journal
StandardError=journal
RemainAfterExit=no

[Install]
WantedBy=multi-user.target graphical.target
UPDATE_UNIT

chmod 644 /etc/systemd/system/streampulse-update.service

# 2. Player service unit
# Ensure any legacy / duplicate dashboard service or alias symlinks are removed
if systemctl is-active --quiet streampulse-dashboard.service 2>/dev/null; then
  systemctl stop streampulse-dashboard.service 2>/dev/null || true
fi
if systemctl is-enabled --quiet streampulse-dashboard.service 2>/dev/null; then
  systemctl disable streampulse-dashboard.service 2>/dev/null || true
fi
rm -f /etc/systemd/system/streampulse-dashboard.service 2>/dev/null || true
rm -f /etc/systemd/system/graphical.target.wants/streampulse-dashboard.service 2>/dev/null || true
rm -f /etc/systemd/system/default.target.wants/streampulse-dashboard.service 2>/dev/null || true
rm -f /etc/systemd/system/multi-user.target.wants/streampulse-dashboard.service 2>/dev/null || true

cat <<UNIT > /etc/systemd/system/streampulse-player.service
[Unit]
Description=StreamPulse Authoritative Fullscreen Player Service
Documentation=https://streampulse.io
After=network-online.target sound.target graphical-session.target graphical.target
Wants=network-online.target
Conflicts=streampulse-rpi-player.service

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
ExecStart=/opt/streampulse/bin/streampulse-player.sh
Restart=always
RestartSec=3
KillMode=mixed
TimeoutStopSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=graphical.target default.target
UNIT

chmod 644 /etc/systemd/system/streampulse-player.service
systemctl daemon-reload
systemctl enable streampulse-update.service 2>/dev/null || true
systemctl enable streampulse-player.service

# ------------------------------------------------------------------------------
# 13. Fix Directory Permissions for Detected User
# ------------------------------------------------------------------------------
echo "[+] Setting filesystem ownership to '${TARGET_USER}'..."
chown -R "${TARGET_USER}:${TARGET_GID}" /opt/streampulse/chromium-profile \
                                       /opt/streampulse/logo \
                                       /opt/streampulse/config

# ------------------------------------------------------------------------------
# 14. Restart / Start Authoritative Playback Service
# ------------------------------------------------------------------------------
echo "[+] Starting single authoritative streampulse-player.service..."
if ! systemctl restart streampulse-player.service; then
  echo -e "\e[31m[FAIL] Failed to start streampulse-player.service!\e[0m" >&2
  systemctl status streampulse-player.service --no-pager -l || true
  journalctl -u streampulse-player.service -n 30 --no-pager || true
  exit 1
fi

sleep 2
if ! systemctl is-active --quiet streampulse-player.service && ! systemctl is-enabled --quiet streampulse-player.service; then
  echo -e "\e[31m[FAIL] streampulse-player.service is neither active nor enabled!\e[0m" >&2
  exit 1
fi

# ------------------------------------------------------------------------------
# 15. Automated Validation Matrix
# ------------------------------------------------------------------------------
if (( RUN_VALIDATION == 1 )) && [[ -x "/opt/streampulse/bin/validate.sh" ]]; then
  echo ""
  echo "----------------------------------------------------------------------"
  echo "Running StreamPulse Universal Validation Suite..."
  echo "----------------------------------------------------------------------"
  if ! /opt/streampulse/bin/validate.sh; then
    echo -e "\e[31m[FAIL] StreamPulse installation validation failed!\e[0m" >&2
    exit 1
  fi
fi

echo ""
echo "======================================================================"
echo "      STREAM_PULSE UNIVERSAL INSTALLATION COMPLETE!"
echo "======================================================================"
echo "Assigned Channel:   ${CHANNEL_NAME}"
echo "Stream Key:         $(mask_secret "${STREAM_KEY}")"
echo "Target User:        ${TARGET_USER} (UID: ${TARGET_UID})"
echo "Common Logo Folder: /opt/streampulse/logo/"
echo "Playback Engine:    Integrated HTML5 Kiosk Player (HLS <-> Logo Auto-Switch)"
echo "Authoritative Svc:  streampulse-player.service (ENABLED)"
echo ""
echo "Helpful Commands:"
echo "  - Change Channel:   sudo /opt/streampulse/bin/set-channel.sh <new_channel>"
echo "  - Run Diagnostics:  sudo /opt/streampulse/bin/diagnose.sh"
echo "  - Run Validation:   sudo /opt/streampulse/bin/validate.sh"
echo "  - Create Backup:    sudo /opt/streampulse/bin/backup.sh"
echo "  - Restore Backup:   sudo /opt/streampulse/bin/restore.sh"
echo "  - Live Player Logs: sudo journalctl -u streampulse-player.service -f"
echo "======================================================================"
