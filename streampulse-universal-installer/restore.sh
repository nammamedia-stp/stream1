#!/usr/bin/env bash
# ==============================================================================
# StreamPulse Restore Wrapper
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "/opt/streampulse/bin/restore.sh" ]]; then
  exec /opt/streampulse/bin/restore.sh "$@"
elif [[ -f "${SCRIPT_DIR}/bin/restore.sh" ]]; then
  exec "${SCRIPT_DIR}/bin/restore.sh" "$@"
else
  echo "Error: restore.sh not found." >&2
  exit 1
fi
