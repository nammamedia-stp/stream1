#!/usr/bin/env bash
# ==============================================================================
# StreamPulse Master Suite - Comprehensive Diagnostics & System Health Engine
# Location: /opt/streampulse/bin/diagnose.sh
# Inspects hardware, OS, Labwc session, Chromium, player, audio & network
# ==============================================================================

set -uo pipefail

TARGET_USER="${SUDO_USER:-$(whoami 2>/dev/null || echo "himakara")}"
if [ "$TARGET_USER" = "root" ]; then
  TARGET_USER="$(logname 2>/dev/null || id -un 1000 2>/dev/null || echo "himakara")"
fi
TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6 || echo "/home/$TARGET_USER")"
CONFIG_FILE="/opt/streampulse/config/kiosk.conf"
DASHBOARD_URL="http://187.127.210.81/"
STREAM_KEY="live_stream"

if [ -f "$CONFIG_FILE" ]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE" 2>/dev/null || true
fi

echo "========================================================================"
echo "          StreamPulse Master Suite - Full Diagnostics Report            "
echo "========================================================================"
echo "Report Timestamp: $(date)"
echo ""

echo "--- 1. OPERATING SYSTEM & HARDWARE ---"
echo "Hardware Model: $([ -f /proc/device-tree/model ] && tr -d '\0' < /proc/device-tree/model || uname -m)"
echo "Kernel: $(uname -r)"
echo "Architecture: $(uname -m)"
if [ -f /etc/os-release ]; then
  grep -E "^(PRETTY_NAME|VERSION_ID|ID)=" /etc/os-release || true
fi
echo ""

echo "--- 2. CURRENT USER & SESSION ENVIRONMENT ---"
echo "Active Target User: $TARGET_USER"
echo "UID/GID: $(id -u "$TARGET_USER" 2>/dev/null || echo "N/A") / $(id -g "$TARGET_USER" 2>/dev/null || echo "N/A")"
echo "User Groups: $(id -Gn "$TARGET_USER" 2>/dev/null || echo "N/A")"
echo "Home Directory: $TARGET_HOME"
echo "DISPLAY: ${DISPLAY:-Not set}"
echo "WAYLAND_DISPLAY: ${WAYLAND_DISPLAY:-Not set}"
echo "XDG_SESSION_TYPE: ${XDG_SESSION_TYPE:-Not set}"
echo "XDG_CURRENT_DESKTOP: ${XDG_CURRENT_DESKTOP:-Not set}"
echo "XDG_RUNTIME_DIR: ${XDG_RUNTIME_DIR:-/run/user/$(id -u "$TARGET_USER" 2>/dev/null || echo 1000)}"
echo "Labwc Process: $(pgrep -a labwc || echo "Not running in current context")"
echo ""

echo "--- 3. BROWSER INSTALLATION & LAUNCH COMMAND ---"
if command -v chromium >/dev/null 2>&1; then
  echo "Chromium Binary: $(command -v chromium) ($(chromium --version 2>&1 | head -n 1))"
elif command -v chromium-browser >/dev/null 2>&1; then
  echo "Chromium Binary: $(command -v chromium-browser) ($(chromium-browser --version 2>&1 | head -n 1))"
else
  echo "Chromium: Not installed on PATH"
fi

if command -v firefox-esr >/dev/null 2>&1; then
  echo "Firefox Binary: $(command -v firefox-esr) ($(firefox-esr --version 2>&1 | head -n 1))"
elif command -v firefox >/dev/null 2>&1; then
  echo "Firefox Binary: $(command -v firefox) ($(firefox --version 2>&1 | head -n 1))"
fi

echo ""
echo "Authoritative Launcher: /opt/streampulse/bin/dashboard-kiosk.sh"
if [ -f /opt/streampulse/bin/dashboard-kiosk.sh ]; then
  echo "Launcher Keyring Flag Check:"
  grep -E "password-store=basic" /opt/streampulse/bin/dashboard-kiosk.sh || echo "  Warning: password-store=basic not found"
else
  echo "Launcher script not present at /opt/streampulse/bin/dashboard-kiosk.sh"
fi

echo ""
echo "Active Dashboard / Browser Processes & Parent PID:"
ps -eo pid,ppid,user,args | grep -E "(chromium|firefox|dashboard-kiosk)" | grep -v grep | head -n 8 || echo "No active browser processes found."
echo ""

echo "--- 4. SYSTEMD SERVICES STATUS ---"
echo ">> Dashboard Kiosk Service (streampulse-dashboard.service):"
systemctl status streampulse-dashboard.service --no-pager 2>&1 | head -n 10 || echo "Service not found."
echo ""
echo ">> Player Service (streampulse-rpi-player.service):"
systemctl status streampulse-rpi-player.service --no-pager 2>&1 | head -n 10 || echo "Service not found."
echo ""
echo ">> Remote Management Service (RustDesk):"
systemctl status rustdesk.service --no-pager 2>&1 | head -n 6 || echo "RustDesk service not found."
echo ""

echo "--- 5. AUDIO SUBSYSTEM (PipeWire & WirePlumber) ---"
if command -v wpctl >/dev/null 2>&1; then
  echo "WirePlumber CLI: Available"
  wpctl status 2>&1 | head -n 10 || true
else
  echo "WirePlumber CLI: Not installed"
fi

echo "PipeWire Service Status:"
systemctl --user -M "${TARGET_USER}@" status pipewire wireplumber --no-pager 2>&1 | head -n 8 || systemctl status pipewire wireplumber --no-pager 2>&1 | head -n 8 || echo "PipeWire system unit check complete."
echo ""

echo "--- 6. NETWORK & DASHBOARD REACHABILITY ---"
echo "Configured Dashboard URL: $DASHBOARD_URL"
echo "Configured Stream Key: $STREAM_KEY"
if curl -sI --connect-timeout 3 "$DASHBOARD_URL" >/tmp/streampulse_curl_diag.txt 2>&1; then
  echo "✓ Dashboard HTTP Reachability: SUCCESS"
  head -n 3 /tmp/streampulse_curl_diag.txt
else
  echo "✗ Dashboard HTTP Reachability: FAILED"
  cat /tmp/streampulse_curl_diag.txt 2>/dev/null || true
fi
rm -f /tmp/streampulse_curl_diag.txt
echo ""

echo "--- 7. AUTOSTART & DESKTOP CONFIGURATIONS ---"
echo ">> Labwc autostart (${TARGET_HOME}/.config/labwc/autostart):"
if [ -f "${TARGET_HOME}/.config/labwc/autostart" ]; then
  cat "${TARGET_HOME}/.config/labwc/autostart"
else
  echo "File does not exist."
fi
echo ""
echo ">> XDG Autostart (${TARGET_HOME}/.config/autostart):"
if [ -d "${TARGET_HOME}/.config/autostart" ]; then
  ls -la "${TARGET_HOME}/.config/autostart"
else
  echo "Directory does not exist."
fi
echo ""

echo "--- 8. RECENT DASHBOARD KIOSK LOGS ---"
if [ -f /var/log/streampulse-kiosk.log ]; then
  echo "Last 15 lines from /var/log/streampulse-kiosk.log:"
  tail -n 15 /var/log/streampulse-kiosk.log
elif [ -f /tmp/streampulse-kiosk.log ]; then
  echo "Last 15 lines from /tmp/streampulse-kiosk.log:"
  tail -n 15 /tmp/streampulse-kiosk.log
else
  echo "No kiosk log file generated yet."
fi

echo ""
echo "========================================================================"
echo "                      Diagnostics Complete                             "
echo "========================================================================"
