#!/usr/bin/env bash
# ==============================================================================
# StreamPulse Backup Engine
# Managed by StreamPulse Universal Installer
# Path: /opt/streampulse/bin/backup.sh
# ==============================================================================

set -uo pipefail

# Detect Target User & Home
TARGET_USER="${1:-${SUDO_USER:-$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $3}' | head -n 1)}}"
if [[ -z "${TARGET_USER}" ]] || [[ "${TARGET_USER}" == "root" ]]; then
  # Fallback to UID 1000 user if available
  TARGET_USER="$(awk -F: '$3 == 1000 {print $1}' /etc/passwd 2>/dev/null || echo "himakara")"
fi

USER_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
if [[ -z "${USER_HOME}" ]] || [[ ! -d "${USER_HOME}" ]]; then
  USER_HOME="/home/${TARGET_USER}"
fi

TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
BACKUP_BASE="${USER_HOME}/streampulse-backups"
BACKUP_DIR="${BACKUP_BASE}/${TIMESTAMP}"

echo "======================================================================"
echo "          StreamPulse Backup Creation Snapshot"
echo "======================================================================"
echo "Timestamp:    ${TIMESTAMP}"
echo "Target User:  ${TARGET_USER}"
echo "Target Home:  ${USER_HOME}"
echo "Backup Path:  ${BACKUP_DIR}"
echo "----------------------------------------------------------------------"

mkdir -p "${BACKUP_DIR}"

# 1. Back up systemd service units
mkdir -p "${BACKUP_DIR}/systemd"
for srv in streampulse-dashboard.service streampulse-rpi-player.service streampulse-kiosk.service streampulse.service rpi-kiosk.service; do
  if [[ -f "/etc/systemd/system/${srv}" ]]; then
    echo "  [+] Backing up systemd unit: /etc/systemd/system/${srv}"
    cp -p "/etc/systemd/system/${srv}" "${BACKUP_DIR}/systemd/"
  fi
  if [[ -f "/lib/systemd/system/${srv}" ]]; then
    echo "  [+] Backing up library unit: /lib/systemd/system/${srv}"
    cp -p "/lib/systemd/system/${srv}" "${BACKUP_DIR}/systemd/"
  fi
done

# 2. Back up /opt/streampulse configurations and scripts (excluding large video binaries if any)
if [[ -d "/opt/streampulse" ]]; then
  mkdir -p "${BACKUP_DIR}/opt_streampulse"
  echo "  [+] Backing up /opt/streampulse structure & configs..."
  if [[ -d "/opt/streampulse/config" ]]; then
    cp -rp "/opt/streampulse/config" "${BACKUP_DIR}/opt_streampulse/"
  fi
  if [[ -d "/opt/streampulse/bin" ]]; then
    cp -rp "/opt/streampulse/bin" "${BACKUP_DIR}/opt_streampulse/"
  fi
  if [[ -f "/opt/streampulse/rpi_player.py" ]]; then
    cp -p "/opt/streampulse/rpi_player.py" "${BACKUP_DIR}/opt_streampulse/"
  fi
fi

# 3. Back up user autostart files (Labwc, XDG, Openbox, LXDE)
mkdir -p "${BACKUP_DIR}/user_autostart"
for autostart_path in \
  "${USER_HOME}/.config/labwc/autostart" \
  "${USER_HOME}/.config/labwc/environment" \
  "${USER_HOME}/.config/autostart" \
  "${USER_HOME}/.config/openbox/autostart" \
  "${USER_HOME}/.config/lxsession/LXDE-pi/autostart" \
  "/etc/xdg/labwc/autostart" \
  "/etc/xdg/autostart"; do
  if [[ -e "${autostart_path}" ]]; then
    echo "  [+] Backing up autostart config: ${autostart_path}"
    cp -rp "${autostart_path}" "${BACKUP_DIR}/user_autostart/" 2>/dev/null || true
  fi
done

# 4. Save metadata manifest
cat <<MANIFEST > "${BACKUP_DIR}/manifest.json"
{
  "timestamp": "${TIMESTAMP}",
  "user": "${TARGET_USER}",
  "user_home": "${USER_HOME}",
  "backup_dir": "${BACKUP_DIR}",
  "hostname": "$(hostname 2>/dev/null || echo 'raspberrypi')",
  "uname": "$(uname -a 2>/dev/null || echo '')"
}
MANIFEST

# Fix permissions so the non-root user owns their backup folder
chown -R "${TARGET_USER}:${TARGET_USER}" "${BACKUP_BASE}" 2>/dev/null || true

# Update latest symlink
ln -sfn "${BACKUP_DIR}" "${BACKUP_BASE}/latest"

echo "----------------------------------------------------------------------"
echo "Backup completed successfully -> ${BACKUP_DIR}"
echo "Symlinked to: ${BACKUP_BASE}/latest"
echo "======================================================================"
