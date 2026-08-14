#!/usr/bin/env bash
# ==============================================================================
# StreamPulse Kiosk Suite - Automated Pre-Flight Backup Engine
# Location: /opt/streampulse/bin/backup.sh
# Creates a timestamped snapshot of all relevant configuration and autostart files
# ==============================================================================

set -uo pipefail

TARGET_USER="${SUDO_USER:-$(whoami 2>/dev/null || echo "himakara")}"
if [ "$TARGET_USER" = "root" ]; then
  TARGET_USER="$(logname 2>/dev/null || id -un 1000 2>/dev/null || echo "himakara")"
fi
TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6 || echo "/home/$TARGET_USER")"

TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
BACKUP_BASE="${TARGET_HOME}/streampulse-backups"
BACKUP_DIR="${BACKUP_BASE}/${TIMESTAMP}"

echo "========================================================================"
echo "          StreamPulse Kiosk Suite - Pre-Flight Backup Engine            "
echo "========================================================================"
echo "Creating timestamped backup at: $BACKUP_DIR"

mkdir -p "$BACKUP_DIR/labwc" "$BACKUP_DIR/autostart" "$BACKUP_DIR/systemd-user" "$BACKUP_DIR/systemd-system" "$BACKUP_DIR/lightdm" "$BACKUP_DIR/opt" 2>/dev/null || true

MANIFEST_FILE="$BACKUP_DIR/manifest.txt"
{
  echo "StreamPulse Kiosk Backup Manifest"
  echo "Timestamp: $(date)"
  echo "User: $TARGET_USER"
  echo "Home: $TARGET_HOME"
  echo "OS: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"' || echo "Debian")"
  echo "----------------------------------------"
} > "$MANIFEST_FILE"

# 1. Backup Labwc Configurations
if [ -d "${TARGET_HOME}/.config/labwc" ]; then
  echo "[+] Backing up Labwc configurations..."
  cp -r "${TARGET_HOME}/.config/labwc/"* "$BACKUP_DIR/labwc/" 2>/dev/null || true
  echo "Labwc config directory: ${TARGET_HOME}/.config/labwc" >> "$MANIFEST_FILE"
fi

# 2. Backup XDG Autostart (.desktop files)
if [ -d "${TARGET_HOME}/.config/autostart" ]; then
  echo "[+] Backing up XDG autostart entries..."
  cp -r "${TARGET_HOME}/.config/autostart/"* "$BACKUP_DIR/autostart/" 2>/dev/null || true
  echo "XDG Autostart directory: ${TARGET_HOME}/.config/autostart" >> "$MANIFEST_FILE"
fi

# 3. Backup User Systemd Services
if [ -d "${TARGET_HOME}/.config/systemd/user" ]; then
  echo "[+] Backing up user systemd units..."
  cp -r "${TARGET_HOME}/.config/systemd/user/"* "$BACKUP_DIR/systemd-user/" 2>/dev/null || true
  echo "User systemd units: ${TARGET_HOME}/.config/systemd/user" >> "$MANIFEST_FILE"
fi

# 4. Backup System Systemd Services (Player, Kiosk, StreamPulse)
echo "[+] Backing up relevant systemd services..."
for svc in /etc/systemd/system/streampulse* /etc/systemd/system/kiosk* /etc/systemd/system/*player* /etc/systemd/system/*logo*; do
  if [ -f "$svc" ]; then
    cp "$svc" "$BACKUP_DIR/systemd-system/" 2>/dev/null || true
    echo "System systemd unit: $svc" >> "$MANIFEST_FILE"
  fi
done

# 5. Backup LightDM Autologin Configuration
if [ -d /etc/lightdm ]; then
  echo "[+] Backing up LightDM display manager configs..."
  [ -f /etc/lightdm/lightdm.conf ] && cp /etc/lightdm/lightdm.conf "$BACKUP_DIR/lightdm/" 2>/dev/null || true
  [ -d /etc/lightdm/lightdm.conf.d ] && cp -r /etc/lightdm/lightdm.conf.d "$BACKUP_DIR/lightdm/" 2>/dev/null || true
  echo "LightDM configs backed up" >> "$MANIFEST_FILE"
fi

# 6. Backup existing /opt/streampulse files if present
if [ -d /opt/streampulse ]; then
  echo "[+] Backing up existing /opt/streampulse scripts..."
  cp -r /opt/streampulse "$BACKUP_DIR/opt/" 2>/dev/null || true
  echo "Opt directory: /opt/streampulse" >> "$MANIFEST_FILE"
fi

# Fix ownership
chown -R "$TARGET_USER:$TARGET_USER" "$BACKUP_DIR" 2>/dev/null || true
chown -R "$TARGET_USER:$TARGET_USER" "$BACKUP_BASE" 2>/dev/null || true

# Create symlink to latest
ln -sfn "$BACKUP_DIR" "${BACKUP_BASE}/latest" 2>/dev/null || true

echo "------------------------------------------------------------------------"
echo "✓ Pre-flight backup successfully created at:"
echo "  $BACKUP_DIR"
echo "  Symlink: ${BACKUP_BASE}/latest"
echo "========================================================================"
