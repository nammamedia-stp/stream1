import fs from 'fs';
import path from 'path';

const rootDir = process.cwd();
const installerDir = path.join(rootDir, 'streampulse-universal-installer');

// Read source files
const playerHtml = fs.readFileSync(path.join(installerDir, 'logo/player.html'), 'utf-8');
const streampulsePlayerSh = fs.readFileSync(path.join(installerDir, 'bin/streampulse-player.sh'), 'utf-8');
const updateSh = fs.readFileSync(path.join(installerDir, 'bin/streampulse-update.sh'), 'utf-8');
const validateSh = fs.readFileSync(path.join(installerDir, 'bin/validate.sh'), 'utf-8');
const backupSh = fs.readFileSync(path.join(installerDir, 'bin/backup.sh'), 'utf-8');
const restoreSh = fs.readFileSync(path.join(installerDir, 'bin/restore.sh'), 'utf-8');
const setChannelSh = fs.readFileSync(path.join(installerDir, 'bin/set-channel.sh'), 'utf-8');
const diagnoseSh = fs.readFileSync(path.join(installerDir, 'bin/diagnose.sh'), 'utf-8');
const uninstallSh = fs.readFileSync(path.join(installerDir, 'uninstall.sh'), 'utf-8');

// Update full-install.sh
let fullInstall = fs.readFileSync(path.join(installerDir, 'full-install.sh'), 'utf-8');

// Replace embedded player.html
const playerHtmlRegex = /cat << 'HTML' > \/opt\/streampulse\/logo\/player\.html\n[\s\S]*?\nHTML\n/m;
fullInstall = fullInstall.replace(playerHtmlRegex, () => `cat << 'HTML' > /opt/streampulse/logo/player.html\n${playerHtml}\nHTML\n`);

// Replace embedded streampulse-player.sh
const playerShRegex = /cat << 'EOF_PLAYER' > \/opt\/streampulse\/bin\/streampulse-player\.sh\n[\s\S]*?\nEOF_PLAYER\n/m;
fullInstall = fullInstall.replace(playerShRegex, () => `cat << 'EOF_PLAYER' > /opt/streampulse/bin/streampulse-player.sh\n${streampulsePlayerSh}\nEOF_PLAYER\n`);

// Replace embedded streampulse-update.sh
const updateShRegex = /cat << 'EOF_UPDATE' > \/opt\/streampulse\/bin\/streampulse-update\.sh\n[\s\S]*?\nEOF_UPDATE\n/m;
fullInstall = fullInstall.replace(updateShRegex, () => `cat << 'EOF_UPDATE' > /opt/streampulse/bin/streampulse-update.sh\n${updateSh}\nEOF_UPDATE\n`);

// Replace embedded set-channel.sh
const setChannelShRegex = /cat << 'EOF_SET_CHANNEL' > \/opt\/streampulse\/bin\/set-channel\.sh\n[\s\S]*?\nEOF_SET_CHANNEL\n/m;
fullInstall = fullInstall.replace(setChannelShRegex, () => `cat << 'EOF_SET_CHANNEL' > /opt/streampulse/bin/set-channel.sh\n${setChannelSh}\nEOF_SET_CHANNEL\n`);

// Replace embedded backup.sh
const backupShRegex = /cat << 'EOF_BACKUP' > \/opt\/streampulse\/bin\/backup\.sh\n[\s\S]*?\nEOF_BACKUP\n/m;
fullInstall = fullInstall.replace(backupShRegex, () => `cat << 'EOF_BACKUP' > /opt/streampulse/bin/backup.sh\n${backupSh}\nEOF_BACKUP\n`);

// Replace embedded restore.sh
const restoreShRegex = /cat << 'EOF_RESTORE' > \/opt\/streampulse\/bin\/restore\.sh\n[\s\S]*?\nEOF_RESTORE\n/m;
fullInstall = fullInstall.replace(restoreShRegex, () => `cat << 'EOF_RESTORE' > /opt/streampulse/bin/restore.sh\n${restoreSh}\nEOF_RESTORE\n`);

// Replace embedded diagnose.sh
const diagnoseShRegex = /cat << 'EOF_DIAGNOSE' > \/opt\/streampulse\/bin\/diagnose\.sh\n[\s\S]*?\nEOF_DIAGNOSE\n/m;
fullInstall = fullInstall.replace(diagnoseShRegex, () => `cat << 'EOF_DIAGNOSE' > /opt/streampulse/bin/diagnose.sh\n${diagnoseSh}\nEOF_DIAGNOSE\n`);

// Replace embedded validate.sh
const validateShRegex = /cat << 'EOF_VALIDATE' > \/opt\/streampulse\/bin\/validate\.sh\n[\s\S]*?\nEOF_VALIDATE\n/m;
fullInstall = fullInstall.replace(validateShRegex, () => `cat << 'EOF_VALIDATE' > /opt/streampulse/bin/validate.sh\n${validateSh}\nEOF_VALIDATE\n`);

// Write updated full-install.sh
fs.writeFileSync(path.join(installerDir, 'full-install.sh'), fullInstall, 'utf-8');
fs.chmodSync(path.join(installerDir, 'full-install.sh'), 0o755);

console.log('✓ Synchronized streampulse-universal-installer/full-install.sh');

// Generate server/rpiUniversalTemplates.ts
let systemInfoSh = "";
try {
  systemInfoSh = fs.readFileSync(path.join(installerDir, 'bin/system-info.sh'), 'utf-8');
} catch (_) {
  systemInfoSh = "#!/usr/bin/env bash\necho 'StreamPulse System Info'\n";
}

const templatesContent = `// Auto-generated universal installer templates
export const EMBEDDED_UNIVERSAL_FULL_INSTALL = ${JSON.stringify(fullInstall)};
export const EMBEDDED_UNIVERSAL_PLAYER_SCRIPT = ${JSON.stringify(streampulsePlayerSh)};
export const EMBEDDED_UNIVERSAL_PLAYER_HTML = ${JSON.stringify(playerHtml)};
export const EMBEDDED_UNIVERSAL_UPDATE = ${JSON.stringify(updateSh)};
export const EMBEDDED_UNIVERSAL_VALIDATE = ${JSON.stringify(validateSh)};
export const EMBEDDED_UNIVERSAL_SET_CHANNEL = ${JSON.stringify(setChannelSh)};
export const EMBEDDED_UNIVERSAL_DIAGNOSE = ${JSON.stringify(diagnoseSh)};
export const EMBEDDED_UNIVERSAL_SYSTEM_INFO = ${JSON.stringify(systemInfoSh)};
export const EMBEDDED_UNIVERSAL_BACKUP = ${JSON.stringify(backupSh)};
export const EMBEDDED_UNIVERSAL_RESTORE = ${JSON.stringify(restoreSh)};
export const EMBEDDED_UNIVERSAL_UNINSTALL = ${JSON.stringify(uninstallSh)};
`;

fs.writeFileSync(path.join(rootDir, 'server/rpiUniversalTemplates.ts'), templatesContent, 'utf-8');
console.log('✓ Synchronized server/rpiUniversalTemplates.ts');
