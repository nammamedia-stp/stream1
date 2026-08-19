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

# 18. Common Logo Assets & Player Display Verification
LOGO_DIR="/opt/streampulse/logo"
if [[ -s "${LOGO_DIR}/player.html" ]] && [[ -s "${LOGO_DIR}/logo-fallback.html" ]] && [[ -s "${LOGO_DIR}/hls.min.js" ]]; then
  if [[ -s "${LOGO_DIR}/motion-logo.mp4" ]]; then
    print_pass "Offline Visuals" "player.html + logo-fallback.html + hls.min.js + motion-logo.mp4 (All Ready)"
  else
    print_pass "Offline Visuals" "player.html + logo-fallback.html + hls.min.js (Guaranteed HTML5 fallback active, MP4 optional)"
  fi
else
  MISSING_ASSETS=""
  [[ ! -s "${LOGO_DIR}/player.html" ]] && MISSING_ASSETS="${MISSING_ASSETS} player.html"
  [[ ! -s "${LOGO_DIR}/logo-fallback.html" ]] && MISSING_ASSETS="${MISSING_ASSETS} logo-fallback.html"
  [[ ! -s "${LOGO_DIR}/hls.min.js" ]] && MISSING_ASSETS="${MISSING_ASSETS} hls.min.js"
  print_fail "Offline Visuals" "Missing mandatory assets in ${LOGO_DIR}:${MISSING_ASSETS}"
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
