#!/usr/bin/env bash
# ==============================================================================
# StreamPulse Restoration Engine
# Managed by StreamPulse Universal Installer
# Path: /opt/streampulse/bin/restore.sh
# ==============================================================================

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Error: restore.sh must be run as root (sudo)." >&2
  exit 1
fi

TARGET_USER="${1:-${SUDO_USER:-$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $3}' | grep -v '^root$' | head -n 1 || awk -F: '$3 >= 1000 {print $1}' /etc/passwd | head -n1 || echo '')}}"
USER_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
BACKUP_BASE="${USER_HOME}/streampulse-backups"

RESTORE_DIR="${2:-${BACKUP_BASE}/latest}"
if [[ ! -d "${RESTORE_DIR}" ]]; then
  echo "Error: No backup directory found at ${RESTORE_DIR}." >&2
  exit 1
fi

echo "======================================================================"
echo "          StreamPulse Rollback & Restore"
echo "======================================================================"
echo "Restoring from: ${RESTORE_DIR}"
echo "----------------------------------------------------------------------"

if [[ -d "${RESTORE_DIR}/systemd" ]]; then
  cp -p "${RESTORE_DIR}/systemd/"*.service /etc/systemd/system/ 2>/dev/null || true
  systemctl daemon-reload
fi

if [[ -d "${RESTORE_DIR}/config" ]]; then
  mkdir -p /opt/streampulse/config
  cp -rp "${RESTORE_DIR}/config/"* /opt/streampulse/config/ 2>/dev/null || true
fi

if [[ -d "${RESTORE_DIR}/autostart/autostart" ]] && [[ -d "${USER_HOME}/.config/labwc" ]]; then
  cp -p "${RESTORE_DIR}/autostart/autostart" "${USER_HOME}/.config/labwc/autostart" 2>/dev/null || true
fi

for srv in streampulse-player.service streampulse-dashboard.service; do
  if systemctl is-enabled --quiet "${srv}" 2>/dev/null; then
    systemctl restart "${srv}" 2>/dev/null || true
  fi
done

echo "[OK] System configuration successfully restored from snapshot."
