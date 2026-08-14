#!/usr/bin/env bash
# ==============================================================================
# StreamPulse Suite - Automated Rollback & Restore Engine
# Location: /opt/streampulse/bin/restore.sh or ./restore.sh
# Restores previous configuration from timestamped backup
# ==============================================================================

set -uo pipefail

TARGET_USER="${SUDO_USER:-$(whoami 2>/dev/null || echo "himakara")}"
if [ "$TARGET_USER" = "root" ]; then
  TARGET_USER="$(logname 2>/dev/null || id -un 1000 2>/dev/null || echo "himakara")"
fi
TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6 || echo "/home/$TARGET_USER")"
BACKUP_BASE="${TARGET_HOME}/streampulse-backups"

# Determine backup directory
SPECIFIED_DIR="${1:-}"
if [ -n "$SPECIFIED_DIR" ] && [ -d "$SPECIFIED_DIR" ]; then
  BACKUP_DIR="$SPECIFIED_DIR"
elif [ -L "${BACKUP_BASE}/latest" ] && [ -d "${BACKUP_BASE}/latest" ]; then
  BACKUP_DIR="$(readlink -f "${BACKUP_BASE}/latest")"
else
  # Find most recent directory in BACKUP_BASE
  BACKUP_DIR="$(ls -td "${BACKUP_BASE}"/20* 2>/dev/null | head -n 1 || true)"
fi

echo "========================================================================"
echo "          StreamPulse Suite - System Restore & Rollback Engine          "
echo "========================================================================"

if [ -z "$BACKUP_DIR" ] || [ ! -d "$BACKUP_DIR" ]; then
  echo "Error: No backup directory found in $BACKUP_BASE to restore."
  exit 1
fi

echo "Restoring system state from: $BACKUP_DIR"
if [ -f "$BACKUP_DIR/manifest.txt" ]; then
  echo "Manifest information:"
  cat "$BACKUP_DIR/manifest.txt" | head -n 6
  echo "----------------------------------------"
fi

# 1. Stop and disable master kiosk services
echo "[1/6] Stopping StreamPulse Dashboard Kiosk service..."
systemctl stop streampulse-dashboard.service 2>/dev/null || true
systemctl disable streampulse-dashboard.service 2>/dev/null || true
rm -f /etc/systemd/system/streampulse-dashboard.service 2>/dev/null || true

# 2. Restore Labwc configurations
echo "[2/6] Restoring Labwc configurations..."
if [ -d "$BACKUP_DIR/labwc" ] && [ "$(ls -A "$BACKUP_DIR/labwc" 2>/dev/null)" ]; then
  mkdir -p "${TARGET_HOME}/.config/labwc"
  cp -r "$BACKUP_DIR/labwc/"* "${TARGET_HOME}/.config/labwc/" 2>/dev/null || true
  chown -R "$TARGET_USER:$TARGET_USER" "${TARGET_HOME}/.config/labwc" 2>/dev/null || true
  echo "  ✓ Restored Labwc files to ${TARGET_HOME}/.config/labwc"
fi

# 3. Restore XDG Autostart entries
echo "[3/6] Restoring XDG Autostart entries..."
if [ -d "$BACKUP_DIR/autostart" ] && [ "$(ls -A "$BACKUP_DIR/autostart" 2>/dev/null)" ]; then
  mkdir -p "${TARGET_HOME}/.config/autostart"
  cp -r "$BACKUP_DIR/autostart/"* "${TARGET_HOME}/.config/autostart/" 2>/dev/null || true
  chown -R "$TARGET_USER:$TARGET_USER" "${TARGET_HOME}/.config/autostart" 2>/dev/null || true
  echo "  ✓ Restored XDG autostart files to ${TARGET_HOME}/.config/autostart"
fi

# 4. Restore User Systemd Services
echo "[4/6] Restoring User Systemd Units..."
if [ -d "$BACKUP_DIR/systemd-user" ] && [ "$(ls -A "$BACKUP_DIR/systemd-user" 2>/dev/null)" ]; then
  mkdir -p "${TARGET_HOME}/.config/systemd/user"
  cp -r "$BACKUP_DIR/systemd-user/"* "${TARGET_HOME}/.config/systemd/user/" 2>/dev/null || true
  chown -R "$TARGET_USER:$TARGET_USER" "${TARGET_HOME}/.config/systemd/user" 2>/dev/null || true
  echo "  ✓ Restored user systemd units"
fi

# 5. Restore System Systemd Services
echo "[5/6] Restoring System Systemd Services..."
if [ -d "$BACKUP_DIR/systemd-system" ] && [ "$(ls -A "$BACKUP_DIR/systemd-system" 2>/dev/null)" ]; then
  cp -r "$BACKUP_DIR/systemd-system/"* /etc/systemd/system/ 2>/dev/null || true
  echo "  ✓ Restored system systemd unit files"
fi

# 6. Restore LightDM configs
echo "[6/6] Restoring Display Manager settings..."
if [ -d "$BACKUP_DIR/lightdm" ]; then
  [ -f "$BACKUP_DIR/lightdm/lightdm.conf" ] && cp "$BACKUP_DIR/lightdm/lightdm.conf" /etc/lightdm/ 2>/dev/null || true
  [ -d "$BACKUP_DIR/lightdm/lightdm.conf.d" ] && cp -r "$BACKUP_DIR/lightdm/lightdm.conf.d" /etc/lightdm/ 2>/dev/null || true
  echo "  ✓ Restored LightDM configuration"
fi

# Reload daemons
systemctl daemon-reload 2>/dev/null || true

echo "========================================================================"
echo "✓ System restoration completed successfully from:"
echo "  $BACKUP_DIR"
echo "========================================================================"
