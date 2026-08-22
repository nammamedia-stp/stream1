import pg from 'pg';
import fs from 'fs';
import path from 'path';
import dotenv from 'dotenv';
import bcrypt from 'bcryptjs';

// Load environment variables before any evaluation is done
dotenv.config();

// Let's create a local file path for fallback JSON persistence
const DATA_DIR = path.resolve('./data');
const JSON_DB_PATH = path.join(DATA_DIR, 'db.json');

// Ensure data directory exists
if (!fs.existsSync(DATA_DIR)) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
}

// Interfaces matching PostgreSQL tables
export interface UserRecord {
  id: number;
  username: string;
  password_hash: string;
  role: 'admin' | 'user';
  created_at: string;
  status?: 'enabled' | 'disabled';
  assigned_stream_id?: string | null;
  login_history?: string | null;
  display_name?: string | null;
}

export interface StreamRecord {
  id: string;
  userId: number;
  channelId?: string;
  title: string;
  broadcaster: string;
  streamKey: string;
  status: 'offline' | 'live' | 'disabled' | 'scheduled';
  scheduledStart?: string;
  rtmpUrl: string;
  resolution: string;
  bitrate: number;
  codec: string;
  ingestIp: string;
  viewers: number;
  startTime?: string;
  width?: number;
  height?: number;
  fps?: number;
  aspectRatio?: string;
  videoCodec?: string;
  audioCodec?: string;
  preset?: string;
  profile?: string;
  pixelFormat?: string;
  enabledProfiles?: string;
  gopSize?: number;
  bufferSize?: number;
  maxBitrate?: number;
  scalingAlgorithm?: string;
  audioEnabled?: boolean;
  audioBitrate?: string;
  audioSampleRate?: number;
  audioChannels?: string;
  audioVolume?: number;
  audioNormalize?: boolean;
  audioNoiseReduction?: boolean;
  audioDelay?: number;
  audioLanguage?: string;
  audioTrackSelection?: string;
  audioPassthrough?: boolean;
  audioTranscoding?: boolean;
  profilesJson?: string;
}

export interface DeviceRecord {
  id: string;
  name: string;
  location?: string;
  description?: string;
  os_version?: string;
  player_version?: string;
  ip_address?: string;
  mac_address?: string;
  last_seen?: string;
  online_status: 'online' | 'offline' | 'playing' | 'buffering' | 'stopped' | 'disconnected';
  current_stream_id?: string;
  current_stream_url?: string;
  current_resolution?: string;
  current_volume: number;
  current_playback_status?: string;
  pairing_code?: string;
  paired: boolean;
  token?: string;
  cpu_usage?: number;
  ram_usage?: number;
  temperature?: number;
  network_speed?: string;
  screenshot_url?: string;
  screenshot_time?: string;
  brightness?: number;
  rotation?: string;
  player_settings?: string;
  network_settings?: string;
  client_version?: string;
}

export interface DeviceGroupRecord {
  id: string;
  name: string;
  description?: string;
}

export interface DeviceGroupMemberRecord {
  group_id: string;
  device_id: string;
}

export interface PlaybackHistoryRecord {
  id: string;
  device_id: string;
  stream_id?: string;
  stream_url?: string;
  action: string;
  timestamp: string;
}

export interface DeviceLogRecord {
  id: string;
  device_id: string;
  level: 'info' | 'warn' | 'error';
  message: string;
  timestamp: string;
}

export interface DeviceScheduleRecord {
  id: string;
  device_id?: string;
  group_id?: string;
  time: string; // e.g. "09:00"
  action: 'play' | 'stop';
  stream_id?: string;
  stream_url?: string;
  enabled: boolean;
}

export interface AuditLogRecord {
  id: string;
  timestamp: string;
  username: string;
  user_role: string;
  action: string;
  module: string; // 'Authentication' | 'User Management' | 'Streaming' | 'Settings' | 'System'
  ip_address: string;
  user_agent: string;
  result: 'success' | 'failed';
  details?: string;
}

// In-Memory Fallback State (persisted to data/db.json)
interface LocalDBState {
  users: UserRecord[];
  streams: StreamRecord[];
  devices: DeviceRecord[];
  deviceGroups: DeviceGroupRecord[];
  deviceGroupMembers: DeviceGroupMemberRecord[];
  playbackHistory: PlaybackHistoryRecord[];
  deviceLogs: DeviceLogRecord[];
  deviceSchedules: DeviceScheduleRecord[];
  auditLogs?: AuditLogRecord[];
  appSettings?: Record<string, string>;
}

let localState: LocalDBState = {
  users: [],
  streams: [
    {
      id: '1',
      userId: 1,
      channelId: 'channel1',
      title: 'Late Night Coding Sessions',
      broadcaster: 'dev_alex',
      viewers: 1240,
      status: 'live',
      startTime: new Date().toISOString(),
      rtmpUrl: 'rtmp://localhost/live',
      streamKey: 'alex_secure_123',
      resolution: '1080p',
      ingestIp: '127.0.0.1',
      bitrate: 6000,
      codec: 'H.264'
    },
    {
      id: '2',
      userId: 1,
      channelId: 'channel2',
      title: 'E-Sports Tournament Qualifiers',
      broadcaster: 'pro_gaming_tv',
      viewers: 8520,
      status: 'live',
      startTime: new Date().toISOString(),
      rtmpUrl: 'rtmp://localhost/live',
      streamKey: 'tournament_alpha',
      resolution: '4K',
      ingestIp: '127.0.0.1',
      bitrate: 10000,
      codec: 'H.265'
    }
  ],
  devices: [],
  deviceGroups: [],
  deviceGroupMembers: [],
  playbackHistory: [],
  deviceLogs: [],
  deviceSchedules: [],
  auditLogs: [],
  appSettings: {}
};

// Load saved data if exists
if (fs.existsSync(JSON_DB_PATH)) {
  try {
    const data = fs.readFileSync(JSON_DB_PATH, 'utf-8');
    const parsed = JSON.parse(data);
    localState = {
      ...localState,
      ...parsed,
      users: parsed.users || [],
      streams: (parsed.streams || []).map((s: any) => ({
        ...s,
        rtmpUrl: s.rtmpUrl || 'rtmp://localhost/ingest',
        ingestIp: s.ingestIp || '127.0.0.1'
      })),
      devices: parsed.devices || [],
      deviceGroups: parsed.deviceGroups || [],
      deviceGroupMembers: parsed.deviceGroupMembers || [],
      playbackHistory: parsed.playbackHistory || [],
      deviceLogs: parsed.deviceLogs || [],
      deviceSchedules: parsed.deviceSchedules || [],
      auditLogs: parsed.auditLogs || [],
      appSettings: parsed.appSettings || {}
    };
  } catch (err) {
    console.error('Error reading JSON DB fallback, using defaults', err);
  }
}

// Helper to verify bcrypt hash format
function isValidBcryptHash(hash: string): boolean {
  if (typeof hash !== 'string') return false;
  // Standard bcrypt string length is 60 chars starting with $2a$, $2b$, or $2y$
  const bcryptRegex = /^\$2[ayb]\$[0-9]{2}\$[A-Za-z0-9./]{53}$/;
  return bcryptRegex.test(hash);
}

// Function to save state to file
const saveLocalState = () => {
  try {
    fs.writeFileSync(JSON_DB_PATH, JSON.stringify(localState, null, 2));
  } catch (err) {
    console.error('Error saving JSON DB fallback', err);
  }
};

// PostgreSQL configuration setup
const { Pool } = pg;
let pgPool: pg.Pool | null = null;
let usePostgres = false;

const storageMode = (process.env.STORAGE_MODE || 'postgres').toLowerCase().trim();

if (storageMode !== 'postgres' && storageMode !== 'json') {
  const errMsg = `CRITICAL CONFIGURATION ERROR: Invalid STORAGE_MODE "${process.env.STORAGE_MODE}". Must be either "postgres" or "json".`;
  console.error(errMsg);
  throw new Error(errMsg);
}

const isDevFallbackAllowed = storageMode === 'json';
const hasPostgresConfig = !!(process.env.DB_HOST && process.env.DB_USER && process.env.DB_PASSWORD && process.env.DB_NAME);

if (storageMode === 'postgres') {
  if (!hasPostgresConfig) {
    const missingKeys = [];
    if (!process.env.DB_HOST) missingKeys.push('DB_HOST');
    if (!process.env.DB_USER) missingKeys.push('DB_USER');
    if (!process.env.DB_PASSWORD) missingKeys.push('DB_PASSWORD');
    if (!process.env.DB_NAME) missingKeys.push('DB_NAME');
    const msg = `CRITICAL CONFIGURATION ERROR: STORAGE_MODE is "postgres" but required PostgreSQL environment variables are missing [${missingKeys.join(', ')}].`;
    console.error(msg);
    throw new Error(msg);
  }

  try {
    pgPool = new Pool({
      host: process.env.DB_HOST,
      port: parseInt(process.env.DB_PORT || '5432', 10),
      user: process.env.DB_USER,
      password: process.env.DB_PASSWORD,
      database: process.env.DB_NAME,
      max: 10,
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 5000,
    });
    
    pgPool.on('error', (err) => {
      console.error('Unexpected error on idle PostgreSQL client:', err);
    });
    
    usePostgres = true;
    console.log('PostgreSQL configuration initialized successfully. Connection pool created.');
  } catch (err) {
    console.error('CRITICAL: Failed to create PostgreSQL connection pool:', err);
    throw err;
  }
} else {
  console.log('STORAGE_MODE explicitly configured to "json". Using local secure file-system persistence (data/db.json).');
}

// Database helper functions supporting both real Postgres and persistent JSON Fallback
export const db = {
  // Initialize Database tables if PostgreSQL is connected
  init: async () => {
    if (usePostgres && pgPool) {
      const maxRetries = 60;
      const initialDelayMs = 1000;
      const maxDelayMs = 10000;

      console.log(`[Database] Initializing PostgreSQL connection to ${process.env.DB_HOST}:${process.env.DB_PORT || '5432'}/${process.env.DB_NAME}...`);

      for (let attempt = 1; attempt <= maxRetries; attempt++) {
        let client: pg.PoolClient | null = null;
        try {
          console.log(`[Database] Connection attempt ${attempt}/${maxRetries} to PostgreSQL...`);
          client = await pgPool.connect();

          await client.query(`
            CREATE TABLE IF NOT EXISTS users (
              id SERIAL PRIMARY KEY,
              username VARCHAR(50) UNIQUE NOT NULL,
              password_hash VARCHAR(255) NOT NULL,
              role VARCHAR(20) DEFAULT 'user',
              created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );

            ALTER TABLE users DROP COLUMN IF EXISTS email;
            ALTER TABLE users ADD COLUMN IF NOT EXISTS status VARCHAR(20) DEFAULT 'enabled';
            ALTER TABLE users ADD COLUMN IF NOT EXISTS assigned_stream_id VARCHAR(50);
            ALTER TABLE users ADD COLUMN IF NOT EXISTS login_history TEXT;
            ALTER TABLE users ADD COLUMN IF NOT EXISTS display_name VARCHAR(100);

            CREATE TABLE IF NOT EXISTS streams (
              id VARCHAR(50) PRIMARY KEY,
              user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
              title VARCHAR(255) NOT NULL,
              broadcaster VARCHAR(100) NOT NULL,
              stream_key VARCHAR(100) UNIQUE NOT NULL,
              status VARCHAR(50) DEFAULT 'offline',
              scheduled_start TIMESTAMP,
              rtmp_url VARCHAR(255) NOT NULL,
              resolution VARCHAR(20) DEFAULT '1080p',
              bitrate INTEGER DEFAULT 4500,
              codec VARCHAR(20) DEFAULT 'H.264',
              ingest_ip VARCHAR(50) NOT NULL,
              viewers INTEGER DEFAULT 0,
              start_time TIMESTAMP
            );

            ALTER TABLE streams ADD COLUMN IF NOT EXISTS channel_id VARCHAR(100);
            ALTER TABLE streams ADD COLUMN IF NOT EXISTS width INTEGER;
            ALTER TABLE streams ADD COLUMN IF NOT EXISTS height INTEGER;
            ALTER TABLE streams ADD COLUMN IF NOT EXISTS fps INTEGER;
            ALTER TABLE streams ADD COLUMN IF NOT EXISTS aspect_ratio VARCHAR(50);
            ALTER TABLE streams ADD COLUMN IF NOT EXISTS video_codec VARCHAR(50);
            ALTER TABLE streams ADD COLUMN IF NOT EXISTS audio_codec VARCHAR(50);
            ALTER TABLE streams ADD COLUMN IF NOT EXISTS preset VARCHAR(50);
            ALTER TABLE streams ADD COLUMN IF NOT EXISTS profile VARCHAR(50);
            ALTER TABLE streams ADD COLUMN IF NOT EXISTS pixel_format VARCHAR(50);
            ALTER TABLE streams ADD COLUMN IF NOT EXISTS enabled_profiles VARCHAR(255);
            ALTER TABLE streams ADD COLUMN IF NOT EXISTS gop_size INTEGER;
            ALTER TABLE streams ADD COLUMN IF NOT EXISTS buffer_size INTEGER;
            ALTER TABLE streams ADD COLUMN IF NOT EXISTS max_bitrate INTEGER;
            ALTER TABLE streams ADD COLUMN IF NOT EXISTS scaling_algorithm VARCHAR(50);
            ALTER TABLE streams ADD COLUMN IF NOT EXISTS audio_enabled BOOLEAN DEFAULT TRUE;
            ALTER TABLE streams ADD COLUMN IF NOT EXISTS audio_bitrate VARCHAR(50);
            ALTER TABLE streams ADD COLUMN IF NOT EXISTS audio_sample_rate INTEGER;
            ALTER TABLE streams ADD COLUMN IF NOT EXISTS audio_channels VARCHAR(50);
            ALTER TABLE streams ADD COLUMN IF NOT EXISTS audio_volume INTEGER DEFAULT 100;
            ALTER TABLE streams ADD COLUMN IF NOT EXISTS audio_normalize BOOLEAN DEFAULT FALSE;
            ALTER TABLE streams ADD COLUMN IF NOT EXISTS audio_noise_reduction BOOLEAN DEFAULT FALSE;
            ALTER TABLE streams ADD COLUMN IF NOT EXISTS audio_delay INTEGER DEFAULT 0;
            ALTER TABLE streams ADD COLUMN IF NOT EXISTS audio_language VARCHAR(50);
            ALTER TABLE streams ADD COLUMN IF NOT EXISTS audio_track_selection VARCHAR(50);
            ALTER TABLE streams ADD COLUMN IF NOT EXISTS audio_passthrough BOOLEAN DEFAULT FALSE;
            ALTER TABLE streams ADD COLUMN IF NOT EXISTS audio_transcoding BOOLEAN DEFAULT TRUE;
            ALTER TABLE streams ADD COLUMN IF NOT EXISTS profiles_json TEXT;

            CREATE TABLE IF NOT EXISTS devices (
              id VARCHAR(50) PRIMARY KEY,
              name VARCHAR(100) NOT NULL,
              location VARCHAR(100),
              description VARCHAR(255),
              os_version VARCHAR(50),
              player_version VARCHAR(50),
              ip_address VARCHAR(50),
              mac_address VARCHAR(50),
              last_seen TIMESTAMP,
              online_status VARCHAR(50) DEFAULT 'offline',
              current_stream_id VARCHAR(50),
              current_stream_url VARCHAR(255),
              current_resolution VARCHAR(50),
              current_volume INTEGER DEFAULT 100,
              current_playback_status VARCHAR(50),
              pairing_code VARCHAR(20),
              paired BOOLEAN DEFAULT FALSE,
              token VARCHAR(255),
              cpu_usage DOUBLE PRECISION,
              ram_usage DOUBLE PRECISION,
              temperature DOUBLE PRECISION,
              network_speed VARCHAR(50),
              screenshot_url VARCHAR(255),
              screenshot_time TIMESTAMP,
              brightness INTEGER DEFAULT 100,
              rotation VARCHAR(20) DEFAULT '0',
              player_settings TEXT,
              network_settings TEXT,
              client_version VARCHAR(50) DEFAULT '1.0.0'
            );

            ALTER TABLE devices ADD COLUMN IF NOT EXISTS brightness INTEGER DEFAULT 100;
            ALTER TABLE devices ADD COLUMN IF NOT EXISTS rotation VARCHAR(20) DEFAULT '0';
            ALTER TABLE devices ADD COLUMN IF NOT EXISTS player_settings TEXT;
            ALTER TABLE devices ADD COLUMN IF NOT EXISTS network_settings TEXT;
            ALTER TABLE devices ADD COLUMN IF NOT EXISTS client_version VARCHAR(50) DEFAULT '1.0.0';

            CREATE TABLE IF NOT EXISTS device_groups (
              id VARCHAR(50) PRIMARY KEY,
              name VARCHAR(100) NOT NULL,
              description VARCHAR(255)
            );

            CREATE TABLE IF NOT EXISTS device_group_members (
              group_id VARCHAR(50) REFERENCES device_groups(id) ON DELETE CASCADE,
              device_id VARCHAR(50) REFERENCES devices(id) ON DELETE CASCADE,
              PRIMARY KEY (group_id, device_id)
            );

            CREATE TABLE IF NOT EXISTS playback_history (
              id VARCHAR(50) PRIMARY KEY,
              device_id VARCHAR(50) REFERENCES devices(id) ON DELETE CASCADE,
              stream_id VARCHAR(50),
              stream_url VARCHAR(255),
              action VARCHAR(50),
              timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );

            CREATE TABLE IF NOT EXISTS device_logs (
              id VARCHAR(50) PRIMARY KEY,
              device_id VARCHAR(50) REFERENCES devices(id) ON DELETE CASCADE,
              level VARCHAR(20) DEFAULT 'info',
              message TEXT NOT NULL,
              timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );

            CREATE TABLE IF NOT EXISTS device_schedules (
              id VARCHAR(50) PRIMARY KEY,
              device_id VARCHAR(50) REFERENCES devices(id) ON DELETE CASCADE,
              group_id VARCHAR(50) REFERENCES device_groups(id) ON DELETE CASCADE,
              time VARCHAR(10) NOT NULL,
              action VARCHAR(20) NOT NULL,
              stream_id VARCHAR(50),
              stream_url VARCHAR(255),
              enabled BOOLEAN DEFAULT TRUE
            );

            CREATE TABLE IF NOT EXISTS app_settings (
              key VARCHAR(100) PRIMARY KEY,
              value TEXT NOT NULL,
              updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );

            CREATE TABLE IF NOT EXISTS audit_logs (
              id VARCHAR(50) PRIMARY KEY,
              timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
              username VARCHAR(100) NOT NULL,
              user_role VARCHAR(50) NOT NULL,
              action VARCHAR(100) NOT NULL,
              module VARCHAR(100) NOT NULL,
              ip_address VARCHAR(50) DEFAULT '0.0.0.0',
              user_agent TEXT,
              result VARCHAR(20) NOT NULL,
              details TEXT
            );

            CREATE INDEX IF NOT EXISTS idx_audit_logs_timestamp ON audit_logs(timestamp DESC);
            CREATE INDEX IF NOT EXISTS idx_audit_logs_username ON audit_logs(username);
            CREATE INDEX IF NOT EXISTS idx_audit_logs_module ON audit_logs(module);
            CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON audit_logs(action);
            CREATE INDEX IF NOT EXISTS idx_audit_logs_result ON audit_logs(result);
          `);

          console.log('[Database] PostgreSQL Database tables verified/created successfully.');
          client.release();
          client = null;
          break; // Connected and migrated successfully
        } catch (err: any) {
          if (client) {
            try { client.release(); } catch (_) {}
            client = null;
          }

          const remaining = maxRetries - attempt;
          const errCode = err.code || 'UNKNOWN';
          const errMsg = err.message || String(err);

          if (attempt === maxRetries) {
            console.error(`[Database] CRITICAL: Exhausted all ${maxRetries} connection/migration attempts. Last error [${errCode}]: ${errMsg}`);
            if (!isDevFallbackAllowed) {
              console.error('[Database] Database connection and migration failures in "postgres" storage mode are fatal. Aborting startup.');
              throw err;
            } else {
              console.log('[Database] Switching to local secure file-system persistence (data/db.json) as allowed by storage mode.');
              usePostgres = false;
            }
          } else {
            const delay = Math.min(Math.round(initialDelayMs * Math.pow(1.25, attempt - 1)), maxDelayMs);
            console.warn(`[Database] Connection attempt ${attempt}/${maxRetries} failed [Code: ${errCode}]: ${errMsg}. Retrying in ${delay}ms... (${remaining} attempts remaining)`);
            await new Promise((resolve) => setTimeout(resolve, delay));
          }
        }
      }
    } else {
      if (!isDevFallbackAllowed) {
        const msg = 'CRITICAL: PostgreSQL pool is not active, but STORAGE_MODE is not "json". Failing startup.';
        console.error(msg);
        throw new Error(msg);
      }
      console.log('PostgreSQL is disabled; using local JSON fallback database as explicitly configured.');
    }

    // --- Unified Administrator Authentication Audit & Verification ---
    const adminUsername = process.env.ADMIN_USERNAME || 'admin';
    const adminPassword = process.env.ADMIN_PASSWORD || 'admin123';
    const resetRequested = process.env.ADMIN_PASSWORD_RESET === 'true';
    const oldHardcodedHash = '$2a$10$Xm3C0H5gLqGz7uB7wF8pZeGbyhS6F1mP689S5fV/M4V8L5Yn4O7yW';

    // Log authentication storage mode
    console.log(`Authentication storage mode: ${usePostgres ? 'PostgreSQL' : 'JSON'}`);

    if (usePostgres && pgPool) {
      try {
        const client = await pgPool.connect();
        try {
          // Look for existing admin users
          const adminCheck = await client.query("SELECT * FROM users WHERE role = 'admin'");
          const existingAdminByUsernameRes = await client.query("SELECT * FROM users WHERE username = $1", [adminUsername]);
          const existingAdminByUsername = existingAdminByUsernameRes.rows[0] || null;

          let targetAdmin = existingAdminByUsername;
          if (!targetAdmin && adminCheck.rows.length > 0) {
            targetAdmin = adminCheck.rows[0];
          }

          if (!targetAdmin) {
            // No administrator exists in PostgreSQL - create default admin
            const salt = await bcrypt.genSalt(10);
            const passwordHash = await bcrypt.hash(adminPassword, salt);
            await client.query(`
              INSERT INTO users (username, password_hash, role, status, display_name)
              VALUES ($1, $2, 'admin', 'enabled', $3)
            `, [adminUsername, passwordHash, adminUsername]);
            console.log(`Default admin created.`);
          } else {
            // An administrator exists - verify the password hash
            const currentHash = targetAdmin.password_hash;
            const isCorrupted = !isValidBcryptHash(currentHash);
            let matchesPassword = false;
            if (!isCorrupted && currentHash) {
              try {
                matchesPassword = await bcrypt.compare(adminPassword, currentHash);
              } catch (_) {
                matchesPassword = false;
              }
            }

            if (isCorrupted) {
              console.warn(`Corrupted password hash detected for admin user "${targetAdmin.username}". Auto-repairing hash...`);
            }

            if (resetRequested || isCorrupted || currentHash === oldHardcodedHash || (!matchesPassword && targetAdmin.username.toLowerCase() === 'admin' && !process.env.ADMIN_PASSWORD)) {
              const salt = await bcrypt.genSalt(10);
              const passwordHash = await bcrypt.hash(adminPassword, salt);
              await client.query("UPDATE users SET password_hash = $1 WHERE id = $2", [passwordHash, targetAdmin.id]);
              if (resetRequested) {
                console.log(`Admin password reset completed.`);
              } else {
                console.log(`Admin password repair/sync completed.`);
              }
            } else {
              console.log(`Existing admin detected.`);
            }
          }
        } finally {
          client.release();
        }
      } catch (err) {
        console.error('Error during PostgreSQL authentication audit:', err);
      }
    } else {
      // JSON storage mode audit & verification - clean up any residual email fields
      localState.users.forEach((u: any) => { delete u.email; });

      const existingAdminByUsername = localState.users.find(u => (u.username || '').toLowerCase() === adminUsername.toLowerCase());
      const existingAdminByRole = localState.users.find(u => u.role === 'admin');

      let targetAdmin = existingAdminByUsername;
      if (!targetAdmin && existingAdminByRole) {
        targetAdmin = existingAdminByRole;
      }

      if (!targetAdmin) {
        // No administrator exists in JSON - create default admin
        const salt = bcrypt.genSaltSync(10);
        const passwordHash = bcrypt.hashSync(adminPassword, salt);
        localState.users.push({
          id: localState.users.length > 0 ? Math.max(0, ...localState.users.map(u => Number(u.id) || 0)) + 1 : 1,
          username: adminUsername,
          password_hash: passwordHash,
          role: 'admin',
          created_at: new Date().toISOString(),
          status: 'enabled',
          display_name: adminUsername
        });
        saveLocalState();
        console.log(`Default admin created.`);
      } else {
        // An administrator exists - verify the password hash
        const currentHash = targetAdmin.password_hash;
        const isCorrupted = !isValidBcryptHash(currentHash);
        let matchesPassword = false;
        if (!isCorrupted && currentHash) {
          try {
            matchesPassword = bcrypt.compareSync(adminPassword, currentHash);
          } catch (_) {
            matchesPassword = false;
          }
        }

        if (isCorrupted) {
          console.warn(`Corrupted password hash detected for admin user "${targetAdmin.username}". Auto-repairing hash...`);
        }

        if (resetRequested || isCorrupted || currentHash === oldHardcodedHash || (!matchesPassword && targetAdmin.username.toLowerCase() === 'admin' && !process.env.ADMIN_PASSWORD)) {
          const salt = bcrypt.genSaltSync(10);
          const passwordHash = bcrypt.hashSync(adminPassword, salt);
          targetAdmin.password_hash = passwordHash;
          saveLocalState();
          if (resetRequested) {
            console.log(`Admin password reset completed.`);
          } else {
            console.log(`Admin password repair/sync completed.`);
          }
        } else {
          console.log(`Existing admin detected.`);
        }
      }
    }

    console.log('Login validation initialized.');
  },

  // USERS
  getUserByUsername: async (username: string): Promise<UserRecord | null> => {
    if (!username) return null;
    const clean = username.trim().toLowerCase();
    if (usePostgres && pgPool) {
      const res = await pgPool.query(
        'SELECT * FROM users WHERE LOWER(TRIM(username)) = $1',
        [clean]
      );
      if (res.rows.length === 0) return null;
      const r = res.rows[0];
      return {
        id: r.id,
        username: r.username,
        password_hash: r.password_hash,
        role: r.role,
        created_at: r.created_at instanceof Date ? r.created_at.toISOString() : String(r.created_at || new Date().toISOString()),
        status: r.status || 'enabled',
        assigned_stream_id: r.assigned_stream_id || null,
        login_history: r.login_history || null,
        display_name: r.display_name || null
      };
    }
    const user = localState.users.find(
      u => (u.username ? u.username.trim().toLowerCase() : '') === clean
    );
    return user || null;
  },

  getUserById: async (id: number | string): Promise<UserRecord | null> => {
    const numericId = typeof id === 'number' ? id : parseInt(id as any, 10);
    if (isNaN(numericId)) return null;
    if (usePostgres && pgPool) {
      const res = await pgPool.query('SELECT * FROM users WHERE id = $1', [numericId]);
      if (res.rows.length === 0) return null;
      const r = res.rows[0];
      return {
        id: r.id,
        username: r.username,
        password_hash: r.password_hash,
        role: r.role,
        created_at: r.created_at instanceof Date ? r.created_at.toISOString() : String(r.created_at || new Date().toISOString()),
        status: r.status || 'enabled',
        assigned_stream_id: r.assigned_stream_id || null,
        login_history: r.login_history || null,
        display_name: r.display_name || null
      };
    }
    return localState.users.find(u => Number(u.id) === numericId) || null;
  },

  getUsers: async (): Promise<UserRecord[]> => {
    if (usePostgres && pgPool) {
      const res = await pgPool.query('SELECT * FROM users ORDER BY id ASC');
      return res.rows.map(r => ({
        id: r.id,
        username: r.username,
        password_hash: r.password_hash,
        role: r.role,
        created_at: r.created_at instanceof Date ? r.created_at.toISOString() : String(r.created_at || new Date().toISOString()),
        status: r.status || 'enabled',
        assigned_stream_id: r.assigned_stream_id || null,
        login_history: r.login_history || null,
        display_name: r.display_name || null
      }));
    }
    return localState.users;
  },

  createUser: async (
    username: string,
    passwordHash: string,
    role: 'admin' | 'user' = 'user',
    assignedStreamId: string | null = null,
    displayName: string | null = null
  ): Promise<UserRecord> => {
    const cleanUsername = username.trim();
    const finalDisplayName = displayName && displayName.trim() ? displayName.trim() : cleanUsername;

    if (usePostgres && pgPool) {
      const res = await pgPool.query(
        'INSERT INTO users (username, password_hash, role, status, assigned_stream_id, login_history, display_name) VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *',
        [cleanUsername, passwordHash, role, 'enabled', assignedStreamId, null, finalDisplayName]
      );
      const r = res.rows[0];
      return {
        id: r.id,
        username: r.username,
        password_hash: r.password_hash,
        role: r.role,
        created_at: r.created_at instanceof Date ? r.created_at.toISOString() : String(r.created_at || new Date().toISOString()),
        status: r.status || 'enabled',
        assigned_stream_id: r.assigned_stream_id || null,
        login_history: r.login_history || null,
        display_name: r.display_name || null
      };
    }
    const newUser: UserRecord = {
      id: localState.users.length > 0 ? Math.max(0, ...localState.users.map(u => Number(u.id) || 0)) + 1 : 1,
      username: cleanUsername,
      password_hash: passwordHash,
      role,
      created_at: new Date().toISOString(),
      status: 'enabled',
      assigned_stream_id: assignedStreamId,
      login_history: null,
      display_name: finalDisplayName
    };
    localState.users.push(newUser);
    saveLocalState();
    return newUser;
  },

  updateUser: async (id: number | string, updates: Partial<UserRecord>): Promise<UserRecord | null> => {
    const numericId = typeof id === 'number' ? id : parseInt(id as any, 10);
    if (isNaN(numericId)) return null;
    if (usePostgres && pgPool) {
      const keys = Object.keys(updates);
      if (keys.length === 0) return await db.getUserById(numericId);

      const setClause = keys.map((key, index) => {
        const pgKey = key === 'password_hash' ? 'password_hash' :
                      key === 'assigned_stream_id' ? 'assigned_stream_id' :
                      key === 'login_history' ? 'login_history' : 
                      key === 'display_name' ? 'display_name' : key;
        return `${pgKey} = $${index + 2}`;
      }).join(', ');

      const vals = keys.map(k => (updates as any)[k]);
      await pgPool.query(`UPDATE users SET ${setClause} WHERE id = $1`, [numericId, ...vals]);
      return await db.getUserById(numericId);
    }

    const index = localState.users.findIndex(u => Number(u.id) === numericId);
    if (index === -1) return null;
    localState.users[index] = { ...localState.users[index], ...updates };
    saveLocalState();
    return localState.users[index];
  },

  deleteUser: async (id: number | string): Promise<boolean> => {
    const numericId = typeof id === 'number' ? id : parseInt(id as any, 10);
    if (usePostgres && pgPool) {
      // Safely remove user-channel assignments in streams before deletion
      await pgPool.query('UPDATE streams SET user_id = NULL WHERE user_id = $1', [numericId]);
      const res = await pgPool.query('DELETE FROM users WHERE id = $1', [numericId]);
      return (res.rowCount ?? 0) > 0;
    }
    // Set userId = 0 on associated localState streams to preserve them safely
    if (localState.streams) {
      localState.streams = localState.streams.map(s => Number(s.userId) === numericId ? { ...s, userId: 0 } : s);
    }
    const lenBefore = localState.users.length;
    localState.users = localState.users.filter(u => Number(u.id) !== numericId);
    if (localState.users.length !== lenBefore) {
      saveLocalState();
      return true;
    }
    return false;
  },

  recordUserLogin: async (userId: number, ip: string): Promise<void> => {
    const timestamp = new Date().toISOString();
    const loginRecord = { timestamp, ip };

    let currentHistoryRaw: string | null = null;
    if (usePostgres && pgPool) {
      const res = await pgPool.query('SELECT login_history FROM users WHERE id = $1', [userId]);
      if (res.rows.length > 0) {
        currentHistoryRaw = res.rows[0].login_history;
      }
    } else {
      const user = localState.users.find(u => u.id === userId);
      if (user) {
        currentHistoryRaw = user.login_history || null;
      }
    }

    let historyList: any[] = [];
    if (currentHistoryRaw) {
      try {
        historyList = JSON.parse(currentHistoryRaw);
        if (!Array.isArray(historyList)) {
          historyList = [];
        }
      } catch (e) {
        historyList = [];
      }
    }
    historyList.unshift(loginRecord);
    if (historyList.length > 50) {
      historyList = historyList.slice(0, 50);
    }

    const updatedHistoryRaw = JSON.stringify(historyList);
    if (usePostgres && pgPool) {
      await pgPool.query('UPDATE users SET login_history = $1 WHERE id = $2', [updatedHistoryRaw, userId]);
    } else {
      const index = localState.users.findIndex(u => u.id === userId);
      if (index !== -1) {
        localState.users[index].login_history = updatedHistoryRaw;
        saveLocalState();
      }
    }
  },

  // STREAMS
  getStreams: async (): Promise<StreamRecord[]> => {
    if (usePostgres && pgPool) {
      const res = await pgPool.query('SELECT * FROM streams ORDER BY start_time DESC, id DESC');
      return res.rows.map(r => ({
        id: r.id,
        userId: r.user_id,
        channelId: r.channel_id || r.id,
        title: r.title,
        broadcaster: r.broadcaster,
        streamKey: r.stream_key,
        status: r.status,
        scheduledStart: r.scheduled_start ? r.scheduled_start.toISOString() : undefined,
        rtmpUrl: r.rtmp_url,
        resolution: r.resolution,
        bitrate: r.bitrate,
        codec: r.codec,
        ingestIp: r.ingest_ip,
        viewers: r.viewers,
        startTime: r.start_time ? r.start_time.toISOString() : undefined,
        width: r.width,
        height: r.height,
        fps: r.fps,
        aspectRatio: r.aspect_ratio,
        videoCodec: r.video_codec,
        audioCodec: r.audio_codec,
        preset: r.preset,
        profile: r.profile,
        pixelFormat: r.pixel_format,
        enabledProfiles: r.enabled_profiles,
        gopSize: r.gop_size,
        bufferSize: r.buffer_size,
        maxBitrate: r.max_bitrate,
        scalingAlgorithm: r.scaling_algorithm,
        audioEnabled: r.audio_enabled,
        audioBitrate: r.audio_bitrate,
        audioSampleRate: r.audio_sample_rate,
        audioChannels: r.audio_channels,
        audioVolume: r.audio_volume,
        audioNormalize: r.audio_normalize,
        audioNoiseReduction: r.audio_noise_reduction,
        audioDelay: r.audio_delay,
        audioLanguage: r.audio_language,
        audioTrackSelection: r.audio_track_selection,
        audioPassthrough: r.audio_passthrough,
        audioTranscoding: r.audio_transcoding,
        profilesJson: r.profiles_json
      }));
    }
    return localState.streams;
  },

  getStreamByKey: async (streamKey: string): Promise<StreamRecord | null> => {
    if (usePostgres && pgPool) {
      const res = await pgPool.query('SELECT * FROM streams WHERE stream_key = $1', [streamKey]);
      if (res.rows.length === 0) return null;
      const r = res.rows[0];
      return {
        id: r.id,
        userId: r.user_id,
        channelId: r.channel_id || r.id,
        title: r.title,
        broadcaster: r.broadcaster,
        streamKey: r.stream_key,
        status: r.status,
        scheduledStart: r.scheduled_start ? r.scheduled_start.toISOString() : undefined,
        rtmpUrl: r.rtmp_url,
        resolution: r.resolution,
        bitrate: r.bitrate,
        codec: r.codec,
        ingestIp: r.ingest_ip,
        viewers: r.viewers,
        startTime: r.start_time ? r.start_time.toISOString() : undefined,
        width: r.width,
        height: r.height,
        fps: r.fps,
        aspectRatio: r.aspect_ratio,
        videoCodec: r.video_codec,
        audioCodec: r.audio_codec,
        preset: r.preset,
        profile: r.profile,
        pixelFormat: r.pixel_format,
        enabledProfiles: r.enabled_profiles,
        gopSize: r.gop_size,
        bufferSize: r.buffer_size,
        maxBitrate: r.max_bitrate,
        scalingAlgorithm: r.scaling_algorithm,
        audioEnabled: r.audio_enabled,
        audioBitrate: r.audio_bitrate,
        audioSampleRate: r.audio_sample_rate,
        audioChannels: r.audio_channels,
        audioVolume: r.audio_volume,
        audioNormalize: r.audio_normalize,
        audioNoiseReduction: r.audio_noise_reduction,
        audioDelay: r.audio_delay,
        audioLanguage: r.audio_language,
        audioTrackSelection: r.audio_track_selection,
        audioPassthrough: r.audio_passthrough,
        audioTranscoding: r.audio_transcoding,
        profilesJson: r.profiles_json
      };
    }
    return localState.streams.find(s => s.streamKey === streamKey) || null;
  },

  getStreamByChannel: async (channelIdentifier: string): Promise<StreamRecord | null> => {
    if (!channelIdentifier) return null;
    const cleanId = channelIdentifier.trim().toLowerCase();
    if (usePostgres && pgPool) {
      const res = await pgPool.query(
        'SELECT * FROM streams WHERE LOWER(channel_id) = $1 OR id = $2 OR stream_key = $2 OR LOWER(title) = $1 LIMIT 1',
        [cleanId, channelIdentifier]
      );
      if (res.rows.length === 0) return null;
      const r = res.rows[0];
      return {
        id: r.id,
        userId: r.user_id,
        channelId: r.channel_id || r.id,
        title: r.title,
        broadcaster: r.broadcaster,
        streamKey: r.stream_key,
        status: r.status,
        scheduledStart: r.scheduled_start ? r.scheduled_start.toISOString() : undefined,
        rtmpUrl: r.rtmp_url,
        resolution: r.resolution,
        bitrate: r.bitrate,
        codec: r.codec,
        ingestIp: r.ingest_ip,
        viewers: r.viewers,
        startTime: r.start_time ? r.start_time.toISOString() : undefined,
        width: r.width,
        height: r.height,
        fps: r.fps,
        aspectRatio: r.aspect_ratio,
        videoCodec: r.video_codec,
        audioCodec: r.audio_codec,
        preset: r.preset,
        profile: r.profile,
        pixelFormat: r.pixel_format,
        enabledProfiles: r.enabled_profiles,
        gopSize: r.gop_size,
        bufferSize: r.buffer_size,
        maxBitrate: r.max_bitrate,
        scalingAlgorithm: r.scaling_algorithm,
        audioEnabled: r.audio_enabled,
        audioBitrate: r.audio_bitrate,
        audioSampleRate: r.audio_sample_rate,
        audioChannels: r.audio_channels,
        audioVolume: r.audio_volume,
        audioNormalize: r.audio_normalize,
        audioNoiseReduction: r.audio_noise_reduction,
        audioDelay: r.audio_delay,
        audioLanguage: r.audio_language,
        audioTrackSelection: r.audio_track_selection,
        audioPassthrough: r.audio_passthrough,
        audioTranscoding: r.audio_transcoding,
        profilesJson: r.profiles_json
      };
    }
    return localState.streams.find(s => 
      (s.channelId && s.channelId.toLowerCase() === cleanId) || 
      s.id === channelIdentifier || 
      s.streamKey === channelIdentifier ||
      (s.title && s.title.toLowerCase() === cleanId)
    ) || null;
  },

  createStream: async (stream: Omit<StreamRecord, 'id' | 'viewers'>): Promise<StreamRecord> => {
    const id = Math.random().toString(36).substring(2, 11);
    
    const dbStream = {
      ...stream,
      rtmpUrl: stream.rtmpUrl || 'rtmp://localhost/ingest',
      ingestIp: stream.ingestIp || '127.0.0.1'
    };

    if (usePostgres && pgPool) {
      await pgPool.query(
        `INSERT INTO streams 
         (id, user_id, channel_id, title, broadcaster, stream_key, status, scheduled_start, rtmp_url, resolution, bitrate, codec, ingest_ip, viewers, start_time, width, height, fps, aspect_ratio, video_codec, audio_codec, preset, profile, pixel_format, enabled_profiles) 
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, $22, $23, $24, $25)`,
        [
          id,
          dbStream.userId,
          dbStream.channelId ?? null,
          dbStream.title,
          dbStream.broadcaster,
          dbStream.streamKey,
          dbStream.status,
          dbStream.scheduledStart ? new Date(dbStream.scheduledStart) : null,
          dbStream.rtmpUrl,
          dbStream.resolution,
          dbStream.bitrate,
          dbStream.codec,
          dbStream.ingestIp,
          0,
          dbStream.startTime ? new Date(dbStream.startTime) : null,
          dbStream.width ?? null,
          dbStream.height ?? null,
          dbStream.fps ?? null,
          dbStream.aspectRatio ?? null,
          dbStream.videoCodec ?? null,
          dbStream.audioCodec ?? null,
          dbStream.preset ?? null,
          dbStream.profile ?? null,
          dbStream.pixelFormat ?? null,
          dbStream.enabledProfiles ?? null
        ]
      );
      return { ...dbStream, id, viewers: 0 };
    }
    const newStream: StreamRecord = { ...dbStream, id, viewers: 0 };
    localState.streams.unshift(newStream);
    saveLocalState();
    return newStream;
  },

  updateStream: async (id: string, updates: Partial<StreamRecord>): Promise<StreamRecord | null> => {
    const dbUpdates = { ...updates };

    if (usePostgres && pgPool) {
      // Formulate dynamic SQL query
      const keys = Object.keys(dbUpdates);
      if (keys.length === 0) return null;
      
      const setClause = keys.map((key, index) => {
        const pgKey = key === 'userId' ? 'user_id' :
                      key === 'channelId' ? 'channel_id' :
                      key === 'streamKey' ? 'stream_key' :
                      key === 'scheduledStart' ? 'scheduled_start' :
                      key === 'rtmpUrl' ? 'rtmp_url' :
                      key === 'ingestIp' ? 'ingest_ip' :
                      key === 'startTime' ? 'start_time' : key.replace(/([A-Z])/g, "_$1").toLowerCase();
        return `${pgKey} = $${index + 2}`;
      }).join(', ');

      const vals = keys.map(k => {
        const val = (dbUpdates as any)[k];
        if (k === 'startTime' || k === 'scheduledStart') {
          return val ? new Date(val) : null;
        }
        return val;
      });

      await pgPool.query(`UPDATE streams SET ${setClause} WHERE id = $1`, [id, ...vals]);
      const res = await pgPool.query('SELECT * FROM streams WHERE id = $1', [id]);
      if (res.rows.length === 0) return null;
      const r = res.rows[0];
      return {
        id: r.id,
        userId: r.user_id,
        channelId: r.channel_id || r.id,
        title: r.title,
        broadcaster: r.broadcaster,
        streamKey: r.stream_key,
        status: r.status,
        scheduledStart: r.scheduled_start ? r.scheduled_start.toISOString() : undefined,
        rtmpUrl: r.rtmp_url,
        resolution: r.resolution,
        bitrate: r.bitrate,
        codec: r.codec,
        ingestIp: r.ingest_ip,
        viewers: r.viewers,
        startTime: r.start_time ? r.start_time.toISOString() : undefined,
        width: r.width,
        height: r.height,
        fps: r.fps,
        aspectRatio: r.aspect_ratio,
        videoCodec: r.video_codec,
        audioCodec: r.audio_codec,
        preset: r.preset,
        profile: r.profile,
        pixelFormat: r.pixel_format,
        enabledProfiles: r.enabled_profiles,
        gopSize: r.gop_size,
        bufferSize: r.buffer_size,
        maxBitrate: r.max_bitrate,
        scalingAlgorithm: r.scaling_algorithm,
        audioEnabled: r.audio_enabled,
        audioBitrate: r.audio_bitrate,
        audioSampleRate: r.audio_sample_rate,
        audioChannels: r.audio_channels,
        audioVolume: r.audio_volume,
        audioNormalize: r.audio_normalize,
        audioNoiseReduction: r.audio_noise_reduction,
        audioDelay: r.audio_delay,
        audioLanguage: r.audio_language,
        audioTrackSelection: r.audio_track_selection,
        audioPassthrough: r.audio_passthrough,
        audioTranscoding: r.audio_transcoding,
        profilesJson: r.profiles_json
      };
    }

    const index = localState.streams.findIndex(s => s.id === id);
    if (index === -1) return null;
    localState.streams[index] = { ...localState.streams[index], ...dbUpdates };
    saveLocalState();
    return localState.streams[index];
  },

  deleteStream: async (id: string): Promise<boolean> => {
    if (usePostgres && pgPool) {
      const res = await pgPool.query('DELETE FROM streams WHERE id = $1', [id]);
      return (res.rowCount ?? 0) > 0;
    }
    const initialLen = localState.streams.length;
    localState.streams = localState.streams.filter(s => s.id !== id);
    if (localState.streams.length !== initialLen) {
      saveLocalState();
      return true;
    }
    return false;
  },

  // --- DEVICES ---
  getDevices: async (): Promise<DeviceRecord[]> => {
    if (usePostgres && pgPool) {
      const res = await pgPool.query('SELECT * FROM devices ORDER BY name ASC');
      return res.rows.map(r => ({
        id: r.id,
        name: r.name,
        location: r.location,
        description: r.description,
        os_version: r.os_version,
        player_version: r.player_version,
        ip_address: r.ip_address,
        mac_address: r.mac_address,
        last_seen: r.last_seen ? r.last_seen.toISOString() : undefined,
        online_status: r.online_status,
        current_stream_id: r.current_stream_id,
        current_stream_url: r.current_stream_url,
        current_resolution: r.current_resolution,
        current_volume: r.current_volume,
        current_playback_status: r.current_playback_status,
        pairing_code: r.pairing_code,
        paired: r.paired,
        token: r.token,
        cpu_usage: r.cpu_usage,
        ram_usage: r.ram_usage,
        temperature: r.temperature,
        network_speed: r.network_speed,
        screenshot_url: r.screenshot_url,
        screenshot_time: r.screenshot_time ? r.screenshot_time.toISOString() : undefined,
        brightness: r.brightness,
        rotation: r.rotation,
        player_settings: r.player_settings,
        network_settings: r.network_settings,
        client_version: r.client_version
      }));
    }
    return localState.devices;
  },

  getDevice: async (id: string): Promise<DeviceRecord | null> => {
    if (usePostgres && pgPool) {
      const res = await pgPool.query('SELECT * FROM devices WHERE id = $1', [id]);
      if (res.rows.length === 0) return null;
      const r = res.rows[0];
      return {
        id: r.id,
        name: r.name,
        location: r.location,
        description: r.description,
        os_version: r.os_version,
        player_version: r.player_version,
        ip_address: r.ip_address,
        mac_address: r.mac_address,
        last_seen: r.last_seen ? r.last_seen.toISOString() : undefined,
        online_status: r.online_status,
        current_stream_id: r.current_stream_id,
        current_stream_url: r.current_stream_url,
        current_resolution: r.current_resolution,
        current_volume: r.current_volume,
        current_playback_status: r.current_playback_status,
        pairing_code: r.pairing_code,
        paired: r.paired,
        token: r.token,
        cpu_usage: r.cpu_usage,
        ram_usage: r.ram_usage,
        temperature: r.temperature,
        network_speed: r.network_speed,
        screenshot_url: r.screenshot_url,
        screenshot_time: r.screenshot_time ? r.screenshot_time.toISOString() : undefined,
        brightness: r.brightness,
        rotation: r.rotation,
        player_settings: r.player_settings,
        network_settings: r.network_settings,
        client_version: r.client_version
      };
    }
    return localState.devices.find(d => d.id === id) || null;
  },

  getDeviceByPairingCode: async (code: string): Promise<DeviceRecord | null> => {
    if (usePostgres && pgPool) {
      const res = await pgPool.query('SELECT * FROM devices WHERE pairing_code = $1', [code]);
      if (res.rows.length === 0) return null;
      const r = res.rows[0];
      return {
        id: r.id,
        name: r.name,
        location: r.location,
        description: r.description,
        os_version: r.os_version,
        player_version: r.player_version,
        ip_address: r.ip_address,
        mac_address: r.mac_address,
        last_seen: r.last_seen ? r.last_seen.toISOString() : undefined,
        online_status: r.online_status,
        current_stream_id: r.current_stream_id,
        current_stream_url: r.current_stream_url,
        current_resolution: r.current_resolution,
        current_volume: r.current_volume,
        current_playback_status: r.current_playback_status,
        pairing_code: r.pairing_code,
        paired: r.paired,
        token: r.token,
        cpu_usage: r.cpu_usage,
        ram_usage: r.ram_usage,
        temperature: r.temperature,
        network_speed: r.network_speed,
        screenshot_url: r.screenshot_url,
        screenshot_time: r.screenshot_time ? r.screenshot_time.toISOString() : undefined,
        brightness: r.brightness,
        rotation: r.rotation,
        player_settings: r.player_settings,
        network_settings: r.network_settings,
        client_version: r.client_version
      };
    }
    return localState.devices.find(d => d.pairing_code === code) || null;
  },

  getDeviceByToken: async (token: string): Promise<DeviceRecord | null> => {
    if (usePostgres && pgPool) {
      const res = await pgPool.query('SELECT * FROM devices WHERE token = $1', [token]);
      if (res.rows.length === 0) return null;
      const r = res.rows[0];
      return {
        id: r.id,
        name: r.name,
        location: r.location,
        description: r.description,
        os_version: r.os_version,
        player_version: r.player_version,
        ip_address: r.ip_address,
        mac_address: r.mac_address,
        last_seen: r.last_seen ? r.last_seen.toISOString() : undefined,
        online_status: r.online_status,
        current_stream_id: r.current_stream_id,
        current_stream_url: r.current_stream_url,
        current_resolution: r.current_resolution,
        current_volume: r.current_volume,
        current_playback_status: r.current_playback_status,
        pairing_code: r.pairing_code,
        paired: r.paired,
        token: r.token,
        cpu_usage: r.cpu_usage,
        ram_usage: r.ram_usage,
        temperature: r.temperature,
        network_speed: r.network_speed,
        screenshot_url: r.screenshot_url,
        screenshot_time: r.screenshot_time ? r.screenshot_time.toISOString() : undefined,
        brightness: r.brightness,
        rotation: r.rotation,
        player_settings: r.player_settings,
        network_settings: r.network_settings,
        client_version: r.client_version
      };
    }
    return localState.devices.find(d => d.token === token) || null;
  },

   createDevice: async (device: Omit<DeviceRecord, 'id'>): Promise<DeviceRecord> => {
    const id = 'device_' + Math.random().toString(36).substring(2, 11);
    if (usePostgres && pgPool) {
      await pgPool.query(
        `INSERT INTO devices 
         (id, name, location, description, os_version, player_version, ip_address, mac_address, last_seen, online_status, current_stream_id, current_stream_url, current_resolution, current_volume, current_playback_status, pairing_code, paired, token, cpu_usage, ram_usage, temperature, network_speed, screenshot_url, screenshot_time, brightness, rotation, player_settings, network_settings, client_version) 
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, $22, $23, $24, $25, $26, $27, $28, $29)`,
        [
          id,
          device.name,
          device.location || null,
          device.description || null,
          device.os_version || null,
          device.player_version || null,
          device.ip_address || null,
          device.mac_address || null,
          device.last_seen ? new Date(device.last_seen) : null,
          device.online_status,
          device.current_stream_id || null,
          device.current_stream_url || null,
          device.current_resolution || null,
          device.current_volume,
          device.current_playback_status || null,
          device.pairing_code || null,
          device.paired,
          device.token || null,
          device.cpu_usage || null,
          device.ram_usage || null,
          device.temperature || null,
          device.network_speed || null,
          device.screenshot_url || null,
          device.screenshot_time ? new Date(device.screenshot_time) : null,
          device.brightness ?? 100,
          device.rotation ?? '0',
          device.player_settings || null,
          device.network_settings || null,
          device.client_version || '1.0.0'
        ]
      );
      return { ...device, id };
    }
    const newDevice: DeviceRecord = { ...device, id };
    localState.devices.push(newDevice);
    saveLocalState();
    return newDevice;
  },

  updateDevice: async (id: string, updates: Partial<DeviceRecord>): Promise<DeviceRecord | null> => {
    if (usePostgres && pgPool) {
      const keys = Object.keys(updates);
      if (keys.length === 0) return null;

      const setClause = keys.map((key, index) => {
        return `${key} = $${index + 2}`;
      }).join(', ');

      const vals = keys.map(k => {
        const val = (updates as any)[k];
        if (k === 'last_seen' || k === 'screenshot_time') {
          return val ? new Date(val) : null;
        }
        return val;
      });

      await pgPool.query(`UPDATE devices SET ${setClause} WHERE id = $1`, [id, ...vals]);
      const res = await pgPool.query('SELECT * FROM devices WHERE id = $1', [id]);
      if (res.rows.length === 0) return null;
      const r = res.rows[0];
      return {
        id: r.id,
        name: r.name,
        location: r.location,
        description: r.description,
        os_version: r.os_version,
        player_version: r.player_version,
        ip_address: r.ip_address,
        mac_address: r.mac_address,
        last_seen: r.last_seen ? r.last_seen.toISOString() : undefined,
        online_status: r.online_status,
        current_stream_id: r.current_stream_id,
        current_stream_url: r.current_stream_url,
        current_resolution: r.current_resolution,
        current_volume: r.current_volume,
        current_playback_status: r.current_playback_status,
        pairing_code: r.pairing_code,
        paired: r.paired,
        token: r.token,
        cpu_usage: r.cpu_usage,
        ram_usage: r.ram_usage,
        temperature: r.temperature,
        network_speed: r.network_speed,
        screenshot_url: r.screenshot_url,
        screenshot_time: r.screenshot_time ? r.screenshot_time.toISOString() : undefined,
        brightness: r.brightness,
        rotation: r.rotation,
        player_settings: r.player_settings,
        network_settings: r.network_settings,
        client_version: r.client_version
      };
    }

    const index = localState.devices.findIndex(d => d.id === id);
    if (index === -1) return null;
    localState.devices[index] = { ...localState.devices[index], ...updates };
    saveLocalState();
    return localState.devices[index];
  },

  deleteDevice: async (id: string): Promise<boolean> => {
    if (usePostgres && pgPool) {
      const res = await pgPool.query('DELETE FROM devices WHERE id = $1', [id]);
      return (res.rowCount ?? 0) > 0;
    }
    const initialLen = localState.devices.length;
    localState.devices = localState.devices.filter(d => d.id !== id);
    if (localState.devices.length !== initialLen) {
      saveLocalState();
      return true;
    }
    return false;
  },

  // --- DEVICE GROUPS ---
  getDeviceGroups: async (): Promise<DeviceGroupRecord[]> => {
    if (usePostgres && pgPool) {
      const res = await pgPool.query('SELECT * FROM device_groups ORDER BY name ASC');
      return res.rows.map(r => ({
        id: r.id,
        name: r.name,
        description: r.description
      }));
    }
    return localState.deviceGroups;
  },

  createDeviceGroup: async (group: Omit<DeviceGroupRecord, 'id'>): Promise<DeviceGroupRecord> => {
    const id = 'group_' + Math.random().toString(36).substring(2, 11);
    if (usePostgres && pgPool) {
      await pgPool.query(
        'INSERT INTO device_groups (id, name, description) VALUES ($1, $2, $3)',
        [id, group.name, group.description || null]
      );
      return { ...group, id };
    }
    const newGroup = { ...group, id };
    localState.deviceGroups.push(newGroup);
    saveLocalState();
    return newGroup;
  },

  updateDeviceGroup: async (id: string, updates: Partial<DeviceGroupRecord>): Promise<DeviceGroupRecord | null> => {
    if (usePostgres && pgPool) {
      const keys = Object.keys(updates);
      if (keys.length === 0) return null;

      const setClause = keys.map((key, index) => `${key} = $${index + 2}`).join(', ');
      const vals = keys.map(k => (updates as any)[k]);

      await pgPool.query(`UPDATE device_groups SET ${setClause} WHERE id = $1`, [id, ...vals]);
      const res = await pgPool.query('SELECT * FROM device_groups WHERE id = $1', [id]);
      if (res.rows.length === 0) return null;
      return res.rows[0];
    }
    const idx = localState.deviceGroups.findIndex(g => g.id === id);
    if (idx === -1) return null;
    localState.deviceGroups[idx] = { ...localState.deviceGroups[idx], ...updates };
    saveLocalState();
    return localState.deviceGroups[idx];
  },

  deleteDeviceGroup: async (id: string): Promise<boolean> => {
    if (usePostgres && pgPool) {
      await pgPool.query('DELETE FROM device_groups WHERE id = $1', [id]);
      return true;
    }
    const initialLen = localState.deviceGroups.length;
    localState.deviceGroups = localState.deviceGroups.filter(g => g.id !== id);
    localState.deviceGroupMembers = localState.deviceGroupMembers.filter(m => m.group_id !== id);
    localState.deviceSchedules = localState.deviceSchedules.filter(s => s.group_id !== id);
    if (localState.deviceGroups.length !== initialLen) {
      saveLocalState();
      return true;
    }
    return false;
  },

  getGroupDevices: async (groupId: string): Promise<DeviceRecord[]> => {
    if (usePostgres && pgPool) {
      const res = await pgPool.query(
        `SELECT d.* FROM devices d 
         JOIN device_group_members m ON d.id = m.device_id 
         WHERE m.group_id = $1 ORDER BY d.name ASC`,
        [groupId]
      );
      return res.rows.map(r => ({
        id: r.id,
        name: r.name,
        location: r.location,
        description: r.description,
        os_version: r.os_version,
        player_version: r.player_version,
        ip_address: r.ip_address,
        mac_address: r.mac_address,
        last_seen: r.last_seen ? r.last_seen.toISOString() : undefined,
        online_status: r.online_status,
        current_stream_id: r.current_stream_id,
        current_stream_url: r.current_stream_url,
        current_resolution: r.current_resolution,
        current_volume: r.current_volume,
        current_playback_status: r.current_playback_status,
        pairing_code: r.pairing_code,
        paired: r.paired,
        token: r.token,
        cpu_usage: r.cpu_usage,
        ram_usage: r.ram_usage,
        temperature: r.temperature,
        network_speed: r.network_speed,
        screenshot_url: r.screenshot_url,
        screenshot_time: r.screenshot_time ? r.screenshot_time.toISOString() : undefined,
        brightness: r.brightness,
        rotation: r.rotation,
        player_settings: r.player_settings,
        network_settings: r.network_settings,
        client_version: r.client_version
      }));
    }
    const memberIds = localState.deviceGroupMembers
      .filter(m => m.group_id === groupId)
      .map(m => m.device_id);
    return localState.devices.filter(d => memberIds.includes(d.id));
  },

  addDeviceToGroup: async (groupId: string, deviceId: string): Promise<boolean> => {
    if (usePostgres && pgPool) {
      try {
        await pgPool.query(
          'INSERT INTO device_group_members (group_id, device_id) VALUES ($1, $2) ON CONFLICT DO NOTHING',
          [groupId, deviceId]
        );
        return true;
      } catch (e) {
        return false;
      }
    }
    const exists = localState.deviceGroupMembers.some(m => m.group_id === groupId && m.device_id === deviceId);
    if (!exists) {
      localState.deviceGroupMembers.push({ group_id: groupId, device_id: deviceId });
      saveLocalState();
    }
    return true;
  },

  removeDeviceFromGroup: async (groupId: string, deviceId: string): Promise<boolean> => {
    if (usePostgres && pgPool) {
      await pgPool.query(
        'DELETE FROM device_group_members WHERE group_id = $1 AND device_id = $2',
        [groupId, deviceId]
      );
      return true;
    }
    localState.deviceGroupMembers = localState.deviceGroupMembers.filter(m => !(m.group_id === groupId && m.device_id === deviceId));
    saveLocalState();
    return true;
  },

  // --- PLAYBACK HISTORY ---
  getPlaybackHistory: async (deviceId?: string): Promise<PlaybackHistoryRecord[]> => {
    if (usePostgres && pgPool) {
      const q = deviceId 
        ? ['SELECT * FROM playback_history WHERE device_id = $1 ORDER BY timestamp DESC LIMIT 100', [deviceId]]
        : ['SELECT * FROM playback_history ORDER BY timestamp DESC LIMIT 200', []];
      const res = await pgPool.query(q[0] as string, q[1] as any[]);
      return res.rows.map(r => ({
        id: r.id,
        device_id: r.device_id,
        stream_id: r.stream_id,
        stream_url: r.stream_url,
        action: r.action,
        timestamp: r.timestamp.toISOString()
      }));
    }
    let hist = localState.playbackHistory;
    if (deviceId) {
      hist = hist.filter(h => h.device_id === deviceId);
    }
    return hist.slice(0, 100);
  },

  addPlaybackHistory: async (history: Omit<PlaybackHistoryRecord, 'id' | 'timestamp'>): Promise<PlaybackHistoryRecord> => {
    const id = 'hist_' + Math.random().toString(36).substring(2, 11);
    const timestamp = new Date().toISOString();
    if (usePostgres && pgPool) {
      await pgPool.query(
        'INSERT INTO playback_history (id, device_id, stream_id, stream_url, action, timestamp) VALUES ($1, $2, $3, $4, $5, $6)',
        [id, history.device_id, history.stream_id || null, history.stream_url || null, history.action, new Date(timestamp)]
      );
      return { ...history, id, timestamp };
    }
    const newHist = { ...history, id, timestamp };
    localState.playbackHistory.unshift(newHist);
    if (localState.playbackHistory.length > 500) {
      localState.playbackHistory = localState.playbackHistory.slice(0, 500);
    }
    saveLocalState();
    return newHist;
  },

  // --- DEVICE LOGS ---
  getDeviceLogs: async (deviceId?: string): Promise<DeviceLogRecord[]> => {
    if (usePostgres && pgPool) {
      const q = deviceId
        ? ['SELECT * FROM device_logs WHERE device_id = $1 ORDER BY timestamp DESC LIMIT 100', [deviceId]]
        : ['SELECT * FROM device_logs ORDER BY timestamp DESC LIMIT 200', []];
      const res = await pgPool.query(q[0] as string, q[1] as any[]);
      return res.rows.map(r => ({
        id: r.id,
        device_id: r.device_id,
        level: r.level,
        message: r.message,
        timestamp: r.timestamp.toISOString()
      }));
    }
    let logs = localState.deviceLogs;
    if (deviceId) {
      logs = logs.filter(l => l.device_id === deviceId);
    }
    return logs.slice(0, 100);
  },

  addDeviceLog: async (deviceId: string, level: 'info' | 'warn' | 'error', message: string): Promise<DeviceLogRecord> => {
    const id = 'log_' + Math.random().toString(36).substring(2, 11);
    const timestamp = new Date().toISOString();
    if (usePostgres && pgPool) {
      await pgPool.query(
        'INSERT INTO device_logs (id, device_id, level, message, timestamp) VALUES ($1, $2, $3, $4, $5)',
        [id, deviceId, level, message, new Date(timestamp)]
      );
      return { id, device_id: deviceId, level, message, timestamp };
    }
    const newLog = { id, device_id: deviceId, level, message, timestamp };
    localState.deviceLogs.unshift(newLog);
    if (localState.deviceLogs.length > 500) {
      localState.deviceLogs = localState.deviceLogs.slice(0, 500);
    }
    saveLocalState();
    return newLog;
  },

  // --- DEVICE SCHEDULES ---
  getDeviceSchedules: async (deviceId?: string, groupId?: string): Promise<DeviceScheduleRecord[]> => {
    if (usePostgres && pgPool) {
      let q = 'SELECT * FROM device_schedules WHERE enabled = TRUE';
      const params = [];
      if (deviceId) {
        q += ' AND device_id = $1';
        params.push(deviceId);
      } else if (groupId) {
        q += ' AND group_id = $1';
        params.push(groupId);
      }
      const res = await pgPool.query(q, params);
      return res.rows.map(r => ({
        id: r.id,
        device_id: r.device_id,
        group_id: r.group_id,
        time: r.time,
        action: r.action,
        stream_id: r.stream_id,
        stream_url: r.stream_url,
        enabled: r.enabled
      }));
    }
    let scheds = localState.deviceSchedules;
    if (deviceId) {
      scheds = scheds.filter(s => s.device_id === deviceId);
    } else if (groupId) {
      scheds = scheds.filter(s => s.group_id === groupId);
    }
    return scheds;
  },

  createDeviceSchedule: async (sched: Omit<DeviceScheduleRecord, 'id'>): Promise<DeviceScheduleRecord> => {
    const id = 'sched_' + Math.random().toString(36).substring(2, 11);
    if (usePostgres && pgPool) {
      await pgPool.query(
        'INSERT INTO device_schedules (id, device_id, group_id, time, action, stream_id, stream_url, enabled) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)',
        [id, sched.device_id || null, sched.group_id || null, sched.time, sched.action, sched.stream_id || null, sched.stream_url || null, sched.enabled]
      );
      return { ...sched, id };
    }
    const newSched = { ...sched, id };
    localState.deviceSchedules.push(newSched);
    saveLocalState();
    return newSched;
  },

  deleteDeviceSchedule: async (id: string): Promise<boolean> => {
    if (usePostgres && pgPool) {
      const res = await pgPool.query('DELETE FROM device_schedules WHERE id = $1', [id]);
      return (res.rowCount ?? 0) > 0;
    }
    const initialLen = localState.deviceSchedules.length;
    localState.deviceSchedules = localState.deviceSchedules.filter(s => s.id !== id);
    if (localState.deviceSchedules.length !== initialLen) {
      saveLocalState();
      return true;
    }
    return false;
  },

  getAppSetting: async (key: string): Promise<string | null> => {
    if (usePostgres && pgPool) {
      const res = await pgPool.query('SELECT value FROM app_settings WHERE key = $1', [key]);
      if (res.rows.length > 0) return res.rows[0].value;
      return null;
    }
    return (localState as any).appSettings?.[key] || null;
  },

  setAppSetting: async (key: string, value: string): Promise<void> => {
    if (usePostgres && pgPool) {
      await pgPool.query(
        'INSERT INTO app_settings (key, value, updated_at) VALUES ($1, $2, CURRENT_TIMESTAMP) ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = CURRENT_TIMESTAMP',
        [key, value]
      );
      return;
    }
    if (!(localState as any).appSettings) (localState as any).appSettings = {};
    (localState as any).appSettings[key] = value;
    saveLocalState();
  },

  getAllAppSettings: async (): Promise<Record<string, string>> => {
    if (usePostgres && pgPool) {
      const res = await pgPool.query('SELECT key, value FROM app_settings');
      const out: Record<string, string> = {};
      res.rows.forEach(r => { out[r.key] = r.value; });
      return out;
    }
    return (localState as any).appSettings || {};
  },

  // --- AUDIT LOGGING SYSTEM ---
  addAuditLog: async (entry: Omit<AuditLogRecord, 'id' | 'timestamp'> & { timestamp?: string }): Promise<AuditLogRecord> => {
    const id = 'audit_' + Date.now() + '_' + Math.random().toString(36).substring(2, 8);
    const timestamp = entry.timestamp || new Date().toISOString();
    const record: AuditLogRecord = {
      id,
      timestamp,
      username: entry.username || 'system',
      user_role: entry.user_role || 'system',
      action: entry.action || 'Unknown Action',
      module: entry.module || 'System',
      ip_address: entry.ip_address || '0.0.0.0',
      user_agent: entry.user_agent || '',
      result: entry.result || 'success',
      details: entry.details || ''
    };

    if (usePostgres && pgPool) {
      try {
        await pgPool.query(
          `INSERT INTO audit_logs (id, timestamp, username, user_role, action, module, ip_address, user_agent, result, details)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
          [record.id, new Date(record.timestamp), record.username, record.user_role, record.action, record.module, record.ip_address, record.user_agent, record.result, record.details]
        );
      } catch (err) {
        console.error('[Audit DB] Failed to insert audit log into Postgres:', err);
      }
    } else {
      if (!localState.auditLogs) localState.auditLogs = [];
      localState.auditLogs.unshift(record);
      if (localState.auditLogs.length > 5000) {
        localState.auditLogs = localState.auditLogs.slice(0, 5000);
      }
      saveLocalState();
    }

    return record;
  },

  getAuditLogs: async (params: {
    search?: string;
    module?: string;
    action?: string;
    result?: string;
    username?: string;
    startDate?: string;
    endDate?: string;
    page?: number;
    limit?: number;
  }): Promise<{ logs: AuditLogRecord[]; totalCount: number; page: number; totalPages: number }> => {
    const page = Math.max(1, Number(params.page) || 1);
    const limit = Math.max(1, Math.min(500, Number(params.limit) || 20));
    const offset = (page - 1) * limit;

    if (usePostgres && pgPool) {
      const conditions: string[] = [];
      const values: any[] = [];
      let idx = 1;

      if (params.search && params.search.trim()) {
        const s = `%${params.search.trim()}%`;
        conditions.push(`(username ILIKE $${idx} OR action ILIKE $${idx} OR module ILIKE $${idx} OR ip_address ILIKE $${idx} OR details ILIKE $${idx})`);
        values.push(s);
        idx++;
      }
      if (params.module && params.module !== 'all') {
        conditions.push(`module = $${idx}`);
        values.push(params.module);
        idx++;
      }
      if (params.action && params.action !== 'all') {
        conditions.push(`action = $${idx}`);
        values.push(params.action);
        idx++;
      }
      if (params.result && params.result !== 'all') {
        conditions.push(`result = $${idx}`);
        values.push(params.result);
        idx++;
      }
      if (params.username && params.username !== 'all') {
        conditions.push(`username = $${idx}`);
        values.push(params.username);
        idx++;
      }
      if (params.startDate) {
        conditions.push(`timestamp >= $${idx}`);
        values.push(new Date(params.startDate));
        idx++;
      }
      if (params.endDate) {
        conditions.push(`timestamp <= $${idx}`);
        values.push(new Date(params.endDate));
        idx++;
      }

      const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';
      const countSql = `SELECT COUNT(*) FROM audit_logs ${whereClause}`;
      const countRes = await pgPool.query(countSql, values);
      const totalCount = parseInt(countRes.rows[0].count, 10) || 0;

      const dataSql = `SELECT * FROM audit_logs ${whereClause} ORDER BY timestamp DESC LIMIT $${idx} OFFSET $${idx + 1}`;
      const dataRes = await pgPool.query(dataSql, [...values, limit, offset]);

      const logs: AuditLogRecord[] = dataRes.rows.map(r => ({
        id: r.id,
        timestamp: r.timestamp instanceof Date ? r.timestamp.toISOString() : String(r.timestamp),
        username: r.username,
        user_role: r.user_role,
        action: r.action,
        module: r.module,
        ip_address: r.ip_address,
        user_agent: r.user_agent || '',
        result: r.result,
        details: r.details || ''
      }));

      return {
        logs,
        totalCount,
        page,
        totalPages: Math.ceil(totalCount / limit) || 1
      };
    }

    // JSON mode filtering
    let filtered = [...(localState.auditLogs || [])];
    if (params.search && params.search.trim()) {
      const s = params.search.trim().toLowerCase();
      filtered = filtered.filter(l =>
        l.username.toLowerCase().includes(s) ||
        l.action.toLowerCase().includes(s) ||
        l.module.toLowerCase().includes(s) ||
        (l.details && l.details.toLowerCase().includes(s)) ||
        l.ip_address.toLowerCase().includes(s)
      );
    }
    if (params.module && params.module !== 'all') {
      filtered = filtered.filter(l => l.module === params.module);
    }
    if (params.action && params.action !== 'all') {
      filtered = filtered.filter(l => l.action === params.action);
    }
    if (params.result && params.result !== 'all') {
      filtered = filtered.filter(l => l.result === params.result);
    }
    if (params.username && params.username !== 'all') {
      filtered = filtered.filter(l => l.username.toLowerCase() === params.username!.toLowerCase());
    }
    if (params.startDate) {
      const startMs = new Date(params.startDate).getTime();
      filtered = filtered.filter(l => new Date(l.timestamp).getTime() >= startMs);
    }
    if (params.endDate) {
      const endMs = new Date(params.endDate).getTime();
      filtered = filtered.filter(l => new Date(l.timestamp).getTime() <= endMs);
    }

    filtered.sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime());

    const totalCount = filtered.length;
    const paginatedLogs = filtered.slice(offset, offset + limit);

    return {
      logs: paginatedLogs,
      totalCount,
      page,
      totalPages: Math.ceil(totalCount / limit) || 1
    };
  },

  getAuditRetentionDays: async (): Promise<number> => {
    const val = await db.getAppSetting('audit_retention_days');
    const num = parseInt(val || '90', 10);
    return isNaN(num) || num <= 0 ? 90 : num;
  },

  setAuditRetentionDays: async (days: number): Promise<void> => {
    const validDays = Math.max(1, Math.min(3650, days));
    await db.setAppSetting('audit_retention_days', String(validDays));
    await db.cleanupAuditLogs(validDays);
  },

  cleanupAuditLogs: async (retentionDays?: number): Promise<number> => {
    const days = retentionDays !== undefined ? retentionDays : await db.getAuditRetentionDays();
    const cutoff = new Date(Date.now() - days * 24 * 60 * 60 * 1000);

    if (usePostgres && pgPool) {
      const res = await pgPool.query('DELETE FROM audit_logs WHERE timestamp < $1', [cutoff]);
      return res.rowCount || 0;
    } else {
      if (!localState.auditLogs) return 0;
      const initialLen = localState.auditLogs.length;
      const cutoffMs = cutoff.getTime();
      localState.auditLogs = localState.auditLogs.filter(l => new Date(l.timestamp).getTime() >= cutoffMs);
      const removed = initialLen - localState.auditLogs.length;
      if (removed > 0) saveLocalState();
      return removed;
    }
  },

  dumpAllData: async (): Promise<any> => {
    if (usePostgres && pgPool) {
      const usersRes = await pgPool.query('SELECT * FROM users ORDER BY id ASC');
      const streamsRes = await pgPool.query('SELECT * FROM streams ORDER BY id ASC');
      const devicesRes = await pgPool.query('SELECT * FROM devices ORDER BY id ASC');
      const groupsRes = await pgPool.query('SELECT * FROM device_groups ORDER BY id ASC');
      const membersRes = await pgPool.query('SELECT * FROM device_group_members');
      const historyRes = await pgPool.query('SELECT * FROM playback_history ORDER BY timestamp DESC LIMIT 5000');
      const logsRes = await pgPool.query('SELECT * FROM device_logs ORDER BY timestamp DESC LIMIT 5000');
      const schedulesRes = await pgPool.query('SELECT * FROM device_schedules ORDER BY id ASC');
      const auditRes = await pgPool.query('SELECT * FROM audit_logs ORDER BY timestamp DESC LIMIT 10000');
      const settingsRes = await pgPool.query('SELECT * FROM app_settings');

      const appSettings: Record<string, string> = {};
      settingsRes.rows.forEach(r => { appSettings[r.key] = r.value; });

      return {
        users: usersRes.rows,
        streams: streamsRes.rows,
        devices: devicesRes.rows,
        deviceGroups: groupsRes.rows,
        deviceGroupMembers: membersRes.rows,
        playbackHistory: historyRes.rows,
        deviceLogs: logsRes.rows,
        deviceSchedules: schedulesRes.rows,
        auditLogs: auditRes.rows,
        appSettings
      };
    } else {
      return {
        users: localState.users || [],
        streams: localState.streams || [],
        devices: localState.devices || [],
        deviceGroups: localState.deviceGroups || [],
        deviceGroupMembers: localState.deviceGroupMembers || [],
        playbackHistory: localState.playbackHistory || [],
        deviceLogs: localState.deviceLogs || [],
        deviceSchedules: localState.deviceSchedules || [],
        auditLogs: localState.auditLogs || [],
        appSettings: localState.appSettings || {}
      };
    }
  },

  restoreAllData: async (data: any): Promise<void> => {
    if (!data || typeof data !== 'object') {
      throw new Error('Invalid backup data payload provided');
    }

    if (usePostgres && pgPool) {
      const client = await pgPool.connect();
      try {
        await client.query('BEGIN');

        // Clean tables
        await client.query('TRUNCATE TABLE audit_logs, device_logs, playback_history, device_schedules, device_group_members, device_groups, devices, streams, app_settings, users RESTART IDENTITY CASCADE');

        // 1. Users
        if (Array.isArray(data.users)) {
          for (const u of data.users) {
            await client.query(
              `INSERT INTO users (id, username, password_hash, role, created_at, status, assigned_stream_id, login_history, display_name)
               VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
              [u.id, u.username, u.password_hash || u.passwordHash, u.role || 'user', u.created_at || u.createdAt || new Date(), u.status || 'enabled', u.assigned_stream_id || u.assignedStreamId || null, u.login_history || u.loginHistory || null, u.display_name || u.displayName || u.username]
            );
          }
          await client.query(`SELECT setval('users_id_seq', (SELECT COALESCE(MAX(id), 1) FROM users))`).catch(() => {});
        }

        // 2. Streams
        if (Array.isArray(data.streams)) {
          for (const s of data.streams) {
            await client.query(
              `INSERT INTO streams (id, user_id, title, broadcaster, stream_key, status, scheduled_start, rtmp_url, resolution, bitrate, codec, ingest_ip, viewers, start_time, width, height, fps, aspect_ratio, video_codec, audio_codec, preset, profile, pixel_format, enabled_profiles, gop_size, buffer_size, max_bitrate, scaling_algorithm, audio_enabled, audio_bitrate, audio_sample_rate, audio_channels, audio_volume, audio_normalize, audio_noise_reduction, audio_delay, audio_language, audio_track_selection, audio_passthrough, audio_transcoding, profiles_json)
               VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, $22, $23, $24, $25, $26, $27, $28, $29, $30, $31, $32, $33, $34, $35, $36, $37, $38, $39, $40, $41)`,
              [s.id, s.user_id || s.userId || 1, s.title, s.broadcaster, s.stream_key || s.streamKey, s.status || 'offline', s.scheduled_start || s.scheduledStart || null, s.rtmp_url || s.rtmpUrl, s.resolution || '1080p', s.bitrate || 6000, s.codec || 'H.264', s.ingest_ip || s.ingestIp || '127.0.0.1', s.viewers || 0, s.start_time || s.startTime || null, s.width, s.height, s.fps, s.aspect_ratio || s.aspectRatio, s.video_codec || s.videoCodec, s.audio_codec || s.audioCodec, s.preset, s.profile, s.pixel_format || s.pixelFormat, s.enabled_profiles || s.enabledProfiles, s.gop_size || s.gopSize, s.buffer_size || s.bufferSize, s.max_bitrate || s.maxBitrate, s.scaling_algorithm || s.scalingAlgorithm, s.audio_enabled !== undefined ? s.audio_enabled : (s.audioEnabled !== undefined ? s.audioEnabled : true), s.audio_bitrate || s.audioBitrate, s.audio_sample_rate || s.audioSampleRate, s.audio_channels || s.audioChannels, s.audio_volume !== undefined ? s.audio_volume : (s.audioVolume !== undefined ? s.audioVolume : 100), s.audio_normalize !== undefined ? s.audio_normalize : (s.audioNormalize !== undefined ? s.audioNormalize : false), s.audio_noise_reduction !== undefined ? s.audio_noise_reduction : (s.audioNoiseReduction !== undefined ? s.audioNoiseReduction : false), s.audio_delay || s.audioDelay, s.audio_language || s.audioLanguage, s.audio_track_selection || s.audioTrackSelection, s.audio_passthrough !== undefined ? s.audio_passthrough : (s.audioPassthrough !== undefined ? s.audioPassthrough : false), s.audio_transcoding !== undefined ? s.audio_transcoding : (s.audioTranscoding !== undefined ? s.audioTranscoding : true), s.profiles_json || s.profilesJson]
            );
          }
        }

        // 3. Devices
        if (Array.isArray(data.devices)) {
          for (const d of data.devices) {
            await client.query(
              `INSERT INTO devices (id, name, location, description, os_version, player_version, ip_address, mac_address, last_seen, online_status, current_stream_id, current_stream_url, current_resolution, current_volume, current_playback_status, pairing_code, paired, token, cpu_usage, ram_usage, temperature, network_speed, screenshot_url, screenshot_time, brightness, rotation, player_settings, network_settings, client_version)
               VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, $22, $23, $24, $25, $26, $27, $28, $29)`,
              [d.id, d.name, d.location, d.description, d.os_version, d.player_version, d.ip_address, d.mac_address, d.last_seen, d.online_status || 'offline', d.current_stream_id, d.current_stream_url, d.current_resolution, d.current_volume || 100, d.current_playback_status, d.pairing_code, d.paired || false, d.token, d.cpu_usage, d.ram_usage, d.temperature, d.network_speed, d.screenshot_url, d.screenshot_time, d.brightness || 100, d.rotation || '0', d.player_settings, d.network_settings, d.client_version]
            );
          }
        }

        // 4. Device Groups
        if (Array.isArray(data.deviceGroups)) {
          for (const g of data.deviceGroups) {
            await client.query(
              `INSERT INTO device_groups (id, name, description) VALUES ($1, $2, $3)`,
              [g.id, g.name, g.description]
            );
          }
        }

        // 5. Device Group Members
        if (Array.isArray(data.deviceGroupMembers)) {
          for (const m of data.deviceGroupMembers) {
            await client.query(
              `INSERT INTO device_group_members (group_id, device_id) VALUES ($1, $2)`,
              [m.group_id, m.device_id]
            );
          }
        }

        // 6. Playback History
        if (Array.isArray(data.playbackHistory)) {
          for (const ph of data.playbackHistory) {
            await client.query(
              `INSERT INTO playback_history (id, device_id, stream_id, stream_url, action, timestamp) VALUES ($1, $2, $3, $4, $5, $6)`,
              [ph.id, ph.device_id, ph.stream_id, ph.stream_url, ph.action, ph.timestamp]
            );
          }
        }

        // 7. Device Logs
        if (Array.isArray(data.deviceLogs)) {
          for (const dl of data.deviceLogs) {
            await client.query(
              `INSERT INTO device_logs (id, device_id, level, message, timestamp) VALUES ($1, $2, $3, $4, $5)`,
              [dl.id, dl.device_id, dl.level, dl.message, dl.timestamp]
            );
          }
        }

        // 8. Device Schedules
        if (Array.isArray(data.deviceSchedules)) {
          for (const ds of data.deviceSchedules) {
            await client.query(
              `INSERT INTO device_schedules (id, device_id, group_id, time, action, stream_id, stream_url, enabled) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
              [ds.id, ds.device_id, ds.group_id, ds.time, ds.action, ds.stream_id, ds.stream_url, ds.enabled]
            );
          }
        }

        // 9. Audit Logs
        if (Array.isArray(data.auditLogs)) {
          for (const al of data.auditLogs) {
            await client.query(
              `INSERT INTO audit_logs (id, timestamp, username, user_role, action, module, ip_address, user_agent, result, details) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
              [al.id, new Date(al.timestamp), al.username, al.user_role, al.action, al.module, al.ip_address, al.user_agent, al.result, al.details]
            );
          }
        }

        // 10. App Settings
        if (data.appSettings && typeof data.appSettings === 'object') {
          for (const [key, val] of Object.entries(data.appSettings)) {
            await client.query(
              `INSERT INTO app_settings (key, value, updated_at) VALUES ($1, $2, CURRENT_TIMESTAMP) ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = CURRENT_TIMESTAMP`,
              [key, String(val)]
            );
          }
        }

        await client.query('COMMIT');
      } catch (err) {
        await client.query('ROLLBACK');
        throw err;
      } finally {
        client.release();
      }
    } else {
      localState.users = Array.isArray(data.users) ? data.users : [];
      localState.streams = Array.isArray(data.streams) ? data.streams : [];
      localState.devices = Array.isArray(data.devices) ? data.devices : [];
      localState.deviceGroups = Array.isArray(data.deviceGroups) ? data.deviceGroups : [];
      localState.deviceGroupMembers = Array.isArray(data.deviceGroupMembers) ? data.deviceGroupMembers : [];
      localState.playbackHistory = Array.isArray(data.playbackHistory) ? data.playbackHistory : [];
      localState.deviceLogs = Array.isArray(data.deviceLogs) ? data.deviceLogs : [];
      localState.deviceSchedules = Array.isArray(data.deviceSchedules) ? data.deviceSchedules : [];
      localState.auditLogs = Array.isArray(data.auditLogs) ? data.auditLogs : [];
      localState.appSettings = data.appSettings && typeof data.appSettings === 'object' ? data.appSettings : {};
      saveLocalState();
    }
  },

  close: async (): Promise<void> => {
    if (pgPool) {
      console.log('Closing PostgreSQL database connection pool gracefully...');
      await pgPool.end();
      pgPool = null;
      usePostgres = false;
      console.log('PostgreSQL pool closed successfully.');
    }
  }

};
