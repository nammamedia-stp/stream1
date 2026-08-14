#!/usr/bin/env bash
# ==============================================================================
# StreamPulse Diagnostic Engine
# Path: /opt/streampulse/bin/diagnose.sh
# ==============================================================================

set -uo pipefail

echo "======================================================================"
echo "          StreamPulse Diagnostics Report"
echo "======================================================================"
echo "Timestamp:    $(date '+%Y-%m-%d %H:%M:%S')"
echo "Hostname:     $(hostname 2>/dev/null || echo 'unknown')"
echo "Hardware:     $(cat /proc/device-tree/model 2>/dev/null || uname -m)"
echo "OS:           $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '\"' || uname -s)"
echo "----------------------------------------------------------------------"

PLAYER_CONF="/opt/streampulse/config/player.conf"
if [[ -f "${PLAYER_CONF}" ]]; then
  CHANNEL="$(grep '^CHANNEL_NAME=' "${PLAYER_CONF}" | cut -d= -f2 | tr -d '\"')"
  RAW_KEY="$(grep '^STREAM_KEY=' "${PLAYER_CONF}" | cut -d= -f2 | tr -d '\"')"
  if (( ${#RAW_KEY} > 6 )); then
    MASKED_KEY="${RAW_KEY:0:3}******${RAW_KEY: -3}"
  else
    MASKED_KEY="******"
  fi
  echo "Assigned Channel: ${CHANNEL}"
  echo "Stream Key:       ${MASKED_KEY} (SECURE)"
  echo "Server URL:       $(grep '^SERVER_URL=' "${PLAYER_CONF}" | cut -d= -f2 | tr -d '\"')"
else
  echo "[!] Player configuration (${PLAYER_CONF}) missing."
fi

echo "----------------------------------------------------------------------"
echo "Authoritative Playback Service Status:"
for srv in streampulse-player.service streampulse-dashboard.service; do
  if systemctl is-active --quiet "${srv}" 2>/dev/null; then
    echo "  [OK] ${srv}: ACTIVE (Running)"
  elif systemctl is-enabled --quiet "${srv}" 2>/dev/null; then
    echo "  [WARN] ${srv}: ENABLED (Not active right now)"
  else
    echo "  [INFO] ${srv}: INACTIVE"
  fi
done

echo "----------------------------------------------------------------------"
echo "Competing Legacy Services Check:"
if systemctl is-active --quiet streampulse-rpi-player.service 2>/dev/null; then
  echo "  [FAIL] streampulse-rpi-player.service is running! (Competing service conflict)"
else
  echo "  [OK] No competing streampulse-rpi-player.service detected."
fi

ROGUE_MPV="$(pgrep -f "mpv.*motion-logo" | tr '\n' ' ')"
if [[ -n "${ROGUE_MPV}" ]]; then
  echo "  [WARN] Legacy mpv loop running: PID ${ROGUE_MPV}"
else
  echo "  [OK] No rogue mpv background processes."
fi

echo "----------------------------------------------------------------------"
echo "Process Lock & Display:"
if [[ -f /tmp/streampulse-player.lock ]]; then
  echo "  Lock File:   /tmp/streampulse-player.lock (Active)"
fi
echo "  IP Address:  $(hostname -I 2>/dev/null || echo 'none')"
echo "  Display:     ${DISPLAY:-:0} | Wayland: ${WAYLAND_DISPLAY:-wayland-0}"
echo "======================================================================"
