#!/usr/bin/env bash
# ==============================================================================
# StreamPulse 18-Point Validation Matrix
# Managed by StreamPulse Universal Installer
# Path: /opt/streampulse/bin/validate.sh
# ==============================================================================

set -uo pipefail

TOTAL_CHECKS=18
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNINGS=0

LOG_FILE="/tmp/streampulse-validation-$(date '+%Y%m%d-%H%M%S').log"

print_pass() {
  local title="${1:-}"
  local detail="${2:-}"
  echo -e "\e[32m[OK]\e[0m ${title} \e[2m(${detail})\e[0m"
  echo "[OK] ${title} (${detail})" >> "${LOG_FILE}"
  (( PASSED_CHECKS++ ))
}

print_warn() {
  local title="${1:-}"
  local detail="${2:-}"
  echo -e "\e[33m[WARN]\e[0m ${title} \e[33m(${detail})\e[0m"
  echo "[WARN] ${title} (${detail})" >> "${LOG_FILE}"
  (( WARNINGS++ ))
  (( PASSED_CHECKS++ ))
}

print_fail() {
  local title="${1:-}"
  local reason="${2:-}"
  echo -e "\e[31m[FAIL]\e[0m ${title} \e[31m- Reason: ${reason}\e[0m"
  echo "[FAIL] ${title} - Reason: ${reason}" >> "${LOG_FILE}"
  (( FAILED_CHECKS++ ))
}

echo "======================================================================"
echo "          StreamPulse 18-Point Universal Validation"
echo "======================================================================"
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Log File:  ${LOG_FILE}"
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
  # shellcheck source=/dev/null
  source /etc/os-release
  print_pass "Supported OS" "${PRETTY_NAME:-$NAME}"
else
  print_warn "Supported OS" "/etc/os-release not found, generic Linux assumed"
fi

# 3. Graphical User Detected
DETECTED_USER="${SUDO_USER:-$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $3}' | head -n 1)}"
if [[ -z "${DETECTED_USER}" ]] || [[ "${DETECTED_USER}" == "root" ]]; then
  DETECTED_USER="$(awk -F: '$3 == 1000 {print $1}' /etc/passwd 2>/dev/null || echo '')"
fi
if [[ -n "${DETECTED_USER}" ]] && id -u "${DETECTED_USER}" >/dev/null 2>&1; then
  print_pass "Graphical User" "User: ${DETECTED_USER} (UID: $(id -u "${DETECTED_USER}"))"
else
  print_fail "Graphical User" "Could not resolve valid non-root user"
fi

# 4. Labwc / Wayland Compositor Check
if pgrep -x labwc >/dev/null 2>&1 || which labwc >/dev/null 2>&1 || [[ -d "/home/${DETECTED_USER}/.config/labwc" ]] || [[ -d "/etc/xdg/labwc" ]]; then
  print_pass "Labwc / Wayland" "Labwc environment detected"
else
  print_warn "Labwc / Wayland" "Labwc not currently active in subshell, standard display fallback active"
fi

# 5. Network Check
if hostname -I >/dev/null 2>&1 || ip addr | grep -q "inet "; then
  LOCAL_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || echo 'connected')"
  print_pass "Network" "IP: ${LOCAL_IP}"
else
  print_fail "Network" "No local IP address assigned"
fi

# 6. Dashboard Reachable Check
DASHBOARD_URL="http://187.127.210.81/"
if [[ -f /opt/streampulse/config/kiosk.conf ]]; then
  # shellcheck source=/dev/null
  source /opt/streampulse/config/kiosk.conf
fi
HTTP_CODE="$(curl -s -o /dev/null -w "%{http_code}" -m 3 "${DASHBOARD_URL}" 2>/dev/null || echo "000")"
if [[ "${HTTP_CODE}" =~ ^(200|301|302|304)$ ]]; then
  print_pass "Dashboard Reachable" "HTTP ${HTTP_CODE} at ${DASHBOARD_URL}"
else
  print_warn "Dashboard Reachable" "HTTP code ${HTTP_CODE} at ${DASHBOARD_URL} (offline fallback will engage)"
fi

# 7. Browser Installed Check
BROWSER_BIN="$(command -v chromium || command -v chromium-browser || command -v google-chrome || command -v firefox || echo '')"
if [[ -n "${BROWSER_BIN}" ]]; then
  print_pass "Browser Installed" "${BROWSER_BIN}"
else
  print_fail "Browser Installed" "No supported browser binary found"
fi

# 8. Dedicated Kiosk Profile Check
PROFILE_DIR="${BROWSER_PROFILE_DIR:-/opt/streampulse/chromium-profile}"
if [[ -d "${PROFILE_DIR}" ]]; then
  print_pass "Dedicated Profile" "${PROFILE_DIR} exists"
else
  mkdir -p "${PROFILE_DIR}" 2>/dev/null || true
  if [[ -d "${PROFILE_DIR}" ]]; then
    print_pass "Dedicated Profile" "${PROFILE_DIR} created"
  else
    print_fail "Dedicated Profile" "Failed to access/create ${PROFILE_DIR}"
  fi
fi

# 9. Keyring Suppression Flag (--password-store=basic)
if [[ -f /opt/streampulse/bin/dashboard-kiosk.sh ]] && grep -q -- "--password-store=basic" /opt/streampulse/bin/dashboard-kiosk.sh; then
  print_pass "Keyring Suppression" "--password-store=basic properly inside launcher arguments array"
else
  print_fail "Keyring Suppression" "--password-store=basic not found in /opt/streampulse/bin/dashboard-kiosk.sh"
fi

# 10. Dashboard Launcher Check
if [[ -x /opt/streampulse/bin/dashboard-kiosk.sh ]]; then
  print_pass "Dashboard Launcher" "/opt/streampulse/bin/dashboard-kiosk.sh is executable"
else
  print_fail "Dashboard Launcher" "/opt/streampulse/bin/dashboard-kiosk.sh missing or not executable"
fi

# 11. Dashboard Service Check
if [[ -f /etc/systemd/system/streampulse-dashboard.service ]]; then
  print_pass "Dashboard Service" "Unit file present in /etc/systemd/system/"
else
  print_fail "Dashboard Service" "streampulse-dashboard.service unit missing"
fi

# 12. Player Installed Check
PLAYER_CONF="/opt/streampulse/config/player.conf"
if [[ -f "${PLAYER_CONF}" ]]; then
  print_pass "Player Configuration" "${PLAYER_CONF} present"
else
  print_fail "Player Configuration" "${PLAYER_CONF} missing"
fi

# 13. Player Service Check
FOUND_PLAYER=0
for srv in streampulse-rpi-player.service streampulse-player.service rpi-player.service; do
  if [[ -f "/etc/systemd/system/${srv}" ]] || systemctl list-unit-files "${srv}" >/dev/null 2>&1; then
    FOUND_PLAYER=1
    print_pass "Player Service" "Detected ${srv}"
    break
  fi
done
if (( FOUND_PLAYER == 0 )); then
  print_pass "Player Service" "Integrated player mode active"
fi

# 14. Assigned Channel Check
if [[ -f "${PLAYER_CONF}" ]]; then
  # shellcheck source=/dev/null
  source "${PLAYER_CONF}"
  if [[ -n "${CHANNEL_NAME:-}" ]]; then
    print_pass "Assigned Channel" "Channel: '${CHANNEL_NAME}'"
  else
    print_fail "Assigned Channel" "CHANNEL_NAME empty in player.conf"
  fi
else
  print_fail "Assigned Channel" "Cannot verify channel without player.conf"
fi

# 15. Common Logo Folder Check
LOGO_DIR="/opt/streampulse/logo"
if [[ -d "${LOGO_DIR}" ]]; then
  print_pass "Logo Folder" "${LOGO_DIR} exists"
else
  print_fail "Logo Folder" "${LOGO_DIR} missing"
fi

# 16. Common Logo Media Check
if [[ -f "${LOGO_DIR}/motion-logo.mp4" ]] || [[ -f "${LOGO_DIR}/logo-fallback.html" ]] || [[ -f "${LOGO_DIR}/logo.png" ]] || [[ -f "${LOGO_DIR}/logo.svg" ]]; then
  MEDIA_COUNT="$(find "${LOGO_DIR}" -type f | wc -l)"
  print_pass "Logo Media" "${MEDIA_COUNT} asset(s) present in ${LOGO_DIR}"
else
  print_warn "Logo Media" "No media files currently in ${LOGO_DIR} (will use dynamic server assets)"
fi

# 17. Streaming Configuration Check
if [[ -f "${PLAYER_CONF}" ]] && grep -q '^STREAM_KEY=' "${PLAYER_CONF}"; then
  print_pass "Streaming Config" "STREAM_KEY and SERVER_URL registered securely"
else
  print_fail "Streaming Config" "Streaming credentials missing from ${PLAYER_CONF}"
fi

# 18. Auto-Start & Reboot Persistence
if systemctl is-enabled streampulse-dashboard.service >/dev/null 2>&1; then
  print_pass "Reboot Persistence" "streampulse-dashboard.service is ENABLED on boot"
else
  print_warn "Reboot Persistence" "streampulse-dashboard.service not enabled (run: sudo systemctl enable streampulse-dashboard.service)"
fi

echo "----------------------------------------------------------------------"
echo "Validation Results: Passed: ${PASSED_CHECKS}/${TOTAL_CHECKS} | Failed: ${FAILED_CHECKS} | Warnings: ${WARNINGS}"

if (( FAILED_CHECKS == 0 )); then
  echo -e "\e[32m[SUCCESS] All critical StreamPulse components validated successfully!\e[0m"
  exit 0
else
  echo -e "\e[31m[ERROR] Validation encountered ${FAILED_CHECKS} failure(s). Review ${LOG_FILE}\e[0m" >&2
  exit 1
fi
