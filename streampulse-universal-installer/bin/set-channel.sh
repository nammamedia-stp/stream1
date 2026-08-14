#!/usr/bin/env bash
# ==============================================================================
# StreamPulse Channel Switcher Utility
# Managed by StreamPulse Universal Installer
# Path: /opt/streampulse/bin/set-channel.sh
# Usage: sudo /opt/streampulse/bin/set-channel.sh <channel_name> [stream_key]
# ==============================================================================

set -uo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Error: set-channel.sh must be run with root privileges (sudo)." >&2
  exit 1
fi

NEW_CHANNEL="${1:-}"
NEW_STREAM_KEY="${2:-}"

if [[ -z "${NEW_CHANNEL}" ]]; then
  echo "Usage: sudo /opt/streampulse/bin/set-channel.sh <channel_name> [stream_key]"
  echo ""
  echo "Example: sudo /opt/streampulse/bin/set-channel.sh channel2"
  echo "         sudo /opt/streampulse/bin/set-channel.sh channel3 live_event_key"
  exit 1
fi

# Sanitize channel name (alphanumeric, underscore, hyphen)
if [[ ! "${NEW_CHANNEL}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "Error: Invalid channel name '${NEW_CHANNEL}'. Must contain only alphanumeric characters, dashes, or underscores." >&2
  exit 1
fi

CONFIG_FILE="/opt/streampulse/config/player.conf"
mkdir -p /opt/streampulse/config

# Load current config if present
CURRENT_CHANNEL="unknown"
if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck source=/dev/null
  CURRENT_CHANNEL="$(grep '^CHANNEL_NAME=' "${CONFIG_FILE}" | cut -d= -f2 | tr -d '"' || echo 'unknown')"
fi

echo "======================================================================"
echo "          StreamPulse Per-Pi Channel Update"
echo "======================================================================"
echo "Current Channel: ${CURRENT_CHANNEL}"
echo "Target Channel:  ${NEW_CHANNEL}"
if [[ -n "${NEW_STREAM_KEY}" ]]; then
  # Mask secret stream key in console logs
  KEY_LEN=${#NEW_STREAM_KEY}
  if (( KEY_LEN > 6 )); then
    MASKED_KEY="${NEW_STREAM_KEY:0:3}***${NEW_STREAM_KEY: -3}"
  else
    MASKED_KEY="******"
  fi
  echo "New Stream Key:  ${MASKED_KEY}"
fi
echo "Timestamp:       $(date '+%Y-%m-%d %H:%M:%S')"
echo "----------------------------------------------------------------------"

# Update player.conf atomically
TMP_CONF="$(mktemp)"
if [[ -f "${CONFIG_FILE}" ]]; then
  cp "${CONFIG_FILE}" "${TMP_CONF}"
  # Replace CHANNEL_NAME
  if grep -q '^CHANNEL_NAME=' "${TMP_CONF}"; then
    sed -i "s|^CHANNEL_NAME=.*|CHANNEL_NAME=\"${NEW_CHANNEL}\"|" "${TMP_CONF}"
  else
    echo "CHANNEL_NAME=\"${NEW_CHANNEL}\"" >> "${TMP_CONF}"
  fi
  # Update STREAM_KEY if provided
  if [[ -n "${NEW_STREAM_KEY}" ]]; then
    if grep -q '^STREAM_KEY=' "${TMP_CONF}"; then
      sed -i "s|^STREAM_KEY=.*|STREAM_KEY=\"${NEW_STREAM_KEY}\"|" "${TMP_CONF}"
    else
      echo "STREAM_KEY=\"${NEW_STREAM_KEY}\"" >> "${TMP_CONF}"
    fi
  fi
  # Update timestamp
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

# Preserve player ownership if needed
DETECTED_USER="${SUDO_USER:-$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $3}' | grep -v '^root$' | head -n1 || awk -F: '$3 == 1000 {print $1}' /etc/passwd 2>/dev/null || stat -c '%U' "${CONFIG_FILE}" 2>/dev/null || echo '')}"
if [[ -n "${DETECTED_USER}" ]] && id -u "${DETECTED_USER}" >/dev/null 2>&1; then
  chown "${DETECTED_USER}:${DETECTED_USER}" "${CONFIG_FILE}" 2>/dev/null || true
fi

echo "  [+] Updated configuration saved to ${CONFIG_FILE}"

# Check for existing player services and restart only the player service
PLAYER_RESTARTED=0
for srv in streampulse-rpi-player.service streampulse-player.service rpi-player.service; do
  if systemctl is-active --quiet "${srv}" 2>/dev/null || systemctl is-enabled --quiet "${srv}" 2>/dev/null; then
    echo "  [+] Restarting player service: ${srv}..."
    systemctl restart "${srv}" 2>/dev/null || true
    PLAYER_RESTARTED=1
  fi
done

if (( PLAYER_RESTARTED == 0 )); then
  echo "  [i] No active standalone player service detected to restart (player configuration updated for next run)."
fi

# Verification
VERIFIED_CHANNEL="$(grep '^CHANNEL_NAME=' "${CONFIG_FILE}" | cut -d= -f2 | tr -d '"')"
echo "----------------------------------------------------------------------"
if [[ "${VERIFIED_CHANNEL}" == "${NEW_CHANNEL}" ]]; then
  echo "[OK] Pi channel successfully switched to '${NEW_CHANNEL}'."
else
  echo "[FAIL] Verification failed. Channel in config is '${VERIFIED_CHANNEL}'." >&2
  exit 1
fi
echo "Logo playback, dashboard kiosk, and remote management preserved."
echo "======================================================================"
