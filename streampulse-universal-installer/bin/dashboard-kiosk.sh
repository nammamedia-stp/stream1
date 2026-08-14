#!/usr/bin/env bash
# ==============================================================================
# StreamPulse Dashboard Kiosk Compatibility Wrapper
# Delegates to authoritative controller: /opt/streampulse/bin/streampulse-player.sh
# ==============================================================================
exec /opt/streampulse/bin/streampulse-player.sh "$@"
