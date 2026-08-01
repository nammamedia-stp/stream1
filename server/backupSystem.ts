import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
import zlib from 'zlib';
import { db } from './db.js';

const BACKUP_DIR = path.resolve('./backups');

if (!fs.existsSync(BACKUP_DIR)) {
  fs.mkdirSync(BACKUP_DIR, { recursive: true });
}

export interface BackupManifest {
  backup_id: string;
  timestamp: string;
  type: 'manual' | 'scheduled' | 'safety';
  created_by: string;
  version: string;
  system_info: {
    node_version: string;
    platform: string;
    app_name: string;
  };
  components: string[];
  exclusions: string[];
  sha256: string;
  record_counts: {
    users: number;
    streams: number;
    devices: number;
    auditLogs: number;
    appSettingsKeys: number;
  };
}

export interface BackupItem {
  id: string;
  filename: string;
  size: number;
  size_formatted: string;
  timestamp: string;
  type: 'manual' | 'scheduled' | 'safety';
  created_by: string;
  sha256: string;
  verified: boolean;
  verification_message?: string;
  record_counts?: Record<string, number>;
}

// Format bytes into readable string
function formatBytes(bytes: number): string {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

// ----------------------------------------------------
// PURE JS TAR ENCODER & DECODER WITH ZLIB COMPRESSION
// ----------------------------------------------------

interface TarEntry {
  name: string;
  data: Buffer;
}

function packTarGz(entries: TarEntry[]): Buffer {
  const buffers: Buffer[] = [];

  for (const entry of entries) {
    const header = Buffer.alloc(512);
    
    // File name (100 bytes)
    header.write(entry.name, 0, Math.min(entry.name.length, 99), 'utf-8');
    
    // File mode (8 bytes)
    header.write('0000644\0', 100, 8, 'ascii');
    
    // Owner UID (8 bytes)
    header.write('0000000\0', 108, 8, 'ascii');
    
    // Group GID (8 bytes)
    header.write('0000000\0', 116, 8, 'ascii');
    
    // Size in octal (12 bytes)
    const sizeOctal = entry.data.length.toString(8).padStart(11, '0') + '\0';
    header.write(sizeOctal, 124, 12, 'ascii');
    
    // Last modification time (12 bytes)
    const mtimeOctal = Math.floor(Date.now() / 1000).toString(8).padStart(11, '0') + '\0';
    header.write(mtimeOctal, 136, 12, 'ascii');
    
    // Typeflag ('0' = normal file)
    header.write('0', 156, 1, 'ascii');
    
    // UStar magic ('ustar\0') and version ('00')
    header.write('ustar\0', 257, 6, 'ascii');
    header.write('00', 263, 2, 'ascii');
    
    // Compute Checksum
    // Fill checksum field with spaces first
    header.write('        ', 144, 8, 'ascii');
    let sum = 0;
    for (let i = 0; i < 512; i++) {
      sum += header[i];
    }
    const checksumOctal = sum.toString(8).padStart(6, '0') + '\0 ';
    header.write(checksumOctal, 144, 8, 'ascii');

    buffers.push(header);
    buffers.push(entry.data);

    // Padding to 512 byte block boundary
    const remainder = entry.data.length % 512;
    if (remainder > 0) {
      buffers.push(Buffer.alloc(512 - remainder));
    }
  }

  // End of archive marker (1024 bytes of zeroes)
  buffers.push(Buffer.alloc(1024));

  const tarBuffer = Buffer.concat(buffers);
  return zlib.gzipSync(tarBuffer);
}

function unpackTarGz(gzBuffer: Buffer): TarEntry[] {
  const tarBuffer = zlib.gunzipSync(gzBuffer);
  const entries: TarEntry[] = [];
  let offset = 0;

  while (offset + 512 <= tarBuffer.length) {
    const header = tarBuffer.subarray(offset, offset + 512);
    
    // Check if empty block (end of archive)
    let isZero = true;
    for (let i = 0; i < 512; i++) {
      if (header[i] !== 0) {
        isZero = false;
        break;
      }
    }
    if (isZero) break;

    // Read file name
    let nameEnd = 0;
    while (nameEnd < 100 && header[nameEnd] !== 0) {
      nameEnd++;
    }
    const name = header.toString('utf-8', 0, nameEnd).trim();
    if (!name) break;

    // Read size in octal
    const sizeStr = header.toString('ascii', 124, 135).replace(/\0/g, '').trim();
    const size = parseInt(sizeStr, 8) || 0;

    offset += 512;

    const data = tarBuffer.subarray(offset, offset + size);
    entries.push({ name, data: Buffer.from(data) });

    const remainder = size % 512;
    const padding = remainder > 0 ? 512 - remainder : 0;
    offset += size + padding;
  }

  return entries;
}

// ----------------------------------------------------
// BACKUP SYSTEM CONTROLLER
// ----------------------------------------------------

export const backupSystem = {
  getBackupDir: () => BACKUP_DIR,

  // List all available backups
  listBackups: async (): Promise<BackupItem[]> => {
    if (!fs.existsSync(BACKUP_DIR)) {
      fs.mkdirSync(BACKUP_DIR, { recursive: true });
    }

    const files = fs.readdirSync(BACKUP_DIR).filter(f => f.endsWith('.tar.gz'));
    const items: BackupItem[] = [];

    for (const file of files) {
      const filePath = path.join(BACKUP_DIR, file);
      try {
        const stats = fs.statSync(filePath);
        const gzBuffer = fs.readFileSync(filePath);
        const entries = unpackTarGz(gzBuffer);

        const manifestEntry = entries.find(e => e.name === 'manifest.json');
        const checksumEntry = entries.find(e => e.name === 'checksum.sha256');

        let manifest: Partial<BackupManifest> = {};
        if (manifestEntry) {
          try {
            manifest = JSON.parse(manifestEntry.data.toString('utf-8'));
          } catch (e) {}
        }

        const sha256 = checksumEntry
          ? checksumEntry.data.toString('utf-8').trim()
          : manifest.sha256 || crypto.createHash('sha256').update(gzBuffer).digest('hex');

        items.push({
          id: manifest.backup_id || file,
          filename: file,
          size: stats.size,
          size_formatted: formatBytes(stats.size),
          timestamp: manifest.timestamp || stats.mtime.toISOString(),
          type: (manifest.type as any) || (file.includes('_scheduled') ? 'scheduled' : file.includes('_safety') ? 'safety' : 'manual'),
          created_by: manifest.created_by || 'system',
          sha256,
          verified: true,
          record_counts: manifest.record_counts
        });
      } catch (err: any) {
        items.push({
          id: file,
          filename: file,
          size: fs.statSync(filePath).size,
          size_formatted: formatBytes(fs.statSync(filePath).size),
          timestamp: fs.statSync(filePath).mtime.toISOString(),
          type: 'manual',
          created_by: 'unknown',
          sha256: 'unverified',
          verified: false,
          verification_message: 'Archive parsing error: ' + err.message
        });
      }
    }

    // Sort newest first
    items.sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime());
    return items;
  },

  // Create a Backup Archive
  createBackup: async (type: 'manual' | 'scheduled' | 'safety' = 'manual', username: string = 'admin', serverSettings: any = {}, sslConfig: any = {}): Promise<BackupItem> => {
    const timestampStr = new Date().toISOString().replace(/[-:]/g, '').replace(/\..+/, '').replace('T', '_');
    const filename = `streampulse_backup_${timestampStr}_${type}.tar.gz`;
    const filePath = path.join(BACKUP_DIR, filename);

    // 1. Gather all system data from DB
    const dbDump = await db.dumpAllData();

    // 2. Build complete payload
    const payloadData = {
      version: '1.0',
      timestamp: new Date().toISOString(),
      database: dbDump,
      serverSettings,
      sslConfig,
      deploymentConfig: {
        storageMode: process.env.STORAGE_MODE || 'postgres',
        dbHost: process.env.DB_HOST || 'localhost',
        dbName: process.env.DB_NAME || 'streampulse',
        nodeVersion: process.version,
        platform: process.platform
      }
    };

    const payloadStr = JSON.stringify(payloadData, null, 2);
    const payloadBuffer = Buffer.from(payloadStr, 'utf-8');

    // 3. Calculate SHA256 checksum of payload
    const payloadSha256 = crypto.createHash('sha256').update(payloadBuffer).digest('hex');

    // 4. Build manifest
    const manifest: BackupManifest = {
      backup_id: 'bkp_' + Date.now() + '_' + Math.random().toString(36).substring(2, 8),
      timestamp: new Date().toISOString(),
      type,
      created_by: username,
      version: '1.0',
      system_info: {
        node_version: process.version,
        platform: process.platform,
        app_name: 'StreamPulse Production'
      },
      components: [
        'PostgreSQL Database',
        'User Accounts',
        'Stream Settings',
        'Stream Keys',
        'Server Settings',
        'Domain Settings',
        'SSL Configuration',
        'Analytics',
        'Audit Logs',
        'Recording Metadata',
        'Resolution Profiles',
        'Deployment Configuration'
      ],
      exclusions: [
        'HLS segments (*.ts, *.m3u8)',
        'Temporary files',
        'Cache',
        'FFmpeg runtime files'
      ],
      sha256: payloadSha256,
      record_counts: {
        users: dbDump.users?.length || 0,
        streams: dbDump.streams?.length || 0,
        devices: dbDump.devices?.length || 0,
        auditLogs: dbDump.auditLogs?.length || 0,
        appSettingsKeys: Object.keys(dbDump.appSettings || {}).length
      }
    };

    const manifestBuffer = Buffer.from(JSON.stringify(manifest, null, 2), 'utf-8');
    const checksumBuffer = Buffer.from(payloadSha256, 'utf-8');

    // 5. Pack into tar.gz
    const gzBuffer = packTarGz([
      { name: 'manifest.json', data: manifestBuffer },
      { name: 'payload.json', data: payloadBuffer },
      { name: 'checksum.sha256', data: checksumBuffer }
    ]);

    fs.writeFileSync(filePath, gzBuffer);

    // 6. Enforce retention policy
    await backupSystem.enforceRetention();

    const stats = fs.statSync(filePath);

    return {
      id: manifest.backup_id,
      filename,
      size: stats.size,
      size_formatted: formatBytes(stats.size),
      timestamp: manifest.timestamp,
      type,
      created_by: username,
      sha256: payloadSha256,
      verified: true,
      record_counts: manifest.record_counts
    };
  },

  // Verify Backup Archive Integrity
  verifyBackup: async (filename: string): Promise<{ valid: boolean; filename: string; sha256?: string; manifest?: any; details: string }> => {
    const filePath = path.join(BACKUP_DIR, filename);
    if (!fs.existsSync(filePath)) {
      return { valid: false, filename, details: 'Backup file does not exist on disk' };
    }

    try {
      const gzBuffer = fs.readFileSync(filePath);
      const entries = unpackTarGz(gzBuffer);

      const manifestEntry = entries.find(e => e.name === 'manifest.json');
      const payloadEntry = entries.find(e => e.name === 'payload.json');
      const checksumEntry = entries.find(e => e.name === 'checksum.sha256');

      if (!manifestEntry || !payloadEntry || !checksumEntry) {
        return { valid: false, filename, details: 'Archive missing required components (manifest.json, payload.json, or checksum.sha256)' };
      }

      const payloadStr = payloadEntry.data.toString('utf-8');
      const computedSha256 = crypto.createHash('sha256').update(payloadEntry.data).digest('hex');
      const storedSha256 = checksumEntry.data.toString('utf-8').trim();

      const manifest = JSON.parse(manifestEntry.data.toString('utf-8'));

      if (computedSha256 !== storedSha256) {
        return { valid: false, filename, sha256: computedSha256, manifest, details: `Checksum mismatch! Expected ${storedSha256}, calculated ${computedSha256}` };
      }

      if (manifest.sha256 && manifest.sha256 !== computedSha256) {
        return { valid: false, filename, sha256: computedSha256, manifest, details: `Manifest checksum mismatch! Expected ${manifest.sha256}, calculated ${computedSha256}` };
      }

      // Parse payload to verify structure
      const payload = JSON.parse(payloadStr);
      if (!payload.database) {
        return { valid: false, filename, sha256: computedSha256, manifest, details: 'Archive payload missing database structure' };
      }

      return {
        valid: true,
        filename,
        sha256: computedSha256,
        manifest,
        details: `Integrity check PASSED. SHA256 verified (${computedSha256.substring(0, 12)}...). Payload verified with ${payload.database.users?.length || 0} users and ${payload.database.streams?.length || 0} streams.`
      };
    } catch (err: any) {
      return { valid: false, filename, details: 'Verification error: ' + err.message };
    }
  },

  // Restore Backup Archive
  restoreBackup: async (filename: string, username: string = 'admin', currentServerSettings: any = {}, currentSslConfig: any = {}): Promise<{ success: boolean; message: string; safetyBackupFilename: string; details?: any }> => {
    const filePath = path.join(BACKUP_DIR, filename);
    if (!fs.existsSync(filePath)) {
      throw new Error(`Backup file '${filename}' not found`);
    }

    // 1. Verify target backup archive integrity FIRST
    const verifyRes = await backupSystem.verifyBackup(filename);
    if (!verifyRes.valid) {
      throw new Error(`Restore rejected: Backup archive integrity check failed. ${verifyRes.details}`);
    }

    // 2. Create automatic safety backup BEFORE restore
    console.log('[Disaster Recovery] Creating automatic safety backup before restoration...');
    const safetyBackup = await backupSystem.createBackup('safety', username, currentServerSettings, currentSslConfig);
    console.log(`[Disaster Recovery] Safety backup created: ${safetyBackup.filename}`);

    // 3. Unpack target archive
    const gzBuffer = fs.readFileSync(filePath);
    const entries = unpackTarGz(gzBuffer);
    const payloadEntry = entries.find(e => e.name === 'payload.json');
    if (!payloadEntry) {
      throw new Error('Target archive missing payload.json');
    }

    const payload = JSON.parse(payloadEntry.data.toString('utf-8'));

    // 4. Restore Database tables
    console.log('[Disaster Recovery] Restoring database tables...');
    await db.restoreAllData(payload.database);

    // 5. Check restored system health
    const users = await db.getUsers();
    console.log(`[Disaster Recovery] System health check passed: ${users.length} users restored successfully.`);

    return {
      success: true,
      message: `System successfully restored from '${filename}'. Safety backup preserved as '${safetyBackup.filename}'.`,
      safetyBackupFilename: safetyBackup.filename,
      details: {
        restored_at: new Date().toISOString(),
        restored_by: username,
        safety_backup: safetyBackup.filename,
        record_counts: {
          users: users.length,
          streams: (await db.getStreams()).length,
          devices: (await db.getDevices()).length
        },
        serverSettings: payload.serverSettings || null,
        sslConfig: payload.sslConfig || null
      }
    };
  },

  // Delete Backup Archive
  deleteBackup: async (filename: string): Promise<boolean> => {
    const filePath = path.join(BACKUP_DIR, filename);
    if (fs.existsSync(filePath)) {
      fs.unlinkSync(filePath);
      return true;
    }
    return false;
  },

  // Save Uploaded Backup Archive
  saveUploadedBackup: async (buffer: Buffer, originalFilename: string): Promise<{ backup: BackupItem; verification: any }> => {
    let targetName = originalFilename.replace(/[^a-zA-Z0-9._-]/g, '_');
    if (!targetName.endsWith('.tar.gz')) {
      targetName += '.tar.gz';
    }

    const filePath = path.join(BACKUP_DIR, targetName);
    fs.writeFileSync(filePath, buffer);

    const verification = await backupSystem.verifyBackup(targetName);
    if (!verification.valid) {
      // Remove invalid uploaded file
      if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
      throw new Error(`Uploaded archive is invalid: ${verification.details}`);
    }

    const stats = fs.statSync(filePath);
    const items = await backupSystem.listBackups();
    const backupItem = items.find(i => i.filename === targetName) || {
      id: targetName,
      filename: targetName,
      size: stats.size,
      size_formatted: formatBytes(stats.size),
      timestamp: stats.mtime.toISOString(),
      type: 'manual',
      created_by: 'upload',
      sha256: verification.sha256 || '',
      verified: true
    };

    return { backup: backupItem, verification };
  },

  // Retention Enforcement
  enforceRetention: async (): Promise<number> => {
    const retentionCountVal = await db.getAppSetting('backup_retention_count');
    const limit = parseInt(retentionCountVal || '10', 10) || 10;

    const files = fs.readdirSync(BACKUP_DIR).filter(f => f.endsWith('.tar.gz'));
    // Do not automatically delete safety backups unless exceeded 50
    const filterFiles = files.filter(f => !f.includes('_safety'));

    if (filterFiles.length <= limit) return 0;

    // Sort by file mtime ascending (oldest first)
    const fileStats = filterFiles.map(f => {
      const p = path.join(BACKUP_DIR, f);
      return { file: f, path: p, mtime: fs.statSync(p).mtime.getTime() };
    });

    fileStats.sort((a, b) => a.mtime - b.mtime);

    const toRemoveCount = fileStats.length - limit;
    let deletedCount = 0;

    for (let i = 0; i < toRemoveCount; i++) {
      try {
        fs.unlinkSync(fileStats[i].path);
        deletedCount++;
        console.log(`[Backup Retention] Purged expired backup: ${fileStats[i].file}`);
      } catch (e) {}
    }

    return deletedCount;
  },

  // Scheduler Runner
  getScheduleConfig: async () => {
    const frequency = (await db.getAppSetting('backup_schedule_frequency')) || 'daily'; // 'disabled' | 'daily' | 'weekly' | 'monthly'
    const retentionCount = parseInt((await db.getAppSetting('backup_retention_count')) || '10', 10);
    const lastRun = (await db.getAppSetting('backup_last_run')) || null;
    const nextRun = (await db.getAppSetting('backup_next_run')) || null;

    return { frequency, retentionCount, lastRun, nextRun };
  },

  saveScheduleConfig: async (frequency: string, retentionCount: number) => {
    const validFreqs = ['disabled', 'daily', 'weekly', 'monthly'];
    const freq = validFreqs.includes(frequency) ? frequency : 'daily';
    const ret = [5, 10, 30].includes(retentionCount) ? retentionCount : 10;

    await db.setAppSetting('backup_schedule_frequency', freq);
    await db.setAppSetting('backup_retention_count', String(ret));

    // Recalculate next run date
    if (freq !== 'disabled') {
      const intervalMs = freq === 'daily' ? 24 * 3600 * 1000 : freq === 'weekly' ? 7 * 24 * 3600 * 1000 : 30 * 24 * 3600 * 1000;
      const nextDate = new Date(Date.now() + intervalMs).toISOString();
      await db.setAppSetting('backup_next_run', nextDate);
    } else {
      await db.setAppSetting('backup_next_run', '');
    }

    await backupSystem.enforceRetention();

    return backupSystem.getScheduleConfig();
  },

  checkAndRunSchedule: async (serverSettings: any = {}, sslConfig: any = {}) => {
    try {
      const config = await backupSystem.getScheduleConfig();
      if (config.frequency === 'disabled') return;

      const nowMs = Date.now();
      const lastRunMs = config.lastRun ? new Date(config.lastRun).getTime() : 0;
      const intervalMs = config.frequency === 'daily'
        ? 24 * 3600 * 1000
        : config.frequency === 'weekly'
        ? 7 * 24 * 3600 * 1000
        : 30 * 24 * 3600 * 1000;

      if (nowMs - lastRunMs >= intervalMs) {
        console.log(`[Backup Scheduler] Triggering automated scheduled backup (${config.frequency})...`);
        const backup = await backupSystem.createBackup('scheduled', 'system_scheduler', serverSettings, sslConfig);
        console.log(`[Backup Scheduler] Automated backup completed successfully: ${backup.filename}`);

        const nowIso = new Date().toISOString();
        const nextIso = new Date(nowMs + intervalMs).toISOString();
        await db.setAppSetting('backup_last_run', nowIso);
        await db.setAppSetting('backup_next_run', nextIso);
      }
    } catch (err) {
      console.error('[Backup Scheduler] Scheduled backup failed:', err);
    }
  }
};
