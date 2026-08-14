#!/usr/bin/env bash
# ==============================================================================
# StreamPulse Kiosk Launcher - Controlled Single Browser Launcher
# Location: /opt/streampulse/bin/dashboard-kiosk.sh
# Target: Debian 13 (Trixie) ARM64 / Labwc Wayland Session
# ==============================================================================

set -uo pipefail

LOG_FILE="/var/log/streampulse-kiosk.log"
CONFIG_FILE="/opt/streampulse/config/kiosk.conf"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || LOG_FILE="/tmp/streampulse-kiosk.log"

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [KioskLauncher] $1"
  echo "$msg"
  echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

log "========================================================"
log "Starting StreamPulse Dashboard Kiosk Launcher"
log "========================================================"

# Source config if present
DASHBOARD_URL="http://187.127.210.81/"
KIOSK_USER="himakara"
BROWSER_PROFILE_DIR="/opt/streampulse/chromium-profile"
BROWSER_ENGINE="auto"
HIDE_CURSOR=1
DISABLE_SCREEN_BLANKING=1
WAIT_NETWORK_TIMEOUT=30
RESTART_DELAY_SEC=3

if [ -f "$CONFIG_FILE" ]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
  log "Loaded configuration from $CONFIG_FILE"
fi

# Detect current session / target user
RUNNING_USER="$(whoami 2>/dev/null || echo "$KIOSK_USER")"
if [ "$RUNNING_USER" = "root" ]; then
  TARGET_USER="${SUDO_USER:-$KIOSK_USER}"
else
  TARGET_USER="$RUNNING_USER"
fi
TARGET_UID="$(id -u "$TARGET_USER" 2>/dev/null || echo "1000")"
TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6 || echo "/home/$TARGET_USER")"

log "Target User: $TARGET_USER (UID: $TARGET_UID, Home: $TARGET_HOME)"

# Set Display / Session environment
export DISPLAY="${DISPLAY:-:0}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$TARGET_UID}"

# Ensure profile directory exists with proper permissions
mkdir -p "$BROWSER_PROFILE_DIR" 2>/dev/null || true
chown -R "$TARGET_USER:$TARGET_USER" "$BROWSER_PROFILE_DIR" 2>/dev/null || true

# Strict Duplicate Prevention: check if browser is already running with our dedicated profile
if pgrep -f "user-data-dir=$BROWSER_PROFILE_DIR" >/dev/null 2>&1; then
  log "WARNING: An existing Chromium instance using profile $BROWSER_PROFILE_DIR is already running."
  log "Exiting new launch request to avoid duplicate windows."
  exit 0
fi

# Clean up stale Chromium lock files inside the dedicated profile ONLY
rm -f "$BROWSER_PROFILE_DIR"/Singleton* 2>/dev/null || true
rm -f "$BROWSER_PROFILE_DIR"/Default/Singleton* 2>/dev/null || true

# Disable screen blanking & DPMS if tools available
if [ "$DISABLE_SCREEN_BLANKING" = "1" ]; then
  if command -v xset >/dev/null 2>&1; then
    xset s off 2>/dev/null || true
    xset -dpms 2>/dev/null || true
    xset s noblank 2>/dev/null || true
  fi
  if command -v wlopm >/dev/null 2>&1; then
    wlopm --on '*' 2>/dev/null || true
  fi
fi

# Hide mouse cursor if unclutter is installed
if [ "$HIDE_CURSOR" = "1" ] && command -v unclutter >/dev/null 2>&1; then
  if ! pgrep -x unclutter >/dev/null 2>&1; then
    unclutter -idle 2 -root &
    log "Started unclutter (idle cursor hiding)."
  fi
fi

# Network Connectivity Probe
log "Testing network connectivity and reachability for $DASHBOARD_URL..."
NET_ELAPSED=0
while true; do
  if curl -s --connect-timeout 2 --max-time 3 "$DASHBOARD_URL" >/dev/null 2>&1; then
    log "Network and Dashboard reachable after ${NET_ELAPSED}s."
    break
  fi

  if [ "$NET_ELAPSED" -ge "$WAIT_NETWORK_TIMEOUT" ]; then
    log "Notice: Reached $WAIT_NETWORK_TIMEOUT seconds waiting for dashboard, proceeding to launch browser with retry loop."
    break
  fi

  sleep 2
  NET_ELAPSED=$((NET_ELAPSED + 2))
done

# Detect Installed Browser
DETECTED_BROWSER=""
if [ "$BROWSER_ENGINE" = "auto" ] || [ "$BROWSER_ENGINE" = "chromium" ]; then
  if command -v chromium >/dev/null 2>&1; then
    DETECTED_BROWSER="chromium"
  elif command -v chromium-browser >/dev/null 2>&1; then
    DETECTED_BROWSER="chromium-browser"
  elif [ -x /usr/bin/chromium ]; then
    DETECTED_BROWSER="/usr/bin/chromium"
  elif [ -x /usr/bin/chromium-browser ]; then
    DETECTED_BROWSER="/usr/bin/chromium-browser"
  fi
fi

# Fallback to Firefox if Chromium is unavailable
if [ -z "$DETECTED_BROWSER" ]; then
  if command -v firefox-esr >/dev/null 2>&1; then
    DETECTED_BROWSER="firefox-esr"
  elif command -v firefox >/dev/null 2>&1; then
    DETECTED_BROWSER="firefox"
  fi
fi

if [ -z "$DETECTED_BROWSER" ]; then
  log "ERROR: No supported web browser (Chromium or Firefox) found on system path!"
  exit 1
fi

log "Selected Browser: $DETECTED_BROWSER"

# Build Browser Arguments
# CRITICAL: --password-store=basic MUST be inside the browser arguments to suppress GNOME/KDE keyring popups.
if [[ "$DETECTED_BROWSER" == *"chromium"* ]]; then
  LAUNCH_ARGS=(
    "--user-data-dir=$BROWSER_PROFILE_DIR"
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
    "--disable-gpu"
    "--window-position=0,0"
    "--window-size=1920,1080"
  )
else
  # Firefox flags
  LAUNCH_ARGS=(
    "--kiosk"
    "--private-window"
    "--profile" "$BROWSER_PROFILE_DIR"
  )
fi

log "Launching Browser: $DETECTED_BROWSER ${LAUNCH_ARGS[*]} $DASHBOARD_URL"

# Main Execution Loop with automatic crash recovery
while true; do
  log "Starting browser process..."
  "$DETECTED_BROWSER" "${LAUNCH_ARGS[@]}" "$DASHBOARD_URL" >> "$LOG_FILE" 2>&1 || true
  EXIT_CODE=$?
  log "Browser exited with code $EXIT_CODE. Restarting in $RESTART_DELAY_SEC seconds..."
  sleep "$RESTART_DELAY_SEC"

  # Clean stale lock files before restart
  rm -f "$BROWSER_PROFILE_DIR"/Singleton* 2>/dev/null || true
  rm -f "$BROWSER_PROFILE_DIR"/Default/Singleton* 2>/dev/null || true
done
