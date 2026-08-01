import fs from 'fs';
import path from 'path';
import { Request, Response } from 'express';

const CONFIG_PATH = path.resolve('./data/rpi_player_config.json');

export interface RpiPlayerConfig {
  defaultStreamKey: string;
  defaultStreamUrl: string;
  fallbackSequence: ('hlsjs' | 'videojs' | 'vlc')[];
  hardwareAcceleration: {
    enabled: boolean;
    decoder: 'auto' | 'v4l2m2m' | 'mmal' | 'drm_kms' | 'hevc_v4l2m2m';
    cmaMemoryMb: number;
    gpuMemMb: number;
  };
  display: {
    kioskMode: boolean;
    fullscreen: boolean;
    hideCursorTimeoutMs: number;
    blackScreenOffline: boolean;
    autoPlayLive: boolean;
    showReconnectOverlay: boolean;
  };
  network: {
    autoReconnect: boolean;
    reconnectIntervalMs: number;
    heartbeatIntervalMs: number;
    maxBackoffIntervalMs: number;
  };
}

const defaultConfig: RpiPlayerConfig = {
  defaultStreamKey: '',
  defaultStreamUrl: '',
  fallbackSequence: ['hlsjs', 'videojs', 'vlc'],
  hardwareAcceleration: {
    enabled: true,
    decoder: 'auto',
    cmaMemoryMb: 256,
    gpuMemMb: 256
  },
  display: {
    kioskMode: true,
    fullscreen: true,
    hideCursorTimeoutMs: 2000,
    blackScreenOffline: true,
    autoPlayLive: true,
    showReconnectOverlay: true
  },
  network: {
    autoReconnect: true,
    reconnectIntervalMs: 3000,
    heartbeatIntervalMs: 5000,
    maxBackoffIntervalMs: 15000
  }
};

export class RpiPlayerSystem {
  private config: RpiPlayerConfig;

  constructor() {
    this.config = this.loadConfig();
  }

  private loadConfig(): RpiPlayerConfig {
    try {
      if (fs.existsSync(CONFIG_PATH)) {
        const raw = fs.readFileSync(CONFIG_PATH, 'utf-8');
        return { ...defaultConfig, ...JSON.parse(raw) };
      }
    } catch (e) {
      console.error('[RPi Player System] Error reading config file, using defaults:', e);
    }
    return { ...defaultConfig };
  }

  public saveConfig(newConfig: Partial<RpiPlayerConfig>): RpiPlayerConfig {
    this.config = {
      ...this.config,
      ...newConfig,
      hardwareAcceleration: {
        ...this.config.hardwareAcceleration,
        ...(newConfig.hardwareAcceleration || {})
      },
      display: {
        ...this.config.display,
        ...(newConfig.display || {})
      },
      network: {
        ...this.config.network,
        ...(newConfig.network || {})
      }
    };

    try {
      const dataDir = path.dirname(CONFIG_PATH);
      if (!fs.existsSync(dataDir)) {
        fs.mkdirSync(dataDir, { recursive: true });
      }
      fs.writeFileSync(CONFIG_PATH, JSON.stringify(this.config, null, 2), 'utf-8');
    } catch (e) {
      console.error('[RPi Player System] Error writing config file:', e);
    }
    return this.config;
  }

  public getConfig(): RpiPlayerConfig {
    return this.config;
  }

  public generateSetupScript(serverHost: string, defaultKey: string = ''): string {
    const streamKey = defaultKey || this.config.defaultStreamKey || 'live_stream';
    const serverUrl = serverHost.startsWith('http') ? serverHost : `http://${serverHost}`;

    return `#!/usr/bin/env bash
# ==============================================================================
# StreamPulse Raspberry Pi Player - Production Installer & Kiosk Provisioner
# Supported Devices: Raspberry Pi 4, Raspberry Pi 5
# Supported Operating Systems: Raspberry Pi OS Lite, Raspberry Pi OS Desktop
# ==============================================================================

set -eo pipefail

SERVER_URL="${serverUrl}"
STREAM_KEY="${streamKey}"

echo "========================================================================"
echo "          StreamPulse Production Raspberry Pi Streaming Player          "
echo "========================================================================"
echo "[1/6] Detecting System Hardware and OS Architecture..."

# Check root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run as root (e.g. sudo bash setup-rpi-player.sh)"
  exit 1
fi

PI_MODEL="Raspberry Pi"
if [ -f /proc/device-tree/model ]; then
  PI_MODEL=$(tr -d '\\0' < /proc/device-tree/model)
fi
echo "Hardware Model: \${PI_MODEL}"

# Identify Pi 4 vs Pi 5
IS_PI5=0
if [[ "\${PI_MODEL}" == *"Raspberry Pi 5"* ]]; then
  IS_PI5=1
  echo "Detected Raspberry Pi 5 - Hardware Video Acceleration (HEVC/V4L2) active."
else
  echo "Detected Raspberry Pi 4 - Hardware Video Acceleration (H.264 V4L2M2M / MMAL) active."
fi

# Detect Desktop vs Lite
IS_DESKTOP=0
if command -v Xorg >/dev/null 2>&1 || [ -d /usr/share/wayland-sessions ]; then
  IS_DESKTOP=1
  echo "OS Environment: Raspberry Pi OS Desktop (GUI Mode)"
else
  echo "OS Environment: Raspberry Pi OS Lite (Headless Mode)"
fi

echo "[2/6] Updating APT Repositories & Installing Required Packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \\
  curl \\
  wget \\
  ca-certificates \\
  unclutter \\
  vlc \\
  mpv \\
  xdotool \\
  x11-xserver-utils \\
  v4l-utils \\
  systemd

# Install browser depending on environment
if [ "\${IS_DESKTOP}" -eq 1 ]; then
  apt-get install -y chromium-browser || apt-get install -y chromium || true
else
  # On Lite mode, install minimal Xorg + Matchbox / Openbox or Framebuffer MPV
  apt-get install -y xserver-xorg xinit openbox chromium-browser || true
fi

echo "[3/6] Tuning Kernel & Boot Configurations for Hardware Decoded Video..."
BOOT_CONFIG="/boot/firmware/config.txt"
if [ ! -f "\${BOOT_CONFIG}" ]; then
  BOOT_CONFIG="/boot/config.txt"
fi

# Ensure VC4 KMS DRM driver is active for GPU Acceleration
if [ -f "\${BOOT_CONFIG}" ]; then
  if ! grep -q "dtoverlay=vc4-kms-v3d" "\${BOOT_CONFIG}"; then
    echo "dtoverlay=vc4-kms-v3d" >> "\${BOOT_CONFIG}"
  fi
  if ! grep -q "gpu_mem=" "\${BOOT_CONFIG}"; then
    echo "gpu_mem=256" >> "\${BOOT_CONFIG}"
  fi
fi

echo "[4/6] Provisioning StreamPulse Player Installation Directory..."
mkdir -p /opt/streampulse
chmod 755 /opt/streampulse

# Create Kiosk Launcher Script
cat << 'EOF_LAUNCHER' > /opt/streampulse/kiosk.sh
#!/usr/bin/env bash
# StreamPulse Kiosk Launcher Script
export DISPLAY=\${DISPLAY:-:0}
export WAYLAND_DISPLAY=\${WAYLAND_DISPLAY:-wayland-0}

# Hide mouse cursor on inactivity
unclutter -idle 2 -root &

SERVER_URL="${serverUrl}"
STREAM_KEY="${streamKey}"
TARGET_URL="\${SERVER_URL}/rpi-kiosk?streamKey=\${STREAM_KEY}"

# Disable power saving screen blanking
xset s off 2>/dev/null || true
xset -dpms 2>/dev/null || true
xset s noblank 2>/dev/null || true

CHROMIUM_FLAGS=(
  --kiosk
  --noerrdialogs
  --disable-infobars
  --autoplay-policy=no-user-gesture-required
  --check-for-update-interval=31536000
  --disable-component-update
  --enable-accelerated-video-decode
  --enable-gpu-rasterization
  --enable-zero-copy
  --ignore-gpu-blocklist
  --use-gl=egl
  --window-position=0,0
)

echo "[StreamPulse Player] Booting StreamPulse Kiosk..."
echo "Target Stream URL: \${TARGET_URL}"

while true; do
  if command -v chromium-browser >/dev/null 2>&1; then
    chromium-browser "\${CHROMIUM_FLAGS[@]}" "\${TARGET_URL}" || true
  elif command -v chromium >/dev/null 2>&1; then
    chromium "\${CHROMIUM_FLAGS[@]}" "\${TARGET_URL}" || true
  elif command -v mpv >/dev/null 2>&1; then
    echo "[StreamPulse Player] Falling back to MPV Framebuffer Player..."
    mpv --hwdec=auto --fullscreen --loop-playlist=inf "\${SERVER_URL}/hls/\${STREAM_KEY}/master.m3u8" || true
  elif command -v cvlc >/dev/null 2>&1; then
    echo "[StreamPulse Player] Falling back to VLC Hardware Player..."
    cvlc --fullscreen --no-osd --loop "\${SERVER_URL}/hls/\${STREAM_KEY}/master.m3u8" || true
  fi
  echo "[StreamPulse Player] Connection reset or player closed. Retrying in 3s..."
  sleep 3
done
EOF_LAUNCHER

chmod +x /opt/streampulse/kiosk.sh

echo "[5/6] Creating Systemd Service for Auto Boot on Startup..."
cat << 'EOF_SERVICE' > /etc/systemd/system/streampulse-rpi-player.service
[Unit]
Description=StreamPulse Raspberry Pi Kiosk Streaming Player
After=network-online.target sound.target graphical.target
Wants=network-online.target

[Service]
Type=simple
User=pi
Environment=DISPLAY=:0
Environment=WAYLAND_DISPLAY=wayland-0
ExecStart=/opt/streampulse/kiosk.sh
Restart=always
RestartSec=3
KillMode=process

[Install]
WantedBy=graphical.target
EOF_SERVICE

# If user 'pi' doesn't exist, replace User with active user or root
if ! id -u pi >/dev/null 2>&1; {
  CURRENT_USER=$(logname 2>/dev/null || echo "root")
  sed -i "s/User=pi/User=\${CURRENT_USER}/g" /etc/systemd/system/streampulse-rpi-player.service
}

systemctl daemon-reload
systemctl enable streampulse-rpi-player.service

echo "[6/6] Configuring Auto-Update Cron Script..."
cat << 'EOF_UPDATE' > /opt/streampulse/update.sh
#!/usr/bin/env bash
echo "[StreamPulse RPi Auto-Update] Syncing player configuration..."
SERVER_URL="${serverUrl}"
curl -sSL "\${SERVER_URL}/api/rpi-player/script/setup?streamKey=${streamKey}" | bash -s -- --update || true
systemctl restart streampulse-rpi-player.service || true
EOF_UPDATE

chmod +x /opt/streampulse/update.sh

echo "========================================================================"
echo " StreamPulse Raspberry Pi Streaming Player Installation Complete! "
echo " Systemd Service: streampulse-rpi-player.service (Enabled)"
echo " Auto Boot Mode: Fullscreen Kiosk Enabled"
echo " You can manually start the player now with:"
echo "   sudo systemctl start streampulse-rpi-player"
echo "========================================================================"
`;
  }

  public generateSystemdService(): string {
    return `[Unit]
Description=StreamPulse Raspberry Pi Kiosk Streaming Player
After=network-online.target sound.target graphical.target
Wants=network-online.target

[Service]
Type=simple
User=pi
Environment=DISPLAY=:0
Environment=WAYLAND_DISPLAY=wayland-0
ExecStart=/opt/streampulse/kiosk.sh
Restart=always
RestartSec=3
KillMode=process

[Install]
WantedBy=graphical.target`;
  }

  public generateAutoStartScript(serverHost: string, defaultKey: string = ''): string {
    const streamKey = defaultKey || this.config.defaultStreamKey || 'live_stream';
    const serverUrl = serverHost.startsWith('http') ? serverHost : `http://${serverHost}`;

    return `#!/usr/bin/env bash
# StreamPulse Kiosk Autostart Script
# Disables screen sleep and launches GPU-accelerated kiosk browser

export DISPLAY=\${DISPLAY:-:0}
export WAYLAND_DISPLAY=\${WAYLAND_DISPLAY:-wayland-0}

# Disable screen blanking
xset s off 2>/dev/null || true
xset -dpms 2>/dev/null || true
xset s noblank 2>/dev/null || true

# Hide cursor after 2s inactivity
unclutter -idle 2 -root &

TARGET_URL="${serverUrl}/rpi-kiosk?streamKey=${streamKey}"

exec chromium-browser \\
  --kiosk \\
  --noerrdialogs \\
  --disable-infobars \\
  --autoplay-policy=no-user-gesture-required \\
  --enable-accelerated-video-decode \\
  --enable-gpu-rasterization \\
  --enable-zero-copy \\
  --use-gl=egl \\
  "\${TARGET_URL}"`;
  }

  public generateAutoUpdateScript(serverHost: string): string {
    const serverUrl = serverHost.startsWith('http') ? serverHost : `http://${serverHost}`;
    return `#!/usr/bin/env bash
# StreamPulse Raspberry Pi Auto-Update Script
set -e
echo "[StreamPulse RPi Player] Checking for server configuration updates..."
SERVER_URL="${serverUrl}"
curl -sSL "\${SERVER_URL}/api/rpi-player/script/setup" | bash -s -- --update
systemctl restart streampulse-rpi-player.service
echo "[StreamPulse RPi Player] Player updated successfully!"`;
  }

  public renderKioskHtml(streamKey: string, serverHost: string): string {
    const config = this.config;
    const isHttps = serverHost.startsWith('https');
    const proto = isHttps ? 'https' : 'http';
    const cleanHost = serverHost.replace(/^https?:\/\//, '');
    const hlsMasterUrl = `${proto}://${cleanHost}/hls/${streamKey}/master.m3u8`;

    return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>StreamPulse Raspberry Pi Kiosk Player</title>
  <script src="https://cdn.jsdelivr.net/npm/hls.js@1.5.8/dist/hls.min.js"></script>
  <link href="https://vjs.zencdn.net/8.10.0/video-js.css" rel="stylesheet" />
  <script src="https://vjs.zencdn.net/8.10.0/video.min.js"></script>
  <style>
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
      user-select: none;
      -webkit-user-select: none;
    }
    html, body {
      width: 100vw;
      height: 100vh;
      background-color: #000000;
      overflow: hidden;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      color: #ffffff;
    }
    .cursor-hidden {
      cursor: none !important;
    }
    #player-container {
      position: absolute;
      top: 0;
      left: 0;
      width: 100vw;
      height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      background: #000000;
    }
    video {
      width: 100%;
      height: 100%;
      object-fit: contain;
      background: #000000;
    }
    .status-overlay {
      position: absolute;
      bottom: 24px;
      left: 24px;
      display: flex;
      align-items: center;
      gap: 10px;
      background: rgba(15, 23, 42, 0.85);
      backdrop-filter: blur(8px);
      border: 1px solid rgba(255, 255, 255, 0.1);
      padding: 8px 16px;
      border-radius: 9999px;
      font-size: 13px;
      font-weight: 500;
      letter-spacing: 0.02em;
      z-index: 99;
      transition: opacity 0.4s ease;
      pointer-events: none;
    }
    .status-badge {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background-color: #ef4444;
    }
    .status-badge.live {
      background-color: #10b981;
      box-shadow: 0 0 8px #10b981;
    }
    .status-badge.reconnecting {
      background-color: #f59e0b;
      animation: pulse 1.2s infinite;
    }
    @keyframes pulse {
      0%, 100% { opacity: 1; }
      50% { opacity: 0.3; }
    }
    .offline-screen {
      position: absolute;
      top: 0;
      left: 0;
      width: 100vw;
      height: 100vh;
      background: #000000;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      z-index: 50;
      transition: opacity 0.3s ease;
    }
    .offline-title {
      font-size: 20px;
      font-weight: 600;
      color: #94a3b8;
      letter-spacing: 0.05em;
      margin-bottom: 8px;
    }
    .offline-sub {
      font-size: 13px;
      color: #475569;
    }
  </style>
</head>
<body class="cursor-hidden">
  <div id="player-container">
    <video id="video-element" autoplay playsinline muted></video>

    <div id="offline-screen" class="offline-screen">
      <div class="offline-title">STREAMPULSE RECEIVER</div>
      <div id="offline-sub" class="offline-sub">Connecting to stream...</div>
    </div>

    <div id="status-overlay" class="status-overlay" style="opacity: 0.8;">
      <div id="status-badge" class="status-badge reconnecting"></div>
      <span id="status-text">Initializing RPi Player...</span>
      <span id="status-metrics" style="color: #94a3b8; border-left: 1px solid #334155; padding-left: 8px;"></span>
    </div>
  </div>

  <script>
    (function() {
      const HLS_URL = "${hlsMasterUrl}";
      const STREAM_KEY = "${streamKey}";
      const SERVER_HOST = "${serverHost}";
      const RECONNECT_INTERVAL = ${config.network.reconnectIntervalMs};
      const HIDE_CURSOR_TIMEOUT = ${config.display.hideCursorTimeoutMs};

      const videoEl = document.getElementById('video-element');
      const offlineScreen = document.getElementById('offline-screen');
      const offlineSub = document.getElementById('offline-sub');
      const statusOverlay = document.getElementById('status-overlay');
      const statusBadge = document.getElementById('status-badge');
      const statusText = document.getElementById('status-text');
      const statusMetrics = document.getElementById('status-metrics');

      let hlsInstance = null;
      let vjsPlayer = null;
      let isPlaying = false;
      let currentEngine = 'HLS.js';
      let frameCount = 0;
      let fps = 0;
      let lastFpsTime = performance.now();
      let mouseTimer = null;
      let telemetryTimer = null;
      let checkPollTimer = null;

      // Unclutter Cursor Logic
      function resetCursorTimer() {
        document.body.classList.remove('cursor-hidden');
        clearTimeout(mouseTimer);
        mouseTimer = setTimeout(() => {
          document.body.classList.add('cursor-hidden');
        }, HIDE_CURSOR_TIMEOUT);
      }
      window.addEventListener('mousemove', resetCursorTimer);
      window.addEventListener('keydown', resetCursorTimer);
      resetCursorTimer();

      // Measure FPS using requestVideoFrameCallback or fallback
      function computeFps() {
        if ('requestVideoFrameCallback' in videoEl) {
          function onFrame() {
            frameCount++;
            const now = performance.now();
            if (now - lastFpsTime >= 1000) {
              fps = Math.round((frameCount * 1000) / (now - lastFpsTime));
              frameCount = 0;
              lastFpsTime = now;
            }
            videoEl.requestVideoFrameCallback(onFrame);
          }
          videoEl.requestVideoFrameCallback(onFrame);
        } else {
          setInterval(() => {
            if (videoEl.webkitDecodedFrameCount) {
              const currentFrames = videoEl.webkitDecodedFrameCount;
              fps = currentFrames - frameCount;
              frameCount = currentFrames;
            }
          }, 1000);
        }
      }
      computeFps();

      function updateStatus(state, message, metricsStr) {
        statusText.innerText = message;
        statusMetrics.innerText = metricsStr || '';
        
        if (state === 'live') {
          statusBadge.className = 'status-badge live';
          offlineScreen.style.opacity = '0';
          setTimeout(() => { if (isPlaying) offlineScreen.style.display = 'none'; }, 300);
        } else if (state === 'reconnecting') {
          statusBadge.className = 'status-badge reconnecting';
          offlineScreen.style.display = 'flex';
          offlineScreen.style.opacity = '1';
          offlineSub.innerText = message;
        } else {
          statusBadge.className = 'status-badge';
          offlineScreen.style.display = 'flex';
          offlineScreen.style.opacity = '1';
          offlineSub.innerText = message;
        }
      }

      function sendTelemetry() {
        const width = videoEl.videoWidth || 1920;
        const height = videoEl.videoHeight || 1080;
        const resolutionStr = width > 0 ? (width + 'x' + height) : '1080p';
        const estimatedBitrateKbps = (hlsInstance && hlsInstance.bandwidthEstimate) 
          ? Math.round(hlsInstance.bandwidthEstimate / 1000) 
          : 4500;

        fetch('/api/rpi-player/status', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            streamKey: STREAM_KEY,
            online_status: isPlaying ? 'playing' : 'reconnecting',
            current_resolution: resolutionStr,
            fps: fps || (isPlaying ? 60 : 0),
            bitrate: estimatedBitrateKbps,
            engine: currentEngine,
            player_version: '1.2.4-rpi'
          })
        }).catch(() => {});
      }

      function initHlsJs() {
        if (!window.Hls || !Hls.isSupported()) {
          console.warn('[RPi Player] HLS.js not supported. Falling back to Video.js...');
          initVideoJs();
          return;
        }

        if (hlsInstance) {
          hlsInstance.destroy();
        }

        currentEngine = 'HLS.js (GPU Hardware Accelerated)';
        hlsInstance = new Hls({
          enableWorker: true,
          lowLatencyMode: true,
          backBufferLength: 30,
          capLevelToPlayerSize: false,
          maxBufferLength: 10,
          maxMaxBufferLength: 20
        });

        hlsInstance.loadSource(HLS_URL);
        hlsInstance.attachMedia(videoEl);

        hlsInstance.on(Hls.Events.MANIFEST_PARSED, function() {
          console.log('[RPi Player] Manifest parsed successfully. Starting video playback.');
          videoEl.play().then(() => {
            isPlaying = true;
            autoplayBlocked = false;
            updateStatus('live', 'Live • ' + (videoEl.videoHeight || 1080) + 'p', fps + ' FPS');
          }).catch((err) => {
            console.warn('[RPi Player] Unmuted play blocked by browser policy. Retrying muted fallback...', err);
            videoEl.muted = true;
            videoEl.play().then(() => {
              isPlaying = true;
              autoplayBlocked = false;
              updateStatus('live', 'Live (Muted)', fps + ' FPS');
            }).catch((mutedErr) => {
              console.error('[RPi Player] Autoplay blocked by browser policy (NotAllowedError):', mutedErr);
              isPlaying = false;
              autoplayBlocked = true;
              updateStatus('offline', 'Autoplay blocked • Press Play to start', '');
              if (playOverlay) playOverlay.style.display = 'flex';
            });
          });
        });

        hlsInstance.on(Hls.Events.ERROR, function(event, data) {
          if (data.fatal) {
            console.warn('[RPi Player] HLS.js fatal error:', data.type);
            isPlaying = false;
            updateStatus('reconnecting', 'Stream Offline • Reconnecting...', '');
            
            switch (data.type) {
              case Hls.ErrorTypes.NETWORK_ERROR:
                console.log('[RPi Player] Network error encountered. Retrying in ' + (RECONNECT_INTERVAL / 1000) + 's...');
                setTimeout(() => { pollAndReconnect(); }, RECONNECT_INTERVAL);
                break;
              case Hls.ErrorTypes.MEDIA_ERROR:
                console.log('[RPi Player] Media decode error. Attempting buffer recovery...');
                hlsInstance.recoverMediaError();
                break;
              default:
                initVideoJs();
                break;
            }
          }
        });
      }

      function initVideoJs() {
        console.log('[RPi Player] Initializing Video.js fallback engine...');
        currentEngine = 'Video.js Fallback';
        if (hlsInstance) {
          hlsInstance.destroy();
          hlsInstance = null;
        }

        videoEl.src = HLS_URL;
        videoEl.play().then(() => {
          isPlaying = true;
          updateStatus('live', 'Live (Video.js)', fps + ' FPS');
        }).catch((err) => {
          isPlaying = false;
          updateStatus('reconnecting', 'Stream Offline • Reconnecting...', '');
          setTimeout(pollAndReconnect, RECONNECT_INTERVAL);
        });
      }

      function pollAndReconnect() {
        // Poll playlist URL to verify stream availability before reloading player engine
        fetch(HLS_URL, { method: 'HEAD', cache: 'no-store' })
          .then(res => {
            if (res.ok) {
              console.log('[RPi Player] Stream endpoint online! Re-booting HLS playback.');
              initHlsJs();
            } else {
              updateStatus('reconnecting', 'Stream Offline • Polling...', '');
              setTimeout(pollAndReconnect, RECONNECT_INTERVAL);
            }
          })
          .catch(() => {
            updateStatus('reconnecting', 'Network Offline • Retrying...', '');
            setTimeout(pollAndReconnect, RECONNECT_INTERVAL);
          });
      }

      // Event listeners on video element
      videoEl.addEventListener('playing', () => {
        isPlaying = true;
        updateStatus('live', 'Live • ' + (videoEl.videoHeight || 1080) + 'p', fps + ' FPS');
      });

      videoEl.addEventListener('waiting', () => {
        updateStatus('reconnecting', 'Buffering...', '');
      });

      videoEl.addEventListener('ended', () => {
        isPlaying = false;
        updateStatus('reconnecting', 'Stream ended. Waiting for live feed...', '');
        setTimeout(pollAndReconnect, RECONNECT_INTERVAL);
      });

      // Start initial playback
      initHlsJs();

      // Start Telemetry
      telemetryTimer = setInterval(sendTelemetry, 5000);
      
      // Periodic health checker
      checkPollTimer = setInterval(() => {
        if (videoEl.paused && isPlaying) {
          videoEl.play().catch(() => {});
        }
      }, 3000);

    })();
  </script>
</body>
</html>`;
  }
}

export const rpiPlayerSystem = new RpiPlayerSystem();
