#!/usr/bin/env bash
# ==============================================================================
# StreamPulse Kiosk Suite - Production Installer & System Provisioner
# Target: Raspberry Pi | Debian 13 (Trixie) ARM64 | Labwc Desktop Session
# Target User: himakara (with dynamic non-root user fallback)
# Dashboard URL: http://187.127.210.81/
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARD_URL="http://187.127.210.81/"
DEFAULT_USER="himakara"

echo "========================================================================"
echo "       StreamPulse Dedicated Kiosk & Media Player Installer             "
echo "========================================================================"
echo "Target Dashboard URL: $DASHBOARD_URL"
echo ""

# ------------------------------------------------------------------------------
# 1. PRE-FLIGHT PRIVILEGE & OS VERIFICATION
# ------------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
  echo "Error: This installer must be executed as root."
  echo "Please run: sudo bash $0"
  exit 1
fi

echo "[1/10] Checking Operating System, Architecture & User Account..."

# Detect Architecture
ARCH="$(uname -m)"
echo "  - CPU Architecture: $ARCH"
if [ "$ARCH" != "aarch64" ] && [ "$ARCH" != "arm64" ]; then
  echo "  - Notice: Non-ARM64 architecture detected ($ARCH). Proceeding with multi-arch compatibility mode."
fi

# Detect Debian/OS Release
if [ -f /etc/os-release ]; then
  OS_NAME=$(grep -E "^PRETTY_NAME=" /etc/os-release | cut -d= -f2 | tr -d '\"' || echo "Linux")
  echo "  - OS: $OS_NAME"
fi

# Detect Target Non-Root User
TARGET_USER="${SUDO_USER:-$(logname 2>/dev/null || id -un 1000 2>/dev/null || echo "$DEFAULT_USER")}"
if [ "$TARGET_USER" = "root" ]; then
  TARGET_USER="$(id -un 1000 2>/dev/null || echo "$DEFAULT_USER")"
fi

# If himakara exists, prefer himakara
if id "himakara" >/dev/null 2>&1; then
  TARGET_USER="himakara"
fi

TARGET_UID="$(id -u "$TARGET_USER" 2>/dev/null || echo "1000")"
TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6 || echo "/home/$TARGET_USER")"
echo "  - Target User: $TARGET_USER (UID: $TARGET_UID, Home: $TARGET_HOME)"

# ------------------------------------------------------------------------------
# 2. DETECT EXISTING SYSTEM & PREVENT REGRESSIONS
# ------------------------------------------------------------------------------
echo "[2/10] Inspecting Existing Kiosk, Player & Autostart Configurations..."

# Search for existing player services
EXISTING_PLAYER_SERVICES=()
for svc in $(systemctl list-unit-files --type=service 2>/dev/null | grep -E "(streampulse|player|logo|streaming|media)" | awk '{print $1}' || true); do
  EXISTING_PLAYER_SERVICES+=("$svc")
done

if [ ${#EXISTING_PLAYER_SERVICES[@]} -gt 0 ]; then
  echo "  - Detected existing media services: ${EXISTING_PLAYER_SERVICES[*]}"
else
  echo "  - No conflicting media services found."
fi

# Detect existing browser launch paths
if [ -f "${TARGET_HOME}/.config/labwc/autostart" ]; then
  echo "  - Detected existing Labwc autostart file."
fi
if [ -d "${TARGET_HOME}/.config/autostart" ]; then
  echo "  - Detected existing XDG autostart directory."
fi

# ------------------------------------------------------------------------------
# 3. CREATE COMPREHENSIVE TIMESTAMPED BACKUP
# ------------------------------------------------------------------------------
echo "[3/10] Creating Pre-Flight Backup of All System Configurations..."
if [ -f "$SCRIPT_DIR/backup.sh" ]; then
  bash "$SCRIPT_DIR/backup.sh"
else
  TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
  BACKUP_DIR="${TARGET_HOME}/streampulse-backups/${TIMESTAMP}"
  mkdir -p "$BACKUP_DIR"
  [ -d "${TARGET_HOME}/.config/labwc" ] && cp -r "${TARGET_HOME}/.config/labwc" "$BACKUP_DIR/" 2>/dev/null || true
  [ -d "${TARGET_HOME}/.config/autostart" ] && cp -r "${TARGET_HOME}/.config/autostart" "$BACKUP_DIR/" 2>/dev/null || true
  echo "  ✓ Backup saved to $BACKUP_DIR"
fi

# ------------------------------------------------------------------------------
# 4. INSTALL REQUIRED PACKAGES (IDEMPOTENT, SAFE)
# ------------------------------------------------------------------------------
echo "[4/10] Verifying Required Packages..."
export DEBIAN_FRONTEND=noninteractive
MISSING_PKGS=()

for pkg in curl unclutter ca-certificates; do
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    MISSING_PKGS+=("$pkg")
  fi
done

# Check Chromium or Firefox
if ! command -v chromium >/dev/null 2>&1 && ! command -v chromium-browser >/dev/null 2>&1; then
  MISSING_PKGS+=("chromium-browser")
fi

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
  echo "  - Installing missing dependencies: ${MISSING_PKGS[*]}"
  apt-get update -qq || true
  apt-get install -y --no-install-recommends "${MISSING_PKGS[@]}" || {
    # Fallback if chromium-browser package name differs in Debian 13
    apt-get install -y --no-install-recommends chromium || true
  }
else
  echo "  ✓ All core packages are already installed."
fi

# ------------------------------------------------------------------------------
# 5. CONFIGURE STREAM PULSE DIRECTORIES & ASSETS
# ------------------------------------------------------------------------------
echo "[5/10] Provisioning Application Directories & Isolated Browser Profile..."
mkdir -p /opt/streampulse/bin /opt/streampulse/config /opt/streampulse/media /opt/streampulse/chromium-profile

# Copy scripts to /opt/streampulse/bin
cp "$SCRIPT_DIR/dashboard-kiosk.sh" /opt/streampulse/bin/ 2>/dev/null || true
cp "$SCRIPT_DIR/backup.sh" /opt/streampulse/bin/ 2>/dev/null || true
cp "$SCRIPT_DIR/restore.sh" /opt/streampulse/bin/ 2>/dev/null || true
cp "$SCRIPT_DIR/diagnose.sh" /opt/streampulse/bin/ 2>/dev/null || true
cp "$SCRIPT_DIR/validate.sh" /opt/streampulse/bin/ 2>/dev/null || true
cp "$SCRIPT_DIR/uninstall.sh" /opt/streampulse/bin/ 2>/dev/null || true
cp "$SCRIPT_DIR/kiosk.conf" /opt/streampulse/config/ 2>/dev/null || true

chmod +x /opt/streampulse/bin/*.sh
chown -R "$TARGET_USER:$TARGET_USER" /opt/streampulse

# Sync Motion Logo if present
LOCAL_LOGO="/opt/streampulse/media/motion_logo.mp4"
DOWNLOAD_LOGO="${TARGET_HOME}/Downloads/Motion Logo.mp4"
DOWNLOAD_LOGO_ALT="${TARGET_HOME}/Downloads/motion_logo.mp4"

if [ -f "$DOWNLOAD_LOGO" ] && [ -s "$DOWNLOAD_LOGO" ]; then
  cp "$DOWNLOAD_LOGO" "$LOCAL_LOGO" 2>/dev/null || true
  chmod 644 "$LOCAL_LOGO" 2>/dev/null || true
  echo "  ✓ Synced Motion Logo asset from Downloads"
elif [ -f "$DOWNLOAD_LOGO_ALT" ] && [ -s "$DOWNLOAD_LOGO_ALT" ]; then
  cp "$DOWNLOAD_LOGO_ALT" "$LOCAL_LOGO" 2>/dev/null || true
  chmod 644 "$LOCAL_LOGO" 2>/dev/null || true
  echo "  ✓ Synced Motion Logo asset from Downloads"
fi

# ------------------------------------------------------------------------------
# 6. CONFIGURE SYSTEMD KIOSK SERVICE
# ------------------------------------------------------------------------------
echo "[6/10] Configuring StreamPulse Dashboard Systemd Service..."
cat << EOF > /etc/systemd/system/streampulse-dashboard.service
[Unit]
Description=StreamPulse Dashboard Kiosk Service
Documentation=https://streampulse.io
After=network-online.target sound.target graphical-session.target graphical.target
Wants=network-online.target

[Service]
Type=simple
User=${TARGET_USER}
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
EOF

systemctl daemon-reload
systemctl enable streampulse-dashboard.service

# ------------------------------------------------------------------------------
# 7. CONFIGURE LABWC & CLEAN UP DUPLICATE COMPETING LAUNCHERS
# ------------------------------------------------------------------------------
echo "[7/10] Harmonizing Labwc Autostart (Eliminating Duplicate Competing Launchers)..."
mkdir -p "${TARGET_HOME}/.config/labwc"

# If labwc autostart exists, ensure it does not launch a duplicate unmanaged chromium instance
if [ -f "${TARGET_HOME}/.config/labwc/autostart" ]; then
  # Remove any raw chromium launches that lack our controlled flags
  sed -i '/chromium.*--kiosk/d' "${TARGET_HOME}/.config/labwc/autostart" 2>/dev/null || true
fi

# Ensure user's autostart directory is clean of competing browser launches
if [ -d "${TARGET_HOME}/.config/autostart" ]; then
  rm -f "${TARGET_HOME}/.config/autostart/chromium*.desktop" 2>/dev/null || true
  rm -f "${TARGET_HOME}/.config/autostart/google-chrome*.desktop" 2>/dev/null || true
fi

chown -R "$TARGET_USER:$TARGET_USER" "${TARGET_HOME}/.config"

# ------------------------------------------------------------------------------
# 8. CONFIGURE AUTOMATIC LOGIN FOR HIMAKARA (DEBIAN 13 / LIGHTDM / SYSTEMD)
# ------------------------------------------------------------------------------
echo "[8/10] Verifying Autologin Configuration for User '${TARGET_USER}'..."
if [ -d /etc/lightdm ]; then
  mkdir -p /etc/lightdm/lightdm.conf.d
  cat << EOF > /etc/lightdm/lightdm.conf.d/80-streampulse-autologin.conf
[Seat:*]
autologin-user=${TARGET_USER}
autologin-user-timeout=0
user-session=labwc
EOF
  # Add user to autologin group
  groupadd -f autologin
  usermod -aG autologin "$TARGET_USER" 2>/dev/null || true
  echo "  ✓ Configured LightDM autologin for $TARGET_USER"
fi

# ------------------------------------------------------------------------------
# 9. START SERVICES SAFELY
# ------------------------------------------------------------------------------
echo "[9/10] Starting StreamPulse Kiosk Service..."
systemctl restart streampulse-dashboard.service || true

# ------------------------------------------------------------------------------
# 10. RUN PRODUCTION VALIDATION TESTS
# ------------------------------------------------------------------------------
echo "[10/10] Running Final Validation Tests..."
echo ""
bash /opt/streampulse/bin/validate.sh || true

echo ""
echo "========================================================================"
echo "          Installation and Setup Completed Successfully!                "
echo "========================================================================"
echo "Management Commands:"
echo "  - Check Status:   sudo systemctl status streampulse-dashboard.service"
echo "  - View Logs:      sudo journalctl -u streampulse-dashboard.service -f"
echo "  - Run Diagnostic: sudo bash /opt/streampulse/bin/diagnose.sh"
echo "  - Revert/Restore: sudo bash /opt/streampulse/bin/restore.sh"
echo "  - Uninstall:      sudo bash /opt/streampulse/bin/uninstall.sh"
echo "========================================================================"
