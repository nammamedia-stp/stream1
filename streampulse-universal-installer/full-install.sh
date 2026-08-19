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
    <video id="motion-video" class="kiosk-video" autoplay loop muted playsinline preload="auto">
      <source src="motion-logo.mp4" type="video/mp4">
      <source src="/opt/streampulse/logo/motion-logo.mp4" type="video/mp4">
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

      // Elements
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
        serverUrl + '/hls/' + streamKey + '/master.m3u8',
        serverUrl + '/hls/' + streamKey + '/Original/index.m3u8',
        serverUrl + '/hls/' + streamKey + '/index.m3u8',
        serverUrl + '/hls/' + channelName + '/master.m3u8',
        serverUrl + '/hls/' + channelName + '/Original/index.m3u8',
        serverUrl + '/hls/' + channelName + '/index.m3u8',
        serverUrl + '/hls/' + channelName + '.m3u8'
      ].filter((url, idx, arr) => url && arr.indexOf(url) === idx);

      // State Machine Variables
      let currentState = 'STANDBY'; // 'STANDBY' | 'LIVE'
      let activeHlsUrl = '';
      let hlsInstance = null;
      let pollIntervalTimer = null;
      let isProbing = false;
      let mp4Failed = false;
      let overlayFadeTimer = null;

      // Auto-Recovery & Stalled Video Watchdog Variables
      let consecutiveHlsFailures = 0;
      let lastPlayheadTime = -1;
      let stallCheckIntervalTimer = null;
      let stallCount = 0;
      const REFRESH_COOLDOWN_MS = 45000; // 45s minimum cooldown between controlled reloads

      // --------------------------------------------------
      // UI / Cursor Auto-Hide & Status Badge Helpers
      // --------------------------------------------------
      let mouseTimer = null;
      function resetCursor() {
        document.body.classList.remove('cursor-hidden');
        clearTimeout(mouseTimer);
        mouseTimer = setTimeout(() => {
          document.body.classList.add('cursor-hidden');
        }, 2500);
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
          overlayFadeTimer = setTimeout(() => {
            statusOverlay.style.opacity = '0';
          }, autoHideMs);
        }
      }

      // --------------------------------------------------
      // Controlled Last-Resort Full Page Refresh (Guarded)
      // --------------------------------------------------
      function triggerControlledReload(reason) {
        console.warn('[StreamPulse Player] Evaluating controlled last-resort page refresh. Reason:', reason);
        const now = Date.now();
        let lastReload = 0;
        try {
          lastReload = parseInt(sessionStorage.getItem('streampulse_last_reload') || '0', 10);
        } catch(e) {}

        if (now - lastReload < REFRESH_COOLDOWN_MS) {
          console.warn('[StreamPulse Player] Controlled refresh in cooldown window (' + Math.round((REFRESH_COOLDOWN_MS - (now - lastReload)) / 1000) + 's remaining). Falling back to offline logo + polling.');
          switchToOfflineStandby('Refresh Cooldown Active - ' + reason);
          return;
        }

        try {
          sessionStorage.setItem('streampulse_last_reload', now.toString());
        } catch(e) {}

        console.warn('[StreamPulse Player] [AUTO-REFRESH] Executing last-resort page reload now (' + reason + ')...');
        window.location.reload();
      }

      // --------------------------------------------------
      // Safe Video Playback Utilities
      // --------------------------------------------------
      function safePlay(videoEl) {
        if (!videoEl) return Promise.resolve();
        videoEl.muted = true;
        videoEl.playsInline = true;
        const playPromise = videoEl.play();
        if (playPromise !== undefined) {
          return playPromise.catch(err => {
            console.warn('[StreamPulse Player] Play rejected, retrying muted:', err.message);
            videoEl.muted = true;
            return videoEl.play().catch(e => {
              console.warn('[StreamPulse Player] Muted play also failed:', e.message);
            });
          });
        }
        return Promise.resolve();
      }

      // User interaction listener to allow unmuting audio
      function tryUnmute() {
        if (currentState === 'LIVE' && liveVideo) {
          liveVideo.muted = false;
        }
      }
      window.addEventListener('click', tryUnmute);
      window.addEventListener('touchstart', tryUnmute);
      window.addEventListener('keydown', tryUnmute);

      // --------------------------------------------------
      // Motion Logo & Fallback HTML Handling
      // --------------------------------------------------
      function showOfflineVisuals() {
        if (!mp4Failed) {
          console.log('[StreamPulse Player] [LOGO ACTIVATION] Displaying Motion Logo MP4 loop.');
          motionVideo.classList.remove('hidden');
          htmlFallback.classList.remove('active');
          motionVideo.currentTime = 0;
          safePlay(motionVideo).catch(() => {
            handleMp4Failure();
          });
        } else {
          console.log('[StreamPulse Player] [LOGO ACTIVATION] Displaying HTML/CSS animated fallback.');
          motionVideo.classList.add('hidden');
          htmlFallback.classList.add('active');
        }
      }

      function handleMp4Failure() {
        mp4Failed = true;
        console.warn('[StreamPulse Player] Motion Logo MP4 unavailable or unplayable. Activating HTML fallback.');
        motionVideo.classList.add('hidden');
        htmlFallback.classList.add('active');
        if (fallbackStatus) {
          fallbackStatus.textContent = 'Stream offline • Polling ' + serverUrl + '...';
        }
      }

      motionVideo.addEventListener('error', handleMp4Failure);
      motionVideo.addEventListener('stalled', () => {
        if (currentState === 'STANDBY' && motionVideo.paused && !mp4Failed) {
          safePlay(motionVideo);
        }
      });
      motionVideo.addEventListener('ended', () => {
        if (currentState === 'STANDBY' && !mp4Failed) {
          motionVideo.currentTime = 0;
          safePlay(motionVideo);
        }
      });

      // --------------------------------------------------
      // STATE A & C: Switch to Offline Standby (Logo / Fallback)
      // --------------------------------------------------
      function switchToOfflineStandby(reason) {
        if (currentState === 'STANDBY') return;
        currentState = 'STANDBY';
        console.log('[StreamPulse Player] [STREAM OFFLINE] Entering STANDBY state. Reason:', reason || 'Stream Dropped');

        // Stop stalled watchdog while offline
        stopStallWatchdog();

        // 1. Destroy active HLS instance
        if (hlsInstance) {
          try {
            hlsInstance.destroy();
          } catch (e) {}
          hlsInstance = null;
        }

        // 2. Hide & pause live video
        liveVideo.classList.remove('active');
        try {
          liveVideo.pause();
          liveVideo.removeAttribute('src');
          liveVideo.load();
        } catch (e) {}

        // 3. Show & play offline logo visuals
        showOfflineVisuals();

        // 4. Update status overlay
        updateStatus('offline', 'Stream Offline • Logo Active', 'Channel: ' + channelName, 0);

        // 5. Resume background polling for HLS
        startStreamPolling();
      }

      // --------------------------------------------------
      // Stalled Video Watchdog
      // --------------------------------------------------
      function startStallWatchdog() {
        stopStallWatchdog();
        lastPlayheadTime = liveVideo ? liveVideo.currentTime : -1;
        stallCount = 0;

        stallCheckIntervalTimer = setInterval(() => {
          if (currentState !== 'LIVE' || !liveVideo) return;

          // Check if video is playing and advancing
          const currentTime = liveVideo.currentTime;
          const isPaused = liveVideo.paused;
          const readyState = liveVideo.readyState;

          if (isPaused || readyState < 2 || (currentTime === lastPlayheadTime && currentTime > 0)) {
            stallCount++;
            console.warn('[StreamPulse Player] [STALLED VIDEO] Playback stall detected (stall ' + stallCount + '/5, readyState=' + readyState + ', paused=' + isPaused + ')');

            // Hierarchy Level 1: Attempt direct play
            safePlay(liveVideo);

            // Hierarchy Level 2: If stalled for > 2 ticks, attempt HLS media recovery
            if (stallCount === 2 && hlsInstance) {
              console.log('[StreamPulse Player] [HLS RECOVERY] Stalled watchdog invoking recoverMediaError...');
              try { hlsInstance.recoverMediaError(); safePlay(liveVideo); } catch(e) {}
            }

            // Hierarchy Level 3: If stalled for > 4 ticks, recreate HLS instance
            if (stallCount >= 4) {
              console.warn('[StreamPulse Player] [HLS RECREATION] Stalled watchdog recreating HLS instance...');
              consecutiveHlsFailures++;
              if (consecutiveHlsFailures >= 5) {
                triggerControlledReload('Persistent Stalled Playback');
                return;
              }
              const currentUrl = activeHlsUrl;
              if (hlsInstance) {
                try { hlsInstance.destroy(); } catch(e) {}
                hlsInstance = null;
              }
              switchToOfflineStandby('Watchdog Stalled Recovery');
              return;
            }
          } else {
            // Normal advancing playback: reset stall counter
            stallCount = 0;
            consecutiveHlsFailures = 0;
          }

          lastPlayheadTime = currentTime;
        }, 3500);
      }

      function stopStallWatchdog() {
        if (stallCheckIntervalTimer) {
          clearInterval(stallCheckIntervalTimer);
          stallCheckIntervalTimer = null;
        }
      }

      // --------------------------------------------------
      // STATE B & D: Switch to Live HLS
      // --------------------------------------------------
      function switchToLiveHls(validHlsUrl) {
        if (currentState === 'LIVE' && activeHlsUrl === validHlsUrl) return;
        currentState = 'LIVE';
        activeHlsUrl = validHlsUrl;
        console.log('[StreamPulse Player] [STREAM ONLINE] Entering LIVE state. HLS URL:', validHlsUrl);

        // Stop polling while actively playing live stream
        stopStreamPolling();

        if (hlsInstance) {
          try { hlsInstance.destroy(); } catch(e) {}
          hlsInstance = null;
        }

        const cacheBustUrl = validHlsUrl + (validHlsUrl.includes('?') ? '&' : '?') + '_t=' + Date.now();

        // If HLS.js is supported (Standard Chromium / Chrome / Firefox)
        if (window.Hls && window.Hls.isSupported()) {
          console.log('[StreamPulse Player] [HLS INITIALIZATION] Instantiating Hls.js engine...');
          hlsInstance = new window.Hls({
            enableWorker: true,
            lowLatencyMode: true,
            backBufferLength: 30,
            maxBufferLength: 10,
            liveBackBufferLength: 6,
            manifestLoadingTimeOut: 6000,
            manifestLoadingMaxRetry: 2,
            levelLoadingTimeOut: 6000,
            fragLoadingTimeOut: 8000
          });

          hlsInstance.on(window.Hls.Events.MEDIA_ATTACHED, function() {
            console.log('[StreamPulse Player] [HLS INITIALIZATION] Live media attached. Attempting autoplay...');
            safePlay(liveVideo);
          });

          hlsInstance.attachMedia(liveVideo);
          hlsInstance.loadSource(cacheBustUrl);

          hlsInstance.on(window.Hls.Events.MANIFEST_PARSED, function() {
            console.log('[StreamPulse Player] [HLS INITIALIZATION] Live manifest parsed. Starting playback...');
            safePlay(liveVideo);
          });

          hlsInstance.on(window.Hls.Events.FRAG_BUFFERED, function() {
            if (liveVideo.paused) {
              safePlay(liveVideo);
            }
          });

          hlsInstance.on(window.Hls.Events.ERROR, function(event, data) {
            console.warn('[StreamPulse Player] [HLS ERROR] Event error: type=' + data.type + ', details=' + data.details + ', fatal=' + data.fatal);

            if (data.fatal) {
              consecutiveHlsFailures++;
              if (data.type === window.Hls.ErrorTypes.MEDIA_ERROR) {
                console.log('[StreamPulse Player] [HLS RECOVERY] Fatal media error encountered. Invoking recoverMediaError()...');
                try {
                  hlsInstance.recoverMediaError();
                  safePlay(liveVideo);
                } catch (e) {
                  console.warn('[StreamPulse Player] [HLS RECOVERY] recoverMediaError failed. Switching to offline standby.');
                  if (consecutiveHlsFailures >= 5) {
                    triggerControlledReload('Fatal Media Error Exhaustion');
                  } else {
                    switchToOfflineStandby('Media Error Unrecoverable');
                  }
                }
              } else if (data.type === window.Hls.ErrorTypes.NETWORK_ERROR) {
                // Manifest / Fragment 404 or stream offline
                console.log('[StreamPulse Player] [HLS ERROR] Fatal network/404 error. Returning to offline logo + polling.');
                switchToOfflineStandby('Stream Endpoint Returned Error/404');
              } else {
                console.warn('[StreamPulse Player] [HLS ERROR] Other fatal HLS error encountered.');
                if (consecutiveHlsFailures >= 5) {
                  triggerControlledReload('Repeated Fatal HLS Errors');
                } else {
                  switchToOfflineStandby('Fatal HLS Error');
                }
              }
            }
          });
        } else if (liveVideo.canPlayType('application/vnd.apple.mpegurl')) {
          // Native Safari / HLS
          liveVideo.src = cacheBustUrl;
          safePlay(liveVideo);
        } else {
          console.error('[StreamPulse Player] No HLS playback engine available.');
          switchToOfflineStandby('HLS Engine Missing');
          return;
        }

        // When live video actually starts rendering frames
        function onLivePlaying() {
          liveVideo.removeEventListener('playing', onLivePlaying);
          if (currentState !== 'LIVE') return;

          console.log('[StreamPulse Player] [LIVE VIDEO ACTIVATION] Live stream rendering confirmed. Hiding offline logo.');

          // Reset failure and stall counters upon verified playback
          consecutiveHlsFailures = 0;
          stallCount = 0;

          // Transition visuals: Hide logo & show live stream
          motionVideo.classList.add('hidden');
          htmlFallback.classList.remove('active');
          try { motionVideo.pause(); } catch(e) {}

          liveVideo.classList.add('active');

          const h = liveVideo.videoHeight || 1080;
          updateStatus('live', 'Live • ' + h + 'p', 'Channel: ' + channelName, 6000);

          // Start stall watchdog to monitor continuous playback
          startStallWatchdog();
        }
        liveVideo.addEventListener('playing', onLivePlaying);
      }

      // Monitor live video stalls or errors
      liveVideo.addEventListener('error', function(e) {
        if (currentState === 'LIVE') {
          console.warn('[StreamPulse Player] Live video element error event fired. Falling back to logo.');
          switchToOfflineStandby('Live Video Element Error');
        }
      });

      // --------------------------------------------------
      // Robust Asynchronous HLS Stream Poller
      // --------------------------------------------------
      async function checkStreamAvailability() {
        if (isProbing || currentState === 'LIVE') return;
        isProbing = true;

        for (const testUrl of candidateHlsUrls) {
          try {
            const probeUrl = testUrl + (testUrl.includes('?') ? '&' : '?') + '_probe=' + Date.now();
            const res = await fetch(probeUrl, {
              method: 'GET',
              cache: 'no-store',
              headers: { 'Accept': 'application/x-mpegURL, application/vnd.apple.mpegurl, */*' }
            });

            if (res.ok && res.status === 200) {
              const text = await res.text();
              if (text && text.includes('#EXTM3U')) {
                console.log('[StreamPulse Player] [HLS PROBING] Active HLS Stream verified at:', testUrl);
                isProbing = false;
                switchToLiveHls(testUrl);
                return;
              }
            }
          } catch (err) {
            // Stream is offline or network connecting; continue gracefully
          }
        }

        isProbing = false;
      }

      function startStreamPolling() {
        stopStreamPolling();
        // Probe immediately, then every 2 seconds
        checkStreamAvailability();
        pollIntervalTimer = setInterval(checkStreamAvailability, 2000);
      }

      function stopStreamPolling() {
        if (pollIntervalTimer) {
          clearInterval(pollIntervalTimer);
          pollIntervalTimer = null;
        }
      }

      // --------------------------------------------------
      // Telemetry Heartbeat (Optional / Safe)
      // --------------------------------------------------
      setInterval(function sendHeartbeat() {
        if (!serverUrl || !serverUrl.startsWith('http')) return;
        fetch(serverUrl + '/api/rpi-player/status', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            channel: channelName,
            streamKey: streamKey,
            online_status: currentState === 'LIVE' ? 'playing' : 'offline_logo',
            current_resolution: (liveVideo.videoWidth || 1920) + 'x' + (liveVideo.videoHeight || 1080),
            engine: currentState === 'LIVE' ? 'HLS.js' : 'Motion Logo',
            player_version: '2.0.0-universal'
          })
        }).catch(() => {});
      }, 10000);

      // --------------------------------------------------
      // Initial Startup Execution
      // --------------------------------------------------
      // 1. Start Motion Logo loop immediately on boot
      showOfflineVisuals();
      updateStatus('offline', 'StreamPulse Standby', 'Channel: ' + channelName + ' • Probing stream...', 0);

      // 2. Begin probing HLS streams
      startStreamPolling();

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
# StreamPulse Authoritative Unified Fullscreen Player Controller
# Managed by StreamPulse Universal Installer
# Path: /opt/streampulse/bin/streampulse-player.sh
# ==============================================================================

set -uo pipefail

# ------------------------------------------------------------------------------
# 1. Strict Process Lock (Guarantees ONLY ONE player instance ever runs)
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
WAIT_NETWORK_TIMEOUT=30
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
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse] Booting Authoritative Fullscreen Player..."
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse] Assigned Channel: ${CHANNEL_NAME}"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse] Server Endpoint:  ${SERVER_URL}"
echo "======================================================================"

# ------------------------------------------------------------------------------
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

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse] Waiting for Wayland / Labwc display session readiness..."

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
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse] Graphical display session confirmed ready (Socket: ${WAYLAND_SOCKET}, Compositor: active) after ${DISPLAY_WAITED}s."
    break
  fi

  # Fallback check for X11 / Xwayland if xset succeeds
  if command -v xset >/dev/null 2>&1 && xset q >/dev/null 2>&1; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse] Display verified ready via xset after ${DISPLAY_WAITED}s."
    break
  fi

  if (( DISPLAY_WAITED >= MAX_DISPLAY_WAIT )); then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse] ERROR: Graphical display / Wayland session failed to become ready after ${MAX_DISPLAY_WAIT}s. Exiting." >&2
    exit 1
  fi

  if (( DISPLAY_WAITED % 5 == 0 && DISPLAY_WAITED > 0 )); then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse] Waiting for Wayland socket & compositor (${DISPLAY_WAITED}/${MAX_DISPLAY_WAIT}s)..."
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
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse] ERROR: No supported browser found." >&2
  exit 1
fi

# ------------------------------------------------------------------------------
# 8. Profile Directory & Clean Singleton Locks
# ------------------------------------------------------------------------------
mkdir -p "${BROWSER_PROFILE_DIR}"
rm -f "${BROWSER_PROFILE_DIR}/SingletonLock" \
      "${BROWSER_PROFILE_DIR}/SingletonSocket" \
      "${BROWSER_PROFILE_DIR}/SingletonCookie" \
      "${BROWSER_PROFILE_DIR}/lockfile" 2>/dev/null || true

# Terminate any previous browser process using this dedicated profile
pkill -f "${BROWSER_PROFILE_DIR}" 2>/dev/null || true
sleep 0.5

# ------------------------------------------------------------------------------
# 9. Assemble Safe Browser Arguments
# ------------------------------------------------------------------------------
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

# ------------------------------------------------------------------------------
# 10. Authoritative Target URL: Integrated HTML5 Kiosk Player
# ------------------------------------------------------------------------------
LOCAL_PLAYER="file:///opt/streampulse/logo/player.html"
TARGET_URL="${LOCAL_PLAYER}?channel=${CHANNEL_NAME}&server=${SERVER_URL}&key=${STREAM_KEY}"

# Support explicit custom non-default URLs if specifically configured
if [[ -n "${DASHBOARD_URL:-}" ]] && [[ "${DASHBOARD_URL}" =~ ^https?:// ]] && [[ "${DASHBOARD_URL}" != "http://187.127.210.81/" ]] && [[ "${DASHBOARD_URL}" != "http://187.127.210.81" ]] && [[ "${DASHBOARD_URL}" != *"127.0.0.1"* ]] && [[ "${DASHBOARD_URL}" != *"localhost"* ]]; then
  # Only use remote dashboard if not a video stream URL
  if [[ ! "${DASHBOARD_URL}" =~ \.m3u8 ]] && [[ ! "${DASHBOARD_URL}" =~ /hls/ ]]; then
    TARGET_URL="${DASHBOARD_URL}"
  fi
fi

LAUNCH_ARGS+=("${TARGET_URL}")

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse] Launching single authoritative fullscreen UI: ${TARGET_URL}"

# ------------------------------------------------------------------------------
# 11. Execute Authoritative Player (Supervised by systemd)
# ------------------------------------------------------------------------------
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

# --- 10.7 validate.sh ---
cat << 'EOF_VALIDATE' > /opt/streampulse/bin/validate.sh
#!/usr/bin/env bash
# ==============================================================================
# StreamPulse Universal Validation Suite
# Managed by StreamPulse Universal Installer
# Path: /opt/streampulse/bin/validate.sh
# ==============================================================================

set -uo pipefail

TOTAL_CHECKS=20
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

# 3. Target User Check
DETECTED_USER="${SUDO_USER:-$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $3}' | grep -v '^root$' | head -n 1 || awk -F: '$3 >= 1000 {print $1}' /etc/passwd | head -n1 || echo '')}"
TARGET_UID="$(id -u "${DETECTED_USER}" 2>/dev/null || echo '1000')"
if [[ -n "${DETECTED_USER}" ]] && id -u "${DETECTED_USER}" >/dev/null 2>&1; then
  print_pass "Target User" "${DETECTED_USER} (UID: ${TARGET_UID})"
else
  print_fail "Target User" "Could not resolve valid non-root desktop user"
fi

# 4. Labwc / Wayland Compositor Check
if pgrep -u "${TARGET_UID}" -x labwc >/dev/null 2>&1 || pgrep -x labwc >/dev/null 2>&1 || which labwc >/dev/null 2>&1 || [[ -d "/home/${DETECTED_USER}/.config/labwc" ]] || [[ -d "/etc/xdg/labwc" ]]; then
  print_pass "Labwc Compositor" "Labwc compositor package & config verified"
else
  print_fail "Labwc Compositor" "Labwc not detected or configured"
fi

# 5. Wayland Socket Readiness Check
WAYLAND_SOCK="/run/user/${TARGET_UID}/wayland-0"
if [[ -S "${WAYLAND_SOCK}" ]] || [[ -e "${WAYLAND_SOCK}" ]] || [[ -n "${WAYLAND_DISPLAY:-}" ]] || [[ -S "/tmp/.X11-unix/X0" ]]; then
  print_pass "Wayland Socket" "Display session ready (${WAYLAND_SOCK})"
else
  print_warn "Wayland Socket" "${WAYLAND_SOCK} standby (will be polled by player launcher)"
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

# 9. HLS Master Stream Verification Check
HLS_MASTER_URL="${SERVER_URL}/hls/${STREAM_KEY}/master.m3u8"
HLS_RESP="$(curl -s -m 6 "${HLS_MASTER_URL}" 2>/dev/null || echo "")"
HLS_FOUND=0
VERIFIED_ENDPOINT=""

if echo "${HLS_RESP}" | grep -q "#EXTM3U"; then
  HLS_FOUND=1
  VERIFIED_ENDPOINT="${HLS_MASTER_URL}"
  # Parse referenced child variant playlist if present
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
  # Check alternative candidate endpoints
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

# 10. Local HLS.js Library Check (Must be local, non-empty, zero CDN runtime dependency)
HLS_JS_FILE="/opt/streampulse/logo/hls.min.js"
if [[ -s "${HLS_JS_FILE}" ]]; then
  HLS_JS_SIZE="$(wc -c < "${HLS_JS_FILE}" | tr -d ' ')"
  print_pass "Local HLS.js Engine" "${HLS_JS_FILE} (${HLS_JS_SIZE} bytes)"
else
  print_fail "Local HLS.js Engine" "${HLS_JS_FILE} missing or empty"
fi

# 11. Browser Binary Check
BROWSER_BIN="$(command -v chromium || command -v chromium-browser || command -v google-chrome || command -v firefox || echo '')"
if [[ -n "${BROWSER_BIN}" ]]; then
  print_pass "Browser Binary" "${BROWSER_BIN}"
else
  print_fail "Browser Binary" "No supported browser binary found"
fi

# 12. Dedicated Profile Directory Check
PROFILE_DIR="${BROWSER_PROFILE_DIR:-/opt/streampulse/chromium-profile}"
if [[ -d "${PROFILE_DIR}" ]]; then
  print_pass "Dedicated Profile" "${PROFILE_DIR} ready"
else
  print_fail "Dedicated Profile" "${PROFILE_DIR} missing"
fi

# 13. Keyring Suppression Flag Check
if [[ -f /opt/streampulse/bin/streampulse-player.sh ]] && grep -q -- "--password-store=basic" /opt/streampulse/bin/streampulse-player.sh; then
  print_pass "Keyring Suppression" "--password-store=basic registered in launcher"
else
  print_fail "Keyring Suppression" "--password-store=basic not found in player launcher"
fi

# 14. Authoritative Player Launcher Check
if [[ -x /opt/streampulse/bin/streampulse-player.sh ]]; then
  print_pass "Player Launcher" "/opt/streampulse/bin/streampulse-player.sh executable"
else
  print_fail "Player Launcher" "/opt/streampulse/bin/streampulse-player.sh missing or not executable"
fi

# 15. Authoritative Systemd Service Registration Check
if [[ -f /etc/systemd/system/streampulse-player.service ]]; then
  print_pass "Service Unit" "/etc/systemd/system/streampulse-player.service registered"
else
  print_fail "Service Unit" "/etc/systemd/system/streampulse-player.service missing"
fi

# 16. Competing Service Conflict Absence Check
if systemctl is-active --quiet streampulse-rpi-player.service 2>/dev/null; then
  print_fail "Conflict Prevention" "Competing streampulse-rpi-player.service is active"
else
  print_pass "Conflict Prevention" "Zero conflicting legacy services active"
fi

# 17. Process Lock Implementation Check
if [[ -f /opt/streampulse/bin/streampulse-player.sh ]] && grep -q "flock" /opt/streampulse/bin/streampulse-player.sh; then
  print_pass "Duplicate Lock" "Process lock (flock) active in launcher"
else
  print_fail "Duplicate Lock" "flock locking missing in launcher"
fi

# 18. Common Logo Assets & Player HTML Check
LOGO_DIR="/opt/streampulse/logo"
if [[ -s "${LOGO_DIR}/player.html" ]]; then
  print_pass "Player HTML" "${LOGO_DIR}/player.html ready"
else
  print_fail "Player HTML" "${LOGO_DIR}/player.html missing or empty"
fi

# 19. Reboot Persistence & Service Auto-Start Check
if systemctl is-enabled streampulse-player.service >/dev/null 2>&1; then
  print_pass "Reboot Persistence" "streampulse-player.service ENABLED on boot"
else
  print_warn "Reboot Persistence" "streampulse-player.service not enabled"
fi

# 20. Authoritative Service Active Status Check
if systemctl is-active --quiet streampulse-player.service 2>/dev/null; then
  print_pass "Playback Service" "streampulse-player.service ACTIVE (Running)"
elif systemctl is-enabled --quiet streampulse-player.service 2>/dev/null; then
  print_warn "Playback Service" "streampulse-player.service is ENABLED (Waiting for display trigger)"
else
  print_fail "Playback Service" "streampulse-player.service is INACTIVE/FAILED"
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
# 12. Authoritative Systemd Service (ONE Single Fullscreen Service)
# ------------------------------------------------------------------------------
echo "[+] Provisioning Single Authoritative systemd service unit..."

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
