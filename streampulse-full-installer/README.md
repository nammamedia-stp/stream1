# StreamPulse Full Installer for Raspberry Pi
**Target:** Raspberry Pi OS 64-bit / Debian 13 (Trixie) ARM64 / Labwc Desktop  
**Target User:** `himakara` (with automatic non-root fallback)

---

## Overview

The StreamPulse Full Installer provisions a brand-new or existing Raspberry Pi into a production-grade live streaming & kiosk display node.

It configures all 10 essential capabilities in a single, idempotent pass:
1. **StreamPulse Logo Player** (offline Motion Logo MP4 loop & fallback)
2. **StreamPulse Streaming Player** (HLS hardware-accelerated playback)
3. **Dashboard Web Interface** (responsive telemetry & controls)
4. **Fullscreen / Kiosk Mode** (dedicated browser profile, no desktop chrome)
5. **Automatic Boot Startup** (systemd supervised service)
6. **Zero Keyring / Password Popups** (`--password-store=basic` argument)
7. **Reboot Persistence & Recovery** (process watchdog & crash recovery)
8. **Backup & Restore Engine** (timestamped snapshots in `~/streampulse-backups/`)
9. **Comprehensive Diagnostics** (`/opt/streampulse/bin/diagnose.sh`)
10. **Automated 10-Point Validation** (`/opt/streampulse/bin/validate.sh`)

---

## 1-Command Installation

Run on the Raspberry Pi:

```bash
curl -fsSL "http://187.127.210.81/api/rpi-player/script/full-install?streamKey=live_stream&dashboardUrl=http://187.127.210.81/" | sudo bash
```

Or clone/download this repository and run locally:

```bash
sudo bash full-install.sh --stream-key "YOUR_STREAM_KEY" --dashboard-url "http://187.127.210.81/"
```

---

## Command-Line Options

```text
Usage:
  sudo bash full-install.sh [OPTIONS]

Options:
  -k, --stream-key KEY        Stream key for StreamPulse Player (default: "live_stream")
  -u, --dashboard-url URL     Target URL for Fullscreen Kiosk (default: "http://187.127.210.81/")
  -s, --server-url URL        StreamPulse backend server URL (default: inferred from dashboard URL)
  -U, --user USERNAME         Linux non-root user (default: "himakara" or current user)
  --no-validate               Skip running post-installation validation tests
  -h, --help                  Show help message and exit
```

---

## Project Structure

```text
streampulse-full-installer/
├── full-install.sh
├── uninstall.sh
├── restore.sh
├── README.md
├── config/
│   └── kiosk.conf
├── systemd/
│   └── streampulse-dashboard.service
└── bin/
    ├── dashboard-kiosk.sh
    ├── backup.sh
    ├── diagnose.sh
    └── validate.sh
```

---

## Management & Operations

### 1. Run Automated Validation Matrix
```bash
sudo /opt/streampulse/bin/validate.sh
```

### 2. Run Comprehensive Diagnostics
```bash
sudo /opt/streampulse/bin/diagnose.sh
```

### 3. Check Live Kiosk Logs
```bash
sudo journalctl -u streampulse-dashboard.service -f
```

### 4. Restore Pre-Installation Backup
```bash
sudo /opt/streampulse/bin/restore.sh
```

### 5. Safe Uninstallation
```bash
sudo /opt/streampulse/bin/uninstall.sh
```
