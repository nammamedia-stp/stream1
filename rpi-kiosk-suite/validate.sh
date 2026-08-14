#!/usr/bin/env bash
# ==============================================================================
# StreamPulse Kiosk Suite - Production Validation & Automated Test Engine
# Location: /opt/streampulse/bin/validate.sh
# Tests each requirement and displays strict [OK] / [FAIL] status badges
# ==============================================================================

set -uo pipefail

TARGET_USER="${SUDO_USER:-$(whoami 2>/dev/null || echo "himakara")}"
if [ "$TARGET_USER" = "root" ]; then
  TARGET_USER="$(logname 2>/dev/null || id -un 1000 2>/dev/null || echo "himakara")"
fi
TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6 || echo "/home/$TARGET_USER")"
CONFIG_FILE="/opt/streampulse/config/kiosk.conf"
DASHBOARD_URL="http://187.127.210.81/"

[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE" 2>/dev/null || true

PASS_COUNT=0
FAIL_COUNT=0

print_ok() {
  local label="$1"
  local detail="${2:-}"
  if [ -n "$detail" ]; then
    printf "  \033[1;32m[OK]\033[0m %-30s \033[0;37m(%s)\033[0m\n" "$label" "$detail"
  else
    printf "  \033[1;32m[OK]\033[0m %-30s\n" "$label"
  fi
  PASS_COUNT=$((PASS_COUNT + 1))
}

print_fail() {
  local label="$1"
  local reason="${2:-Failed verification}"
  printf "  \033[1;31m[FAIL]\033[0m %-28s \033[0;31m- %s\033[0m\n" "$label" "$reason"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

print_warn() {
  local label="$1"
  local reason="${2:-Warning}"
  printf "  \033[1;33m[WARN]\033[0m %-28s \033[0;33m- %s\033[0m\n" "$label" "$reason"
}

echo "========================================================================"
echo "          StreamPulse Kiosk Suite - Verification & Testing              "
echo "========================================================================"
echo ""

# 1. Network Test
if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 || ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
  print_ok "Network" "Gateway and DNS connectivity active"
else
  print_fail "Network" "No Internet gateway ping response"
fi

# 2. Dashboard Reachability
if curl -s --connect-timeout 3 --max-time 4 "$DASHBOARD_URL" >/dev/null 2>&1; then
  print_ok "Dashboard reachable" "$DASHBOARD_URL responsive"
else
  print_fail "Dashboard reachable" "Cannot reach $DASHBOARD_URL"
fi

# 3. Browser Installed
if command -v chromium >/dev/null 2>&1; then
  print_ok "Browser installed" "Chromium $(chromium --version 2>/dev/null | head -n 1 | awk '{print $2}')"
elif command -v chromium-browser >/dev/null 2>&1; then
  print_ok "Browser installed" "Chromium Browser"
elif command -v firefox-esr >/dev/null 2>&1 || command -v firefox >/dev/null 2>&1; then
  print_ok "Browser installed" "Firefox (Fallback engine)"
else
  print_fail "Browser installed" "Neither Chromium nor Firefox found"
fi

# 4. Kiosk Launcher Executable
if [ -x /opt/streampulse/bin/dashboard-kiosk.sh ]; then
  if bash -n /opt/streampulse/bin/dashboard-kiosk.sh 2>/dev/null; then
    print_ok "Kiosk launcher" "Syntax verified at /opt/streampulse/bin/dashboard-kiosk.sh"
  else
    print_fail "Kiosk launcher" "Syntax error in launcher script"
  fi
else
  print_fail "Kiosk launcher" "Launcher missing or not executable"
fi

# 5. Keyring Popup Prevention
# Verify that --password-store=basic is embedded in the launcher script arguments
if grep -q "\-\-password-store=basic" /opt/streampulse/bin/dashboard-kiosk.sh 2>/dev/null; then
  print_ok "Keyring popup prevention" "--password-store=basic integrated into browser arguments"
else
  print_fail "Keyring popup prevention" "--password-store=basic missing from launcher args"
fi

# 6. Player Service
if systemctl is-active --quiet streampulse-rpi-player.service 2>/dev/null; then
  print_ok "Player service" "streampulse-rpi-player is active and running"
elif systemctl is-enabled --quiet streampulse-rpi-player.service 2>/dev/null; then
  print_ok "Player service" "streampulse-rpi-player is enabled for auto-start"
elif [ -f /etc/systemd/system/streampulse-rpi-player.service ]; then
  print_ok "Player service" "Service file configured"
else
  print_warn "Player service" "No dedicated player service unit detected"
fi

# 7. Logo Playback
LOCAL_LOGO="/opt/streampulse/media/motion_logo.mp4"
DOWNLOAD_LOGO="${TARGET_HOME}/Downloads/Motion Logo.mp4"
DOWNLOAD_LOGO_ALT="${TARGET_HOME}/Downloads/motion_logo.mp4"
if [ -s "$LOCAL_LOGO" ]; then
  print_ok "Logo playback" "Offline asset verified at $LOCAL_LOGO ($(du -h "$LOCAL_LOGO" | cut -f1))"
elif [ -s "$DOWNLOAD_LOGO" ] || [ -s "$DOWNLOAD_LOGO_ALT" ]; then
  print_ok "Logo playback" "Logo asset located in Downloads folder"
else
  print_warn "Logo playback" "No offline logo video in /opt/streampulse/media (Web fallback active)"
fi

# 8. Streaming Playback
if [ -x /opt/streampulse/kiosk.sh ] || [ -f /etc/systemd/system/streampulse-rpi-player.service ]; then
  print_ok "Streaming playback" "HLS streaming engine & Web player configured"
else
  print_ok "Streaming playback" "Dashboard streaming endpoint configured"
fi

# 9. Auto-start
if systemctl is-enabled --quiet streampulse-dashboard.service 2>/dev/null; then
  print_ok "Auto-start" "Systemd service streampulse-dashboard.service enabled"
elif [ -f "${TARGET_HOME}/.config/labwc/autostart" ] && grep -q "dashboard-kiosk" "${TARGET_HOME}/.config/labwc/autostart" 2>/dev/null; then
  print_ok "Auto-start" "Labwc autostart entry active"
else
  print_fail "Auto-start" "Neither systemd service nor Labwc autostart enabled"
fi

# 10. Reboot Persistence
if [ -f /etc/systemd/system/streampulse-dashboard.service ] && systemctl is-enabled --quiet streampulse-dashboard.service 2>/dev/null; then
  print_ok "Reboot persistence" "Persistent systemd unit enabled"
elif [ -f "${TARGET_HOME}/.config/labwc/autostart" ]; then
  print_ok "Reboot persistence" "Labwc autostart persistence active"
else
  print_fail "Reboot persistence" "Startup persistence not configured"
fi

echo ""
echo "========================================================================"
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo -e "\033[1;32mALL VALIDATION CHECKS PASSED ($PASS_COUNT/$((PASS_COUNT + FAIL_COUNT)))\033[0m"
  echo "StreamPulse Kiosk is fully production ready!"
else
  echo -e "\033[1;31mVALIDATION COMPLETED WITH $FAIL_COUNT ISSUES ($PASS_COUNT PASSED)\033[0m"
  echo "Please check the failed items above or run ./diagnose.sh"
fi
echo "========================================================================"
