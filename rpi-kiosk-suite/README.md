# StreamPulse Dedicated Kiosk & Media Suite for Raspberry Pi

**Target Device:** Raspberry Pi 4 / 5  
**Operating System:** Debian 13 (Trixie) ARM64 / Raspberry Pi OS 64-bit  
**Compositor / Desktop Environment:** Labwc (Wayland)  
**Target User:** `himakara` (or active non-root user)  
**Dashboard URL:** `http://187.127.210.81/`  

---

## Architecture Overview

```
Raspberry Pi Boot
   │
   ├─► System Services (PipeWire / WirePlumber / RustDesk) [UNTOUCHED]
   ├─► LightDM Autologin -> user 'himakara' -> Labwc Wayland Session
   │
   └─► streampulse-dashboard.service (systemd)
          │
          ▼
       /opt/streampulse/bin/dashboard-kiosk.sh
          │
          ├─► Checks Single Instance Lock (no duplicate browsers)
          ├─► Probes Network & Dashboard URL reachability
          ├─► Passes --password-store=basic (PREVENTS Keyring Popups)
          ├─► Dedicated Profile: /opt/streampulse/chromium-profile
          └─► Fullscreen Kiosk Mode (no desktop panels or borders)
```

---

## 1-Command Quick Installation

Run this single command on your Raspberry Pi terminal:

```bash
curl -sSL http://187.127.210.81/api/rpi-player/script/kiosk-install | sudo bash
```

Or clone/copy the `rpi-kiosk-suite` directory and execute:

```bash
chmod +x install.sh
sudo ./install.sh
```

---

## File Structure

| Path | Purpose |
|---|---|
| `/opt/streampulse/bin/dashboard-kiosk.sh` | Controlled browser launcher with keyring suppression and retry loop |
| `/opt/streampulse/bin/backup.sh` | Timestamped pre-flight snapshot engine |
| `/opt/streampulse/bin/restore.sh` | Rollback engine to restore previous configurations |
| `/opt/streampulse/bin/diagnose.sh` | Complete system health and session diagnostic reporter |
| `/opt/streampulse/bin/validate.sh` | Automated 10-point production test suite |
| `/opt/streampulse/bin/uninstall.sh` | Safe uninstaller (preserves user data and media) |
| `/opt/streampulse/config/kiosk.conf` | Centralized kiosk configuration file |
| `/etc/systemd/system/streampulse-dashboard.service` | Production systemd unit managing browser lifecycle |
| `~/streampulse-backups/YYYYMMDD-HHMMSS/` | Historical configuration snapshots |

---

## Control & Diagnostics Commands

### Check Kiosk Status
```bash
sudo systemctl status streampulse-dashboard.service
```

### View Live Kiosk Logs
```bash
sudo journalctl -u streampulse-dashboard.service -f
# OR
tail -f /var/log/streampulse-kiosk.log
```

### Run Diagnostics Report
```bash
sudo bash /opt/streampulse/bin/diagnose.sh
```

### Run Validation Checks
```bash
sudo bash /opt/streampulse/bin/validate.sh
```

### Rollback / Restore Previous Config
```bash
sudo bash /opt/streampulse/bin/restore.sh
```

### Safe Uninstall
```bash
sudo bash /opt/streampulse/bin/uninstall.sh
```
