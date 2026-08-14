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
MOTION_LOGO_URL="\${SERVER_URL}/api/rpi-player/motion-logo"

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

# Detect active graphical/non-root user for systemd service
LOGGED_USER="\${SUDO_USER:-$(logname 2>/dev/null || id -un 1000 2>/dev/null || echo "pi")}"
if [ "\${LOGGED_USER}" = "root" ]; then
  LOGGED_USER=$(id -un 1000 2>/dev/null || echo "pi")
fi
LOGGED_UID=$(id -u "\${LOGGED_USER}" 2>/dev/null || echo "1000")
LOGGED_HOME=$(getent passwd "\${LOGGED_USER}" | cut -d: -f6 || echo "/home/\${LOGGED_USER}")
echo "Target Graphical User: \${LOGGED_USER} (UID: \${LOGGED_UID}, Home: \${LOGGED_HOME})"

# Detect Desktop vs Lite
IS_DESKTOP=0
if command -v Xorg >/dev/null 2>&1 || [ -d /usr/share/wayland-sessions ] || [ -n "\${WAYLAND_DISPLAY}" ]; then
  IS_DESKTOP=1
  echo "OS Environment: Raspberry Pi OS Desktop (GUI / Wayland / X11 Mode)"
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
  python3 \\
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

echo "[4/6] Provisioning Installation Directories & Checking Local Motion Logo Asset..."
mkdir -p /opt/streampulse/media /opt/streampulse/chromium-profile
chmod 755 /opt/streampulse /opt/streampulse/media /opt/streampulse/chromium-profile

LOCAL_MOTION_FILE="/opt/streampulse/media/motion_logo.mp4"
USER_DOWNLOAD_LOGO="\${LOGGED_HOME}/Downloads/Motion Logo.mp4"
USER_DOWNLOAD_LOGO_ALT="\${LOGGED_HOME}/Downloads/motion_logo.mp4"

if [ -f "\${USER_DOWNLOAD_LOGO}" ] && [ -s "\${USER_DOWNLOAD_LOGO}" ]; then
  echo "[StreamPulse Player] Detected user Motion Logo at '\${USER_DOWNLOAD_LOGO}'."
  cp "\${USER_DOWNLOAD_LOGO}" "\${LOCAL_MOTION_FILE}"
elif [ -f "\${USER_DOWNLOAD_LOGO_ALT}" ] && [ -s "\${USER_DOWNLOAD_LOGO_ALT}" ]; then
  echo "[StreamPulse Player] Detected user Motion Logo at '\${USER_DOWNLOAD_LOGO_ALT}'."
  cp "\${USER_DOWNLOAD_LOGO_ALT}" "\${LOCAL_MOTION_FILE}"
fi

if [ -s "\${LOCAL_MOTION_FILE}" ]; then
  echo "[StreamPulse Player] Motion Logo verified successfully ($(du -h \${LOCAL_MOTION_FILE} | cut -f1))."
else
  echo "[Notice] Motion Logo not found in '\${USER_DOWNLOAD_LOGO}'. Kiosk player will run without offline Motion Logo loop."
fi
chown -R "\${LOGGED_USER}:\${LOGGED_USER}" /opt/streampulse || true
chmod 644 "\${LOCAL_MOTION_FILE}" 2>/dev/null || true

# Create Kiosk Launcher Script
cat << 'EOF_LAUNCHER' > /opt/streampulse/kiosk.sh
#!/usr/bin/env bash
# StreamPulse Kiosk Launcher Script
LOGGED_USER="$(id -un)"
if [ "\${LOGGED_USER}" = "root" ]; then
  LOGGED_USER="\${SUDO_USER:-$(logname 2>/dev/null || id -un 1000 2>/dev/null || echo "pi")}"
  if [ "\${LOGGED_USER}" = "root" ]; then
    LOGGED_USER=$(id -un 1000 2>/dev/null || echo "pi")
  fi
fi
LOGGED_UID=$(id -u "\${LOGGED_USER}" 2>/dev/null || echo "1000")
LOGGED_HOME=$(getent passwd "\${LOGGED_USER}" | cut -d: -f6 || echo "/home/\${LOGGED_USER}")
if [ -z "\${LOGGED_HOME}" ] || [ ! -d "\${LOGGED_HOME}" ]; then
  LOGGED_HOME="/home/\${LOGGED_USER}"
fi

export DISPLAY="\${DISPLAY:-:0}"
export WAYLAND_DISPLAY="\${WAYLAND_DISPLAY:-wayland-0}"
export XDG_RUNTIME_DIR="\${XDG_RUNTIME_DIR:-/run/user/\${LOGGED_UID}}"

# Dedicated StreamPulse Chromium profile directory to isolate from normal user profile
CHROMIUM_PROFILE_DIR="/opt/streampulse/chromium-profile"
mkdir -p "\${CHROMIUM_PROFILE_DIR}" 2>/dev/null || true

# Prevent spawning duplicate Chromium kiosk windows if already running with dedicated profile
if pgrep -f "chromium.*--user-data-dir=/opt/streampulse/chromium-profile" >/dev/null 2>&1; then
  echo "[StreamPulse Player] StreamPulse Chromium kiosk is already running with dedicated profile. Exiting."
  exit 0
fi

# Clean up stale singleton lock files ONLY in our dedicated profile directory
rm -f "\${CHROMIUM_PROFILE_DIR}"/Singleton* 2>/dev/null || true
rm -f "\${CHROMIUM_PROFILE_DIR}"/Default/Singleton* 2>/dev/null || true

# Hide mouse cursor on inactivity if unclutter is present
if command -v unclutter >/dev/null 2>&1; then
  unclutter -idle 2 -root &
fi

# Sync user Motion Logo from Downloads if present
mkdir -p /opt/streampulse/media
USER_DOWNLOAD_LOGO="\${LOGGED_HOME}/Downloads/Motion Logo.mp4"
USER_DOWNLOAD_LOGO_ALT="\${LOGGED_HOME}/Downloads/motion_logo.mp4"
LOCAL_MOTION_FILE="/opt/streampulse/media/motion_logo.mp4"

if [ -f "\${USER_DOWNLOAD_LOGO}" ] && [ -s "\${USER_DOWNLOAD_LOGO}" ]; then
  if [ ! -s "\${LOCAL_MOTION_FILE}" ] || [ "\${USER_DOWNLOAD_LOGO}" -nt "\${LOCAL_MOTION_FILE}" ]; then
    cp "\${USER_DOWNLOAD_LOGO}" "\${LOCAL_MOTION_FILE}" 2>/dev/null || true
    chmod 644 "\${LOCAL_MOTION_FILE}" 2>/dev/null || true
  fi
elif [ -f "\${USER_DOWNLOAD_LOGO_ALT}" ] && [ -s "\${USER_DOWNLOAD_LOGO_ALT}" ]; then
  if [ ! -s "\${LOCAL_MOTION_FILE}" ] || [ "\${USER_DOWNLOAD_LOGO_ALT}" -nt "\${LOCAL_MOTION_FILE}" ]; then
    cp "\${USER_DOWNLOAD_LOGO_ALT}" "\${LOCAL_MOTION_FILE}" 2>/dev/null || true
    chmod 644 "\${LOCAL_MOTION_FILE}" 2>/dev/null || true
  fi
fi

# Start local web server for offline Motion Logo media if not running
if command -v python3 >/dev/null 2>&1; then
  if ! pgrep -f "python3 -m http.server 18765" >/dev/null 2>&1; then
    python3 -m http.server 18765 --directory /opt/streampulse/media >/dev/null 2>&1 &
  fi
fi

SERVER_URL="${serverUrl}"
STREAM_KEY="${streamKey}"
TARGET_URL="\${SERVER_URL}/rpi-kiosk?streamKey=\${STREAM_KEY}"

# Disable power saving screen blanking
xset s off 2>/dev/null || true
xset -dpms 2>/dev/null || true
xset s noblank 2>/dev/null || true

CHROMIUM_FLAGS=(
  --user-data-dir="\${CHROMIUM_PROFILE_DIR}"
  --kiosk
  --start-fullscreen
  --fullscreen
  --noerrdialogs
  --disable-infobars
  --autoplay-policy=no-user-gesture-required
  --no-first-run
  --disable-restore-session-state
  --disable-session-crashed-bubble
  --enable-accelerated-video-decode
  --enable-gpu-rasterization
  --enable-zero-copy
  --ignore-gpu-blocklist
  --use-gl=egl
  --check-for-update-interval=31536000
  --disable-component-update
  --disable-features=TranslateUI
  --disable-save-password-bubble
  --allow-file-access-from-files
  --disable-web-security
  --window-position=0,0
  --window-size=1920,1080
)

echo "[StreamPulse Player] Booting StreamPulse Kiosk..."
echo "Target Stream URL: \${TARGET_URL}"

CHROMIUM_BIN=""
if command -v chromium-browser >/dev/null 2>&1; then
  CHROMIUM_BIN="chromium-browser"
elif command -v chromium >/dev/null 2>&1; then
  CHROMIUM_BIN="chromium"
elif [ -x /usr/bin/chromium-browser ]; then
  CHROMIUM_BIN="/usr/bin/chromium-browser"
elif [ -x /usr/bin/chromium ]; then
  CHROMIUM_BIN="/usr/bin/chromium"
fi

if [ -n "\${CHROMIUM_BIN}" ]; then
  exec "\${CHROMIUM_BIN}" "\${CHROMIUM_FLAGS[@]}" "\${TARGET_URL}"
elif command -v mpv >/dev/null 2>&1; then
  exec mpv --hwdec=auto --fullscreen --loop-playlist=inf "\${SERVER_URL}/hls/\${STREAM_KEY}/master.m3u8"
elif command -v cvlc >/dev/null 2>&1; then
  exec cvlc --fullscreen --no-osd --loop "\${SERVER_URL}/hls/\${STREAM_KEY}/master.m3u8"
fi
EOF_LAUNCHER

chmod +x /opt/streampulse/kiosk.sh
chown "\${LOGGED_USER}:\${LOGGED_USER}" /opt/streampulse/kiosk.sh

echo "[5/6] Creating Systemd Service for Auto Boot on Startup..."
cat << EOF_SERVICE > /etc/systemd/system/streampulse-rpi-player.service
[Unit]
Description=StreamPulse Raspberry Pi Kiosk Streaming Player
After=network-online.target sound.target graphical-session.target graphical.target
Wants=network-online.target

[Service]
Type=simple
User=\${LOGGED_USER}
Environment=DISPLAY=:0
Environment=WAYLAND_DISPLAY=wayland-0
Environment=XDG_RUNTIME_DIR=/run/user/\${LOGGED_UID}
ExecStart=/opt/streampulse/kiosk.sh
Restart=on-failure
RestartSec=5
KillMode=process

[Install]
WantedBy=graphical.target
EOF_SERVICE

systemctl daemon-reload
systemctl enable streampulse-rpi-player.service

echo "[6/6] Configuring Auto-Update Script..."
cat << EOF_UPDATE > /opt/streampulse/update.sh
#!/usr/bin/env bash
echo "[StreamPulse RPi Auto-Update] Syncing player configuration..."
SERVER_URL="${serverUrl}"
STREAM_KEY="${streamKey}"
curl -sSL "\${SERVER_URL}/api/rpi-player/script/setup?streamKey=\${STREAM_KEY}" | sudo bash -s -- --update || true
systemctl restart streampulse-rpi-player.service || true
EOF_UPDATE

chmod +x /opt/streampulse/update.sh

echo "========================================================================"
echo " StreamPulse Raspberry Pi Streaming Player Installation Complete! "
echo " Systemd Service: streampulse-rpi-player.service (Enabled)"
echo " Auto Boot Mode: Fullscreen Kiosk Enabled"
echo " Target User: \${LOGGED_USER}"
echo " Motion Logo Media: /opt/streampulse/media/motion_logo.mp4"
echo " You can manually start the player now with:"
echo "   sudo systemctl start streampulse-rpi-player"
echo "========================================================================"
`;
  }

  public generateSystemdService(): string {
    return `[Unit]
Description=StreamPulse Raspberry Pi Kiosk Streaming Player
After=network-online.target sound.target graphical-session.target graphical.target
Wants=network-online.target

[Service]
Type=simple
User=pi
Environment=DISPLAY=:0
Environment=WAYLAND_DISPLAY=wayland-0
Environment=XDG_RUNTIME_DIR=/run/user/1000
ExecStart=/opt/streampulse/kiosk.sh
Restart=on-failure
RestartSec=5
KillMode=process

[Install]
WantedBy=graphical.target`;
  }

  public generateAutoStartScript(serverHost: string, defaultKey: string = ''): string {
    const streamKey = defaultKey || this.config.defaultStreamKey || 'live_stream';
    const serverUrl = serverHost.startsWith('http') ? serverHost : `http://${serverHost}`;

    return `#!/usr/bin/env bash
# StreamPulse Kiosk Autostart Script
LOGGED_USER="$(id -un)"
if [ "\${LOGGED_USER}" = "root" ]; then
  LOGGED_USER="\${SUDO_USER:-$(logname 2>/dev/null || id -un 1000 2>/dev/null || echo "pi")}"
  if [ "\${LOGGED_USER}" = "root" ]; then
    LOGGED_USER=$(id -un 1000 2>/dev/null || echo "pi")
  fi
fi
LOGGED_UID=$(id -u "\${LOGGED_USER}" 2>/dev/null || echo "1000")
LOGGED_HOME=$(getent passwd "\${LOGGED_USER}" | cut -d: -f6 || echo "/home/\${LOGGED_USER}")
if [ -z "\${LOGGED_HOME}" ] || [ ! -d "\${LOGGED_HOME}" ]; then
  LOGGED_HOME="/home/\${LOGGED_USER}"
fi

export DISPLAY="\${DISPLAY:-:0}"
export WAYLAND_DISPLAY="\${WAYLAND_DISPLAY:-wayland-0}"
export XDG_RUNTIME_DIR="\${XDG_RUNTIME_DIR:-/run/user/\${LOGGED_UID}}"

# Dedicated StreamPulse Chromium profile directory to isolate from normal user profile
CHROMIUM_PROFILE_DIR="/opt/streampulse/chromium-profile"
mkdir -p "\${CHROMIUM_PROFILE_DIR}" 2>/dev/null || true

# Prevent spawning duplicate Chromium kiosk windows if already running with dedicated profile
if pgrep -f "chromium.*--user-data-dir=/opt/streampulse/chromium-profile" >/dev/null 2>&1; then
  echo "[StreamPulse Player] StreamPulse Chromium kiosk is already running with dedicated profile. Exiting."
  exit 0
fi

# Clean up stale singleton lock files ONLY in our dedicated profile directory
rm -f "\${CHROMIUM_PROFILE_DIR}"/Singleton* 2>/dev/null || true
rm -f "\${CHROMIUM_PROFILE_DIR}"/Default/Singleton* 2>/dev/null || true

# Disable screen blanking
xset s off 2>/dev/null || true
xset -dpms 2>/dev/null || true
xset s noblank 2>/dev/null || true

# Hide cursor after 2s inactivity
if command -v unclutter >/dev/null 2>&1; then
  unclutter -idle 2 -root &
fi

# Sync user Motion Logo from Downloads if present
mkdir -p /opt/streampulse/media
USER_DOWNLOAD_LOGO="\${LOGGED_HOME}/Downloads/Motion Logo.mp4"
USER_DOWNLOAD_LOGO_ALT="\${LOGGED_HOME}/Downloads/motion_logo.mp4"
LOCAL_MOTION_FILE="/opt/streampulse/media/motion_logo.mp4"

if [ -f "\${USER_DOWNLOAD_LOGO}" ] && [ -s "\${USER_DOWNLOAD_LOGO}" ]; then
  if [ ! -s "\${LOCAL_MOTION_FILE}" ] || [ "\${USER_DOWNLOAD_LOGO}" -nt "\${LOCAL_MOTION_FILE}" ]; then
    cp "\${USER_DOWNLOAD_LOGO}" "\${LOCAL_MOTION_FILE}" 2>/dev/null || true
    chmod 644 "\${LOCAL_MOTION_FILE}" 2>/dev/null || true
  fi
elif [ -f "\${USER_DOWNLOAD_LOGO_ALT}" ] && [ -s "\${USER_DOWNLOAD_LOGO_ALT}" ]; then
  if [ ! -s "\${LOCAL_MOTION_FILE}" ] || [ "\${USER_DOWNLOAD_LOGO_ALT}" -nt "\${LOCAL_MOTION_FILE}" ]; then
    cp "\${USER_DOWNLOAD_LOGO_ALT}" "\${LOCAL_MOTION_FILE}" 2>/dev/null || true
    chmod 644 "\${LOCAL_MOTION_FILE}" 2>/dev/null || true
  fi
fi

# Start local web server for offline Motion Logo media if not running
if command -v python3 >/dev/null 2>&1; then
  if ! pgrep -f "python3 -m http.server 18765" >/dev/null 2>&1; then
    python3 -m http.server 18765 --directory /opt/streampulse/media >/dev/null 2>&1 &
  fi
fi

SERVER_URL="${serverUrl}"
STREAM_KEY="${streamKey}"
TARGET_URL="\${SERVER_URL}/rpi-kiosk?streamKey=\${STREAM_KEY}"

CHROMIUM_FLAGS=(
  --user-data-dir="\${CHROMIUM_PROFILE_DIR}"
  --kiosk
  --start-fullscreen
  --fullscreen
  --noerrdialogs
  --disable-infobars
  --autoplay-policy=no-user-gesture-required
  --no-first-run
  --disable-restore-session-state
  --disable-session-crashed-bubble
  --enable-accelerated-video-decode
  --enable-gpu-rasterization
  --enable-zero-copy
  --ignore-gpu-blocklist
  --use-gl=egl
  --check-for-update-interval=31536000
  --disable-component-update
  --disable-features=TranslateUI
  --disable-save-password-bubble
  --allow-file-access-from-files
  --disable-web-security
  --window-position=0,0
  --window-size=1920,1080
)

echo "[StreamPulse Player] Booting StreamPulse Kiosk..."
echo "Target Stream URL: \${TARGET_URL}"

CHROMIUM_BIN=""
if command -v chromium-browser >/dev/null 2>&1; then
  CHROMIUM_BIN="chromium-browser"
elif command -v chromium >/dev/null 2>&1; then
  CHROMIUM_BIN="chromium"
elif [ -x /usr/bin/chromium-browser ]; then
  CHROMIUM_BIN="/usr/bin/chromium-browser"
elif [ -x /usr/bin/chromium ]; then
  CHROMIUM_BIN="/usr/bin/chromium"
fi

if [ -n "\${CHROMIUM_BIN}" ]; then
  exec "\${CHROMIUM_BIN}" "\${CHROMIUM_FLAGS[@]}" "\${TARGET_URL}"
elif command -v mpv >/dev/null 2>&1; then
  exec mpv --hwdec=auto --fullscreen --loop-playlist=inf "\${SERVER_URL}/hls/\${STREAM_KEY}/master.m3u8"
elif command -v cvlc >/dev/null 2>&1; then
  exec cvlc --fullscreen --no-osd --loop "\${SERVER_URL}/hls/\${STREAM_KEY}/master.m3u8"
fi`;
  }

  public generateAutoUpdateScript(serverHost: string): string {
    const serverUrl = serverHost.startsWith('http') ? serverHost : `http://${serverHost}`;
    return `#!/usr/bin/env bash
# StreamPulse Raspberry Pi Auto-Update Script
set -e
echo "[StreamPulse RPi Player] Checking for server configuration updates..."
SERVER_URL="${serverUrl}"
curl -sSL "\${SERVER_URL}/api/rpi-player/script/setup" | sudo bash -s -- --update
systemctl restart streampulse-rpi-player.service
echo "[StreamPulse RPi Player] Player updated successfully!"`;
  }

  public generateDebian13KioskInstallScript(dashboardUrl: string = 'http://187.127.210.81/', targetUser: string = 'himakara'): string {
    const cleanUrl = dashboardUrl.startsWith('http') ? dashboardUrl : `http://${dashboardUrl}`;
    const kioskScript = fs.readFileSync(path.resolve('./rpi-kiosk-suite/install.sh'), 'utf-8');
    return kioskScript.replace(/DASHBOARD_URL="http:\/\/187\.127\.210\.81\/"/g, `DASHBOARD_URL="${cleanUrl}"`)
                      .replace(/DEFAULT_USER="himakara"/g, `DEFAULT_USER="${targetUser}"`);
  }

  public generateDebian13KioskLauncher(dashboardUrl: string = 'http://187.127.210.81/', targetUser: string = 'himakara'): string {
    const cleanUrl = dashboardUrl.startsWith('http') ? dashboardUrl : `http://${dashboardUrl}`;
    const launcherScript = fs.readFileSync(path.resolve('./rpi-kiosk-suite/dashboard-kiosk.sh'), 'utf-8');
    return launcherScript.replace(/DASHBOARD_URL="http:\/\/187\.127\.210\.81\/"/g, `DASHBOARD_URL="${cleanUrl}"`)
                         .replace(/KIOSK_USER="himakara"/g, `KIOSK_USER="${targetUser}"`);
  }

  public generateDebian13KioskDiagnoseScript(): string {
    return fs.readFileSync(path.resolve('./rpi-kiosk-suite/diagnose.sh'), 'utf-8');
  }

  public generateDebian13KioskValidateScript(): string {
    return fs.readFileSync(path.resolve('./rpi-kiosk-suite/validate.sh'), 'utf-8');
  }

  public generateDebian13KioskRestoreScript(): string {
    return fs.readFileSync(path.resolve('./rpi-kiosk-suite/restore.sh'), 'utf-8');
  }

  public generateDebian13KioskUninstallScript(): string {
    return fs.readFileSync(path.resolve('./rpi-kiosk-suite/uninstall.sh'), 'utf-8');
  }

  public generateDebian13KioskBackupScript(): string {
    return fs.readFileSync(path.resolve('./rpi-kiosk-suite/backup.sh'), 'utf-8');
  }

  public generateFullInstallerScript(dashboardUrl: string = 'http://187.127.210.81/', streamKey: string = 'live_stream', targetUser: string = 'himakara', serverHost: string = 'http://187.127.210.81'): string {
    const cleanDashboardUrl = dashboardUrl.startsWith('http') ? dashboardUrl : `http://${dashboardUrl}`;
    const cleanServerHost = serverHost.startsWith('http') ? serverHost : `http://${serverHost}`;
    const installerTemplate = fs.readFileSync(path.resolve('./streampulse-full-installer/full-install.sh'), 'utf-8');
    
    return installerTemplate
      .replace(/STREAM_KEY="live_stream"/g, `STREAM_KEY="${streamKey}"`)
      .replace(/DASHBOARD_URL="http:\/\/187\.127\.210\.81\/"/g, `DASHBOARD_URL="${cleanDashboardUrl}"`)
      .replace(/SERVER_URL="http:\/\/187\.127\.210\.81"/g, `SERVER_URL="${cleanServerHost}"`)
      .replace(/TARGET_USER="himakara"/g, `TARGET_USER="${targetUser}"`);
  }

  public generateUniversalInstallerScript(
    dashboardUrl: string = 'http://187.127.210.81/',
    streamKey: string = 'live_stream',
    channelName: string = 'channel1',
    targetUser: string = '',
    serverHost: string = 'http://187.127.210.81'
  ): string {
    const cleanDashboardUrl = dashboardUrl.startsWith('http') ? dashboardUrl : `http://${dashboardUrl}`;
    const cleanServerHost = serverHost.startsWith('http') ? serverHost : `http://${serverHost}`;
    const installerTemplate = fs.readFileSync(path.resolve('./streampulse-universal-installer/full-install.sh'), 'utf-8');
    
    let result = installerTemplate
      .replace(/CHANNEL_NAME="channel1"/g, `CHANNEL_NAME="${channelName}"`)
      .replace(/STREAM_KEY="live_stream"/g, `STREAM_KEY="${streamKey}"`)
      .replace(/DASHBOARD_URL="http:\/\/187\.127\.210\.81\/"/g, `DASHBOARD_URL="${cleanDashboardUrl}"`)
      .replace(/SERVER_URL="http:\/\/187\.127\.210\.81"/g, `SERVER_URL="${cleanServerHost}"`);

    if (targetUser) {
      result = result.replace(/OVERRIDE_USER=""/g, `OVERRIDE_USER="${targetUser}"`);
    }

    return result;
  }

  public getUniversalSetChannelScript(): string {
    return fs.readFileSync(path.resolve('./streampulse-universal-installer/bin/set-channel.sh'), 'utf-8');
  }

  public getUniversalValidateScript(): string {
    return fs.readFileSync(path.resolve('./streampulse-universal-installer/bin/validate.sh'), 'utf-8');
  }

  public getUniversalDiagnoseScript(): string {
    return fs.readFileSync(path.resolve('./streampulse-universal-installer/bin/diagnose.sh'), 'utf-8');
  }

  public getUniversalBackupScript(): string {
    return fs.readFileSync(path.resolve('./streampulse-universal-installer/bin/backup.sh'), 'utf-8');
  }

  public getUniversalRestoreScript(): string {
    return fs.readFileSync(path.resolve('./streampulse-universal-installer/bin/restore.sh'), 'utf-8');
  }

  public getUniversalUninstallScript(): string {
    return fs.readFileSync(path.resolve('./streampulse-universal-installer/uninstall.sh'), 'utf-8');
  }

  public renderKioskHtml(streamKey: string, serverHost: string): string {
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
    .kiosk-video {
      position: absolute;
      top: 0;
      left: 0;
      width: 100vw;
      height: 100vh;
      object-fit: contain;
      background: #000000;
      border: none;
      outline: none;
    }
    #live-video {
      z-index: 10;
    }
    #motion-video {
      z-index: 5;
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
  </style>
</head>
<body class="cursor-hidden">
  <div id="player-container">
    <!-- Live HLS Video Element -->
    <video id="live-video" class="kiosk-video" autoplay playsinline muted></video>

    <!-- Offline Local Motion Logo Video Element -->
    <video id="motion-video" class="kiosk-video" autoplay playsinline loop muted style="display: none;">
      <source src="http://127.0.0.1:18765/motion_logo.mp4" type="video/mp4">
      <source src="${proto}://${cleanHost}/api/rpi-player/motion-logo" type="video/mp4">
    </video>

    <!-- Overlay Status Badge -->
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

      const liveVideo = document.getElementById('live-video');
      const motionVideo = document.getElementById('motion-video');
      const statusBadge = document.getElementById('status-badge');
      const statusText = document.getElementById('status-text');
      const statusMetrics = document.getElementById('status-metrics');

      let currentState = 'INITIALIZING'; // 'LIVE_HLS' | 'OFFLINE_MOTION'
      let hlsInstance = null;
      let pollTimer = null;
      let mouseTimer = null;
      let telemetryTimer = null;
      let fps = 0;
      let frameCount = 0;
      let lastFpsTime = performance.now();

      function resetCursorTimer() {
        document.body.classList.remove('cursor-hidden');
        clearTimeout(mouseTimer);
        mouseTimer = setTimeout(() => {
          document.body.classList.add('cursor-hidden');
        }, 2000);
      }
      window.addEventListener('mousemove', resetCursorTimer);
      window.addEventListener('keydown', resetCursorTimer);
      resetCursorTimer();

      function computeFps() {
        if ('requestVideoFrameCallback' in liveVideo) {
          function onFrame() {
            frameCount++;
            const now = performance.now();
            if (now - lastFpsTime >= 1000) {
              fps = Math.round((frameCount * 1000) / (now - lastFpsTime));
              frameCount = 0;
              lastFpsTime = now;
            }
            liveVideo.requestVideoFrameCallback(onFrame);
          }
          liveVideo.requestVideoFrameCallback(onFrame);
        }
      }
      computeFps();

      function updateStatus(mode, text, metrics) {
        statusText.textContent = text || '';
        statusMetrics.textContent = metrics || '';
        statusBadge.className = 'status-badge ' + (mode || 'reconnecting');
      }

      function safePlay(videoEl) {
        if (!videoEl) return Promise.resolve();
        videoEl.muted = true;
        videoEl.playsInline = true;
        videoEl.autoplay = true;
        return videoEl.play().catch(err => {
          console.warn('[RPi Player] Playback start rejected:', err);
          videoEl.muted = true;
          return videoEl.play().catch(e => {
            console.error('[RPi Player] Muted retry rejected:', e);
          });
        });
      }

      function sendTelemetry() {
        const activeVideo = currentState === 'LIVE_HLS' ? liveVideo : motionVideo;
        const width = activeVideo.videoWidth || 1920;
        const height = activeVideo.videoHeight || 1080;

        fetch('/api/rpi-player/status', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            streamKey: STREAM_KEY,
            online_status: currentState === 'LIVE_HLS' ? 'playing' : 'offline_motion_fallback',
            current_resolution: width + 'x' + height,
            fps: fps || (currentState === 'LIVE_HLS' ? 60 : 30),
            engine: currentState === 'LIVE_HLS' ? 'HLS.js' : 'Local Motion Logo',
            player_version: '1.3.0-rpi'
          })
        }).catch(() => {});
      }
      telemetryTimer = setInterval(sendTelemetry, 5000);

      // ----------------------------------------------------
      // STATE MACHINE: OFFLINE_MOTION <---> LIVE_HLS
      // ----------------------------------------------------

      function switchToOfflineMotion(reason) {
        if (currentState === 'OFFLINE_MOTION') return;
        currentState = 'OFFLINE_MOTION';
        console.warn('[RPi Player State] Entering OFFLINE_MOTION. Reason:', reason || 'Stream Offline');

        // Destroy HLS instance
        if (hlsInstance) {
          try { hlsInstance.destroy(); } catch(e) {}
          hlsInstance = null;
        }

        // Pause & hide live stream video
        liveVideo.pause();
        liveVideo.style.display = 'none';

        // Show & play local Motion Logo video
        motionVideo.style.display = 'block';
        motionVideo.currentTime = 0;
        safePlay(motionVideo);

        updateStatus('reconnecting', 'Offline • Motion Logo Active', 'Polling Live Stream...');

        startHlsPolling();
      }

      function switchToLiveHls() {
        if (currentState === 'LIVE_HLS') return;
        currentState = 'LIVE_HLS';
        console.log('[RPi Player State] Entering LIVE_HLS.');

        stopHlsPolling();

        // Pause & hide Motion Logo video
        motionVideo.pause();
        motionVideo.style.display = 'none';

        // Show & play live video element
        liveVideo.style.display = 'block';

        if (hlsInstance) {
          try { hlsInstance.destroy(); } catch(e) {}
          hlsInstance = null;
        }

        const cacheBustUrl = HLS_URL + (HLS_URL.includes('?') ? '&' : '?') + '_t=' + Date.now();

        if (window.Hls && Hls.isSupported()) {
          hlsInstance = new Hls({
            enableWorker: true,
            lowLatencyMode: true,
            backBufferLength: 30,
            maxBufferLength: 10,
            liveBackBufferLength: 10,
            manifestLoadingTimeOut: 5000,
            manifestLoadingMaxRetry: 2
          });

          hlsInstance.attachMedia(liveVideo);
          hlsInstance.loadSource(cacheBustUrl);

          hlsInstance.on(Hls.Events.MANIFEST_PARSED, function() {
            console.log('[RPi Player] Live manifest parsed. Playing HLS live stream...');
            safePlay(liveVideo);
            updateStatus('live', 'Live • ' + (liveVideo.videoHeight || 1080) + 'p', 'HLS Active');
          });

          hlsInstance.on(Hls.Events.ERROR, function(event, data) {
            if (data.fatal) {
              console.warn('[RPi Player] HLS fatal error:', data.type, data.details);
              if (data.type === Hls.ErrorTypes.MEDIA_ERROR) {
                try {
                  hlsInstance.recoverMediaError();
                  safePlay(liveVideo);
                } catch(e) {
                  switchToOfflineMotion('Media Error Recovery Failed');
                }
              } else {
                switchToOfflineMotion('HLS Network/Manifest Error');
              }
            }
          });
        } else {
          liveVideo.src = cacheBustUrl;
          safePlay(liveVideo);
          updateStatus('live', 'Live (Native)', 'HLS Active');
        }
      }

      function startHlsPolling() {
        stopHlsPolling();
        pollTimer = setInterval(async () => {
          if (currentState !== 'OFFLINE_MOTION') return;
          try {
            const checkUrl = HLS_URL + (HLS_URL.includes('?') ? '&' : '?') + '_t=' + Date.now();
            const res = await fetch(checkUrl, { method: 'GET', cache: 'no-store' });
            if (res.ok) {
              const text = await res.text();
              if (text && text.includes('#EXTM3U')) {
                console.log('[RPi Player] Valid HLS master playlist detected! Transitioning to live stream.');
                switchToLiveHls();
              }
            }
          } catch(e) {
            // HLS stream still offline
          }
        }, 2000);
      }

      function stopHlsPolling() {
        if (pollTimer) {
          clearInterval(pollTimer);
          pollTimer = null;
        }
      }

      // Motion video loop enforcement
      motionVideo.addEventListener('ended', () => {
        if (currentState === 'OFFLINE_MOTION') {
          motionVideo.currentTime = 0;
          safePlay(motionVideo);
        }
      });

      // Unexpected pause recovery
      liveVideo.addEventListener('pause', () => {
        if (currentState === 'LIVE_HLS') {
          safePlay(liveVideo);
        }
      });

      motionVideo.addEventListener('pause', () => {
        if (currentState === 'OFFLINE_MOTION') {
          safePlay(motionVideo);
        }
      });

      // User interaction listener to allow unmuting
      function tryUnmute() {
        const activeVideo = currentState === 'LIVE_HLS' ? liveVideo : motionVideo;
        if (activeVideo && activeVideo.muted) {
          activeVideo.muted = false;
          setTimeout(() => {
            if (activeVideo.paused) {
              console.warn('[RPi Player] Unmute caused pause. Re-muting and resuming playback...');
              activeVideo.muted = true;
              safePlay(activeVideo);
            }
          }, 100);
        }
      }
      window.addEventListener('click', tryUnmute);
      window.addEventListener('touchstart', tryUnmute);
      window.addEventListener('keydown', tryUnmute);

      // Periodic sanity checker
      setInterval(() => {
        if (currentState === 'LIVE_HLS' && liveVideo.paused) {
          safePlay(liveVideo);
        } else if (currentState === 'OFFLINE_MOTION' && motionVideo.paused) {
          safePlay(motionVideo);
        }
      }, 3000);

      // Initial check on load
      (async function init() {
        try {
          const checkUrl = HLS_URL + (HLS_URL.includes('?') ? '&' : '?') + '_t=' + Date.now();
          const res = await fetch(checkUrl, { method: 'GET', cache: 'no-store' });
          if (res.ok) {
            const text = await res.text();
            if (text && text.includes('#EXTM3U')) {
              switchToLiveHls();
              return;
            }
          }
        } catch(e) {}
        
        // Default to offline Motion Logo loop if live stream is not instantly available
        switchToOfflineMotion('Initial HLS Check Offline');
      })();

    })();
  </script>
</body>
</html>`;
  }
}

export const rpiPlayerSystem = new RpiPlayerSystem();
