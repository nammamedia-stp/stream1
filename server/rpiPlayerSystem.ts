import fs from 'fs';
import path from 'path';
import { Request, Response } from 'express';
import {
  EMBEDDED_UNIVERSAL_FULL_INSTALL,
  EMBEDDED_UNIVERSAL_SET_CHANNEL,
  EMBEDDED_UNIVERSAL_VALIDATE,
  EMBEDDED_UNIVERSAL_DIAGNOSE,
  EMBEDDED_UNIVERSAL_BACKUP,
  EMBEDDED_UNIVERSAL_RESTORE,
  EMBEDDED_UNIVERSAL_UNINSTALL
} from './rpiUniversalTemplates';

const CONFIG_PATH = path.resolve(process.cwd(), 'data/rpi_player_config.json');

function safeReadTemplate(relPath: string): string {
  const cwd = process.cwd();
  const baseDir = typeof __dirname !== 'undefined' ? __dirname : cwd;
  const candidatePaths = [
    path.resolve(cwd, relPath),
    path.resolve(baseDir, '..', relPath),
    path.resolve(baseDir, relPath),
    path.join('/app', relPath),
    path.resolve('.', relPath)
  ];
  for (const p of candidatePaths) {
    try {
      if (fs.existsSync(p)) {
        const content = fs.readFileSync(p, 'utf-8');
        if (content && content.length > 0) return content;
      }
    } catch (e) {}
  }
  console.warn(`[StreamPulse] Warning: Could not locate ${relPath} on disk across candidates:`, candidatePaths);
  return '';
}

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
    const rawUrl = (dashboardUrl || 'http://187.127.210.81/').toString().trim();
    const cleanUrl = rawUrl.startsWith('http://') || rawUrl.startsWith('https://') || rawUrl.startsWith('file://') ? rawUrl : `http://${rawUrl}`;
    const launcherScript = safeReadTemplate('rpi-kiosk-suite/dashboard-kiosk.sh');
    return launcherScript.replace(/DASHBOARD_URL="http:\/\/187\.127\.210\.81\/"/g, () => `DASHBOARD_URL="${cleanUrl}"`)
                         .replace(/KIOSK_USER="himakara"/g, () => `KIOSK_USER="${targetUser}"`);
  }

  public generateDebian13KioskDiagnoseScript(): string {
    return safeReadTemplate('rpi-kiosk-suite/diagnose.sh');
  }

  public generateDebian13KioskValidateScript(): string {
    return safeReadTemplate('rpi-kiosk-suite/validate.sh');
  }

  public generateDebian13KioskRestoreScript(): string {
    return safeReadTemplate('rpi-kiosk-suite/restore.sh');
  }

  public generateDebian13KioskUninstallScript(): string {
    return safeReadTemplate('rpi-kiosk-suite/uninstall.sh');
  }

  public generateDebian13KioskBackupScript(): string {
    return safeReadTemplate('rpi-kiosk-suite/backup.sh');
  }

  public generateFullInstallerScript(dashboardUrl: string = 'http://187.127.210.81/', streamKey: string = 'live_stream', targetUser: string = 'himakara', serverHost: string = 'http://187.127.210.81'): string {
    const rawUrl = (dashboardUrl || 'http://187.127.210.81/').toString().trim();
    const cleanDashboardUrl = rawUrl.startsWith('http://') || rawUrl.startsWith('https://') || rawUrl.startsWith('file://') ? rawUrl : `http://${rawUrl}`;
    const rawServer = (serverHost || 'http://187.127.210.81').toString().trim();
    const cleanServerHost = rawServer.startsWith('http://') || rawServer.startsWith('https://') ? rawServer : `http://${rawServer}`;
    let installerTemplate = safeReadTemplate('streampulse-full-installer/full-install.sh');
    if (!installerTemplate || installerTemplate.trim().length === 0) {
      installerTemplate = safeReadTemplate('streampulse-universal-installer/full-install.sh') || EMBEDDED_UNIVERSAL_FULL_INSTALL;
    }
    
    return installerTemplate
      .replace(/STREAM_KEY="live_stream"/g, () => `STREAM_KEY="${streamKey}"`)
      .replace(/DASHBOARD_URL="http:\/\/187\.127\.210\.81\/"/g, () => `DASHBOARD_URL="${cleanDashboardUrl}"`)
      .replace(/SERVER_URL="http:\/\/187\.127\.210\.81"/g, () => `SERVER_URL="${cleanServerHost}"`)
      .replace(/TARGET_USER="himakara"/g, () => `TARGET_USER="${targetUser}"`);
  }

  public generateUniversalInstallerScript(
    dashboardUrl: string = 'http://187.127.210.81/',
    streamKey: string = 'live_stream',
    channelName: string = 'channel1',
    targetUser: string = '',
    serverHost: string = 'http://187.127.210.81'
  ): string {
    const rawUrl = (dashboardUrl || 'http://187.127.210.81/').toString().trim();
    const cleanDashboardUrl = rawUrl.startsWith('http://') || rawUrl.startsWith('https://') || rawUrl.startsWith('file://') ? rawUrl : `http://${rawUrl}`;
    const rawServer = (serverHost || 'http://187.127.210.81').toString().trim();
    const cleanServerHost = rawServer.startsWith('http://') || rawServer.startsWith('https://') ? rawServer : `http://${rawServer}`;
    const cleanChannel = (channelName || 'channel1').toString().trim();
    const cleanKey = (streamKey || 'live_stream').toString().trim();
    const cleanUser = (targetUser || '').toString().trim();

    let installerTemplate = safeReadTemplate('streampulse-universal-installer/full-install.sh');
    if (!installerTemplate || installerTemplate.trim().length === 0) {
      installerTemplate = safeReadTemplate('streampulse-full-installer/full-install.sh');
    }
    if (!installerTemplate || installerTemplate.trim().length === 0) {
      installerTemplate = EMBEDDED_UNIVERSAL_FULL_INSTALL;
    }
    
    let result = installerTemplate
      .replace(/CHANNEL_NAME="channel1"/g, () => `CHANNEL_NAME="${cleanChannel}"`)
      .replace(/STREAM_KEY="live_stream"/g, () => `STREAM_KEY="${cleanKey}"`)
      .replace(/DASHBOARD_URL="http:\/\/187\.127\.210\.81\/"/g, () => `DASHBOARD_URL="${cleanDashboardUrl}"`)
      .replace(/SERVER_URL="http:\/\/187\.127\.210\.81"/g, () => `SERVER_URL="${cleanServerHost}"`);

    if (cleanUser) {
      result = result.replace(/OVERRIDE_USER=""/g, () => `OVERRIDE_USER="${cleanUser}"`);
    }

    return result;
  }

  public getUniversalSetChannelScript(): string {
    const s = safeReadTemplate('streampulse-universal-installer/bin/set-channel.sh');
    return (s && s.trim().length > 0) ? s : EMBEDDED_UNIVERSAL_SET_CHANNEL;
  }

  public getUniversalValidateScript(): string {
    const s = safeReadTemplate('streampulse-universal-installer/bin/validate.sh');
    return (s && s.trim().length > 0) ? s : EMBEDDED_UNIVERSAL_VALIDATE;
  }

  public getUniversalDiagnoseScript(): string {
    const s = safeReadTemplate('streampulse-universal-installer/bin/diagnose.sh');
    return (s && s.trim().length > 0) ? s : EMBEDDED_UNIVERSAL_DIAGNOSE;
  }

  public getUniversalBackupScript(): string {
    const s = safeReadTemplate('streampulse-universal-installer/bin/backup.sh');
    return (s && s.trim().length > 0) ? s : EMBEDDED_UNIVERSAL_BACKUP;
  }

  public getUniversalRestoreScript(): string {
    const s = safeReadTemplate('streampulse-universal-installer/bin/restore.sh');
    return (s && s.trim().length > 0) ? s : EMBEDDED_UNIVERSAL_RESTORE;
  }

  public getUniversalUninstallScript(): string {
    const s = safeReadTemplate('streampulse-universal-installer/uninstall.sh');
    return (s && s.trim().length > 0) ? s : EMBEDDED_UNIVERSAL_UNINSTALL;
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
      overflow: hidden;
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
      transition: opacity 0.3s ease-in-out;
    }
    #live-video {
      z-index: 20;
      opacity: 0;
      pointer-events: none;
    }
    #live-video.active {
      opacity: 1;
      pointer-events: auto;
    }
    #motion-video {
      z-index: 10;
      opacity: 1;
    }
    #motion-video.hidden {
      opacity: 0;
      pointer-events: none;
    }
    #html-fallback {
      position: absolute;
      top: 0;
      left: 0;
      width: 100vw;
      height: 100vh;
      z-index: 5;
      background-color: #090d16;
      color: #f8fafc;
      display: none;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      text-align: center;
      padding: 32px;
    }
    #html-fallback.active {
      display: flex;
    }
    .pulse-ring {
      width: 150px;
      height: 150px;
      border-radius: 50%;
      border: 3px solid #6366f1;
      display: flex;
      align-items: center;
      justify-content: center;
      animation: pulse-ring 2.8s infinite ease-in-out;
      margin-bottom: 28px;
      box-shadow: 0 0 30px rgba(99, 102, 241, 0.25);
    }
    .pulse-core {
      width: 108px;
      height: 108px;
      border-radius: 50%;
      background: linear-gradient(135deg, #4f46e5, #06b6d4);
      display: flex;
      align-items: center;
      justify-content: center;
      box-shadow: 0 0 20px rgba(6, 182, 212, 0.4);
    }
    .brand-title {
      font-size: 34px;
      font-weight: 800;
      letter-spacing: -0.5px;
      background: linear-gradient(135deg, #ffffff 40%, #94a3b8);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      margin-bottom: 6px;
    }
    .channel-badge {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      background: rgba(30, 41, 59, 0.8);
      border: 1px solid rgba(99, 102, 241, 0.3);
      padding: 6px 16px;
      border-radius: 9999px;
      color: #818cf8;
      font-size: 15px;
      font-weight: 600;
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
      margin-top: 8px;
    }
    .channel-dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background-color: #f59e0b;
      animation: blink 1.2s infinite;
    }
    .status-message {
      color: #64748b;
      font-size: 14px;
      margin-top: 20px;
      letter-spacing: 0.02em;
    }
    @keyframes pulse-ring {
      0%, 100% {
        transform: scale(1);
        border-color: #6366f1;
        opacity: 0.8;
      }
      50% {
        transform: scale(1.1);
        border-color: #06b6d4;
        opacity: 1;
        box-shadow: 0 0 45px rgba(6, 182, 212, 0.4);
      }
    }
    @keyframes blink {
      0%, 100% { opacity: 1; }
      50% { opacity: 0.3; }
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
    <video id="live-video" class="kiosk-video" autoplay playsinline muted preload="auto"></video>

    <!-- Offline Permanent Motion Logo Video Element -->
    <video id="motion-video" class="kiosk-video" autoplay loop muted playsinline preload="auto">
      <source src="motion-logo.mp4" type="video/mp4">
      <source src="/opt/streampulse/logo/motion-logo.mp4" type="video/mp4">
      <source src="${proto}://${cleanHost}/api/rpi-player/motion-logo" type="video/mp4">
    </video>

    <!-- Local HTML Fallback (when MP4 is unplayable) -->
    <div id="html-fallback">
      <div class="pulse-ring">
        <div class="pulse-core">
          <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="#ffffff" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
            <polygon points="5 3 19 12 5 21 5 3"></polygon>
          </svg>
        </div>
      </div>
      <div class="brand-title">StreamPulse</div>
      <div class="channel-badge">
        <span class="channel-dot"></span>
        <span id="fallback-channel-name">Channel Standby</span>
      </div>
      <div id="fallback-status" class="status-message">Waiting for live broadcast stream...</div>
    </div>

    <!-- Overlay Status Badge -->
    <div id="status-overlay" class="status-overlay" style="opacity: 0.8;">
      <div id="status-badge" class="status-badge reconnecting"></div>
      <span id="status-text">Standby • Motion Logo Active</span>
      <span id="status-metrics" style="color: #94a3b8; border-left: 1px solid #334155; padding-left: 8px;">Polling stream...</span>
    </div>
  </div>

  <script>
    (function() {
      const HLS_URL = "${hlsMasterUrl}";
      const STREAM_KEY = "${streamKey}";
      const SERVER_HOST = "${serverHost}";

      const liveVideo = document.getElementById('live-video');
      const motionVideo = document.getElementById('motion-video');
      const htmlFallback = document.getElementById('html-fallback');
      const fallbackChannelName = document.getElementById('fallback-channel-name');
      const fallbackStatus = document.getElementById('fallback-status');
      const statusOverlay = document.getElementById('status-overlay');
      const statusBadge = document.getElementById('status-badge');
      const statusText = document.getElementById('status-text');
      const statusMetrics = document.getElementById('status-metrics');

      if (fallbackChannelName) {
        fallbackChannelName.textContent = 'Channel: ' + STREAM_KEY;
      }

      let currentState = 'STANDBY'; // 'STANDBY' | 'LIVE'
      let hlsInstance = null;
      let pollTimer = null;
      let mouseTimer = null;
      let telemetryTimer = null;
      let mp4Failed = false;
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
        const playPromise = videoEl.play();
        if (playPromise !== undefined) {
          return playPromise.catch(err => {
            console.warn('[StreamPulse Player] Playback start rejected:', err);
            videoEl.muted = true;
            return videoEl.play().catch(e => {
              console.error('[StreamPulse Player] Muted retry rejected:', e);
            });
          });
        }
        return Promise.resolve();
      }

      function showOfflineVisuals() {
        if (!mp4Failed) {
          motionVideo.classList.remove('hidden');
          htmlFallback.classList.remove('active');
          motionVideo.currentTime = 0;
          safePlay(motionVideo).catch(() => {
            handleMp4Failure();
          });
        } else {
          motionVideo.classList.add('hidden');
          htmlFallback.classList.add('active');
        }
      }

      function handleMp4Failure() {
        mp4Failed = true;
        console.warn('[StreamPulse Player] Motion Logo MP4 unplayable. Using HTML fallback.');
        motionVideo.classList.add('hidden');
        htmlFallback.classList.add('active');
        if (fallbackStatus) {
          fallbackStatus.textContent = 'Stream offline • Polling ' + SERVER_HOST + '...';
        }
      }

      motionVideo.addEventListener('error', handleMp4Failure);
      motionVideo.addEventListener('stalled', () => {
        if (currentState === 'STANDBY' && motionVideo.paused && !mp4Failed) {
          safePlay(motionVideo);
        }
      });
      motionVideo.addEventListener('ended', () => {
        if (currentState === 'STANDBY' && !mp4Failed) {
          motionVideo.currentTime = 0;
          safePlay(motionVideo);
        }
      });

      function sendTelemetry() {
        const activeVideo = currentState === 'LIVE' ? liveVideo : motionVideo;
        const width = activeVideo.videoWidth || 1920;
        const height = activeVideo.videoHeight || 1080;

        fetch('/api/rpi-player/status', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            streamKey: STREAM_KEY,
            online_status: currentState === 'LIVE' ? 'playing' : 'offline_logo',
            current_resolution: width + 'x' + height,
            fps: fps || (currentState === 'LIVE' ? 60 : 30),
            engine: currentState === 'LIVE' ? 'HLS.js' : 'Motion Logo',
            player_version: '2.0.0-universal'
          })
        }).catch(() => {});
      }
      telemetryTimer = setInterval(sendTelemetry, 5000);

      // ----------------------------------------------------
      // STATE MACHINE: STANDBY (LOGO) <---> LIVE (HLS)
      // ----------------------------------------------------

      function switchToOfflineStandby(reason) {
        if (currentState === 'STANDBY') return;
        currentState = 'STANDBY';
        console.warn('[StreamPulse Player] Entering STANDBY state. Reason:', reason || 'Stream Offline');

        // Destroy active HLS instance
        if (hlsInstance) {
          try { hlsInstance.destroy(); } catch(e) {}
          hlsInstance = null;
        }

        // Hide & pause live video
        liveVideo.classList.remove('active');
        try {
          liveVideo.pause();
          liveVideo.removeAttribute('src');
          liveVideo.load();
        } catch (e) {}

        // Show offline visuals
        showOfflineVisuals();

        updateStatus('reconnecting', 'Offline • Motion Logo Active', 'Polling Live Stream...');
        startHlsPolling();
      }

        let activeLiveUrl = HLS_URL;

        function switchToLiveHls(customUrl) {
        if (currentState === 'LIVE' && (!customUrl || activeLiveUrl === customUrl)) return;
        currentState = 'LIVE';
        if (customUrl) activeLiveUrl = customUrl;
        console.log('[StreamPulse Player] Entering LIVE state with URL:', activeLiveUrl);

        stopHlsPolling();

        if (hlsInstance) {
          try { hlsInstance.destroy(); } catch(e) {}
          hlsInstance = null;
        }

        const cacheBustUrl = activeLiveUrl + (activeLiveUrl.includes('?') ? '&' : '?') + '_t=' + Date.now();

        if (window.Hls && Hls.isSupported()) {
          hlsInstance = new Hls({
            enableWorker: true,
            lowLatencyMode: true,
            backBufferLength: 30,
            maxBufferLength: 10,
            liveBackBufferLength: 6,
            manifestLoadingTimeOut: 6000,
            manifestLoadingMaxRetry: 2,
            fragLoadingTimeOut: 8000
          });

          hlsInstance.attachMedia(liveVideo);
          hlsInstance.loadSource(cacheBustUrl);

          hlsInstance.on(Hls.Events.MANIFEST_PARSED, function() {
            console.log('[StreamPulse Player] Live manifest parsed. Playing HLS stream...');
            safePlay(liveVideo);
          });

          hlsInstance.on(Hls.Events.ERROR, function(event, data) {
            // NEVER TREAT 404 AS A FATAL UNRECOVERABLE APP CRASH!
            console.warn('[StreamPulse Player] HLS error:', data.type, data.details, 'Fatal:', data.fatal);
            if (data.fatal) {
              if (data.type === Hls.ErrorTypes.MEDIA_ERROR) {
                try {
                  hlsInstance.recoverMediaError();
                  safePlay(liveVideo);
                } catch(e) {
                  switchToOfflineStandby('Media Error Recovery Failed');
                }
              } else if (data.type === Hls.ErrorTypes.NETWORK_ERROR) {
                switchToOfflineStandby('Stream Stopped / Network Error (HTTP ' + (data.response ? data.response.code : 'offline') + ')');
              } else {
                switchToOfflineStandby('HLS Error');
              }
            }
          });
        } else if (liveVideo.canPlayType('application/vnd.apple.mpegurl')) {
          liveVideo.src = cacheBustUrl;
          safePlay(liveVideo);
          updateStatus('live', 'Live (Native)', 'HLS Active');
        } else {
          switchToOfflineStandby('HLS Engine Missing');
          return;
        }

        function onLivePlaying() {
          liveVideo.removeEventListener('playing', onLivePlaying);
          if (currentState !== 'LIVE') return;

          motionVideo.classList.add('hidden');
          htmlFallback.classList.remove('active');
          try { motionVideo.pause(); } catch(e) {}

          liveVideo.classList.add('active');
          updateStatus('live', 'Live • ' + (liveVideo.videoHeight || 1080) + 'p', 'Stream Key: ' + STREAM_KEY);
        }
        liveVideo.addEventListener('playing', onLivePlaying);
      }

      liveVideo.addEventListener('error', function() {
        if (currentState === 'LIVE') {
          switchToOfflineStandby('Live Video Element Error');
        }
      });

      function startHlsPolling() {
        stopHlsPolling();
        pollTimer = setInterval(async () => {
          if (currentState === 'LIVE') return;
          const candidateUrls = [HLS_URL];
          try {
            const discUrl = '${proto}://${cleanHost}/api/stream/active?channel=' + encodeURIComponent(STREAM_KEY) + '&key=' + encodeURIComponent(STREAM_KEY) + '&_t=' + Date.now();
            const discRes = await fetch(discUrl, { headers: { 'Accept': 'application/json' } });
            if (discRes.ok) {
              const data = await discRes.json();
              if (data.hlsMasterUrl && !candidateUrls.includes(data.hlsMasterUrl)) candidateUrls.unshift(data.hlsMasterUrl);
              if (data.candidateUrls) {
                for (const u of data.candidateUrls) {
                  if (u && !candidateUrls.includes(u)) candidateUrls.push(u);
                }
              }
            }
          } catch(e) {}

          for (const testUrl of candidateUrls) {
            try {
              const checkUrl = testUrl + (testUrl.includes('?') ? '&' : '?') + '_t=' + Date.now();
              const res = await fetch(checkUrl, { method: 'GET', cache: 'no-store' });
              if (res.ok && res.status === 200) {
                const text = await res.text();
                if (text && text.includes('#EXTM3U')) {
                  console.log('[StreamPulse Player] Valid HLS playlist detected at:', testUrl);
                  switchToLiveHls(testUrl);
                  return;
                }
              }
            } catch(e) {
              // Stream offline
            }
          }
        }, 2000);
      }

      function stopHlsPolling() {
        if (pollTimer) {
          clearInterval(pollTimer);
          pollTimer = null;
        }
      }

      // User interaction listener to allow unmuting
      function tryUnmute() {
        if (currentState === 'LIVE' && liveVideo) {
          liveVideo.muted = false;
        }
      }
      window.addEventListener('click', tryUnmute);
      window.addEventListener('touchstart', tryUnmute);
      window.addEventListener('keydown', tryUnmute);

      // Initial check on load
      (async function init() {
        showOfflineVisuals();
        updateStatus('reconnecting', 'Standby • Logo Active', 'Checking HLS stream...');

        try {
          const checkUrl = HLS_URL + (HLS_URL.includes('?') ? '&' : '?') + '_t=' + Date.now();
          const res = await fetch(checkUrl, { method: 'GET', cache: 'no-store' });
          if (res.ok && res.status === 200) {
            const text = await res.text();
            if (text && text.includes('#EXTM3U')) {
              switchToLiveHls();
              return;
            }
          }
        } catch(e) {}
        
        startHlsPolling();
      })();

    })();
  </script>
</body>
</html>`;
  }

  /**
   * Render a dedicated standalone HTML5 HLS Direct Player page.
   * Provides 100% reliable muted autoplay in Chrome/Safari/Firefox
   * with seamless 1-click unmuting and MSE / hls.js acceleration.
   */
  public renderDirectPlayerHtml(streamKey: string, protoHost: string): string {
    const cleanHost = protoHost.replace(/^https?:\/\//, '');
    const isHttps = protoHost.startsWith('https');
    const proto = isHttps ? 'https' : 'http';
    const hlsUrl = `${proto}://${cleanHost}/hls/${encodeURIComponent(streamKey)}/master.m3u8`;

    return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>StreamPulse Live - ${streamKey}</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">
  <script src="https://cdn.jsdelivr.net/npm/hls.js@1.5.8/dist/hls.min.js"></script>
  <style>
    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
    }
    body, html {
      width: 100%;
      height: 100%;
      background-color: #090d16;
      color: #f1f5f9;
      font-family: 'Plus Jakarta Sans', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      overflow: hidden;
      display: flex;
      flex-direction: column;
    }
    header {
      height: 56px;
      padding: 0 24px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      background: rgba(15, 23, 42, 0.75);
      backdrop-filter: blur(12px);
      border-bottom: 1px solid rgba(255, 255, 255, 0.08);
      z-index: 20;
    }
    .brand {
      display: flex;
      align-items: center;
      gap: 10px;
      font-weight: 700;
      font-size: 16px;
      letter-spacing: -0.01em;
    }
    .brand-icon {
      width: 28px;
      height: 28px;
      border-radius: 8px;
      background: linear-gradient(135deg, #6366f1 0%, #06b6d4 100%);
      display: flex;
      align-items: center;
      justify-content: center;
      box-shadow: 0 2px 8px rgba(99, 102, 241, 0.35);
    }
    .stream-meta {
      display: flex;
      align-items: center;
      gap: 12px;
    }
    .live-badge {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      background: rgba(239, 68, 68, 0.15);
      border: 1px solid rgba(239, 68, 68, 0.3);
      color: #f87171;
      padding: 4px 10px;
      border-radius: 9999px;
      font-size: 11px;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.05em;
    }
    .live-dot {
      width: 6px;
      height: 6px;
      border-radius: 50%;
      background-color: #ef4444;
      box-shadow: 0 0 8px #ef4444;
      animation: pulse 1.4s infinite;
    }
    .key-badge {
      font-family: monospace;
      font-size: 12px;
      color: #94a3b8;
      background: rgba(255, 255, 255, 0.06);
      padding: 4px 10px;
      border-radius: 6px;
    }
    main {
      flex: 1;
      position: relative;
      display: flex;
      align-items: center;
      justify-content: center;
      background: #000;
    }
    video {
      width: 100%;
      height: 100%;
      object-fit: contain;
      background: #000;
    }
    #unmute-banner {
      position: absolute;
      bottom: 72px;
      left: 50%;
      transform: translateX(-50%);
      background: rgba(15, 23, 42, 0.9);
      backdrop-filter: blur(12px);
      border: 1px solid rgba(255, 255, 255, 0.15);
      color: #fff;
      padding: 10px 20px;
      border-radius: 9999px;
      font-size: 13px;
      font-weight: 600;
      display: flex;
      align-items: center;
      gap: 8px;
      cursor: pointer;
      box-shadow: 0 8px 24px rgba(0, 0, 0, 0.5);
      transition: all 0.2s ease;
      z-index: 30;
      user-select: none;
    }
    #unmute-banner:hover {
      background: rgba(30, 41, 59, 0.95);
      transform: translateX(-50%) scale(1.04);
      border-color: rgba(99, 102, 241, 0.5);
    }
    #status-toast {
      position: absolute;
      top: 16px;
      left: 16px;
      background: rgba(15, 23, 42, 0.85);
      backdrop-filter: blur(8px);
      border: 1px solid rgba(255, 255, 255, 0.1);
      padding: 6px 14px;
      border-radius: 8px;
      font-size: 12px;
      color: #cbd5e1;
      display: none;
      z-index: 25;
      pointer-events: none;
    }
    @keyframes pulse {
      0%, 100% { opacity: 1; }
      50% { opacity: 0.3; }
    }
  </style>
</head>
<body>
  <header>
    <div class="brand">
      <div class="brand-icon">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#ffffff" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
          <polygon points="5 3 19 12 5 21 5 3"></polygon>
        </svg>
      </div>
      <span>StreamPulse Direct</span>
    </div>
    <div class="stream-meta">
      <div class="key-badge">${streamKey}</div>
      <div class="live-badge">
        <span class="live-dot"></span>
        <span>Live</span>
      </div>
    </div>
  </header>

  <main id="player-wrapper">
    <video id="video-element" autoplay playsinline muted preload="auto" controls></video>
    
    <div id="unmute-banner">
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"></polygon>
        <line x1="23" y1="9" x2="17" y2="15"></line>
        <line x1="17" y1="9" x2="23" y2="15"></line>
      </svg>
      <span>Click to Unmute Stream</span>
    </div>

    <div id="status-toast">Connecting...</div>
  </main>

  <script>
    (function() {
      const HLS_MANIFEST_URL = "${hlsUrl}";
      const video = document.getElementById('video-element');
      const unmuteBanner = document.getElementById('unmute-banner');
      const statusToast = document.getElementById('status-toast');

      function showStatus(msg) {
        if (!statusToast) return;
        statusToast.textContent = msg;
        statusToast.style.display = 'block';
        setTimeout(() => { statusToast.style.display = 'none'; }, 4000);
      }

      function updateUnmuteVisibility() {
        if (!unmuteBanner) return;
        if (video.muted || video.volume === 0) {
          unmuteBanner.style.display = 'flex';
        } else {
          unmuteBanner.style.display = 'none';
        }
      }

      function performUnmute() {
        video.muted = false;
        video.volume = 1.0;
        updateUnmuteVisibility();
      }

      unmuteBanner.addEventListener('click', performUnmute);
      video.addEventListener('volumechange', updateUnmuteVisibility);
      video.addEventListener('play', updateUnmuteVisibility);

      // Initialize Video & HLS
      video.muted = true;
      video.defaultMuted = true;

      if (window.Hls && Hls.isSupported()) {
        const hls = new Hls({
          enableWorker: true,
          lowLatencyMode: true,
          backBufferLength: 30,
          manifestLoadingTimeOut: 10000,
          manifestLoadingMaxRetry: 6,
          levelLoadingTimeOut: 10000,
          levelLoadingMaxRetry: 6,
          fragLoadingTimeOut: 15000,
          fragLoadingMaxRetry: 8
        });

        hls.attachMedia(video);

        hls.on(Hls.Events.MEDIA_ATTACHED, function() {
          hls.loadSource(HLS_MANIFEST_URL);
        });

        hls.on(Hls.Events.MANIFEST_PARSED, function() {
          video.play().catch(function(e) {
            console.warn('[DirectPlayer] Autoplay prevented:', e);
          });
        });

        hls.on(Hls.Events.ERROR, function(event, data) {
          if (data.fatal) {
            switch(data.type) {
              case Hls.ErrorTypes.NETWORK_ERROR:
                showStatus('Reconnecting to stream...');
                hls.startLoad();
                break;
              case Hls.ErrorTypes.MEDIA_ERROR:
                showStatus('Recovering media...');
                hls.recoverMediaError();
                break;
              default:
                hls.destroy();
                setTimeout(() => {
                  window.location.reload();
                }, 3000);
                break;
            }
          }
        });
      } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
        video.src = HLS_MANIFEST_URL;
        video.addEventListener('loadedmetadata', function() {
          video.play().catch(function(e) {
            console.warn('[DirectPlayer] Native autoplay prevented:', e);
          });
        });
      }

      // Initial autoplay trigger
      video.play().catch(function() {});
    })();
  </script>
</body>
</html>`;
  }
}

export const rpiPlayerSystem = new RpiPlayerSystem();

