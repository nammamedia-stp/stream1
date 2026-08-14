#!/usr/bin/env bash
# ==============================================================================
# StreamPulse Backup Engine
# Managed by StreamPulse Universal Installer
# Path: /opt/streampulse/bin/backup.sh
# ==============================================================================

set -uo pipefail

TARGET_USER="${1:-${SUDO_USER:-$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $3}' | grep -v '^root$' | head -n 1 || awk -F: '$3 >= 1000 && $3 < 60000 {print $1}' /etc/passwd | head -n1 || echo '')}}"
if [[ -z "${TARGET_USER}" ]]; then
  echo "Error: Could not resolve target user for backup." >&2
  exit 1
fi

USER_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
BACKUP_BASE="${USER_HOME}/streampulse-backups"
BACKUP_DIR="${BACKUP_BASE}/${TIMESTAMP}"

echo "======================================================================"
echo "          StreamPulse Backup Creation Snapshot"
echo "======================================================================"
echo "Timestamp:    ${TIMESTAMP}"
echo "Target User:  ${TARGET_USER}"
echo "Backup Path:  ${BACKUP_DIR}"
echo "----------------------------------------------------------------------"

mkdir -p "${BACKUP_DIR}/systemd" "${BACKUP_DIR}/config" "${BACKUP_DIR}/bin" "${BACKUP_DIR}/autostart"

for srv in streampulse-player.service streampulse-dashboard.service streampulse-rpi-player.service streampulse-kiosk.service; do
  if [[ -f "/etc/systemd/system/${srv}" ]]; then
    cp -p "/etc/systemd/system/${srv}" "${BACKUP_DIR}/systemd/"
  fi
done

if [[ -d "/opt/streampulse/config" ]]; then
  cp -rp "/opt/streampulse/config" "${BACKUP_DIR}/"
fi
if [[ -d "/opt/streampulse/bin" ]]; then
  cp -rp "/opt/streampulse/bin" "${BACKUP_DIR}/"
fi

if [[ -f "${USER_HOME}/.config/labwc/autostart" ]]; then
  cp -p "${USER_HOME}/.config/labwc/autostart" "${BACKUP_DIR}/autostart/" 2>/dev/null || true
fi

cat <<MANIFEST > "${BACKUP_DIR}/manifest.json"
{
  "timestamp": "${TIMESTAMP}",
  "user": "${TARGET_USER}",
  "backup_dir": "${BACKUP_DIR}"
}
MANIFEST

chown -R "${TARGET_USER}:${TARGET_USER}" "${BACKUP_BASE}" 2>/dev/null || true
ln -sfn "${BACKUP_DIR}" "${BACKUP_BASE}/latest"

echo "Backup completed successfully -> ${BACKUP_DIR}"
