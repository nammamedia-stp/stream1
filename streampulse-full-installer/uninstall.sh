#!/usr/bin/env bash
# ==============================================================================
# StreamPulse Master Installer - Safe Uninstallation Script
# Location: /opt/streampulse/bin/uninstall.sh or ./uninstall.sh
# Removes master installer kiosk services safely without deleting media or player
# ==============================================================================

set -uo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run as root (e.g. sudo bash uninstall.sh)"
  exit 1
fi

TARGET_USER="${SUDO_USER:-$(whoami 2>/dev/null || echo "himakara")}"
if [ "$TARGET_USER" = "root" ]; then
  TARGET_USER="$(logname 2>/dev/null || id -un 1000 2>/dev/null || echo "himakara")"
fi
TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6 || echo "/home/$TARGET_USER")"

echo "========================================================================"
echo "          StreamPulse Master Suite - Safe Uninstaller                   "
echo "========================================================================"

echo "[1/4] Stopping and disabling StreamPulse Dashboard Kiosk services..."
systemctl stop streampulse-dashboard.service 2>/dev/null || true
systemctl disable streampulse-dashboard.service 2>/dev/null || true
rm -f /etc/systemd/system/streampulse-dashboard.service 2>/dev/null || true
systemctl daemon-reload

echo "[2/4] Removing kiosk launch scripts and configs..."
rm -f /opt/streampulse/bin/dashboard-kiosk.sh 2>/dev/null || true
rm -f /opt/streampulse/config/kiosk.conf 2>/dev/null || true

# Remove labwc autostart kiosk line if present
if [ -f "${TARGET_HOME}/.config/labwc/autostart" ]; then
  sed -i '/dashboard-kiosk\.sh/d' "${TARGET_HOME}/.config/labwc/autostart" 2>/dev/null || true
fi

# Remove desktop autostart entry if present
rm -f "${TARGET_HOME}/.config/autostart/streampulse-kiosk.desktop" 2>/dev/null || true

echo "[3/4] Preserving media, player service, and user configurations..."
echo "  - /opt/streampulse/media preserved"
echo "  - streampulse-rpi-player service preserved"
echo "  - RustDesk and Audio (PipeWire/WirePlumber) untouched"

echo "[4/4] Finalizing uninstallation..."
echo "========================================================================"
echo "✓ StreamPulse Kiosk Suite has been successfully uninstalled."
echo "If you wish to fully restore your pre-installation snapshot, run:"
echo "  sudo bash /opt/streampulse/bin/restore.sh"
echo "========================================================================"
