# StreamPulse Universal Master Installer for Raspberry Pi
**Target:** Raspberry Pi OS 64-bit / Debian 13 (Trixie) ARM64 / Labwc Desktop  
**Compatibility:** Works on **Both Fresh / New Pis** and **Existing / Older Pis**  
**User Detection:** Automatic Desktop Login User Detection (`himakara`, `pi`, `operator`, `admin`, etc.)

---

## Architecture Overview

```text
ONE RASPBERRY PI
  ├── COMMON LOGO (/opt/streampulse/logo/)
  │   ├── motion-logo.mp4 (Offline loop)
  │   └── logo-fallback.html (Local webview fallback)
  ├── PI-SPECIFIC STREAM CHANNEL (/opt/streampulse/config/player.conf)
  │   ├── Assigned Channel: channel1 / channel2 / etc.
  │   └── Stream Key: Protected local storage (Masked in diagnostics)
  ├── DASHBOARD FULLSCREEN KIOSK (/opt/streampulse/config/kiosk.conf)
  │   ├── Dedicated profile: /opt/streampulse/chromium-profile
  │   └── Keyring suppression: --password-store=basic (Inside Chromium args)
  └── AUTHORITATIVE SYSTEMD SERVICE
      └── streampulse-dashboard.service (Survives reboots, auto-recovers)
```

---

## 1-Command Universal Installation

Run on the target Raspberry Pi terminal:

```bash
curl -fsSL "http://187.127.210.81/api/rpi-player/script/universal-install?channel=channel1&streamKey=live_stream&dashboardUrl=http://187.127.210.81/" | sudo bash
```

Or pass arguments directly:

```bash
curl -fsSL "http://187.127.210.81/api/rpi-player/script/universal-install" | sudo bash -s -- \
  --channel "channel1" \
  --stream-key "live_stream" \
  --dashboard-url "http://187.127.210.81/"
```

---

## Per-Pi Channel Assignment Examples

- **Pi 1 (Main Hall):**
  ```bash
  curl -fsSL "http://187.127.210.81/api/rpi-player/script/universal-install?channel=channel1&streamKey=live_stream" | sudo bash
  ```
- **Pi 2 (Auditorium):**
  ```bash
  curl -fsSL "http://187.127.210.81/api/rpi-player/script/universal-install?channel=channel2&streamKey=auditorium_feed" | sudo bash
  ```
- **Pi 3 (Lobby):**
  ```bash
  curl -fsSL "http://187.127.210.81/api/rpi-player/script/universal-install?channel=channel3&streamKey=lobby_feed" | sudo bash
  ```

---

## Project Structure

```text
streampulse-universal-installer/
├── full-install.sh                      # Universal Master Installer
├── uninstall.sh                         # Safe Uninstaller (Preserves Logo & Audio)
├── restore.sh                           # Fast Snapshot Restorer
├── README.md                            # Documentation
├── config/
│   ├── kiosk.conf                       # Kiosk & Browser Profile Settings
│   └── player.conf                      # Per-Pi Assigned Channel & Stream Keys
├── systemd/
│   └── streampulse-dashboard.service    # Authoritative systemd Unit
└── bin/
    ├── dashboard-kiosk.sh               # Authoritative Kiosk Launcher
    ├── backup.sh                        # Timestamped Backup Engine
    ├── restore.sh                       # Restoration Tool
    ├── diagnose.sh                      # Diagnostic Tool (Masks Stream Keys)
    ├── validate.sh                      # 18-Point Verification Suite
    └── set-channel.sh                   # Safe Per-Pi Channel Switcher
```

---

## Operations & Management

### 1. Switch Channel on a Running Pi (No Rebuild Required)
```bash
sudo /opt/streampulse/bin/set-channel.sh channel2
# Or with new stream key:
sudo /opt/streampulse/bin/set-channel.sh channel3 new_stream_key
```

### 2. Run 18-Point Validation Matrix
```bash
sudo /opt/streampulse/bin/validate.sh
```

### 3. Run System Diagnostics (Safe Key Masking)
```bash
sudo /opt/streampulse/bin/diagnose.sh
```

### 4. Create a Manual Backup Snapshot
```bash
sudo /opt/streampulse/bin/backup.sh
```

### 5. Restore From Latest Backup
```bash
sudo /opt/streampulse/bin/restore.sh
```

### 6. View Live Kiosk Journal Logs
```bash
sudo journalctl -u streampulse-dashboard.service -f
```
