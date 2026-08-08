#!/bin/bash

# StreamPulse Multi-Bitrate Adaptive HLS Transcoding Script v2.1
# Dynamic Variant Configuration & Hostinger VPS Production Optimized Engine
# Strict Session Ownership & Parent/Child PID Isolation Enabled
# Args: $1 = Stream Key / Stream Name

set -euo pipefail

STREAM_KEY=$1
HLS_PATH="/var/www/hls/${STREAM_KEY}"
RTMP_INPUT="rtmp://127.0.0.1:1935/live/${STREAM_KEY}"
LOG_FILE="/var/log/nginx/transcode_${STREAM_KEY}.log"
PID_FILE="/tmp/ffmpeg_${STREAM_KEY}.pid"
TRANSCODER_PID_FILE="/tmp/transcoder_${STREAM_KEY}.pid"
SESSION_FILE="/tmp/transcoder_${STREAM_KEY}.session"
FFMPEG_CMD_FILE="/tmp/ffmpeg_cmd_${STREAM_KEY}.sh"
SESSION_ID="$(date +%s%N)_$$"

if [ -z "$STREAM_KEY" ]; then
    echo "No stream key specified. Exiting..."
    exit 1
fi

mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
touch "$LOG_FILE" 2>/dev/null || true

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "=========================================================="
log "StreamPulse Production Transcoder Initiated for key: ${STREAM_KEY} | Session: ${SESSION_ID}"
log "RTMP Input Target: ${RTMP_INPUT}"

FFMPEG_PID=""
CLEANUP_DONE=0

cleanup() {
    local exit_code=$?
    if [ "$CLEANUP_DONE" -eq 1 ]; then
        return
    fi
    CLEANUP_DONE=1
    trap - EXIT SIGTERM SIGINT SIGHUP SIGQUIT

    log "Termination event received (exit status: $exit_code). Initiating cleanup for session: ${SESSION_ID}..."

    if [ -n "${FFMPEG_PID:-}" ] && kill -0 "$FFMPEG_PID" 2>/dev/null; then
        log "Sending SIGTERM to child FFmpeg process (PID: $FFMPEG_PID)..."
        kill -TERM "$FFMPEG_PID" 2>/dev/null || true
        local count=0
        while kill -0 "$FFMPEG_PID" 2>/dev/null && [ $count -lt 30 ]; do
            sleep 0.1
            count=$((count + 1))
        done
        if kill -0 "$FFMPEG_PID" 2>/dev/null; then
            log "FFmpeg process PID $FFMPEG_PID did not exit on SIGTERM. Sending SIGKILL..."
            kill -KILL "$FFMPEG_PID" 2>/dev/null || true
        fi
    fi

    # Check if this session still owns the active stream session before removing HLS output
    local active_session=""
    if [ -f "$SESSION_FILE" ]; then
        active_session=$(cat "$SESSION_FILE" 2>/dev/null || echo "")
    fi

    if [ -z "$active_session" ] || [ "$active_session" = "$SESSION_ID" ]; then
        log "Cleaning up HLS output directory for ${STREAM_KEY} (Session: ${SESSION_ID})..."
        rm -rf "$HLS_PATH" 2>/dev/null || true
        rm -f "$SESSION_FILE" 2>/dev/null || true
    else
        log "Skipping HLS directory cleanup for ${STREAM_KEY}: new active session detected ($active_session != $SESSION_ID)."
    fi

    if [ -f "$PID_FILE" ]; then
        local curr_pid
        curr_pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
        if [ "$curr_pid" = "${FFMPEG_PID:-}" ]; then
            rm -f "$PID_FILE" 2>/dev/null || true
        fi
    fi

    if [ -f "$TRANSCODER_PID_FILE" ]; then
        local curr_trans_pid
        curr_trans_pid=$(cat "$TRANSCODER_PID_FILE" 2>/dev/null || echo "")
        if [ "$curr_trans_pid" = "$$" ]; then
            rm -f "$TRANSCODER_PID_FILE" 2>/dev/null || true
        fi
    fi

    rm -f "$FFMPEG_CMD_FILE" 2>/dev/null || true

    log "Transcoding process for ${STREAM_KEY} (Session: ${SESSION_ID}) finished."

    if [ "$exit_code" -ne 0 ]; then
        exit "$exit_code"
    fi
}

trap 'cleanup' SIGTERM SIGINT SIGHUP SIGQUIT EXIT

# Graceful cleanup of any prior transcoder instance for this stream key
if [ -f "$TRANSCODER_PID_FILE" ]; then
    OLD_TRANSCODER_PID=$(cat "$TRANSCODER_PID_FILE" 2>/dev/null || echo "")
    if [ -n "$OLD_TRANSCODER_PID" ] && kill -0 "$OLD_TRANSCODER_PID" 2>/dev/null; then
        if grep -q "${STREAM_KEY}" "/proc/$OLD_TRANSCODER_PID/cmdline" 2>/dev/null; then
            log "Gracefully stopping prior transcoder session (PID $OLD_TRANSCODER_PID) for stream key: ${STREAM_KEY}"
            kill -TERM "$OLD_TRANSCODER_PID" 2>/dev/null || true
            count=0
            while kill -0 "$OLD_TRANSCODER_PID" 2>/dev/null && [ $count -lt 30 ]; do
                sleep 0.1
                count=$((count + 1))
            done
            if kill -0 "$OLD_TRANSCODER_PID" 2>/dev/null; then
                log "Prior transcoder session (PID $OLD_TRANSCODER_PID) did not stop on SIGTERM. Sending SIGKILL..."
                kill -KILL "$OLD_TRANSCODER_PID" 2>/dev/null || true
            fi
        fi
    fi
    rm -f "$TRANSCODER_PID_FILE" 2>/dev/null || true
fi

# Write current transcoder script PID and Session ID
echo "$$" > "$TRANSCODER_PID_FILE"
echo "$SESSION_ID" > "$SESSION_FILE"

# Clean up any leftover FFmpeg child process PID file from prior session
if [ -f "$PID_FILE" ]; then
    OLD_FFMPEG_PID=$(cat "$PID_FILE" 2>/dev/null || echo "")
    if [ -n "$OLD_FFMPEG_PID" ] && kill -0 "$OLD_FFMPEG_PID" 2>/dev/null; then
        kill -TERM "$OLD_FFMPEG_PID" 2>/dev/null || true
        sleep 0.2
        if kill -0 "$OLD_FFMPEG_PID" 2>/dev/null; then
            kill -KILL "$OLD_FFMPEG_PID" 2>/dev/null || true
        fi
    fi
    rm -f "$PID_FILE" 2>/dev/null || true
fi

# Ensure output HLS root directory exists and is completely clean for fresh session
rm -rf "$HLS_PATH" 2>/dev/null || true
mkdir -p "$HLS_PATH" 2>/dev/null || true

# Function to probe both video and audio tracks on RTMP_INPUT
HAS_VIDEO="false"
HAS_AUDIO="false"

probe_stream() {
    local probe_v
    probe_v=$(ffprobe -v error \
        -rw_timeout 5000000 \
        -analyzeduration 10000000 \
        -probesize 10000000 \
        -select_streams v:0 \
        -show_entries stream=codec_name \
        -of csv=p=0 "$RTMP_INPUT" 2>/dev/null || echo "")

    local probe_a
    probe_a=$(ffprobe -v error \
        -rw_timeout 5000000 \
        -analyzeduration 10000000 \
        -probesize 10000000 \
        -select_streams a:0 \
        -show_entries stream=codec_name \
        -of csv=p=0 "$RTMP_INPUT" 2>/dev/null || echo "")

    HAS_VIDEO="false"
    HAS_AUDIO="false"

    if [ -n "$probe_v" ]; then
        HAS_VIDEO="true"
    fi
    if [ -n "$probe_a" ]; then
        HAS_AUDIO="true"
    fi
}

# 1. PROBE PHASE: Wait for video track to become available before attempting FFmpeg launch
MAX_PROBE_ATTEMPTS=15
probe_attempt=0

while [ $probe_attempt -lt $MAX_PROBE_ATTEMPTS ]; do
    probe_attempt=$((probe_attempt + 1))
    probe_stream
    log "[PROBE] Attempt ${probe_attempt}/${MAX_PROBE_ATTEMPTS} for ${STREAM_KEY} | Video detected: ${HAS_VIDEO} | Audio detected: ${HAS_AUDIO}"

    if [ "$HAS_VIDEO" = "true" ]; then
        log "[PROBE SUCCESS] Video stream detected on attempt ${probe_attempt}."
        break
    fi

    if [ $probe_attempt -lt $MAX_PROBE_ATTEMPTS ]; then
        sleep 1.5
    fi
done

if [ "$HAS_VIDEO" != "true" ]; then
    log "[PROBE ERROR] Video stream not detected on ${RTMP_INPUT} after ${MAX_PROBE_ATTEMPTS} attempts. Exiting."
    exit 1
fi

# Query dynamic stream profile configuration from local API
CONFIG_JSON=$(curl -sf --max-time 3 "http://127.0.0.1:3000/api/rtmp/transcode-config/${STREAM_KEY}" || echo "")

generate_ffmpeg_command() {
    node - "$CONFIG_JSON" "$RTMP_INPUT" "$HLS_PATH" "$FFMPEG_CMD_FILE" "$HAS_AUDIO" << 'EOF'
const fs = require('fs');
const [,, configJsonStr, rtmpInput, hlsPath, outputFile, hasAudioStr] = process.argv;
const hasAudio = hasAudioStr === 'true';

let config = null;
try {
  if (configJsonStr && configJsonStr.trim().startsWith('{')) {
    config = JSON.parse(configJsonStr);
  }
} catch (e) {
  console.error("Config parse error:", e);
}

// Fallback variants if server API unreachable
let variants = [
  { name: '1080p', width: 1920, height: 1080, bitrate: '4500k', maxBitrate: '4800k', bufferSize: '7500k', audioBitrate: '128k' },
  { name: '720p',  width: 1280, height: 720,  bitrate: '2500k', maxBitrate: '2700k', bufferSize: '4000k', audioBitrate: '128k' },
  { name: '480p',  width: 854,  height: 480,  bitrate: '1200k', maxBitrate: '1350k', bufferSize: '2000k', audioBitrate: '96k' },
  { name: '360p',  width: 640,  height: 360,  bitrate: '700k',  maxBitrate: '800k',  bufferSize: '1200k', audioBitrate: '64k' }
];

if (config && Array.isArray(config.variants) && config.variants.length > 0) {
  variants = config.variants;
}

// Create subdirectories for all variants
variants.forEach(v => {
  const vDir = `${hlsPath}/${v.name}`;
  if (!fs.existsSync(vDir)) {
    fs.mkdirSync(vDir, { recursive: true });
  }
});

// Construct FFmpeg filter graph (only for transcoded variants, bypassing stream-copy / Original)
const transcodedItems = variants.map((v, i) => {
  const isCopy = !!(v.isOriginal || v.videoCodec === 'copy' || v.name === 'Original' || v.name === 'Source (Original)' || v.width === 0 || v.height === 0);
  return { v, i, isCopy };
}).filter(x => !x.isCopy);

let filterParts = [];
if (transcodedItems.length === 1) {
  const item = transcodedItems[0];
  filterParts.push(`[0:v:0]scale=w=${item.v.width}:h=${item.v.height}:force_original_aspect_ratio=decrease:flags=bicubic,pad=${item.v.width}:${item.v.height}:(ow-iw)/2:(oh-ih)/2,format=yuv420p[v${item.i}]`);
} else if (transcodedItems.length > 1) {
  let splitStr = `[0:v:0]split=${transcodedItems.length}`;
  for (let idx = 0; idx < transcodedItems.length; idx++) {
    splitStr += `[vin${idx}]`;
  }
  filterParts.push(splitStr);

  transcodedItems.forEach((item, idx) => {
    filterParts.push(`[vin${idx}]scale=w=${item.v.width}:h=${item.v.height}:force_original_aspect_ratio=decrease:flags=bicubic,pad=${item.v.width}:${item.v.height}:(ow-iw)/2:(oh-ih)/2,format=yuv420p[v${item.i}]`);
  });
}

const args = [
  'exec',
  'ffmpeg',
  '-y',
  '-rw_timeout', '5000000',
  '-analyzeduration', '10000000',
  '-probesize', '10000000',
  '-i', `"${rtmpInput}"`
];

if (filterParts.length > 0) {
  const filterComplex = filterParts.join(';\n ');
  args.push('-filter_complex', `"${filterComplex}"`);
}

let varStreamMapParts = [];

variants.forEach((v, i) => {
  const isCopy = !!(v.isOriginal || v.videoCodec === 'copy' || v.name === 'Original' || v.name === 'Source (Original)' || v.width === 0 || v.height === 0);
  const preset = v.encoderPreset || 'superfast';

  let bv = v.bitrate;
  if (!bv || bv === '0k' || bv === '0') {
    bv = isCopy ? '0k' : '2500k';
  }
  let maxrate = v.maxBitrate;
  if (!maxrate || maxrate === '0k' || maxrate === '0') {
    maxrate = isCopy ? '0k' : '2875k';
  }
  let bufsize = v.bufferSize;
  if (!bufsize || bufsize === '0k' || bufsize === '0') {
    bufsize = isCopy ? '0k' : '4000k';
  }
  let ba = v.audioBitrate;
  if (!ba || ba === '0k' || ba === '0') {
    ba = isCopy ? '0k' : '128k';
  }

  if (isCopy) {
    args.push('-map', '0:v:0', `-c:v:${i}`, 'copy');
    if (hasAudio) {
      args.push('-map', '0:a:0?', `-c:a:${i}`, 'copy');
    }
  } else {
    args.push(
      '-map', `"[v${i}]"`,
      `-c:v:${i}`, 'libx264',
      `-preset:v:${i}`, preset,
      `-profile:v:${i}`, 'main',
      `-level:v:${i}`, '4.1',
      `-pix_fmt:v:${i}`, 'yuv420p',
      `-b:v:${i}`, bv,
      `-maxrate:v:${i}`, maxrate,
      `-bufsize:v:${i}`, bufsize,
      `-g:v:${i}`, '60',
      `-keyint_min:v:${i}`, '60',
      `-sc_threshold:v:${i}`, '0'
    );
    if (hasAudio) {
      args.push(
        '-map', '0:a:0?',
        `-c:a:${i}`, 'aac',
        `-b:a:${i}`, ba,
        `-ac:a:${i}`, '2',
        `-ar:a:${i}`, '44100'
      );
    }
  }
  if (hasAudio) {
    varStreamMapParts.push(`v:${i},a:${i},name:${v.name}`);
  } else {
    varStreamMapParts.push(`v:${i},name:${v.name}`);
  }
});

args.push(
  '-f', 'hls',
  '-hls_time', '2',
  '-hls_list_size', '6',
  '-hls_flags', 'delete_segments+independent_segments+omit_endlist',
  '-start_number', '1',
  '-hls_segment_type', 'mpegts',
  '-master_pl_name', 'master.m3u8',
  '-hls_segment_filename', `"${hlsPath}/%v/file%05d.ts"`,
  '-var_stream_map', `"${varStreamMapParts.join(' ')}"`,
  `"${hlsPath}/%v/index.m3u8"`
);

fs.writeFileSync(outputFile, args.join(' '));
EOF
}

generate_ffmpeg_command
chmod +x "$FFMPEG_CMD_FILE" 2>/dev/null || true

# 2. FFMPEG EXECUTION & RETRY LOOP: Resilient against initial RTMP connection race conditions
MAX_FFMPEG_RETRIES=10
ffmpeg_retry_count=0
STARTUP_THRESHOLD_SECONDS=10

while [ $ffmpeg_retry_count -lt $MAX_FFMPEG_RETRIES ]; do
    ffmpeg_retry_count=$((ffmpeg_retry_count + 1))

    # Re-probe and regenerate command if retrying after startup exit
    if [ $ffmpeg_retry_count -gt 1 ]; then
        log "[FFMPEG RETRY] Re-probing RTMP input before attempt ${ffmpeg_retry_count}/${MAX_FFMPEG_RETRIES}..."
        probe_stream
        if [ "$HAS_VIDEO" != "true" ]; then
            log "[FFMPEG RETRY] Video track missing on re-probe. Publisher disconnected or unavailable. Exiting."
            break
        fi
        generate_ffmpeg_command
        chmod +x "$FFMPEG_CMD_FILE" 2>/dev/null || true
    fi

    log "[FFMPEG LAUNCH] Attempt ${ffmpeg_retry_count}/${MAX_FFMPEG_RETRIES} | Command: $(cat "$FFMPEG_CMD_FILE")"

    start_time=$(date +%s)

    bash "$FFMPEG_CMD_FILE" >> "$LOG_FILE" 2>&1 &
    FFMPEG_PID=$!
    echo "$FFMPEG_PID" > "$PID_FILE"

    log "[FFMPEG RUNNING] Stream Key: ${STREAM_KEY} | PID: ${FFMPEG_PID} | Attempt: ${ffmpeg_retry_count}"

    FFMPEG_EXIT=0
    wait "$FFMPEG_PID" || FFMPEG_EXIT=$?

    end_time=$(date +%s)
    runtime=$((end_time - start_time))

    log "[FFMPEG EXITED] Stream Key: ${STREAM_KEY} | PID: ${FFMPEG_PID} | Exit Code: ${FFMPEG_EXIT} | Runtime: ${runtime}s"

    if [ "$CLEANUP_DONE" -eq 1 ]; then
        log "[FFMPEG CLEANUP] Process exited due to script termination signal. Stopping loop."
        break
    fi

    # Check if publisher disconnected vs transient failure
    log "[RTMP CHECK] Probing RTMP input to verify if publisher is still active..."
    probe_stream

    if [ "$HAS_VIDEO" != "true" ]; then
        log "[RTMP DISCONNECT] RTMP stream no longer active on ${RTMP_INPUT}. Publisher disconnected. Stopping transcoder."
        break
    fi

    # Reset retry counter if process was running stably before exiting
    if [ $runtime -ge $STARTUP_THRESHOLD_SECONDS ]; then
        log "[FFMPEG STABLE] FFmpeg ran for ${runtime}s (>= ${STARTUP_THRESHOLD_SECONDS}s). Resetting retry counter."
        ffmpeg_retry_count=0
    fi

    if [ "$FFMPEG_EXIT" -eq 0 ]; then
        log "[FFMPEG SUCCESS] Process exited cleanly with exit code 0."
        break
    fi

    if [ $ffmpeg_retry_count -lt $MAX_FFMPEG_RETRIES ]; then
        log "[FFMPEG RETRY] Transient failure detected (code ${FFMPEG_EXIT}, runtime ${runtime}s). Retrying in 2 seconds..."
        sleep 2
    else
        log "[FFMPEG FATAL] FFmpeg failed ${MAX_FFMPEG_RETRIES} consecutive times. Exiting transcoder."
        exit $FFMPEG_EXIT
    fi
done


