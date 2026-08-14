#!/usr/bin/env bash
# ==============================================================================
# StreamPulse Dashboard Kiosk Authoritative Launcher
# Managed by StreamPulse Universal Installer
# Path: /opt/streampulse/bin/dashboard-kiosk.sh
# ==============================================================================

set -uo pipefail

CONFIG_FILE="/opt/streampulse/config/kiosk.conf"
PLAYER_CONFIG="/opt/streampulse/config/player.conf"

# Load Kiosk Configuration
if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck source=/dev/null
  source "${CONFIG_FILE}"
else
  DASHBOARD_URL="http://187.127.210.81/"
  BROWSER_PROFILE_DIR="/opt/streampulse/chromium-profile"
  BROWSER_ENGINE="auto"
  WAIT_NETWORK_TIMEOUT=30
  RESTART_DELAY_SEC=3
fi

# Load Player Configuration for channel context if available
if [[ -f "${PLAYER_CONFIG}" ]]; then
  # shellcheck source=/dev/null
  source "${PLAYER_CONFIG}"
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse] Initializing Authoritative Dashboard Kiosk..."
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse] Assigned Channel: ${CHANNEL_NAME:-default}"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse] Target URL: ${DASHBOARD_URL}"

# 1. Environment & Display Resolution
export DISPLAY="${DISPLAY:-:0}"
if [[ -z "${WAYLAND_DISPLAY:-}" ]] && [[ -e "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/wayland-0" ]]; then
  export WAYLAND_DISPLAY="wayland-0"
fi
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# 2. Wait for Display / Graphical Compositor
MAX_DISPLAY_WAIT=30
DISPLAY_WAITED=0
while ! (wlr-randr >/dev/null 2>&1 || xset q >/dev/null 2>&1 || [[ -n "${WAYLAND_DISPLAY:-}" ]] || [[ -n "${DISPLAY:-}" ]]); do
  if (( DISPLAY_WAITED >= MAX_DISPLAY_WAIT )); then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse] Warning: Display server check timed out, attempting launch anyway..."
    break
  fi
  sleep 1
  (( DISPLAY_WAITED++ ))
done

# 3. Disable Screen Blanking / DPMS Power Saving
if command -v xset >/dev/null 2>&1; then
  xset s off -dpms s noblank 2>/dev/null || true
fi
if command -v wlr-randr >/dev/null 2>&1; then
  # Labwc Wayland DPMS keepalive
  wlr-randr --output HDMI-A-1 --on 2>/dev/null || true
fi

# 4. Hide Cursor if unclutter is available
if command -v unclutter >/dev/null 2>&1; then
  pgrep -x unclutter >/dev/null 2>&1 || unclutter -idle 0.5 -root &
fi

# 5. Network & Target Reachability Wait
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse] Verifying network and endpoint reachability..."
TIMEOUT_SEC=${WAIT_NETWORK_TIMEOUT:-30}
ELAPSED=0
REACHABLE=0

while (( ELAPSED < TIMEOUT_SEC )); do
  if curl -s -f -m 2 "${DASHBOARD_URL}" >/dev/null 2>&1 || curl -s -m 2 -I "${DASHBOARD_URL}" >/dev/null 2>&1; then
    REACHABLE=1
    break
  fi
  sleep 1
  (( ELAPSED++ ))
done

if (( REACHABLE == 1 )); then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse] Dashboard endpoint is REACHABLE."
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse] Warning: Dashboard endpoint not yet reachable (${DASHBOARD_URL}). Launching browser with offline resilience..."
fi

# 6. Locate Browser Binary
BROWSER_BIN=""
for CANDIDATE in chromium chromium-browser google-chrome firefox; do
  if command -v "${CANDIDATE}" >/dev/null 2>&1; then
    BROWSER_BIN="$(command -v "${CANDIDATE}")"
    break
  fi
done

if [[ -z "${BROWSER_BIN}" ]]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse] ERROR: No supported browser found (checked chromium, chromium-browser, google-chrome, firefox)." >&2
  exit 1
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse] Using browser: ${BROWSER_BIN}"

# 7. Dedicated Profile Initialization & Lock Cleanup
mkdir -p "${BROWSER_PROFILE_DIR}"
# Clean stale singleton locks to prevent "Chromium did not shut down cleanly" or multi-instance blockage
rm -f "${BROWSER_PROFILE_DIR}/SingletonLock" \
      "${BROWSER_PROFILE_DIR}/SingletonSocket" \
      "${BROWSER_PROFILE_DIR}/SingletonCookie" \
      "${BROWSER_PROFILE_DIR}/lockfile" 2>/dev/null || true

# 8. Prevent duplicate running browser instances for this dedicated profile
pkill -f "${BROWSER_PROFILE_DIR}" 2>/dev/null || true
sleep 0.5

# 9. Assemble Safe Browser Arguments
# CRITICAL: --password-store=basic is an argument to Chromium, NOT a shell command
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

# Append extra flags if defined in kiosk.conf
if [[ -n "${CHROMIUM_EXTRA_FLAGS:-}" ]]; then
  for flag in "${CHROMIUM_EXTRA_FLAGS[@]}"; do
    # avoid duplicates
    if [[ ! " ${LAUNCH_ARGS[*]} " =~ " ${flag} " ]]; then
      LAUNCH_ARGS+=("${flag}")
    fi
  done
fi

# Determine target URL:
# If DASHBOARD_URL is empty, points to an .m3u8 stream, /hls/, local player, or if external dashboard is unreachable:
LOCAL_PLAYER="file:///opt/streampulse/logo/player.html"
TARGET_URL="${DASHBOARD_URL:-}"

if [[ -z "${TARGET_URL}" ]] || [[ "${TARGET_URL}" =~ \.m3u8 ]] || [[ "${TARGET_URL}" =~ /hls/ ]] || [[ "${TARGET_URL}" == "file://"* ]] || [[ "${TARGET_URL}" == *"/logo/player.html"* ]]; then
  TARGET_URL="${LOCAL_PLAYER}?channel=${CHANNEL_NAME:-channel1}&server=${SERVER_URL:-http://187.127.210.81}&key=${STREAM_KEY:-live_stream}"
elif [[ "${TARGET_URL}" =~ ^https?:// ]]; then
  # If remote HTTP URL, check if reachable. If unreachable or 404/5xx, fallback to local resilient player
  HTTP_STATUS="$(curl -s -o /dev/null -w "%{http_code}" -m 3 "${TARGET_URL}" 2>/dev/null || echo "000")"
  if [[ ! "${HTTP_STATUS}" =~ ^(200|301|302|304)$ ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse] DASHBOARD_URL returned HTTP ${HTTP_STATUS} (offline/unavailable). Launching local resilient player..."
    TARGET_URL="${LOCAL_PLAYER}?channel=${CHANNEL_NAME:-channel1}&server=${SERVER_URL:-http://187.127.210.81}&key=${STREAM_KEY:-live_stream}"
  fi
fi

# Append target dashboard URL
LAUNCH_ARGS+=("${TARGET_URL}")

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse] Launching Kiosk Browser (${TARGET_URL}) with dedicated profile and basic keyring suppression..."

# 10. Execute Browser (Supervised by systemd)
exec "${BROWSER_BIN}" "${LAUNCH_ARGS[@]}"
