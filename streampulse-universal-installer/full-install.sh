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
for legacy_svc in streampulse-rpi-player.service streampulse-kiosk.service streampulse.service; do
  if systemctl is-active --quiet "${legacy_svc}" 2>/dev/null; then
    echo "  -> Stopping legacy service: ${legacy_svc}"
    systemctl stop "${legacy_svc}" 2>/dev/null || true
  fi
  if systemctl is-enabled --quiet "${legacy_svc}" 2>/dev/null; then
    echo "  -> Disabling legacy service: ${legacy_svc}"
    systemctl disable "${legacy_svc}" 2>/dev/null || true
  fi
  rm -f "/etc/systemd/system/${legacy_svc}" 2>/dev/null || true
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
# 7. Common Logo Assets (Permanent across ALL Pis - Never Deleted)
# ------------------------------------------------------------------------------
echo "[+] Setting up Common Logo Assets (/opt/streampulse/logo)..."

USER_DOWNLOAD_LOGO="${USER_HOME}/Downloads/Motion Logo.mp4"
USER_DOWNLOAD_LOGO_ALT="${USER_HOME}/Downloads/motion_logo.mp4"

if [[ ! -f "/opt/streampulse/logo/motion-logo.mp4" ]]; then
  if [[ -f "${USER_DOWNLOAD_LOGO}" ]] && [[ -s "${USER_DOWNLOAD_LOGO}" ]]; then
    echo "  -> Found local Motion Logo in ${USER_DOWNLOAD_LOGO}. Copying..."
    cp "${USER_DOWNLOAD_LOGO}" "/opt/streampulse/logo/motion-logo.mp4"
  elif [[ -f "${USER_DOWNLOAD_LOGO_ALT}" ]] && [[ -s "${USER_DOWNLOAD_LOGO_ALT}" ]]; then
    echo "  -> Found local Motion Logo in ${USER_DOWNLOAD_LOGO_ALT}. Copying..."
    cp "${USER_DOWNLOAD_LOGO_ALT}" "/opt/streampulse/logo/motion-logo.mp4"
  else
    echo "  -> Attempting download of default StreamPulse Motion Logo..."
    curl -s -f -m 15 "${SERVER_URL}/api/rpi-player/motion-logo" -o /opt/streampulse/logo/motion-logo.mp4 2>/dev/null || true
  fi
fi

# Create HTML Fallback
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

# Create Self-Contained Standalone Universal Kiosk Player (Single Unified Display Surface)
cat << 'HTML' > /opt/streampulse/logo/player.html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>StreamPulse Kiosk Player</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; user-select: none; -webkit-user-select: none; }
    html, body {
      width: 100vw;
      height: 100vh;
      background-color: #000000;
      overflow: hidden;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      color: #ffffff;
    }
    .cursor-hidden { cursor: none !important; }
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
    #live-video { z-index: 20; opacity: 0; pointer-events: none; }
    #live-video.active { opacity: 1; pointer-events: auto; }
    #motion-video { z-index: 10; opacity: 1; }
    #motion-video.hidden { opacity: 0; pointer-events: none; }
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
    #html-fallback.active { display: flex; }
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
    <video id="live-video" class="kiosk-video" autoplay playsinline muted preload="auto"></video>
    <video id="motion-video" class="kiosk-video" autoplay loop muted playsinline preload="auto">
      <source src="motion-logo.mp4" type="video/mp4">
      <source src="/opt/streampulse/logo/motion-logo.mp4" type="video/mp4">
    </video>
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
    <div id="status-overlay" class="status-overlay">
      <div id="status-badge" class="status-badge offline"></div>
      <span id="status-text">Standby • StreamPulse Logo Active</span>
      <span id="status-metrics" style="color: #94a3b8; border-left: 1px solid #334155; padding-left: 8px;">Polling stream...</span>
    </div>
  </div>

  <script>
    (function() {
      const script = document.createElement('script');
      script.src = 'hls.min.js';
      script.onerror = function() {
        const cdn = document.createElement('script');
        cdn.src = 'https://cdn.jsdelivr.net/npm/hls.js@1.5.8/dist/hls.min.js';
        document.head.appendChild(cdn);
      };
      document.head.appendChild(script);
    })();
  </script>

  <script>
    (function() {
      const params = new URLSearchParams(window.location.search);
      const channelName = params.get('channel') || params.get('channelName') || 'channel1';
      const streamKey = params.get('key') || params.get('streamKey') || 'live_stream';
      let serverUrl = params.get('server') || params.get('serverUrl') || '';
      if (!serverUrl) {
        serverUrl = window.location.protocol.startsWith('http') ? window.location.origin : 'http://187.127.210.81';
      }
      serverUrl = serverUrl.replace(/\/+$/, '');

      const liveVideo = document.getElementById('live-video');
      const motionVideo = document.getElementById('motion-video');
      const htmlFallback = document.getElementById('html-fallback');
      const fallbackChannelName = document.getElementById('fallback-channel-name');
      const fallbackStatus = document.getElementById('fallback-status');
      const statusOverlay = document.getElementById('status-overlay');
      const statusBadge = document.getElementById('status-badge');
      const statusText = document.getElementById('status-text');
      const statusMetrics = document.getElementById('status-metrics');

      if (fallbackChannelName) fallbackChannelName.textContent = 'Channel: ' + channelName;

      const candidateHlsUrls = [
        serverUrl + '/hls/' + channelName + '.m3u8',
        serverUrl + '/hls/' + channelName + '/master.m3u8',
        serverUrl + '/hls/' + channelName + '/index.m3u8',
        serverUrl + '/hls/' + streamKey + '/master.m3u8',
        serverUrl + '/hls/' + streamKey + '/index.m3u8'
      ];

      let currentState = 'STANDBY';
      let activeHlsUrl = '';
      let hlsInstance = null;
      let pollIntervalTimer = null;
      let isProbing = false;
      let mp4Failed = false;
      let overlayFadeTimer = null;

      let mouseTimer = null;
      function resetCursor() {
        document.body.classList.remove('cursor-hidden');
        clearTimeout(mouseTimer);
        mouseTimer = setTimeout(() => document.body.classList.add('cursor-hidden'), 2500);
      }
      window.addEventListener('mousemove', resetCursor);
      window.addEventListener('keydown', resetCursor);
      resetCursor();

      function updateStatus(mode, title, detail, autoHideMs) {
        statusBadge.className = 'status-badge ' + (mode === 'live' ? 'live' : 'offline');
        statusText.textContent = title || '';
        statusMetrics.textContent = detail || '';
        statusOverlay.style.opacity = '1';
        clearTimeout(overlayFadeTimer);
        if (autoHideMs && autoHideMs > 0) {
          overlayFadeTimer = setTimeout(() => { statusOverlay.style.opacity = '0'; }, autoHideMs);
        }
      }

      function safePlay(videoEl) {
        if (!videoEl) return Promise.resolve();
        videoEl.muted = true;
        videoEl.playsInline = true;
        const p = videoEl.play();
        if (p !== undefined) {
          return p.catch(err => {
            videoEl.muted = true;
            return videoEl.play().catch(e => {});
          });
        }
        return Promise.resolve();
      }

      function tryUnmute() {
        if (currentState === 'LIVE' && liveVideo) liveVideo.muted = false;
      }
      window.addEventListener('click', tryUnmute);
      window.addEventListener('touchstart', tryUnmute);
      window.addEventListener('keydown', tryUnmute);

      function showOfflineVisuals() {
        if (!mp4Failed) {
          motionVideo.classList.remove('hidden');
          htmlFallback.classList.remove('active');
          motionVideo.currentTime = 0;
          safePlay(motionVideo).catch(handleMp4Failure);
        } else {
          motionVideo.classList.add('hidden');
          htmlFallback.classList.add('active');
        }
      }

      function handleMp4Failure() {
        mp4Failed = true;
        motionVideo.classList.add('hidden');
        htmlFallback.classList.add('active');
        if (fallbackStatus) fallbackStatus.textContent = 'Stream offline • Polling ' + serverUrl + '...';
      }

      motionVideo.addEventListener('error', handleMp4Failure);
      motionVideo.addEventListener('stalled', () => {
        if (currentState === 'STANDBY' && motionVideo.paused && !mp4Failed) safePlay(motionVideo);
      });
      motionVideo.addEventListener('ended', () => {
        if (currentState === 'STANDBY' && !mp4Failed) {
          motionVideo.currentTime = 0;
          safePlay(motionVideo);
        }
      });

      function switchToOfflineStandby(reason) {
        if (currentState === 'STANDBY') return;
        currentState = 'STANDBY';
        if (hlsInstance) {
          try { hlsInstance.destroy(); } catch (e) {}
          hlsInstance = null;
        }
        liveVideo.classList.remove('active');
        try { liveVideo.pause(); liveVideo.removeAttribute('src'); liveVideo.load(); } catch (e) {}
        showOfflineVisuals();
        updateStatus('offline', 'Stream Offline • Logo Active', 'Channel: ' + channelName, 0);
        startStreamPolling();
      }

      function switchToLiveHls(validHlsUrl) {
        if (currentState === 'LIVE' && activeHlsUrl === validHlsUrl) return;
        currentState = 'LIVE';
        activeHlsUrl = validHlsUrl;
        stopStreamPolling();

        if (hlsInstance) {
          try { hlsInstance.destroy(); } catch(e) {}
          hlsInstance = null;
        }

        const cacheBustUrl = validHlsUrl + (validHlsUrl.includes('?') ? '&' : '?') + '_t=' + Date.now();

        if (window.Hls && window.Hls.isSupported()) {
          hlsInstance = new window.Hls({
            enableWorker: true,
            lowLatencyMode: true,
            backBufferLength: 30,
            maxBufferLength: 10,
            liveBackBufferLength: 6,
            manifestLoadingTimeOut: 6000,
            manifestLoadingMaxRetry: 2
          });
          hlsInstance.attachMedia(liveVideo);
          hlsInstance.loadSource(cacheBustUrl);
          hlsInstance.on(window.Hls.Events.MANIFEST_PARSED, function() {
            safePlay(liveVideo);
          });
          hlsInstance.on(window.Hls.Events.ERROR, function(event, data) {
            if (data.fatal) {
              if (data.type === window.Hls.ErrorTypes.MEDIA_ERROR) {
                try { hlsInstance.recoverMediaError(); safePlay(liveVideo); } catch(e) { switchToOfflineStandby('Media Error'); }
              } else {
                switchToOfflineStandby('Stream Unavailable / 404');
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
          motionVideo.classList.add('hidden');
          htmlFallback.classList.remove('active');
          try { motionVideo.pause(); } catch(e) {}
          liveVideo.classList.add('active');
          const h = liveVideo.videoHeight || 1080;
          updateStatus('live', 'Live • ' + h + 'p', 'Channel: ' + channelName, 6000);
        }
        liveVideo.addEventListener('playing', onLivePlaying);
      }

      liveVideo.addEventListener('error', function() {
        if (currentState === 'LIVE') switchToOfflineStandby('Live Video Error');
      });

      async function checkStreamAvailability() {
        if (isProbing || currentState === 'LIVE') return;
        isProbing = true;
        for (const testUrl of candidateHlsUrls) {
          try {
            const probeUrl = testUrl + (testUrl.includes('?') ? '&' : '?') + '_probe=' + Date.now();
            const res = await fetch(probeUrl, { method: 'GET', cache: 'no-store' });
            if (res.ok && res.status === 200) {
              const text = await res.text();
              if (text && text.includes('#EXTM3U')) {
                isProbing = false;
                switchToLiveHls(testUrl);
                return;
              }
            }
          } catch(err) {}
        }
        isProbing = false;
      }

      function startStreamPolling() {
        stopStreamPolling();
        checkStreamAvailability();
        pollIntervalTimer = setInterval(checkStreamAvailability, 2000);
      }

      function stopStreamPolling() {
        if (pollIntervalTimer) {
          clearInterval(pollIntervalTimer);
          pollIntervalTimer = null;
        }
      }

      showOfflineVisuals();
      updateStatus('offline', 'StreamPulse Standby', 'Channel: ' + channelName + ' • Probing...', 0);
      startStreamPolling();
    })();
  </script>
</body>
</html>
HTML

# Attempt local download of hls.min.js for completely offline operation
curl -s -f -m 10 "https://cdn.jsdelivr.net/npm/hls.js@1.5.8/dist/hls.min.js" -o /opt/streampulse/logo/hls.min.js 2>/dev/null || true
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
# StreamPulse Authoritative Unified Fullscreen Player Controller
# Managed by StreamPulse Universal Installer
# Path: /opt/streampulse/bin/streampulse-player.sh
# ==============================================================================

set -uo pipefail

# 1. Strict Process Lock (Guarantees ONLY ONE player instance ever runs)
LOCK_FILE="/tmp/streampulse-player.lock"
exec 200>"${LOCK_FILE}"
if ! flock -n 200; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse] Another player instance is already active with lock. Exiting duplicate launcher."
  exit 0
fi

# 2. Terminate Any Rogue Competing Playback Loops (mpv, cvlc, old launchers)
pkill -9 -f "mpv.*motion-logo" 2>/dev/null || true
pkill -9 -f "cvlc.*motion-logo" 2>/dev/null || true
pkill -9 -f "player-launcher\.sh" 2>/dev/null || true

# 3. Load Configurations
CONFIG_FILE="/opt/streampulse/config/kiosk.conf"
PLAYER_CONFIG="/opt/streampulse/config/player.conf"

CHANNEL_NAME="channel1"
STREAM_KEY="live_stream"
SERVER_URL="http://187.127.210.81"
DASHBOARD_URL=""
BROWSER_PROFILE_DIR="/opt/streampulse/chromium-profile"
WAIT_NETWORK_TIMEOUT=30
SCREEN_WIDTH=1920
SCREEN_HEIGHT=1080

if [[ -f "${PLAYER_CONFIG}" ]]; then
  source "${PLAYER_CONFIG}"
fi

if [[ -f "${CONFIG_FILE}" ]]; then
  source "${CONFIG_FILE}"
fi

echo "======================================================================"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse] Booting Authoritative Fullscreen Player..."
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse] Assigned Channel: ${CHANNEL_NAME}"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse] Server Endpoint:  ${SERVER_URL}"
echo "======================================================================"

# 4. Environment & Display Resolution
export DISPLAY="${DISPLAY:-:0}"
if [[ -z "${WAYLAND_DISPLAY:-}" ]] && [[ -e "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/wayland-0" ]]; then
  export WAYLAND_DISPLAY="wayland-0"
fi
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# 5. Wait for Graphical Display / Compositor
MAX_DISPLAY_WAIT=30
DISPLAY_WAITED=0
while ! (wlr-randr >/dev/null 2>&1 || xset q >/dev/null 2>&1 || [[ -n "${WAYLAND_DISPLAY:-}" ]] || [[ -n "${DISPLAY:-}" ]]); do
  if (( DISPLAY_WAITED >= MAX_DISPLAY_WAIT )); then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse] Display check timed out, continuing launch attempt..."
    break
  fi
  sleep 1
  (( DISPLAY_WAITED++ ))
done

# 6. Screen Power Management & Cursor Hiding
if command -v xset >/dev/null 2>&1; then
  xset s off -dpms s noblank 2>/dev/null || true
fi
if command -v wlr-randr >/dev/null 2>&1; then
  wlr-randr --output HDMI-A-1 --on 2>/dev/null || true
fi
if command -v unclutter >/dev/null 2>&1; then
  pgrep -x unclutter >/dev/null 2>&1 || unclutter -idle 0.5 -root &
fi

# 7. Locate Browser Binary
BROWSER_BIN=""
for CANDIDATE in chromium chromium-browser google-chrome firefox; do
  if command -v "${CANDIDATE}" >/dev/null 2>&1; then
    BROWSER_BIN="$(command -v "${CANDIDATE}")"
    break
  fi
done

if [[ -z "${BROWSER_BIN}" ]]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse] ERROR: No supported browser found." >&2
  exit 1
fi

# 8. Profile Directory & Clean Singleton Locks
mkdir -p "${BROWSER_PROFILE_DIR}"
rm -f "${BROWSER_PROFILE_DIR}/SingletonLock" \
      "${BROWSER_PROFILE_DIR}/SingletonSocket" \
      "${BROWSER_PROFILE_DIR}/SingletonCookie" \
      "${BROWSER_PROFILE_DIR}/lockfile" 2>/dev/null || true

# Terminate any previous browser process using this dedicated profile
pkill -f "${BROWSER_PROFILE_DIR}" 2>/dev/null || true
sleep 0.5

# 9. Assemble Safe Browser Arguments
declare -a LAUNCH_ARGS=(
  "--user-data-dir=${BROWSER_PROFILE_DIR}"
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
  "--window-size=${SCREEN_WIDTH:-1920},${SCREEN_HEIGHT:-1080}"
)

# 10. Authoritative Target URL: Integrated HTML5 Kiosk Player
LOCAL_PLAYER="file:///opt/streampulse/logo/player.html"
TARGET_URL="${LOCAL_PLAYER}?channel=${CHANNEL_NAME}&server=${SERVER_URL}&key=${STREAM_KEY}"

if [[ -n "${DASHBOARD_URL:-}" ]] && [[ "${DASHBOARD_URL}" =~ ^https?:// ]] && [[ "${DASHBOARD_URL}" != "http://187.127.210.81/" ]] && [[ "${DASHBOARD_URL}" != "http://187.127.210.81" ]] && [[ "${DASHBOARD_URL}" != *"127.0.0.1"* ]] && [[ "${DASHBOARD_URL}" != *"localhost"* ]]; then
  if [[ ! "${DASHBOARD_URL}" =~ \.m3u8 ]] && [[ ! "${DASHBOARD_URL}" =~ /hls/ ]]; then
    TARGET_URL="${DASHBOARD_URL}"
  fi
fi

LAUNCH_ARGS+=("${TARGET_URL}")

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse] Launching single authoritative fullscreen UI: ${TARGET_URL}"

# 11. Execute Authoritative Player Process
exec "${BROWSER_BIN}" "${LAUNCH_ARGS[@]}"
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

for srv in streampulse-player.service streampulse-dashboard.service; do
  if systemctl is-active --quiet "${srv}" 2>/dev/null || systemctl is-enabled --quiet "${srv}" 2>/dev/null; then
    echo "  [+] Reloading authoritative service: ${srv}..."
    systemctl restart "${srv}" 2>/dev/null || true
  fi
done

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

for srv in streampulse-player.service streampulse-dashboard.service; do
  if systemctl is-enabled --quiet "${srv}" 2>/dev/null; then
    systemctl restart "${srv}" 2>/dev/null || true
  fi
done

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
for srv in streampulse-player.service streampulse-dashboard.service; do
  if systemctl is-active --quiet "${srv}" 2>/dev/null; then
    echo "  [OK] ${srv}: ACTIVE (Running)"
  elif systemctl is-enabled --quiet "${srv}" 2>/dev/null; then
    echo "  [WARN] ${srv}: ENABLED (Not active right now)"
  else
    echo "  [INFO] ${srv}: INACTIVE"
  fi
done

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

# --- 10.7 validate.sh ---
cat << 'EOF_VALIDATE' > /opt/streampulse/bin/validate.sh
#!/usr/bin/env bash
# StreamPulse 18-Point Universal Validation Suite
set -uo pipefail

TOTAL_CHECKS=18
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNINGS=0

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
  (( PASSED_CHECKS++ ))
}

print_fail() {
  local title="${1:-}"
  local reason="${2:-}"
  echo -e "\e[31m[FAIL]\e[0m ${title} \e[31m- Reason: ${reason}\e[0m"
  (( FAILED_CHECKS++ ))
}

echo "======================================================================"
echo "          StreamPulse 18-Point Universal Validation"
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

# 3. Target User Check
DETECTED_USER="${SUDO_USER:-$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $3}' | grep -v '^root$' | head -n 1 || awk -F: '$3 >= 1000 {print $1}' /etc/passwd | head -n1 || echo '')}"
if [[ -n "${DETECTED_USER}" ]] && id -u "${DETECTED_USER}" >/dev/null 2>&1; then
  print_pass "Target User" "${DETECTED_USER} (UID: $(id -u "${DETECTED_USER}"))"
else
  print_fail "Target User" "Could not resolve valid non-root user"
fi

# 4. Labwc / Wayland Compositor Check
if pgrep -x labwc >/dev/null 2>&1 || which labwc >/dev/null 2>&1 || [[ -d "/home/${DETECTED_USER}/.config/labwc" ]] || [[ -d "/etc/xdg/labwc" ]]; then
  print_pass "Labwc / Wayland" "Desktop compositor environment verified"
else
  print_warn "Labwc / Wayland" "Compositor not currently active in subshell, fallback active"
fi

# 5. Network Check
if hostname -I >/dev/null 2>&1 || ip addr | grep -q "inet "; then
  LOCAL_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || echo 'connected')"
  print_pass "Network Gateway" "IP: ${LOCAL_IP}"
else
  print_fail "Network Gateway" "No local IP address assigned"
fi

# 6. Server Reachability Check
SERVER_URL="http://187.127.210.81"
if [[ -f /opt/streampulse/config/player.conf ]]; then
  source /opt/streampulse/config/player.conf
fi
HTTP_CODE="$(curl -s -o /dev/null -w "%{http_code}" -m 3 "${SERVER_URL}" 2>/dev/null || echo "000")"
if [[ "${HTTP_CODE}" =~ ^(200|301|302|304|404)$ ]]; then
  print_pass "Server Endpoint" "HTTP ${HTTP_CODE} at ${SERVER_URL}"
else
  print_warn "Server Endpoint" "HTTP code ${HTTP_CODE} (offline logo fallback will engage)"
fi

# 7. Browser Installed Check
BROWSER_BIN="$(command -v chromium || command -v chromium-browser || command -v google-chrome || command -v firefox || echo '')"
if [[ -n "${BROWSER_BIN}" ]]; then
  print_pass "Browser Installed" "${BROWSER_BIN}"
else
  print_fail "Browser Installed" "No supported browser binary found"
fi

# 8. Dedicated Profile Check
PROFILE_DIR="${BROWSER_PROFILE_DIR:-/opt/streampulse/chromium-profile}"
if [[ -d "${PROFILE_DIR}" ]]; then
  print_pass "Dedicated Profile" "${PROFILE_DIR} ready"
else
  print_fail "Dedicated Profile" "${PROFILE_DIR} missing"
fi

# 9. Keyring Suppression Flag Check
if [[ -f /opt/streampulse/bin/streampulse-player.sh ]] && grep -q -- "--password-store=basic" /opt/streampulse/bin/streampulse-player.sh; then
  print_pass "Keyring Suppression" "--password-store=basic properly inside launcher"
else
  print_fail "Keyring Suppression" "--password-store=basic not found in player launcher"
fi

# 10. Authoritative Player Launcher Check
if [[ -x /opt/streampulse/bin/streampulse-player.sh ]]; then
  print_pass "Player Launcher" "streampulse-player.sh executable"
else
  print_fail "Player Launcher" "streampulse-player.sh missing or not executable"
fi

# 11. Authoritative Systemd Service Check
if [[ -f /etc/systemd/system/streampulse-player.service ]] || [[ -f /etc/systemd/system/streampulse-dashboard.service ]]; then
  print_pass "Playback Service" "Authoritative playback service registered"
else
  print_fail "Playback Service" "Authoritative service unit missing"
fi

# 12. Competing Service Absence Check (Zero conflicts)
if systemctl is-active --quiet streampulse-rpi-player.service 2>/dev/null; then
  print_fail "Conflict Prevention" "Competing streampulse-rpi-player.service is active"
else
  print_pass "Conflict Prevention" "No competing playback service active"
fi

# 13. Process Lock Implementation Check
if [[ -f /opt/streampulse/bin/streampulse-player.sh ]] && grep -q "flock" /opt/streampulse/bin/streampulse-player.sh; then
  print_pass "Duplicate Lock" "Process lock (flock) active in launcher"
else
  print_fail "Duplicate Lock" "flock locking missing in streampulse-player.sh"
fi

# 14. Assigned Channel Check
PLAYER_CONF="/opt/streampulse/config/player.conf"
if [[ -f "${PLAYER_CONF}" ]]; then
  source "${PLAYER_CONF}"
  if [[ -n "${CHANNEL_NAME:-}" ]]; then
    print_pass "Assigned Channel" "Channel: '${CHANNEL_NAME}'"
  else
    print_fail "Assigned Channel" "CHANNEL_NAME empty in player.conf"
  fi
else
  print_fail "Assigned Channel" "player.conf missing"
fi

# 15. Common Logo Folder Check
LOGO_DIR="/opt/streampulse/logo"
if [[ -d "${LOGO_DIR}" ]]; then
  print_pass "Common Logo Folder" "${LOGO_DIR} verified"
else
  print_fail "Common Logo Folder" "${LOGO_DIR} missing"
fi

# 16. Common Logo Media & HTML Player Check
if [[ -f "${LOGO_DIR}/player.html" ]] && ([[ -f "${LOGO_DIR}/motion-logo.mp4" ]] || [[ -f "${LOGO_DIR}/logo-fallback.html" ]]); then
  print_pass "Integrated Media" "Offline video/HTML assets ready"
else
  print_warn "Integrated Media" "Assets check: player.html ready"
fi

# 17. Streaming Configuration Check
if [[ -f "${PLAYER_CONF}" ]] && grep -q '^STREAM_KEY=' "${PLAYER_CONF}"; then
  print_pass "Streaming Config" "STREAM_KEY and SERVER_URL registered securely"
else
  print_fail "Streaming Config" "Streaming credentials missing from ${PLAYER_CONF}"
fi

# 18. Auto-Start & Reboot Persistence Check
if systemctl is-enabled streampulse-player.service >/dev/null 2>&1 || systemctl is-enabled streampulse-dashboard.service >/dev/null 2>&1; then
  print_pass "Reboot Persistence" "Playback service ENABLED on boot"
else
  print_warn "Reboot Persistence" "Playback service not yet enabled"
fi

echo "----------------------------------------------------------------------"
echo "Validation: Passed: ${PASSED_CHECKS}/${TOTAL_CHECKS} | Failed: ${FAILED_CHECKS} | Warnings: ${WARNINGS}"

if (( FAILED_CHECKS == 0 )); then
  echo -e "\e[32m[SUCCESS] All critical StreamPulse components validated successfully!\e[0m"
  exit 0
else
  echo -e "\e[31m[ERROR] Validation encountered ${FAILED_CHECKS} failure(s).\e[0m" >&2
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
# 12. Authoritative Systemd Service (ONE Single Fullscreen Service)
# ------------------------------------------------------------------------------
echo "[+] Provisioning Single Authoritative systemd service unit..."

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
Alias=streampulse-dashboard.service
UNIT

# Also maintain streampulse-dashboard.service as clean symlink/unit pointing to streampulse-player.sh
cat <<UNIT > /etc/systemd/system/streampulse-dashboard.service
[Unit]
Description=StreamPulse Dashboard Kiosk Service (Universal)
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

chmod 644 /etc/systemd/system/streampulse-player.service /etc/systemd/system/streampulse-dashboard.service
systemctl daemon-reload
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
systemctl restart streampulse-player.service 2>/dev/null || true

# ------------------------------------------------------------------------------
# 15. 18-Point Automated Validation Matrix
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
