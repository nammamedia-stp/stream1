#!/bin/bash

# StreamPulse Multi-Bitrate Adaptive HLS Transcoding Script
# Dynamic Variant Configuration & Hostinger VPS (2 vCPU / 8GB RAM) Production Optimized Engine
# Args: $1 = Stream Key / Stream Name

set -euo pipefail

STREAM_KEY=$1
HLS_PATH="/var/www/hls/${STREAM_KEY}"
RTMP_INPUT="rtmp://127.0.0.1:1935/live/${STREAM_KEY}"
LOG_FILE="/var/log/nginx/transcode_${STREAM_KEY}.log"

if [ -z "$STREAM_KEY" ]; then
    echo "No stream key specified. Exiting..."
    exit 1
fi

touch "$LOG_FILE" 2>/dev/null || true
echo "==========================================================" >> "$LOG_FILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] StreamPulse Production Transcoder Initiated for key: ${STREAM_KEY}" >> "$LOG_FILE"

FFMPEG_PID=""
PID_FILE="/tmp/ffmpeg_${STREAM_KEY}.pid"
FFMPEG_CMD_FILE="/tmp/ffmpeg_cmd_${STREAM_KEY}.sh"

cleanup() {
    trap - EXIT SIGTERM SIGINT SIGHUP SIGQUIT
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Termination signal received. Initiating cleanup..." >> "$LOG_FILE"
    if [ -n "$FFMPEG_PID" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Sending SIGTERM to FFmpeg PID: $FFMPEG_PID" >> "$LOG_FILE"
        kill -TERM "$FFMPEG_PID" 2>/dev/null || true
        wait "$FFMPEG_PID" 2>/dev/null || true
    fi
    if [ -f "$PID_FILE" ]; then
        CURR_PID=$(cat "$PID_FILE" 2>/dev/null || echo "")
        if [ "$CURR_PID" = "$FFMPEG_PID" ]; then
            rm -f "$PID_FILE" 2>/dev/null || true
        fi
    fi
    rm -f "$FFMPEG_CMD_FILE" 2>/dev/null || true

    # HLS output directory cleanup is safely managed by StreamPulse server with a 60s grace period for encoder reconnects.
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Transcoding process for ${STREAM_KEY} stopped." >> "$LOG_FILE"
    exit 0
}

trap 'cleanup' SIGTERM SIGINT SIGHUP SIGQUIT EXIT

# Graceful cleanup of any previous FFmpeg session for this specific stream key using its isolated PID file
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null || echo "")
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        if grep -q "ffmpeg" "/proc/$OLD_PID/cmdline" 2>/dev/null && grep -q "${STREAM_KEY}" "/proc/$OLD_PID/cmdline" 2>/dev/null; then
            STATE=$(awk '{print $3}' "/proc/$OLD_PID/stat" 2>/dev/null || echo "")
            if [ "$STATE" != "Z" ]; then
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Gracefully stopping prior FFmpeg session (PID $OLD_PID) for stream key: ${STREAM_KEY}" >> "$LOG_FILE"
                kill -TERM "$OLD_PID" 2>/dev/null || true
                timeout=50
                while kill -0 "$OLD_PID" 2>/dev/null; do
                    STATE=$(awk '{print $3}' "/proc/$OLD_PID/stat" 2>/dev/null || echo "")
                    if [ "$STATE" = "Z" ]; then
                        break
                    fi
                    sleep 0.1
                    timeout=$((timeout - 1))
                    if [ "$timeout" -le 0 ]; then
                        break
                    fi
                done
            fi
        fi
    fi
    rm -f "$PID_FILE" 2>/dev/null || true
fi

# Query dynamic stream profile configuration from local API
CONFIG_JSON=$(curl -sf --max-time 3 "http://127.0.0.1:3000/api/rtmp/transcode-config/${STREAM_KEY}" || echo "")

FFMPEG_CMD_FILE="/tmp/ffmpeg_cmd_${STREAM_KEY}.sh"

# Probe incoming stream to determine if an audio track exists
HAS_AUDIO_TRACK=$(ffprobe -v error -rw_timeout 3000000 -select_streams a:0 -show_entries stream=index -of csv=p=0 "$RTMP_INPUT" 2>/dev/null || echo "")
HAS_AUDIO="false"
if [ -n "$HAS_AUDIO_TRACK" ]; then
  HAS_AUDIO="true"
fi

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
  '-analyzeduration', '500000',
  '-probesize', '500000',
  '-fflags', '+genpts+nobuffer',
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
  '-hls_flags', 'delete_segments+independent_segments+omit_endlist+append_list+discont_start',
  '-start_number', '1',
  '-hls_segment_type', 'mpegts',
  '-master_pl_name', 'master.m3u8',
  '-hls_segment_filename', `"${hlsPath}/%v/file%05d.ts"`,
  '-var_stream_map', `"${varStreamMapParts.join(' ')}"`,
  `"${hlsPath}/%v/index.m3u8"`
);

fs.writeFileSync(outputFile, args.join(' '));
EOF

chmod +x "$FFMPEG_CMD_FILE" 2>/dev/null || true

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Executing FFmpeg production command..." >> "$LOG_FILE"
cat "$FFMPEG_CMD_FILE" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

bash "$FFMPEG_CMD_FILE" >> "$LOG_FILE" 2>&1 &
FFMPEG_PID=$!
echo "$FFMPEG_PID" > "$PID_FILE" 2>/dev/null || true

echo "[$(date '+%Y-%m-%d %H:%M:%S')] FFmpeg running with PID: $FFMPEG_PID" >> "$LOG_FILE"
FFMPEG_EXIT=0
wait "$FFMPEG_PID" || FFMPEG_EXIT=$?

rm -f "$FFMPEG_CMD_FILE" 2>/dev/null || true
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Transcode process ended with exit code: ${FFMPEG_EXIT}" >> "$LOG_FILE"
