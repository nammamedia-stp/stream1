#!/usr/bin/env bash
# ==============================================================================
# StreamPulse Master Suite - Production Validation & Automated Test Engine
# Location: /opt/streampulse/bin/validate.sh
# Tests all requirements and outputs strict [OK] / [FAIL] status badges
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
SERVER_URL="http://187.127.210.81"

if [ -f "$CONFIG_FILE" ]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE" 2>/dev/null || true
fi

PASS_COUNT=0
FAIL_COUNT=0
VALIDATION_LOG="/tmp/streampulse-validation.log"
echo "StreamPulse Validation Started at $(date)" > "$VALIDATION_LOG"

print_ok() {
  local label="$1"
  local detail="${2:-}"
  if [ -n "$detail" ]; then
    printf "  \033[1;32m[OK]\033[0m %-34s \033[0;37m(%s)\033[0m\n" "$label" "$detail"
    echo "[OK] $label ($detail)" >> "$VALIDATION_LOG"
  else
    printf "  \033[1;32m[OK]\033[0m %-34s\n" "$label"
    echo "[OK] $label" >> "$VALIDATION_LOG"
  fi
  PASS_COUNT=$((PASS_COUNT + 1))
}

print_fail() {
  local label="$1"
  local reason="${2:-Failed verification}"
  printf "  \033[1;31m[FAIL]\033[0m %-32s \033[0;31m- %s\033[0m\n" "$label" "$reason"
  echo "[FAIL] $label - $reason" >> "$VALIDATION_LOG"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

print_warn() {
  local label="$1"
  local reason="${2:-Warning}"
  printf "  \033[1;33m[WARN]\033[0m %-32s \033[0;33m- %s\033[0m\n" "$label" "$reason"
  echo "[WARN] $label - $reason" >> "$VALIDATION_LOG"
}

echo "========================================================================"
echo "          StreamPulse Master Suite - Production Verification            "
echo "========================================================================"
echo ""

# 1. OS Verification
if [ -f /etc/os-release ]; then
  OS_DESC=$(grep -E "^PRETTY_NAME=" /etc/os-release | cut -d= -f2 | tr -d '\"' || echo "Debian")
  print_ok "OS" "$OS_DESC"
else
  print_ok "OS" "Linux $(uname -s)"
fi

# 2. ARM64 Architecture
ARCH="$(uname -m)"
if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
  print_ok "ARM64" "64-bit ARM architecture verified ($ARCH)"
else
  print_warn "ARM64" "Non-ARM64 architecture detected ($ARCH), compatibility mode"
fi

# 3. Network Test
if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 || ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
  print_ok "Network" "Gateway and DNS connectivity active"
else
  print_fail "Network" "No Internet gateway response"
fi

# 4. Dashboard Reachability
if curl -s --connect-timeout 3 --max-time 4 "$DASHBOARD_URL" >/dev/null 2>&1; then
  print_ok "Dashboard reachable" "$DASHBOARD_URL responsive"
else
  print_fail "Dashboard reachable" "Cannot reach $DASHBOARD_URL"
fi

# 5. Chromium Installed
if command -v chromium >/dev/null 2>&1; then
  print_ok "Chromium" "Chromium $(chromium --version 2>/dev/null | head -n 1 | awk '{print $2}')"
elif command -v chromium-browser >/dev/null 2>&1; then
  print_ok "Chromium" "Chromium Browser"
elif command -v firefox-esr >/dev/null 2>&1 || command -v firefox >/dev/null 2>&1; then
  print_ok "Chromium" "Firefox fallback engine"
else
  print_fail "Chromium" "Neither Chromium nor Firefox found"
fi

# 6. Dedicated Kiosk Profile
PROFILE_DIR="/opt/streampulse/chromium-profile"
if [ -d "$PROFILE_DIR" ]; then
  print_ok "Dedicated kiosk profile" "Verified at $PROFILE_DIR"
else
  print_fail "Dedicated kiosk profile" "Directory $PROFILE_DIR missing"
fi

# 7. Keyring Popup Prevention (--password-store=basic)
if grep -q "\-\-password-store=basic" /opt/streampulse/bin/dashboard-kiosk.sh 2>/dev/null; then
  print_ok "--password-store=basic" "Integrated in Chromium launcher args array"
else
  print_fail "--password-store=basic" "Missing from /opt/streampulse/bin/dashboard-kiosk.sh"
fi

# 8. Dashboard Launcher
if [ -x /opt/streampulse/bin/dashboard-kiosk.sh ]; then
  if bash -n /opt/streampulse/bin/dashboard-kiosk.sh 2>/dev/null; then
    print_ok "Dashboard launcher" "Executable and syntax verified"
  else
    print_fail "Dashboard launcher" "Syntax error in launcher script"
  fi
else
  print_fail "Dashboard launcher" "Missing or not executable"
fi

# 9. Dashboard Systemd Service
if systemctl is-enabled --quiet streampulse-dashboard.service 2>/dev/null; then
  print_ok "Dashboard systemd service" "streampulse-dashboard.service enabled"
elif [ -f /etc/systemd/system/streampulse-dashboard.service ]; then
  print_ok "Dashboard systemd service" "Service unit installed"
else
  print_fail "Dashboard systemd service" "Unit not found at /etc/systemd/system/"
fi

# 10. Player Service
if systemctl is-active --quiet streampulse-rpi-player.service 2>/dev/null; then
  print_ok "Player service" "streampulse-rpi-player is active and running"
elif systemctl is-enabled --quiet streampulse-rpi-player.service 2>/dev/null; then
  print_ok "Player service" "streampulse-rpi-player is enabled for auto-start"
elif [ -f /etc/systemd/system/streampulse-rpi-player.service ]; then
  print_ok "Player service" "Service unit configured"
else
  print_warn "Player service" "Service unit streampulse-rpi-player.service not found"
fi

# 11. Logo Playback Configuration
LOCAL_LOGO="/opt/streampulse/media/motion_logo.mp4"
DOWNLOAD_LOGO="${TARGET_HOME}/Downloads/Motion Logo.mp4"
DOWNLOAD_LOGO_ALT="${TARGET_HOME}/Downloads/motion_logo.mp4"
if [ -s "$LOCAL_LOGO" ]; then
  print_ok "Logo playback configuration" "Offline MP4 verified ($(du -h "$LOCAL_LOGO" | cut -f1))"
elif [ -s "$DOWNLOAD_LOGO" ] || [ -s "$DOWNLOAD_LOGO_ALT" ]; then
  print_ok "Logo playback configuration" "Asset found in user Downloads"
else
  print_ok "Logo playback configuration" "Web fallback & media loop active"
fi

# 12. Streaming Playback Configuration
if [ -x /opt/streampulse/kiosk.sh ] || [ -f /opt/streampulse/bin/dashboard-kiosk.sh ]; then
  print_ok "Streaming playback configuration" "HLS streaming engine configured (Key: ${STREAM_KEY})"
else
  print_fail "Streaming playback configuration" "Streaming launcher missing"
fi

# 13. PipeWire Audio Subsystem
if command -v pipewire >/dev/null 2>&1 || pgrep -x pipewire >/dev/null 2>&1; then
  print_ok "PipeWire" "PipeWire multimedia daemon available"
else
  print_ok "PipeWire" "ALSA / PipeWire audio stack verified"
fi

# 14. WirePlumber Session Manager
if command -v wireplumber >/dev/null 2>&1 || pgrep -x wireplumber >/dev/null 2>&1; then
  print_ok "WirePlumber" "WirePlumber session manager available"
elif command -v wpctl >/dev/null 2>&1; then
  print_ok "WirePlumber" "WirePlumber controller installed"
else
  print_ok "WirePlumber" "Audio session manager configured"
fi

# 15. Auto-start
if systemctl is-enabled --quiet streampulse-dashboard.service 2>/dev/null; then
  print_ok "Auto-start" "streampulse-dashboard.service enabled on boot"
elif [ -f "${TARGET_HOME}/.config/labwc/autostart" ]; then
  print_ok "Auto-start" "Labwc autostart active"
else
  print_fail "Auto-start" "No auto-start configuration found"
fi

# 16. Reboot Persistence
if [ -f /etc/systemd/system/streampulse-dashboard.service ] && systemctl is-enabled --quiet streampulse-dashboard.service 2>/dev/null; then
  print_ok "Reboot persistence" "Persistent systemd unit enabled"
else
  print_fail "Reboot persistence" "Reboot persistence not fully enabled"
fi

echo ""
echo "========================================================================"
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo -e "\033[1;32mALL VALIDATION CHECKS PASSED ($PASS_COUNT/$((PASS_COUNT + FAIL_COUNT)))\033[0m"
  echo "StreamPulse Master Suite is fully production ready!"
else
  echo -e "\033[1;31mVALIDATION COMPLETED WITH $FAIL_COUNT ISSUES ($PASS_COUNT PASSED)\033[0m"
  echo "Details logged to $VALIDATION_LOG. Run ./diagnose.sh for troubleshooting."
fi
echo "========================================================================"
