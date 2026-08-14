#!/usr/bin/env bash
# ==============================================================================
# StreamPulse Kiosk Suite - Comprehensive Diagnostic & Health Engine
# Location: /opt/streampulse/bin/diagnose.sh
# Inspects hardware, OS, Labwc session, browser processes, player, audio & network
# ==============================================================================

set -uo pipefail

TARGET_USER="${SUDO_USER:-$(whoami 2>/dev/null || echo "himakara")}"
if [ "$TARGET_USER" = "root" ]; then
  TARGET_USER="$(logname 2>/dev/null || id -un 1000 2>/dev/null || echo "himakara")"
fi
TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6 || echo "/home/$TARGET_USER")"
DASHBOARD_URL="http://187.127.210.81/"
CONFIG_FILE="/opt/streampulse/config/kiosk.conf"

[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE" 2>/dev/null || true

echo "========================================================================"
echo "          StreamPulse Kiosk Suite - System Diagnostics Report           "
echo "========================================================================"
echo "Report Timestamp: $(date)"
echo ""

echo "--- 1. OPERATING SYSTEM & HARDWARE ---"
echo "Hardware Model: $([ -f /proc/device-tree/model ] && tr -d '\0' < /proc/device-tree/model || uname -m)"
echo "Kernel: $(uname -r) ($(uname -m))"
if [ -f /etc/os-release ]; then
  grep -E "^(PRETTY_NAME|VERSION_ID|ID)=" /etc/os-release || true
fi
echo ""

echo "--- 2. USER & SESSION ENVIRONMENT ---"
echo "Active User: $TARGET_USER"
echo "UID/GID: $(id -u "$TARGET_USER" 2>/dev/null || echo "N/A") / $(id -g "$TARGET_USER" 2>/dev/null || echo "N/A")"
echo "Groups: $(id -Gn "$TARGET_USER" 2>/dev/null || echo "N/A")"
echo "Home Directory: $TARGET_HOME"
echo "DISPLAY: ${DISPLAY:-Not set}"
echo "WAYLAND_DISPLAY: ${WAYLAND_DISPLAY:-Not set}"
echo "XDG_SESSION_TYPE: ${XDG_SESSION_TYPE:-Not set}"
echo "XDG_CURRENT_DESKTOP: ${XDG_CURRENT_DESKTOP:-Not set}"
echo "Labwc Process: $(pgrep -a labwc || echo "Not running")"
echo ""

echo "--- 3. BROWSER INSTALLATION & RUNNING PROCESSES ---"
if command -v chromium >/dev/null 2>&1; then
  echo "Chromium Version: $(chromium --version 2>&1 | head -n 1)"
elif command -v chromium-browser >/dev/null 2>&1; then
  echo "Chromium Browser Version: $(chromium-browser --version 2>&1 | head -n 1)"
else
  echo "Chromium: Not installed on PATH"
fi

if command -v firefox-esr >/dev/null 2>&1; then
  echo "Firefox Version: $(firefox-esr --version 2>&1 | head -n 1)"
elif command -v firefox >/dev/null 2>&1; then
  echo "Firefox Version: $(firefox --version 2>&1 | head -n 1)"
fi

echo ""
echo "Active Browser Processes:"
ps aux | grep -E "(chromium|firefox)" | grep -v grep | head -n 5 || echo "No active browser processes found."
echo ""

echo "--- 4. SYSTEMD SERVICES STATUS ---"
echo ">> Dashboard Kiosk Service (streampulse-dashboard):"
systemctl status streampulse-dashboard.service --no-pager 2>&1 | head -n 8 || echo "Service not found."
echo ""
echo ">> Player Service (streampulse-rpi-player):"
systemctl status streampulse-rpi-player.service --no-pager 2>&1 | head -n 8 || echo "Service not found."
echo ""
echo ">> Remote Admin (RustDesk):"
systemctl status rustdesk.service --no-pager 2>&1 | head -n 5 || echo "RustDesk not installed or not managed by systemd."
echo ""

echo "--- 5. AUDIO SUBSYSTEM (PipeWire / WirePlumber) ---"
if command -v wpctl >/dev/null 2>&1; then
  echo "WirePlumber Status: Available"
  wpctl status 2>&1 | head -n 10 || true
else
  echo "PipeWire / ALSA Status:"
  systemctl status pipewire wireplumber --no-pager 2>&1 | head -n 6 || true
fi
echo ""

echo "--- 6. AUTOSTART CONFIGURATIONS ---"
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

echo "--- 7. NETWORK & DASHBOARD REACHABILITY ---"
echo "Target Dashboard URL: $DASHBOARD_URL"
if curl -sI --connect-timeout 3 "$DASHBOARD_URL" >/tmp/curl_diag.txt 2>&1; then
  echo "✓ Dashboard HTTP Connection: SUCCESS"
  head -n 3 /tmp/curl_diag.txt
else
  echo "✗ Dashboard HTTP Connection: FAILED"
  cat /tmp/curl_diag.txt 2>/dev/null || true
fi
rm -f /tmp/curl_diag.txt
echo ""

echo "--- 8. RECENT KIOSK LOGS ---"
if [ -f /var/log/streampulse-kiosk.log ]; then
  echo "Last 15 lines from /var/log/streampulse-kiosk.log:"
  tail -n 15 /var/log/streampulse-kiosk.log
elif [ -f /tmp/streampulse-kiosk.log ]; then
  echo "Last 15 lines from /tmp/streampulse-kiosk.log:"
  tail -n 15 /tmp/streampulse-kiosk.log
else
  echo "No kiosk log file found yet."
fi

echo ""
echo "========================================================================"
echo "                      Diagnostics Complete                             "
echo "========================================================================"
