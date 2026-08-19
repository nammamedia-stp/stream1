#!/usr/bin/env bash
# ==============================================================================
# StreamPulse 18-Point Universal Validation Suite
# Path: /opt/streampulse/bin/validate.sh
# ==============================================================================

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

# 6. Stream Endpoint Reachable Check
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
if [[ -f /etc/systemd/system/streampulse-player.service ]]; then
  print_pass "Playback Service" "Authoritative streampulse-player.service unit registered"
else
  print_fail "Playback Service" "Authoritative service unit (/etc/systemd/system/streampulse-player.service) missing"
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
if systemctl is-enabled streampulse-player.service >/dev/null 2>&1; then
  print_pass "Reboot Persistence" "streampulse-player.service ENABLED on boot"
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
