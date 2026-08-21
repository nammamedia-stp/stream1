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
  "--js-flags=--max-old-space-size=512"
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
TARGET_URL="${LOCAL_PLAYER}?channel=${CHANNEL_NAME}&server=${SERVER_URL}&key=${STREAM_KEY}"

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
