#!/usr/bin/env bash
# ==============================================================================
# StreamPulse Diagnostic Engine
# Managed by StreamPulse Universal Installer
# Path: /opt/streampulse/bin/diagnose.sh
# ==============================================================================

set -uo pipefail

# Helper function to mask sensitive strings
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

echo "======================================================================"
echo "          StreamPulse Universal System Diagnostics"
echo "======================================================================"
echo "Date/Time:        $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "Hostname:         $(hostname 2>/dev/null || echo 'unknown')"
echo "Kernel:           $(uname -r 2>/dev/null || echo 'unknown')"
echo "Architecture:     $(uname -m 2>/dev/null || echo 'unknown')"
if [[ -f /etc/os-release ]]; then
  # shellcheck source=/dev/null
  source /etc/os-release
  echo "OS Distribution:  ${PRETTY_NAME:-$NAME $VERSION}"
fi
echo "----------------------------------------------------------------------"

# 1. User & Desktop Session Detection
DETECTED_USER="${SUDO_USER:-$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $3}' | head -n 1)}"
if [[ -z "${DETECTED_USER}" ]] || [[ "${DETECTED_USER}" == "root" ]]; then
  DETECTED_USER="$(awk -F: '$3 == 1000 {print $1}' /etc/passwd 2>/dev/null || echo "himakara")"
fi
USER_UID="$(id -u "${DETECTED_USER}" 2>/dev/null || echo 'unknown')"
USER_HOME="$(getent passwd "${DETECTED_USER}" 2>/dev/null | cut -d: -f6 || echo "/home/${DETECTED_USER}")"

echo "Detected User:    ${DETECTED_USER} (UID: ${USER_UID})"
echo "User Home:        ${USER_HOME}"
echo "Current Sessions: $(loginctl list-sessions --no-legend 2>/dev/null | wc -l || echo '0') active session(s)"
echo "Wayland Display:  ${WAYLAND_DISPLAY:-wayland-0}"
echo "X11 Display:      ${DISPLAY:-:0}"

# Check Compositor / Window Manager
if pgrep -x labwc >/dev/null 2>&1; then
  echo "Compositor:       Labwc (Active, PID $(pgrep -x labwc | tr '\n' ' '))"
elif pgrep -x wayfire >/dev/null 2>&1; then
  echo "Compositor:       Wayfire (Active)"
elif pgrep -x openbox >/dev/null 2>&1; then
  echo "Window Manager:   Openbox (Active)"
else
  echo "Compositor/WM:    Not running in current subshell context or unlisted"
fi
echo "----------------------------------------------------------------------"

# 2. Per-Pi Channel & Player Configuration
PLAYER_CONF="/opt/streampulse/config/player.conf"
if [[ -f "${PLAYER_CONF}" ]]; then
  # shellcheck source=/dev/null
  source "${PLAYER_CONF}"
  echo "Assigned Channel: ${CHANNEL_NAME:-not set}"
  echo "Stream Key:       $(mask_secret "${STREAM_KEY:-live_stream}")"
  echo "Playback Mode:    ${PLAYBACK_MODE:-auto}"
  echo "Server Host:      ${SERVER_URL:-http://187.127.210.81}"
  echo "Last Updated:     ${LAST_UPDATED:-initial}"
else
  echo "Player Config:    MISSING (/opt/streampulse/config/player.conf)"
fi

# Check Player Services
echo "Player Services Status:"
FOUND_PLAYER_SVC=0
for srv in streampulse-rpi-player.service streampulse-player.service rpi-player.service; do
  if systemctl list-unit-files "${srv}" >/dev/null 2>&1 || [[ -f "/etc/systemd/system/${srv}" ]]; then
    FOUND_PLAYER_SVC=1
    STATUS="$(systemctl is-active "${srv}" 2>/dev/null || echo 'inactive')"
    ENABLED="$(systemctl is-enabled "${srv}" 2>/dev/null || echo 'disabled')"
    echo "  - ${srv}: Active=${STATUS} | Enabled=${ENABLED}"
  fi
done
if (( FOUND_PLAYER_SVC == 0 )); then
  echo "  - No standalone player service registered (integrated or custom setup)."
fi
echo "----------------------------------------------------------------------"

# 3. Common Logo Directory & Media Assets
LOGO_DIR="/opt/streampulse/logo"
echo "Common Logo Path: ${LOGO_DIR}"
if [[ -d "${LOGO_DIR}" ]]; then
  echo "Logo Folder:      EXISTS (Permissions: $(stat -c '%a %U:%G' "${LOGO_DIR}" 2>/dev/null || echo 'unknown'))"
  echo "Logo Media Files:"
  find "${LOGO_DIR}" -maxdepth 2 -type f -exec ls -lh {} + 2>/dev/null | awk '{print "  * " $9 " (" $5 ")"}'
else
  echo "Logo Folder:      MISSING"
fi
echo "----------------------------------------------------------------------"

# 4. Kiosk Browser & Dashboard Configuration
KIOSK_CONF="/opt/streampulse/config/kiosk.conf"
if [[ -f "${KIOSK_CONF}" ]]; then
  # shellcheck source=/dev/null
  source "${KIOSK_CONF}"
  echo "Dashboard URL:    ${DASHBOARD_URL:-http://187.127.210.81/}"
  echo "Profile Dir:      ${BROWSER_PROFILE_DIR:-/opt/streampulse/chromium-profile}"
  echo "Keyring Flag:     --password-store=basic (Configured)"
else
  echo "Kiosk Config:     MISSING (/opt/streampulse/config/kiosk.conf)"
fi

# Check Installed Browser
BROWSER_BIN="$(command -v chromium || command -v chromium-browser || command -v google-chrome || command -v firefox || echo '')"
if [[ -n "${BROWSER_BIN}" ]]; then
  echo "Browser Binary:   ${BROWSER_BIN} ($("${BROWSER_BIN}" --version 2>/dev/null || echo 'version unknown'))"
else
  echo "Browser Binary:   NOT FOUND"
fi

# Check Dashboard Systemd Service
echo "Dashboard Service (streampulse-dashboard.service):"
if systemctl list-unit-files streampulse-dashboard.service >/dev/null 2>&1 || [[ -f /etc/systemd/system/streampulse-dashboard.service ]]; then
  DASH_STATUS="$(systemctl is-active streampulse-dashboard.service 2>/dev/null || echo 'inactive')"
  DASH_ENABLED="$(systemctl is-enabled streampulse-dashboard.service 2>/dev/null || echo 'disabled')"
  echo "  - Active:        ${DASH_STATUS}"
  echo "  - Enabled:       ${DASH_ENABLED}"
else
  echo "  - Service unit file not found."
fi

# Check Running Browser Processes
BROWSER_PIDS="$(pgrep -f "chromium-profile|dashboard-kiosk" | tr '\n' ' ')"
if [[ -n "${BROWSER_PIDS}" ]]; then
  echo "Running Kiosk PID: ${BROWSER_PIDS}"
else
  echo "Running Kiosk:    Not running currently"
fi
echo "----------------------------------------------------------------------"

# 5. Network Connectivity & Dashboard Reachability
echo "Network & Connectivity:"
IP_ADDRS="$(hostname -I 2>/dev/null || ip -4 addr show | grep inet | awk '{print $2}' | tr '\n' ' ')"
echo "  - Local IP(s):   ${IP_ADDRS:-unknown}"

CHECK_URL="${DASHBOARD_URL:-http://187.127.210.81/}"
HTTP_CODE="$(curl -s -o /dev/null -w "%{http_code}" -m 3 "${CHECK_URL}" 2>/dev/null || echo "000")"
if [[ "${HTTP_CODE}" =~ ^(200|301|302|304)$ ]]; then
  echo "  - Dashboard URL: REACHABLE (HTTP ${HTTP_CODE} at ${CHECK_URL})"
else
  echo "  - Dashboard URL: UNREACHABLE / Timeout (HTTP ${HTTP_CODE} at ${CHECK_URL})"
fi
echo "----------------------------------------------------------------------"

# 6. Audio Subsystem Health
echo "Audio Subsystem:"
if pgrep -x pipewire >/dev/null 2>&1; then
  echo "  - PipeWire:      ACTIVE (Preserved)"
fi
if pgrep -x wireplumber >/dev/null 2>&1; then
  echo "  - WirePlumber:   ACTIVE"
fi
if command -v aplay >/dev/null 2>&1; then
  echo "  - Sound Cards:   $(aplay -l 2>/dev/null | grep -c '^card' || echo '0') card(s) detected"
fi
echo "----------------------------------------------------------------------"

# 7. Recent Dashboard Service Journal Logs (Masking sensitive info)
echo "Recent Dashboard Service Logs:"
journalctl -u streampulse-dashboard.service -n 10 --no-pager 2>/dev/null | sed 's/[a-zA-Z0-9]\{20,\}/[MASKED_HASH]/g' || echo "  (No journal logs available)"
echo "======================================================================"
