#!/usr/bin/env bash
# ==============================================================================
# StreamPulse Safe Uninstallation Engine
# Managed by StreamPulse Universal Installer
# ==============================================================================

set -uo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Error: Uninstaller must be run with root privileges (sudo)." >&2
  exit 1
fi

echo "======================================================================"
echo "          StreamPulse Safe Uninstallation"
echo "======================================================================"
echo "This will safely disable and remove StreamPulse Dashboard Kiosk services,"
echo "authoritative scripts, and dedicated browser profiles."
echo ""
echo "SAFE PRESERVATION GUARANTEES:"
echo "  [✓] Common Logo directory (/opt/streampulse/logo) is PRESERVED."
echo "  [✓] Media assets and player recordings are PRESERVED."
echo "  [✓] User personal files & home directory are PRESERVED."
echo "  [✓] PipeWire & WirePlumber audio subsystems are PRESERVED."
echo "  [✓] Remote desktop tools (RustDesk/VNC) are PRESERVED."
echo "----------------------------------------------------------------------"

# 1. Stop and disable dashboard service
if systemctl is-active --quiet streampulse-dashboard.service 2>/dev/null; then
  echo "  [+] Stopping streampulse-dashboard.service..."
  systemctl stop streampulse-dashboard.service 2>/dev/null || true
fi

if systemctl is-enabled --quiet streampulse-dashboard.service 2>/dev/null; then
  echo "  [+] Disabling streampulse-dashboard.service..."
  systemctl disable streampulse-dashboard.service 2>/dev/null || true
fi

rm -f /etc/systemd/system/streampulse-dashboard.service
systemctl daemon-reload

# 2. Terminate any running kiosk instances
pkill -f "chromium-profile" 2>/dev/null || true
pkill -f "dashboard-kiosk.sh" 2>/dev/null || true

# 3. Clean dedicated browser profile & temporary locks
if [[ -d "/opt/streampulse/chromium-profile" ]]; then
  echo "  [+] Removing isolated kiosk browser profile (/opt/streampulse/chromium-profile)..."
  rm -rf /opt/streampulse/chromium-profile
fi

# 4. Remove binaries and kiosk configs while preserving logo directory
if [[ -d "/opt/streampulse/bin" ]]; then
  echo "  [+] Removing /opt/streampulse/bin scripts..."
  rm -rf /opt/streampulse/bin
fi

if [[ -f "/opt/streampulse/config/kiosk.conf" ]]; then
  echo "  [+] Removing /opt/streampulse/config/kiosk.conf..."
  rm -f /opt/streampulse/config/kiosk.conf
fi

echo "----------------------------------------------------------------------"
echo "Uninstallation completed safely."
echo "Note: Common logo folder (/opt/streampulse/logo) was preserved intact."
echo ""
echo "To restore a previous backup, run:"
echo "  sudo /opt/streampulse/bin/restore.sh"
echo "  or from home directory: ~/streampulse-backups/latest/"
echo "======================================================================"
