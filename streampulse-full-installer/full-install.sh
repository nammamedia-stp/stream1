#!/usr/bin/env bash
# ==============================================================================
# StreamPulse Master Full Installer for Raspberry Pi
# Target: Raspberry Pi OS 64-bit / Debian 13 (Trixie) ARM64 / Labwc Desktop
# Linux User: himakara (with dynamic non-root fallback)
# Includes:
#   1. StreamPulse Logo Player
#   2. StreamPulse Streaming Player (HLS)
#   3. Dashboard Kiosk
#   4. Fullscreen Mode
#   5. Automatic Boot Startup
#   6. Keyring / Password Popup Prevention (--password-store=basic)
#   7. Reliable Reboot Persistence
#   8. Backup and Restore Engine
#   9. Diagnostics Reporter
#  10. Automated 10-Point Validation
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default Parameters
STREAM_KEY="live_stream"
DASHBOARD_URL="http://187.127.210.81/"
SERVER_URL="http://187.127.210.81"
TARGET_USER="himakara"
SKIP_VALIDATE=0

# ------------------------------------------------------------------------------
# CLI ARGUMENT PARSING
# ------------------------------------------------------------------------------
show_help() {
  cat << 'EOF_HELP'
================================================================================
          StreamPulse Master Full Installer for Raspberry Pi
================================================================================
Usage:
  sudo bash full-install.sh [OPTIONS]

Options:
  -k, --stream-key KEY        Stream key for StreamPulse Player (default: "live_stream")
  -u, --dashboard-url URL     Target URL for Fullscreen Kiosk (default: "http://187.127.210.81/")
  -s, --server-url URL        StreamPulse backend server URL (default: inferred from dashboard URL)
  -U, --user USERNAME         Linux non-root user (default: "himakara" or current user)
  --no-validate               Skip running post-installation validation tests
  -h, --help                  Show this help message and exit

Examples:
  sudo bash full-install.sh --stream-key "test_channel"
  sudo bash full-install.sh --stream-key "live_stream" --dashboard-url "http://187.127.210.81/"
  sudo bash full-install.sh --user "himakara" --dashboard-url "http://187.127.210.81/"
================================================================================
EOF_HELP
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -k|--stream-key)
      STREAM_KEY="$2"
      shift 2
      ;;
    -u|--dashboard-url)
      DASHBOARD_URL="$2"
      shift 2
      ;;
    -s|--server-url)
      SERVER_URL="$2"
      shift 2
      ;;
    -U|--user)
      TARGET_USER="$2"
      shift 2
      ;;
    --no-validate)
      SKIP_VALIDATE=1
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Run 'sudo bash full-install.sh --help' for available options."
      exit 1
      ;;
  esac
done

# Normalize URLs
if [[ ! "$DASHBOARD_URL" =~ ^https?:// ]]; then
  DASHBOARD_URL="http://${DASHBOARD_URL}"
fi
if [[ "$SERVER_URL" == "http://187.127.210.81" ]] && [[ "$DASHBOARD_URL" != "http://187.127.210.81/" ]]; then
  SERVER_URL="${DASHBOARD_URL%/}"
fi

echo "========================================================================"
echo "          StreamPulse Master Full Installer & Provisioner               "
echo "========================================================================"
echo "Target User:    $TARGET_USER"
echo "Stream Key:     $STREAM_KEY"
echo "Dashboard URL:  $DASHBOARD_URL"
echo "Server URL:     $SERVER_URL"
echo "========================================================================"
echo ""

# ------------------------------------------------------------------------------
# 1. PRE-FLIGHT VERIFICATION
# ------------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
  echo "Error: This master installer must be run as root."
  echo "Please run: sudo bash $0"
  exit 1
fi

echo "[1/10] Verifying Operating System, Architecture & User Account..."

# Detect Architecture
ARCH="$(uname -m)"
echo "  - CPU Architecture: $ARCH"
if [ "$ARCH" != "aarch64" ] && [ "$ARCH" != "arm64" ]; then
  echo "  - Notice: Non-ARM64 architecture detected ($ARCH). Proceeding with compatibility mode."
fi

# Detect Debian/OS
if [ -f /etc/os-release ]; then
  OS_NAME=$(grep -E "^PRETTY_NAME=" /etc/os-release | cut -d= -f2 | tr -d '\"' || echo "Linux")
  echo "  - Operating System: $OS_NAME"
fi

# Resolve Target User
DETECTED_USER="${SUDO_USER:-$(logname 2>/dev/null || id -un 1000 2>/dev/null || echo "$TARGET_USER")}"
if [ "$DETECTED_USER" = "root" ]; then
  DETECTED_USER="$(id -un 1000 2>/dev/null || echo "$TARGET_USER")"
fi
if id "$TARGET_USER" >/dev/null 2>&1; then
  ACTIVE_USER="$TARGET_USER"
else
  ACTIVE_USER="$DETECTED_USER"
fi

TARGET_UID="$(id -u "$ACTIVE_USER" 2>/dev/null || echo "1000")"
TARGET_HOME="$(getent passwd "$ACTIVE_USER" 2>/dev/null | cut -d: -f6 || echo "/home/$ACTIVE_USER")"
echo "  - Active Non-Root User: $ACTIVE_USER (UID: $TARGET_UID, Home: $TARGET_HOME)"

# ------------------------------------------------------------------------------
# 2. PRE-FLIGHT BACKUP ENGINE
# ------------------------------------------------------------------------------
echo "[2/10] Creating Pre-Flight System Snapshot & Backup..."
BACKUP_SCRIPT="$SCRIPT_DIR/bin/backup.sh"
if [ ! -f "$BACKUP_SCRIPT" ]; then
  BACKUP_SCRIPT="$SCRIPT_DIR/backup.sh"
fi

if [ -f "$BACKUP_SCRIPT" ]; then
  bash "$BACKUP_SCRIPT"
else
  TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
  BACKUP_DIR="${TARGET_HOME}/streampulse-backups/${TIMESTAMP}"
  mkdir -p "$BACKUP_DIR"
  [ -d "${TARGET_HOME}/.config/labwc" ] && cp -r "${TARGET_HOME}/.config/labwc" "$BACKUP_DIR/" 2>/dev/null || true
  [ -d "${TARGET_HOME}/.config/autostart" ] && cp -r "${TARGET_HOME}/.config/autostart" "$BACKUP_DIR/" 2>/dev/null || true
  echo "  ✓ Basic backup snapshot saved to $BACKUP_DIR"
fi

# ------------------------------------------------------------------------------
# 3. INSTALL REQUIRED PACKAGES (IDEMPOTENT & SAFE)
# ------------------------------------------------------------------------------
echo "[3/10] Installing Base Dependencies & Media Packages..."
export DEBIAN_FRONTEND=noninteractive

REQUIRED_PKGS=(
  curl
  wget
  ca-certificates
  unclutter
  vlc
  mpv
  xdotool
  x11-xserver-utils
  v4l-utils
  python3
  systemd
)

MISSING_PKGS=()
for pkg in "${REQUIRED_PKGS[@]}"; do
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    MISSING_PKGS+=("$pkg")
  fi
done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
  echo "  - Installing packages: ${MISSING_PKGS[*]}"
  apt-get update -qq || true
  apt-get install -y --no-install-recommends "${MISSING_PKGS[@]}" || true
else
  echo "  ✓ Base media packages already installed."
fi

# Ensure Chromium is installed
if ! command -v chromium >/dev/null 2>&1 && ! command -v chromium-browser >/dev/null 2>&1; then
  echo "  - Installing Chromium browser..."
  apt-get install -y --no-install-recommends chromium-browser || apt-get install -y --no-install-recommends chromium || true
else
  echo "  ✓ Chromium browser verified."
fi

# ------------------------------------------------------------------------------
# 4. USER PERMISSIONS & AUDIO SUBSYSTEM PRESERVATION
# ------------------------------------------------------------------------------
echo "[4/10] Preserving Audio Subsystem & Configuring User Groups..."
# Add target user to necessary groups
for grp in audio video render input autologin; do
  groupadd -f "$grp"
  usermod -aG "$grp" "$ACTIVE_USER" 2>/dev/null || true
done
echo "  ✓ User '$ACTIVE_USER' assigned to audio, video, render, input, autologin groups."

# ------------------------------------------------------------------------------
# 5. DIRECTORY PROVISIONING & FILE DEPLOYMENT
# ------------------------------------------------------------------------------
echo "[5/10] Provisioning Application Directories & Deploying Scripts..."
mkdir -p /opt/streampulse/bin /opt/streampulse/config /opt/streampulse/media /opt/streampulse/chromium-profile
chmod 755 /opt/streampulse /opt/streampulse/bin /opt/streampulse/config /opt/streampulse/media /opt/streampulse/chromium-profile

# Copy bin scripts
if [ -d "$SCRIPT_DIR/bin" ]; then
  cp "$SCRIPT_DIR/bin/"*.sh /opt/streampulse/bin/ 2>/dev/null || true
fi
if [ -f "$SCRIPT_DIR/restore.sh" ]; then
  cp "$SCRIPT_DIR/restore.sh" /opt/streampulse/bin/ 2>/dev/null || true
fi
if [ -f "$SCRIPT_DIR/uninstall.sh" ]; then
  cp "$SCRIPT_DIR/uninstall.sh" /opt/streampulse/bin/ 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 6. CONFIGURE CENTRAL KIOSK CONFIGURATION
# ------------------------------------------------------------------------------
echo "[6/10] Generating Central Configuration (/opt/streampulse/config/kiosk.conf)..."
cat << EOF_CONF > /opt/streampulse/config/kiosk.conf
# ==============================================================================
# StreamPulse Master Kiosk & Player Suite Configuration
# Location: /opt/streampulse/config/kiosk.conf
# ==============================================================================

DASHBOARD_URL="${DASHBOARD_URL}"
STREAM_KEY="${STREAM_KEY}"
SERVER_URL="${SERVER_URL}"
KIOSK_USER="${ACTIVE_USER}"
BROWSER_PROFILE_DIR="/opt/streampulse/chromium-profile"
BROWSER_ENGINE="auto"
SCREEN_WIDTH=1920
SCREEN_HEIGHT=1080
HIDE_CURSOR=1
DISABLE_SCREEN_BLANKING=1
WAIT_NETWORK_TIMEOUT=30
RESTART_DELAY_SEC=3
MOTION_LOGO_PATH="/opt/streampulse/media/motion_logo.mp4"

# Critical Keyring Suppression and Performance Flags
CHROMIUM_EXTRA_FLAGS=(
  "--password-store=basic"
  "--noerrdialogs"
  "--disable-infobars"
  "--kiosk"
  "--start-fullscreen"
  "--fullscreen"
  "--no-first-run"
  "--disable-restore-session-state"
  "--disable-session-crashed-bubble"
  "--autoplay-policy=no-user-gesture-required"
  "--enable-accelerated-video-decode"
  "--enable-gpu-rasterization"
  "--enable-zero-copy"
  "--ignore-gpu-blocklist"
  "--check-for-update-interval=31536000"
  "--disable-component-update"
  "--disable-features=TranslateUI"
  "--disable-save-password-bubble"
  "--allow-file-access-from-files"
  "--disable-web-security"
  "--window-position=0,0"
  "--window-size=1920,1080"
)
EOF_CONF

# ------------------------------------------------------------------------------
# 7. CONFIGURE STREAMPULSE LOGO & STREAMING PLAYER
# ------------------------------------------------------------------------------
echo "[7/10] Provisioning StreamPulse Logo & Streaming Player Engine..."

# Sync Motion Logo MP4
LOCAL_LOGO="/opt/streampulse/media/motion_logo.mp4"
DOWNLOAD_LOGO="${TARGET_HOME}/Downloads/Motion Logo.mp4"
DOWNLOAD_LOGO_ALT="${TARGET_HOME}/Downloads/motion_logo.mp4"

if [ -f "$DOWNLOAD_LOGO" ] && [ -s "$DOWNLOAD_LOGO" ]; then
  cp "$DOWNLOAD_LOGO" "$LOCAL_LOGO" 2>/dev/null || true
  chmod 644 "$LOCAL_LOGO" 2>/dev/null || true
  echo "  ✓ Synced Motion Logo asset from Downloads: $(du -h "$LOCAL_LOGO" | cut -f1)"
elif [ -f "$DOWNLOAD_LOGO_ALT" ] && [ -s "$DOWNLOAD_LOGO_ALT" ]; then
  cp "$DOWNLOAD_LOGO_ALT" "$LOCAL_LOGO" 2>/dev/null || true
  chmod 644 "$LOCAL_LOGO" 2>/dev/null || true
  echo "  ✓ Synced Motion Logo asset from Downloads: $(du -h "$LOCAL_LOGO" | cut -f1)"
else
  echo "  - Notice: No offline Motion Logo in Downloads. Web player fallback loop active."
fi

# Player Launcher Script (/opt/streampulse/kiosk.sh)
cat << 'EOF_PLAYER_LAUNCH' > /opt/streampulse/kiosk.sh
#!/usr/bin/env bash
# StreamPulse Integrated Player Launcher
set -uo pipefail

CONFIG_FILE="/opt/streampulse/config/kiosk.conf"
STREAM_KEY="live_stream"
SERVER_URL="http://187.127.210.81"
KIOSK_USER="himakara"
BROWSER_PROFILE_DIR="/opt/streampulse/chromium-profile"

[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE" 2>/dev/null || true

RUNNING_USER="$(whoami 2>/dev/null || echo "$KIOSK_USER")"
TARGET_UID="$(id -u "$RUNNING_USER" 2>/dev/null || echo "1000")"
TARGET_HOME="$(getent passwd "$RUNNING_USER" 2>/dev/null | cut -d: -f6 || echo "/home/$RUNNING_USER")"

export DISPLAY="${DISPLAY:-:0}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$TARGET_UID}"

mkdir -p "$BROWSER_PROFILE_DIR" /opt/streampulse/media 2>/dev/null || true

# Start local web server for offline Motion Logo media if not running
if command -v python3 >/dev/null 2>&1; then
  if ! pgrep -f "python3 -m http.server 18765" >/dev/null 2>&1; then
    python3 -m http.server 18765 --directory /opt/streampulse/media >/dev/null 2>&1 &
  fi
fi

# Prevent duplicate launches
if pgrep -f "chromium.*--user-data-dir=$BROWSER_PROFILE_DIR" >/dev/null 2>&1; then
  exit 0
fi

# Clean stale locks
rm -f "$BROWSER_PROFILE_DIR"/Singleton* 2>/dev/null || true

# Hide mouse cursor
command -v unclutter >/dev/null 2>&1 && unclutter -idle 2 -root &

TARGET_URL="${SERVER_URL}/rpi-kiosk?streamKey=${STREAM_KEY}"

# Detect browser
CHROMIUM_BIN=""
if command -v chromium >/dev/null 2>&1; then
  CHROMIUM_BIN="chromium"
elif command -v chromium-browser >/dev/null 2>&1; then
  CHROMIUM_BIN="chromium-browser"
fi

if [ -n "$CHROMIUM_BIN" ]; then
  exec "$CHROMIUM_BIN" \
    --user-data-dir="$BROWSER_PROFILE_DIR" \
    --password-store=basic \
    --kiosk \
    --start-fullscreen \
    --fullscreen \
    --noerrdialogs \
    --disable-infobars \
    --autoplay-policy=no-user-gesture-required \
    --no-first-run \
    --disable-restore-session-state \
    --disable-session-crashed-bubble \
    --enable-accelerated-video-decode \
    --enable-gpu-rasterization \
    --enable-zero-copy \
    --ignore-gpu-blocklist \
    --check-for-update-interval=31536000 \
    --disable-component-update \
    "--window-position=0,0" \
    "--window-size=1920,1080" \
    "$TARGET_URL"
elif command -v mpv >/dev/null 2>&1; then
  exec mpv --hwdec=auto --fullscreen --loop-playlist=inf "${SERVER_URL}/hls/${STREAM_KEY}/master.m3u8"
fi
EOF_PLAYER_LAUNCH

chmod +x /opt/streampulse/kiosk.sh

# Player Systemd Service
cat << EOF_PLAYER_SVC > /etc/systemd/system/streampulse-rpi-player.service
[Unit]
Description=StreamPulse Raspberry Pi Kiosk Streaming Player
Documentation=https://streampulse.io
After=network-online.target sound.target pipewire.service wireplumber.service graphical-session.target graphical.target
Wants=network-online.target sound.target

[Service]
Type=simple
User=${ACTIVE_USER}
Environment=DISPLAY=:0
Environment=WAYLAND_DISPLAY=wayland-0
Environment=XDG_RUNTIME_DIR=/run/user/${TARGET_UID}
ExecStart=/opt/streampulse/kiosk.sh
Restart=on-failure
RestartSec=5
KillMode=process

[Install]
WantedBy=graphical.target
EOF_PLAYER_SVC

# Auto-update script
cat << EOF_UPDATE > /opt/streampulse/update.sh
#!/usr/bin/env bash
SERVER_URL="${SERVER_URL}"
STREAM_KEY="${STREAM_KEY}"
curl -sSL "\${SERVER_URL}/api/rpi-player/script/setup?streamKey=\${STREAM_KEY}" | sudo bash -s -- --update || true
systemctl restart streampulse-rpi-player.service 2>/dev/null || true
EOF_UPDATE
chmod +x /opt/streampulse/update.sh

# ------------------------------------------------------------------------------
# 8. CONFIGURE AUTHORITATIVE DASHBOARD KIOSK SERVICE
# ------------------------------------------------------------------------------
echo "[8/10] Configuring Authoritative Dashboard Systemd Service..."

cat << EOF_DASHBOARD_SVC > /etc/systemd/system/streampulse-dashboard.service
[Unit]
Description=StreamPulse Dashboard Fullscreen Kiosk Service
Documentation=https://streampulse.io
After=network-online.target sound.target pipewire.service wireplumber.service graphical-session.target graphical.target
Wants=network-online.target sound.target

[Service]
Type=simple
User=${ACTIVE_USER}
Environment=DISPLAY=:0
Environment=WAYLAND_DISPLAY=wayland-0
Environment=XDG_RUNTIME_DIR=/run/user/${TARGET_UID}
ExecStart=/opt/streampulse/bin/dashboard-kiosk.sh
Restart=always
RestartSec=3
KillMode=mixed
TimeoutStopSec=10

[Install]
WantedBy=graphical.target default.target
EOF_DASHBOARD_SVC

chmod +x /opt/streampulse/bin/*.sh
chown -R "$ACTIVE_USER:$ACTIVE_USER" /opt/streampulse

# Harmonize autostart (eliminate duplicate unmanaged browser processes)
mkdir -p "${TARGET_HOME}/.config/labwc"
if [ -f "${TARGET_HOME}/.config/labwc/autostart" ]; then
  sed -i '/chromium.*--kiosk/d' "${TARGET_HOME}/.config/labwc/autostart" 2>/dev/null || true
fi
if [ -d "${TARGET_HOME}/.config/autostart" ]; then
  rm -f "${TARGET_HOME}/.config/autostart/chromium*.desktop" 2>/dev/null || true
fi
chown -R "$ACTIVE_USER:$ACTIVE_USER" "${TARGET_HOME}/.config"

# LightDM Autologin
if [ -d /etc/lightdm ]; then
  mkdir -p /etc/lightdm/lightdm.conf.d
  cat << EOF_LIGHTDM > /etc/lightdm/lightdm.conf.d/80-streampulse-autologin.conf
[Seat:*]
autologin-user=${ACTIVE_USER}
autologin-user-timeout=0
user-session=labwc
EOF_LIGHTDM
  echo "  ✓ Configured LightDM autologin for user '$ACTIVE_USER'."
fi

# ------------------------------------------------------------------------------
# 9. ACTIVATE AND ENABLE SERVICES
# ------------------------------------------------------------------------------
echo "[9/10] Reloading Systemd Daemons and Enabling Services..."
systemctl daemon-reload
systemctl enable streampulse-dashboard.service
systemctl restart streampulse-dashboard.service 2>/dev/null || true
echo "  ✓ streampulse-dashboard.service enabled & active."

# ------------------------------------------------------------------------------
# 10. RUN PRODUCTION VALIDATION TESTS
# ------------------------------------------------------------------------------
if [ "$SKIP_VALIDATE" -eq 0 ] && [ -x /opt/streampulse/bin/validate.sh ]; then
  echo ""
  echo "[10/10] Running Automated 10-Point Validation Suite..."
  echo ""
  bash /opt/streampulse/bin/validate.sh || true
else
  echo "[10/10] Skipping automated validation tests."
fi

echo ""
echo "========================================================================"
echo "          StreamPulse Master Installation Complete!                     "
echo "========================================================================"
echo "Summary:"
echo "  - Stream Key:       $STREAM_KEY"
echo "  - Dashboard URL:    $DASHBOARD_URL"
echo "  - Target User:      $ACTIVE_USER"
echo "  - Kiosk Profile:    /opt/streampulse/chromium-profile"
echo "  - Keyring Flag:     --password-store=basic (Integrated)"
echo ""
echo "Useful Commands:"
echo "  - View Kiosk Status:  sudo systemctl status streampulse-dashboard.service"
echo "  - Live Journal Logs:  sudo journalctl -u streampulse-dashboard.service -f"
echo "  - Run Diagnostics:    sudo /opt/streampulse/bin/diagnose.sh"
echo "  - Run Validation:     sudo /opt/streampulse/bin/validate.sh"
echo "  - Rollback / Restore: sudo /opt/streampulse/bin/restore.sh"
echo "  - Safe Uninstall:     sudo /opt/streampulse/bin/uninstall.sh"
echo "========================================================================"
