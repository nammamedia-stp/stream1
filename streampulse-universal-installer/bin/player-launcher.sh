#!/usr/bin/env bash
# ==============================================================================
# StreamPulse Player Engine Launcher
# Managed by StreamPulse Universal Installer
# Path: /opt/streampulse/bin/player-launcher.sh
# ==============================================================================

set -euo pipefail

PLAYER_CONF="/opt/streampulse/config/player.conf"

if [[ -f "${PLAYER_CONF}" ]]; then
  # shellcheck source=/dev/null
  source "${PLAYER_CONF}"
else
  CHANNEL_NAME="channel1"
  STREAM_KEY="live_stream"
  SERVER_URL="http://187.127.210.81"
  LOGO_DIR="/opt/streampulse/logo"
  OFFLINE_LOGO_MEDIA="/opt/streampulse/logo/motion-logo.mp4"
  OFFLINE_FALLBACK_HTML="/opt/streampulse/logo/logo-fallback.html"
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse Player] Launching Player Engine..."
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse Player] Assigned Channel: ${CHANNEL_NAME}"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse Player] Server Endpoint: ${SERVER_URL}"

# Determine primary and fallback playback sources
PRIMARY_STREAM="${SERVER_URL}/hls/${CHANNEL_NAME}.m3u8"
FALLBACK_STREAM="${SERVER_URL}/hls/${STREAM_KEY}/master.m3u8"
LOCAL_LOGO="${OFFLINE_LOGO_MEDIA:-/opt/streampulse/logo/motion-logo.mp4}"

# Continuous playback loop with automatic stream recovery & logo fallback
while true; do
  # Check if primary channel stream is live
  if curl -s -f -m 3 "${PRIMARY_STREAM}" | grep -q "#EXTM3U" 2>/dev/null; then
    ACTIVE_SOURCE="${PRIMARY_STREAM}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse Player] Channel '${CHANNEL_NAME}' is LIVE. Streaming..."
  elif curl -s -f -m 3 "${FALLBACK_STREAM}" | grep -q "#EXTM3U" 2>/dev/null; then
    ACTIVE_SOURCE="${FALLBACK_STREAM}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse Player] Stream Key '${STREAM_KEY}' is LIVE. Streaming..."
  elif [[ -f "${LOCAL_LOGO}" ]] && [[ -s "${LOCAL_LOGO}" ]]; then
    ACTIVE_SOURCE="${LOCAL_LOGO}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse Player] Stream offline. Playing local Motion Logo loop (${LOCAL_LOGO})..."
  else
    ACTIVE_SOURCE="${FALLBACK_STREAM}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse Player] Waiting for broadcast stream on channel '${CHANNEL_NAME}'..."
  fi

  # Play via MPV if available
  if command -v mpv >/dev/null 2>&1; then
    mpv --hwdec=auto \
        --vo=gpu \
        --fullscreen \
        --no-terminal \
        --cache=yes \
        --cache-secs=3 \
        --idle=once \
        "${ACTIVE_SOURCE}" || true
  elif command -v cvlc >/dev/null 2>&1; then
    cvlc --fullscreen \
         --no-video-title-show \
         --play-and-exit \
         "${ACTIVE_SOURCE}" vlc://quit || true
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [StreamPulse Player] Native media player (mpv/vlc) idle; web kiosk player is active."
    sleep 10
  fi

  sleep 2
done
