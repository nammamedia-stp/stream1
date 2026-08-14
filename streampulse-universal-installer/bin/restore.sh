#!/usr/bin/env bash
# ==============================================================================
# StreamPulse Restore Engine
# Managed by StreamPulse Universal Installer
# Path: /opt/streampulse/bin/restore.sh
# ==============================================================================

set -uo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Error: Restore script must be run as root (sudo)." >&2
  exit 1
fi

TARGET_USER="${SUDO_USER:-$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $3}' | head -n 1)}"
if [[ -z "${TARGET_USER}" ]] || [[ "${TARGET_USER}" == "root" ]]; then
  TARGET_USER="$(awk -F: '$3 == 1000 {print $1}' /etc/passwd 2>/dev/null || echo "himakara")"
fi

USER_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
if [[ -z "${USER_HOME}" ]] || [[ ! -d "${USER_HOME}" ]]; then
  USER_HOME="/home/${TARGET_USER}"
fi

BACKUP_SOURCE="${1:-${USER_HOME}/streampulse-backups/latest}"

if [[ ! -d "${BACKUP_SOURCE}" ]]; then
  echo "Error: Backup directory not found at '${BACKUP_SOURCE}'" >&2
  echo "Available backups in ${USER_HOME}/streampulse-backups/:"
  ls -la "${USER_HOME}/streampulse-backups/" 2>/dev/null || echo "  (None found)"
  exit 1
fi

echo "======================================================================"
echo "          StreamPulse Restore from Snapshot"
echo "======================================================================"
echo "Restoring from: ${BACKUP_SOURCE}"
echo "Target User:    ${TARGET_USER}"
echo "----------------------------------------------------------------------"

# 1. Stop current services safely
systemctl stop streampulse-dashboard.service 2>/dev/null || true

# 2. Restore systemd units
if [[ -d "${BACKUP_SOURCE}/systemd" ]]; then
  echo "  [+] Restoring systemd unit files..."
  cp -p "${BACKUP_SOURCE}/systemd/"*.service /etc/systemd/system/ 2>/dev/null || true
  systemctl daemon-reload
fi

# 3. Restore /opt/streampulse configs
if [[ -d "${BACKUP_SOURCE}/opt_streampulse" ]]; then
  echo "  [+] Restoring /opt/streampulse directory items..."
  if [[ -d "${BACKUP_SOURCE}/opt_streampulse/config" ]]; then
    mkdir -p /opt/streampulse/config
    cp -rp "${BACKUP_SOURCE}/opt_streampulse/config/"* /opt/streampulse/config/ 2>/dev/null || true
  fi
  if [[ -d "${BACKUP_SOURCE}/opt_streampulse/bin" ]]; then
    mkdir -p /opt/streampulse/bin
    cp -rp "${BACKUP_SOURCE}/opt_streampulse/bin/"* /opt/streampulse/bin/ 2>/dev/null || true
    chmod +x /opt/streampulse/bin/*.sh 2>/dev/null || true
  fi
  if [[ -f "${BACKUP_SOURCE}/opt_streampulse/rpi_player.py" ]]; then
    cp -p "${BACKUP_SOURCE}/opt_streampulse/rpi_player.py" /opt/streampulse/
  fi
fi

# 4. Restore user autostarts if present in backup
if [[ -d "${BACKUP_SOURCE}/user_autostart" ]]; then
  echo "  [+] Restoring autostart configuration files..."
  if [[ -f "${BACKUP_SOURCE}/user_autostart/autostart" ]]; then
    mkdir -p "${USER_HOME}/.config/labwc"
    cp -p "${BACKUP_SOURCE}/user_autostart/autostart" "${USER_HOME}/.config/labwc/autostart"
    chown -R "${TARGET_USER}:${TARGET_USER}" "${USER_HOME}/.config/labwc" 2>/dev/null || true
  fi
fi

# 5. Restart services if enabled
if systemctl is-enabled streampulse-dashboard.service >/dev/null 2>&1; then
  echo "  [+] Restarting streampulse-dashboard.service..."
  systemctl restart streampulse-dashboard.service 2>/dev/null || true
fi

echo "----------------------------------------------------------------------"
echo "Restore operation finished successfully."
echo "======================================================================"
