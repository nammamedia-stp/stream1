#!/usr/bin/env bash
# ==============================================================================
# StreamPulse Channel Switcher Utility
# Path: /opt/streampulse/bin/set-channel.sh
# ==============================================================================

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Error: set-channel.sh must be run with root privileges (sudo)." >&2
  exit 1
fi

NEW_CHANNEL="${1:-}"
NEW_STREAM_KEY="${2:-}"

if [[ -z "${NEW_CHANNEL}" ]]; then
  echo "Usage: sudo /opt/streampulse/bin/set-channel.sh <channel_name> [stream_key]"
  echo "Example: sudo /opt/streampulse/bin/set-channel.sh channel2"
  exit 1
fi

if [[ ! "${NEW_CHANNEL}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "Error: Invalid channel name '${NEW_CHANNEL}'. Alphanumerics, hyphens and underscores only." >&2
  exit 1
fi

CONFIG_FILE="/opt/streampulse/config/player.conf"
mkdir -p /opt/streampulse/config

CURRENT_CHANNEL="unknown"
if [[ -f "${CONFIG_FILE}" ]]; then
  CURRENT_CHANNEL="$(grep '^CHANNEL_NAME=' "${CONFIG_FILE}" | cut -d= -f2 | tr -d '"' || echo 'unknown')"
fi

echo "======================================================================"
echo "          StreamPulse Per-Pi Channel Update"
echo "======================================================================"
echo "Current Channel: ${CURRENT_CHANNEL}"
echo "Target Channel:  ${NEW_CHANNEL}"
echo "Timestamp:       $(date '+%Y-%m-%d %H:%M:%S')"
echo "----------------------------------------------------------------------"

TMP_CONF="$(mktemp)"
if [[ -f "${CONFIG_FILE}" ]]; then
  cp "${CONFIG_FILE}" "${TMP_CONF}"
  if grep -q '^CHANNEL_NAME=' "${TMP_CONF}"; then
    sed -i "s|^CHANNEL_NAME=.*|CHANNEL_NAME=\"${NEW_CHANNEL}\"|" "${TMP_CONF}"
  else
    echo "CHANNEL_NAME=\"${NEW_CHANNEL}\"" >> "${TMP_CONF}"
  fi
  if [[ -n "${NEW_STREAM_KEY}" ]]; then
    if grep -q '^STREAM_KEY=' "${TMP_CONF}"; then
      sed -i "s|^STREAM_KEY=.*|STREAM_KEY=\"${NEW_STREAM_KEY}\"|" "${TMP_CONF}"
    else
      echo "STREAM_KEY=\"${NEW_STREAM_KEY}\"" >> "${TMP_CONF}"
    fi
  fi
  if grep -q '^LAST_UPDATED=' "${TMP_CONF}"; then
    sed -i "s|^LAST_UPDATED=.*|LAST_UPDATED=\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"|" "${TMP_CONF}"
  else
    echo "LAST_UPDATED=\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"" >> "${TMP_CONF}"
  fi
else
  cat <<CONF > "${TMP_CONF}"
# StreamPulse Player & Channel Configuration
CHANNEL_NAME="${NEW_CHANNEL}"
STREAM_KEY="${NEW_STREAM_KEY:-live_stream}"
SERVER_URL="http://187.127.210.81"
LOGO_DIR="/opt/streampulse/logo"
OFFLINE_LOGO_MEDIA="/opt/streampulse/logo/motion-logo.mp4"
OFFLINE_FALLBACK_HTML="/opt/streampulse/logo/logo-fallback.html"
PLAYBACK_MODE="auto"
ENABLE_HW_ACCEL=1
AUDIO_OUTPUT="default"
LAST_UPDATED="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
CONF
fi

mv "${TMP_CONF}" "${CONFIG_FILE}"
chmod 644 "${CONFIG_FILE}"

DETECTED_USER="${SUDO_USER:-$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $3}' | grep -v '^root$' | head -n1 || awk -F: '$3 == 1000 {print $1}' /etc/passwd 2>/dev/null || echo '')}"
if [[ -n "${DETECTED_USER}" ]] && id -u "${DETECTED_USER}" >/dev/null 2>&1; then
  chown "${DETECTED_USER}:${DETECTED_USER}" "${CONFIG_FILE}" 2>/dev/null || true
fi

echo "  [+] Updated configuration saved to ${CONFIG_FILE}"

# Safely restart the single authoritative player service
if systemctl is-active --quiet streampulse-player.service 2>/dev/null || systemctl is-enabled --quiet streampulse-player.service 2>/dev/null; then
  echo "  [+] Reloading authoritative service: streampulse-player.service..."
  systemctl restart streampulse-player.service 2>/dev/null || true
fi

VERIFIED_CHANNEL="$(grep '^CHANNEL_NAME=' "${CONFIG_FILE}" | cut -d= -f2 | tr -d '"')"
if [[ "${VERIFIED_CHANNEL}" == "${NEW_CHANNEL}" ]]; then
  echo "[OK] Pi channel successfully switched to '${NEW_CHANNEL}'."
else
  echo "[FAIL] Verification failed. Channel in config is '${VERIFIED_CHANNEL}'." >&2
  exit 1
fi
