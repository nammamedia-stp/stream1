#!/bin/bash

# StreamPulse Multi-Bitrate Adaptive HLS Transcoding Script
# Dynamic Variant Configuration & Hostinger VPS (2 vCPU / 8GB RAM) Production Optimized Engine
# Args: $1 = Stream Key / Stream Name

set -euo pipefail

STREAM_KEY=$1
HLS_PATH="/var/www/hls/${STREAM_KEY}"
RTMP_INPUT="rtmp://127.0.0.1:1935/ingest/${STREAM_KEY}"
LOG_FILE="/var/log/nginx/transcode_${STREAM_KEY}.log"

if [ -z "$STREAM_KEY" ]; then
    echo "No stream key specified. Exiting..."
    exit 1
fi

touch "$LOG_FILE" 2>/dev/null || true
echo "==========================================================" >> "$LOG_FILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] StreamPulse Production Transcoder Initiated for key: ${STREAM_KEY}" >> "$LOG_FILE"

FFMPEG_PID=""

cleanup() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Termination signal received. Initiating cleanup..." >> "$LOG_FILE"
    if [ -n "$FFMPEG_PID" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Sending SIGTERM to FFmpeg PID: $FFMPEG_PID" >> "$LOG_FILE"
        kill -TERM "$FFMPEG_PID" 2>/dev/null || true
        wait "$FFMPEG_PID" 2>/dev/null || true
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Transcoding process for ${STREAM_KEY} stopped." >> "$LOG_FILE"
    exit 0
}

trap 'cleanup' SIGTERM SIGINT SIGHUP SIGQUIT EXIT

# Detect audio stream presence with rapid 1s timeout (no sleep delay)
HAS_AUDIO=0
AUDIO_COUNT=$(ffprobe -v error -rw_timeout 1000000 -select_streams a -show_entries stream=codec_name -of csv=p=0 "$RTMP_INPUT" 2>/dev/null | grep -c "[a-zA-Z0-9]" || true)

if [ "$AUDIO_COUNT" -gt 0 ]; then
    HAS_AUDIO=1
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Audio track detected in input stream." >> "$LOG_FILE"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] No audio track detected. Proceeding with video-only transcode." >> "$LOG_FILE"
fi

# Query dynamic stream profile configuration from local API
CONFIG_JSON=$(curl -sf --max-time 1 "http://127.0.0.1:3000/api/rtmp/transcode-config/${STREAM_KEY}" || echo "")

FFMPEG_CMD_FILE="/tmp/ffmpeg_cmd_${STREAM_KEY}.sh"

node - "$CONFIG_JSON" "$RTMP_INPUT" "$HLS_PATH" "$HAS_AUDIO" "$FFMPEG_CMD_FILE" << 'EOF'
const fs = require('fs');
const [,, configJsonStr, rtmpInput, hlsPath, hasAudioStr, outputFile] = process.argv;

let config = null;
try {
  if (configJsonStr && configJsonStr.trim().startsWith('{')) {
    config = JSON.parse(configJsonStr);
  }
} catch (e) {
  console.error("Config parse error:", e);
}

const hasAudio = hasAudioStr === '1';
const sessionTag = Date.now();

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

// Construct FFmpeg filter graph
let filterParts = [];
if (variants.length === 1) {
  const v = variants[0];
  if (v.width === 0 || v.height === 0 || v.name === 'Original' || v.name === 'Source (Original)') {
    filterParts.push(`[v:0]null[v0]`);
  } else {
    filterParts.push(`[v:0]scale=w=${v.width}:h=${v.height}:force_original_aspect_ratio=decrease:flags=bicubic,pad=${v.width}:${v.height}:(ow-iw)/2:(oh-ih)/2,format=yuv420p[v0]`);
  }
} else {
  let splitStr = `[v:0]split=${variants.length}`;
  for (let i = 0; i < variants.length; i++) {
    splitStr += `[vin${i}]`;
  }
  filterParts.push(splitStr);

  variants.forEach((v, i) => {
    if (v.width === 0 || v.height === 0 || v.name === 'Original' || v.name === 'Source (Original)') {
      filterParts.push(`[vin${i}]null[v${i}]`);
    } else {
      filterParts.push(`[vin${i}]scale=w=${v.width}:h=${v.height}:force_original_aspect_ratio=decrease:flags=bicubic,pad=${v.width}:${v.height}:(ow-iw)/2:(oh-ih)/2,format=yuv420p[v${i}]`);
    }
  });
}

const filterComplex = filterParts.join(';\n ');

const args = [
  'ffmpeg',
  '-y',
  '-rw_timeout', '5000000',
  '-i', `"${rtmpInput}"`,
  '-filter_complex', `"${filterComplex}"`
];

let varStreamMapParts = [];

variants.forEach((v, i) => {
  const preset = v.encoderPreset || 'superfast';
  const bv = v.bitrate || '2500k';
  const maxrate = v.maxBitrate || '2700k';
  const bufsize = v.bufferSize || '4000k';

  args.push(
    '-map', `"[v${i}]"`,
    `-c:v:${i}`, 'libx264',
    `-preset:v:${i}`, preset,
    `-b:v:${i}`, bv,
    `-maxrate:v:${i}`, maxrate,
    `-bufsize:v:${i}`, bufsize,
    `-g:v:${i}`, '60',
    `-keyint_min:v:${i}`, '60',
    `-sc_threshold:v:${i}`, '0'
  );

  if (hasAudio) {
    const ba = v.audioBitrate || '128k';
    args.push(
      '-map', '0:a:0?',
      `-c:a:${i}`, 'aac',
      `-b:a:${i}`, ba,
      `-ac:a:${i}`, '2',
      `-ar:a:${i}`, '44100'
    );
    varStreamMapParts.push(`v:${i},a:${i},name:${v.name}`);
  } else {
    varStreamMapParts.push(`v:${i},name:${v.name}`);
  }
});

args.push(
  '-f', 'hls',
  '-hls_time', '2',
  '-hls_list_size', '5',
  '-hls_flags', 'delete_segments+omit_endlist+independent_segments+program_date_time+discont_start',
  '-hls_segment_type', 'mpegts',
  '-master_pl_name', 'master.m3u8',
  '-hls_segment_filename', `"${hlsPath}/%v/seg_${sessionTag}_%05d.ts"`,
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

echo "[$(date '+%Y-%m-%d %H:%M:%S')] FFmpeg running with PID: $FFMPEG_PID" >> "$LOG_FILE"
wait "$FFMPEG_PID"

rm -f "$FFMPEG_CMD_FILE" 2>/dev/null || true
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Transcode process ended with exit code: $?" >> "$LOG_FILE"
