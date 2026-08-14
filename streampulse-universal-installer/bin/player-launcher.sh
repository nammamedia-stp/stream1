#!/usr/bin/env bash
# ==============================================================================
# StreamPulse Player Engine Launcher Compatibility Wrapper
# Delegates to authoritative controller: /opt/streampulse/bin/streampulse-player.sh
# (Eliminates separate competing mpv/cvlc process loop)
# ==============================================================================
exec /opt/streampulse/bin/streampulse-player.sh "$@"
