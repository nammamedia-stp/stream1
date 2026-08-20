#!/usr/bin/env bash
# ==============================================================================
# StreamPulse Lightweight Auto-Update Engine
# Runs safely on boot via streampulse-update.service
# Path: /opt/streampulse/bin/streampulse-update.sh
# ==============================================================================

set -uo pipefail

PLAYER_CONF="/opt/streampulse/config/player.conf"
VERSION_FILE="/opt/streampulse/VERSION"
LOCAL_VERSION="1.0.0"

if [[ -f "${VERSION_FILE}" ]]; then
  LOCAL_VERSION="$(tr -d ' \r\n' < "${VERSION_FILE}" || echo "1.0.0")"
fi

if [[ ! -f "${PLAYER_CONF}" ]]; then
  echo "[StreamPulse Update] Configuration (${PLAYER_CONF}) missing. Skipping update check."
  exit 0
fi

SERVER_URL="$(grep '^SERVER_URL=' "${PLAYER_CONF}" 2>/dev/null | cut -d= -f2- | tr -d '"\r\n' || echo '')"
if [[ -z "${SERVER_URL}" ]]; then
  echo "[StreamPulse Update] SERVER_URL not defined in player.conf. Skipping update check."
  exit 0
fi

# Ensure trailing slash removed
SERVER_URL="${SERVER_URL%/}"

echo "[StreamPulse Update] Checking for updates (Local Version: ${LOCAL_VERSION}, Server: ${SERVER_URL})..."

# Fetch server version with strict timeout
REMOTE_VERSION_RESP="$(curl -sSL -m 8 --connect-timeout 5 "${SERVER_URL}/api/rpi-player/version" 2>/dev/null || echo '')"

if [[ -z "${REMOTE_VERSION_RESP}" ]]; then
  echo "[StreamPulse Update] Server unreachable or network offline. Preserving current version (${LOCAL_VERSION})."
  exit 0
fi

# Extract version string (support plain text or JSON { "version": "x.y.z" })
if echo "${REMOTE_VERSION_RESP}" | grep -q '^{'; then
  REMOTE_VERSION="$(echo "${REMOTE_VERSION_RESP}" | grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4 || echo '')"
else
  REMOTE_VERSION="$(echo "${REMOTE_VERSION_RESP}" | tr -d ' \r\n' || echo '')"
fi

if [[ -z "${REMOTE_VERSION}" ]]; then
  echo "[StreamPulse Update] Invalid version response from server. Preserving current version (${LOCAL_VERSION})."
  exit 0
fi

echo "[StreamPulse Update] Remote version: ${REMOTE_VERSION} | Local version: ${LOCAL_VERSION}"

if [[ "${REMOTE_VERSION}" == "${LOCAL_VERSION}" ]]; then
  echo "[StreamPulse Update] StreamPulse is up to date (${LOCAL_VERSION}). No action required."
  exit 0
fi

echo "[StreamPulse Update] New StreamPulse update detected: ${REMOTE_VERSION} (Current: ${LOCAL_VERSION}). Initiating safe update..."

# Create staging and backup directories
STAGING_DIR="/tmp/streampulse-update-staging"
BACKUP_DIR="/opt/streampulse/backups/pre-update-${LOCAL_VERSION}"
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}" "${BACKUP_DIR}"

# 1. Download updated installer payload
UPDATE_SCRIPT="${STAGING_DIR}/full-install.sh"
if ! curl -fsSL -m 30 --connect-timeout 10 "${SERVER_URL}/api/rpi-player/script/universal-install" -o "${UPDATE_SCRIPT}"; then
  echo "[StreamPulse Update] [ERROR] Failed to download update payload from server. Aborting update." >&2
  rm -rf "${STAGING_DIR}"
  exit 0
fi

# 2. Syntax integrity check
if ! bash -n "${UPDATE_SCRIPT}"; then
  echo "[StreamPulse Update] [ERROR] Downloaded update script failed syntax verification (bash -n). Aborting." >&2
  rm -rf "${STAGING_DIR}"
  exit 0
fi

# 3. Create pre-update backup of current scripts, configs, and assets
echo "[StreamPulse Update] Backing up current installation to ${BACKUP_DIR}..."
cp -rp /opt/streampulse/bin "${BACKUP_DIR}/" 2>/dev/null || true
cp -rp /opt/streampulse/config "${BACKUP_DIR}/" 2>/dev/null || true
cp -p /opt/streampulse/logo/player.html "${BACKUP_DIR}/" 2>/dev/null || true
cp -p /opt/streampulse/logo/logo-fallback.html "${BACKUP_DIR}/" 2>/dev/null || true
cp -p /opt/streampulse/logo/hls.min.js "${BACKUP_DIR}/" 2>/dev/null || true
[[ -f /opt/streampulse/logo/motion-logo.mp4 ]] && cp -p /opt/streampulse/logo/motion-logo.mp4 "${BACKUP_DIR}/" 2>/dev/null || true
[[ -f "${VERSION_FILE}" ]] && cp -p "${VERSION_FILE}" "${BACKUP_DIR}/" 2>/dev/null || true

# 4. Execute the update using installer in safe non-destructive update mode
echo "[StreamPulse Update] Applying StreamPulse update payload (${REMOTE_VERSION})..."

CHANNEL="$(grep '^CHANNEL_NAME=' "${PLAYER_CONF}" 2>/dev/null | cut -d= -f2- | tr -d '"\r\n' || echo 'channel1')"
STREAM_KEY="$(grep '^STREAM_KEY=' "${PLAYER_CONF}" 2>/dev/null | cut -d= -f2- | tr -d '"\r\n' || echo 'live_stream')"

if bash "${UPDATE_SCRIPT}" --channel "${CHANNEL}" --key "${STREAM_KEY}" --server "${SERVER_URL}" --no-validate; then
  echo "${REMOTE_VERSION}" > "${VERSION_FILE}"
  echo "[StreamPulse Update] [SUCCESS] StreamPulse successfully updated to version ${REMOTE_VERSION}!"
  
  # Trigger post-update validation if available
  if [[ -x "/opt/streampulse/bin/validate.sh" ]]; then
    /opt/streampulse/bin/validate.sh || true
  fi
else
  echo "[StreamPulse Update] [ERROR] Update execution failed. Rolling back previous version..." >&2
  if [[ -d "${BACKUP_DIR}/bin" ]]; then
    cp -rp "${BACKUP_DIR}/bin/"* /opt/streampulse/bin/ 2>/dev/null || true
  fi
  if [[ -f "${BACKUP_DIR}/player.html" ]]; then
    cp -p "${BACKUP_DIR}/player.html" /opt/streampulse/logo/ 2>/dev/null || true
  fi
  if [[ -f "${BACKUP_DIR}/logo-fallback.html" ]]; then
    cp -p "${BACKUP_DIR}/logo-fallback.html" /opt/streampulse/logo/ 2>/dev/null || true
  fi
  if [[ -f "${BACKUP_DIR}/hls.min.js" ]]; then
    cp -p "${BACKUP_DIR}/hls.min.js" /opt/streampulse/logo/ 2>/dev/null || true
  fi
  if [[ -f "${BACKUP_DIR}/motion-logo.mp4" ]]; then
    cp -p "${BACKUP_DIR}/motion-logo.mp4" /opt/streampulse/logo/ 2>/dev/null || true
  fi
  if [[ -f "${BACKUP_DIR}/VERSION" ]]; then
    cp -p "${BACKUP_DIR}/VERSION" /opt/streampulse/ 2>/dev/null || true
  fi
  systemctl restart streampulse-player.service 2>/dev/null || true
  echo "[StreamPulse Update] Rollback complete. Preserved working version ${LOCAL_VERSION}."
fi

# Clean temporary staging
rm -rf "${STAGING_DIR}"
exit 0
