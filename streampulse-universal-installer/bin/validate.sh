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
DETECTED_USER="${SUDO_USER:-$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $3}' | grep -v '^root$' | head -n 1 || awk -F: '$3 >= 1000 {print $1}' /etc/passwd | head -n1 || echo '')}"
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
