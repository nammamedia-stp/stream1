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
# 4. Environment & Display Resolution
# ------------------------------------------------------------------------------
export DISPLAY="${DISPLAY:-:0}"
if [[ -z "${WAYLAND_DISPLAY:-}" ]] && [[ -e "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/wayland-0" ]]; then
  export WAYLAND_DISPLAY="wayland-0"
fi
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# ------------------------------------------------------------------------------
# 5. Wait for Graphical Display / Compositor
# ------------------------------------------------------------------------------
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
