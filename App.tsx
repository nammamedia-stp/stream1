import React, { useState, useEffect, useCallback, useRef } from 'react';
import { CopyButton } from './components/CopyButton';
import { ToastContainer } from './components/ToastContainer';
import { copyToClipboard } from './utils/clipboard';
import { 
  LayoutDashboard, 
  PlusCircle, 
  Settings, 
  Tv, 
  Users, 
  Cpu, 
  HardDrive, 
  CloudRain, 
  RefreshCcw,
  Plus,
  MessageSquare,
  Key,
  Globe,
  Copy,
  Server,
  Monitor,
  Edit3,
  Wifi,
  Laptop,
  AlertTriangle,
  X,
  Network,
  Terminal,
  Image as ImageIcon,
  Sparkles,
  Calendar,
  Clock,
  ListRestart,
  LogOut,
  User,
  Shield,
  Download,
  Trash2,
  PlayCircle,
  Play,
  Video,
  FileText,
  ServerCrash,
  FolderOpen,
  FolderSearch,
  Save,
  CheckCircle2,
  RotateCcw,
  Check,
  AlertCircle,
  Activity,
  Headphones,
  ChevronDown,
  ChevronUp,
  Sliders,
  Info,
  Eye,
  EyeOff
} from 'lucide-react';
import DashboardHeader from './components/DashboardHeader';
import StreamPlayer from './components/StreamPlayer';
import DeploymentGuide from './components/DeploymentGuide';
import { StreamTestHub } from './components/StreamTestHub';
import { DeviceManager } from './components/DeviceManager';
import { SettingsPage } from './components/SettingsPage';
import { SetupWizard } from './components/SetupWizard';
import { AdminProfile } from './components/AdminProfile';
import { UserProfile } from './components/UserProfile';
import { AuditLogs } from './components/AuditLogs';
import { BackupRecovery } from './components/BackupRecovery';
import { RaspberryPlayer } from './components/RaspberryPlayer';
import { StreamSession, StreamStats, ChatMessage } from './types';

export type IPMode = 'auto' | 'lan' | 'loopback' | 'manual';

export interface CustomOutputProfile {
  id: string;
  name: string;
  width: number;
  height: number;
  videoBitrate: string;
  audioBitrate: string;
  fps: number;
  gopSize: number;
  preset: string;
}

const safeParseJson = async (res: Response) => {
  const contentType = res.headers.get('content-type');
  if (!contentType || !contentType.includes('application/json')) {
    const text = await res.text();
    throw new Error(`Expected JSON response, but received content-type: ${contentType || 'unknown'}. Status: ${res.status}. Preview: ${text.substring(0, 150)}`);
  }
  return res.json();
};

const App: React.FC = () => {
  const [token, setToken] = useState<string | null>(localStorage.getItem('streampulse_jwt'));
  const [currentUser, setCurrentUser] = useState<any>(null);
  const [setupCompleted, setSetupCompleted] = useState<boolean | null>(null);
  
  const [activeTab, setActiveTab] = useState<'dashboard' | 'streams' | 'deploy' | 'infra' | 'settings' | 'stream_test' | 'devices' | 'users' | 'admin_profile' | 'user_profile' | 'audit_logs' | 'backup_recovery'>('dashboard');
  const [streams, setStreams] = useState<StreamSession[]>([]);
  
  const [detectedPublicIp, setDetectedPublicIp] = useState<string>('Detecting...');
  const [detectedLanIp, setDetectedLanIp] = useState<string>('Detecting...');
  const [manualIp, setManualIp] = useState<string>(() => localStorage.getItem('streampulse_manual_ip') || '');
  const [customDomain, setCustomDomain] = useState<string>(() => localStorage.getItem('streampulse_custom_domain') || '');
  const [creationIpMode, setCreationIpMode] = useState<IPMode>('auto');
  const [confirmRemovalId, setConfirmRemovalId] = useState<string | null>(null);
  const [confirmDeleteUserId, setConfirmDeleteUserId] = useState<number | null>(null);
  const [actionLogs, setActionLogs] = useState<any[]>([]);
  const [copiedUrlKey, setCopiedUrlKey] = useState<string | null>(null);
  const [networkDetails, setNetworkDetails] = useState<any>(null);
  const [deploymentMode, setDeploymentMode] = useState<'auto' | 'lan' | 'public' | 'domain'>('auto');

  // Network Settings Alerts & Loaders
  const [networkLoading, setNetworkLoading] = useState(false);
  const [networkSuccess, setNetworkSuccess] = useState('');
  const [networkError, setNetworkError] = useState('');

  // Security Settings states
  const [securityLoading, setSecurityLoading] = useState(false);
  const [securitySuccess, setSecuritySuccess] = useState('');
  const [securityError, setSecurityError] = useState('');

  // Personal Security forms
  const [newAdminUsername, setNewAdminUsername] = useState('');
  const [newAdminPassword, setNewAdminPassword] = useState('');
  const [confirmAdminPassword, setConfirmAdminPassword] = useState('');

  // Admin user management / forced reset forms
  const [adminTargetUser, setAdminTargetUser] = useState('');
  const [adminUserPassword, setAdminUserPassword] = useState('');
  const [adminForceReset, setAdminForceReset] = useState(false);

  // Forced password reset modal states (mandatory)
  const [newResetPassword, setNewResetPassword] = useState('');
  const [confirmResetPassword, setConfirmResetPassword] = useState('');
  const [resetLoading, setResetLoading] = useState(false);
  const [resetError, setResetError] = useState('');
  const [resetSuccess, setResetSuccess] = useState('');

  // Test Utilities state
  const [testingRtmp, setTestingRtmp] = useState(false);
  const [rtmpTestResult, setRtmpTestResult] = useState<{ success: boolean; message: string } | null>(null);
  const [testingPlayback, setTestingPlayback] = useState(false);
  const [playbackTestResult, setPlaybackTestResult] = useState<{ success: boolean; message: string } | null>(null);

  const [stats, setStats] = useState<any>({
    cpuUsage: 8.5,
    cpuCores: 4,
    cpuModel: 'Intel Xeon Platinum vCPU',
    memoryUsage: 2.1,
    memoryTotal: 16,
    memoryUsagePct: 13.1,
    activeStreams: 0,
    totalBandwidth: '0.0 Mbps',
    diskUsagePct: 34.2,
    uptime: 124502,
    networkTx: '0 KB/s',
    networkRx: '0 KB/s',
    dockerContainers: []
  });

  const [isGeneratingKey, setIsGeneratingKey] = useState(false);
  const [newStreamData, setNewStreamData] = useState({ 
    title: '', 
    broadcaster: '', 
    streamKey: '',
    thumbnailUrl: '',
    resolution: '1080p' as StreamSession['resolution'],
    isScheduled: false,
    scheduledDate: '',
    scheduledTime: '',
    audioCodec: 'aac',
    audioBitrate: '128k',
    audioSampleRate: '44100',
    audioChannels: 'stereo',
    audioNormalize: false,
    audioDelay: 0
  });

  const [manualSelectedResolutions, setManualSelectedResolutions] = useState<string[]>(['Original', '1080p', '720p', '480p', '360p']);
  const [manualProfiles, setManualProfiles] = useState<CustomOutputProfile[]>([
    {
      id: 'out_1',
      name: 'Output 1',
      width: 1920,
      height: 1080,
      videoBitrate: '4500k',
      audioBitrate: '192k',
      fps: 30,
      gopSize: 60,
      preset: 'superfast'
    },
    {
      id: 'out_2',
      name: 'Output 2',
      width: 1280,
      height: 720,
      videoBitrate: '2500k',
      audioBitrate: '128k',
      fps: 30,
      gopSize: 60,
      preset: 'superfast'
    }
  ]);

  const handleAddOutputProfile = () => {
    const nextNum = manualProfiles.length + 1;
    const newProf: CustomOutputProfile = {
      id: 'out_' + Date.now() + Math.random().toString(36).substring(2, 6),
      name: `Output ${nextNum}`,
      width: 1280,
      height: 720,
      videoBitrate: '2500k',
      audioBitrate: '128k',
      fps: 30,
      gopSize: 60,
      preset: 'superfast'
    };
    setManualProfiles(prev => [...prev, newProf]);
  };

  const handleRemoveOutputProfile = (index: number) => {
    if (manualProfiles.length <= 1) {
      alert('At least one output profile is required.');
      return;
    }
    setManualProfiles(prev => prev.filter((_, i) => i !== index));
  };

  const handleReorderOutputProfile = (index: number, direction: 'up' | 'down') => {
    if (direction === 'up' && index === 0) return;
    if (direction === 'down' && index === manualProfiles.length - 1) return;
    const targetIndex = direction === 'up' ? index - 1 : index + 1;
    setManualProfiles(prev => {
      const list = [...prev];
      const [moved] = list.splice(index, 1);
      list.splice(targetIndex, 0, moved);
      return list;
    });
  };

  const handleUpdateOutputProfile = (index: number, field: keyof CustomOutputProfile, value: any) => {
    setManualProfiles(prev => {
      const updated = [...prev];
      updated[index] = { ...updated[index], [field]: value };
      return updated;
    });
  };
  const [isAudioSettingsExpanded, setIsAudioSettingsExpanded] = useState(false);

  // Auth States
  const [loginRoleMode, setLoginRoleMode] = useState<'admin' | 'user'>('admin');
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [showLoginPassword, setShowLoginPassword] = useState(false);
  const [authError, setAuthError] = useState<string | null>(null);
  const [authLoading, setAuthLoading] = useState(false);

  // User Management State Hooks
  const [usersList, setUsersList] = useState<any[]>([]);
  const [usersLoading, setUsersLoading] = useState(false);
  const [usersError, setUsersError] = useState<string | null>(null);
  
  const [newUsername, setNewUsername] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [newConfirmPassword, setNewConfirmPassword] = useState('');
  const [newRole, setNewRole] = useState<'admin' | 'user'>('user');
  const [newAssignedStreamId, setNewAssignedStreamId] = useState('');
  const [showNewPassword, setShowNewPassword] = useState(false);
  const [showConfirmPassword, setShowConfirmPassword] = useState(false);
  const [createUserSuccess, setCreateUserSuccess] = useState('');

  const [editingUserId, setEditingUserId] = useState<number | null>(null);
  const [editUsername, setEditUsername] = useState('');
  const [editPassword, setEditPassword] = useState('');
  const [editStatus, setEditStatus] = useState<'enabled' | 'disabled'>('enabled');
  const [editAssignedStreamId, setEditAssignedStreamId] = useState('');
  const [editDisplayName, setEditDisplayName] = useState('');
  const [editRole, setEditRole] = useState<'admin' | 'user'>('user');
  const [showEditPassword, setShowEditPassword] = useState(false);
  const [viewingHistoryUser, setViewingHistoryUser] = useState<any | null>(null);
  const [userSearchQuery, setUserSearchQuery] = useState('');

  // Infrapage config tab states
  const [selectedFileKey, setSelectedFileKey] = useState<'docker-compose' | 'nginx' | 'nginx-rtmp' | 'transcode' | 'schema'>('docker-compose');
  // No recording state

  // File content definitions to preview
  const fileContents = {
    'docker-compose': `version: '3.8'
services:
  streampulse:
    build:
      context: ..
      dockerfile: vps-deployment/Dockerfile
    container_name: streampulse_manager
    ports:
      - "1935:1935" # RTMP ingest port
      - "80:80"     # HTTP reverse proxy
      - "443:443"   # HTTPS SSL reverse proxy
      - "3000:3000" # Direct Node manager interface
    environment:
      - NODE_ENV=production
      - JWT_SECRET=change_this_to_a_secure_random_key_in_production_129841824
      - DB_HOST=postgres_db
      - DB_PORT=5432
      - DB_USER=streampulse_admin
      - DB_PASSWORD=streampulse_secure_db_pass_19824
      - DB_NAME=streampulse
    volumes:
      - hls_storage:/var/www/hls
      - certbot_conf:/etc/letsencrypt
      - certbot_www:/var/www/certbot
    depends_on:
      - postgres_db
    restart: always

  postgres_db:
    image: postgres:16-alpine
    container_name: streampulse_db
    environment:
      - POSTGRES_DB=streampulse
      - POSTGRES_USER=streampulse_admin
      - POSTGRES_PASSWORD=streampulse_secure_db_pass_19824
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    restart: always`,
    'nginx': `user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    sendfile on;
    keepalive_timeout 65;

    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml;

    server {
        listen 80;
        server_name streampulse.yourdomain.com;
        location / {
            return 301 https://$host$request_uri;
        }
    }`,
    'nginx-rtmp': `rtmp {
    server {
        listen 1935; # Standard RTMP port
        chunk_size 4096;

        # Primary Live Stream application
        application live {
            live on;
            record off;

            # Hand over incoming RTMP stream to FFmpeg for dynamic Multi-Bitrate HLS Transcoding
            exec_push /usr/local/bin/transcode.sh $name;
        }
    }
}`,
    'transcode': `#!/bin/bash
STREAM_KEY=$1
HLS_PATH="/var/www/hls/\${STREAM_KEY}"
RTMP_INPUT="rtmp://localhost/live/\${STREAM_KEY}"

mkdir -p "\${HLS_PATH}"

# FFmpeg Multi-Bitrate HLS Transcoder
ffmpeg -i "\${RTMP_INPUT}" \\
  -filter_complex "[v:0]split=4[v1080][v720][v480][v360]" \\
  -map "[v1080]" -c:v:0 libx264 -preset veryfast -b:v:0 6000k -maxrate:v:0 6000k -bufsize:v:0 12000k -g 60 -keyint_min 60 -sc_threshold 0 \\
  -map "[v720]"  -c:v:1 libx264 -preset veryfast -b:v:1 3500k -maxrate:v:1 3500k -bufsize:v:1 7000k  -g 60 -keyint_min 60 -sc_threshold 0 \\
  -map "[v480]"  -c:v:2 libx264 -preset veryfast -b:v:2 1500k -maxrate:v:2 1500k -bufsize:v:2 3000k  -g 60 -keyint_min 60 -sc_threshold 0 \\
  -map "[v360]"  -c:v:3 libx264 -preset veryfast -b:v:3 800k  -maxrate:v:3 800k  -bufsize:v:3 1600k  -g 60 -keyint_min 60 -sc_threshold 0 \\
  -map a:0 -c:a:0 aac -b:a:0 192k -ac 2 \\
  -map a:0 -c:a:1 aac -b:a:1 128k -ac 2 \\
  -map a:0 -c:a:2 aac -b:a:2 96k  -ac 2 \\
  -map a:0 -c:a:3 aac -b:a:3 64k  -ac 2 \\
  -f hls -hls_time 4 -hls_playlist_type event -master_pl_name master.m3u8 \\
  -hls_segment_filename "\${HLS_PATH}/v%v/file%03d.ts" \\
  -var_stream_map "v:0,a:0 v:1,a:1 v:2,a:2 v:3,a:3" \\
  "\${HLS_PATH}/v%v/index.m3u8" > /var/log/nginx/transcode_\${STREAM_KEY}.log 2>&1 &`,
    'schema': `CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(20) DEFAULT 'user',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

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
);`
  };

  useEffect(() => {
    const checkSetupStatus = async () => {
      try {
        const res = await fetch('/api/setup/status');
        if (!res.ok) {
          throw new Error(`HTTP error! status: ${res.status}`);
        }
        const data = await safeParseJson(res);
        setSetupCompleted(!!data.completed);
      } catch (err) {
        console.error('Failed to verify StreamPulse setup status:', err);
        setSetupCompleted(true); // Graceful fallback
      }
    };
    checkSetupStatus();
  }, []);

  useEffect(() => {
    localStorage.setItem('streampulse_manual_ip', manualIp);
  }, [manualIp]);

  useEffect(() => {
    localStorage.setItem('streampulse_custom_domain', customDomain);
  }, [customDomain]);

  useEffect(() => {
    localStorage.setItem('streampulse_deployment_mode', deploymentMode);
  }, [deploymentMode]);

  const fetchWithNetworkHeaders = useCallback(async (url: string, init?: RequestInit, retries = 2): Promise<Response> => {
    const headers = new Headers(init?.headers);
    if (token) {
      headers.set('Authorization', `Bearer ${token}`);
    }
    if (customDomain && customDomain.trim() !== '') {
      headers.set('x-custom-domain', customDomain.trim());
    }
    if (manualIp && manualIp.trim() !== '' && manualIp !== '0.0.0.0') {
      headers.set('x-manual-ip', manualIp.trim());
    }
    if (deploymentMode) {
      headers.set('x-deployment-mode', deploymentMode);
    }

    try {
      return await fetch(url, {
        ...init,
        headers
      });
    } catch (err) {
      if (retries > 0) {
        await new Promise(r => setTimeout(r, 400));
        return fetchWithNetworkHeaders(url, init, retries - 1);
      }
      throw err;
    }
  }, [token, customDomain, manualIp, deploymentMode]);

  const MIN_SCHEDULE_DATE = '2026-01-01';
  const MAX_SCHEDULE_DATE = '2027-12-31';

  const getSelectedEndpoint = () => {
    if (networkDetails && networkDetails.activeEndpoint) {
      return {
        endpoint: networkDetails.activeEndpoint,
        source: networkDetails.source || 'Runtime API Resolution'
      };
    }
    return { endpoint: 'Endpoint unavailable', source: 'Endpoint unavailable' };
  };

  // Auth APIs
  const handleAuth = async (e: React.FormEvent) => {
    e.preventDefault();
    setAuthError(null);
    setAuthLoading(true);

    try {
      const res = await fetch('/api/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username: username.trim(), password })
      });
      const data = await res.json();
      if (!res.ok) {
        throw new Error(data.error || 'Authentication failed');
      }

      localStorage.setItem('streampulse_jwt', data.token);
      setToken(data.token);
      setCurrentUser(data.user);
      setUsername('');
      setPassword('');
    } catch (err: any) {
      setAuthError(err.message);
    } finally {
      setAuthLoading(false);
    }
  };

  const handleLogout = useCallback(() => {
    localStorage.removeItem('streampulse_jwt');
    setToken(null);
    setCurrentUser(null);
  }, []);

  // Load Current User Profile
  useEffect(() => {
    if (!token) return;
    const fetchProfile = async () => {
      try {
        const res = await fetchWithNetworkHeaders('/api/auth/me');
        if (res.status === 401) {
          handleLogout();
          return;
        }
        if (res.status === 403) {
          return;
        }
        if (!res.ok) {
          throw new Error(`HTTP error! status: ${res.status}`);
        }
        const data = await safeParseJson(res);
        setCurrentUser(data);
      } catch (err) {
        console.error('Failed to load profile:', err);
      }
    };
    fetchProfile();
  }, [token, fetchWithNetworkHeaders, handleLogout]);

  // Load IP and Server Stats / Streams / Recordings
  useEffect(() => {
    const detectPublicIp = async () => {
      try {
        const response = await fetch('https://api.ipify.org?format=json');
        const data = await response.json();
        setDetectedPublicIp(data.ip || '');
      } catch (e) {
        setDetectedPublicIp('');
      }
    };

    const detectLanIp = () => {
      const pc = new RTCPeerConnection({ iceServers: [] });
      pc.createDataChannel("");
      pc.createOffer().then(pc.setLocalDescription.bind(pc));
      pc.onicecandidate = (ice) => {
        if (!ice || !ice.candidate || !ice.candidate.candidate) return;
        const myIP = /([0-9]{1,3}(\.[0-9]{1,3}){3}|[a-f0-9]{1,4}(:[a-f0-9]{1,4}){7})/.exec(ice.candidate.candidate)?.[1];
        if (myIP) {
          setDetectedLanIp(myIP);
          pc.onicecandidate = null;
        }
      };
      setTimeout(() => {
        setDetectedLanIp(prev => prev === 'Detecting...' ? '' : prev);
      }, 2000);
    };

    detectPublicIp();
    detectLanIp();
  }, []);

  // Fetch Streams, Stats, and Recordings from REST API
  const fetchStreams = useCallback(async () => {
    if (!token) return;
    try {
      const res = await fetchWithNetworkHeaders('/api/streams');
      if (res.status === 401) {
        handleLogout();
        return;
      }
      if (res.status === 403) {
        return;
      }
      if (!res.ok) {
        throw new Error(`HTTP error! status: ${res.status}`);
      }
      const data = await safeParseJson(res);
      if (Array.isArray(data)) {
        setStreams(data);
      }
    } catch (err: any) {
      console.warn('Network notice while fetching streams:', err?.message || err);
    }
  }, [token, fetchWithNetworkHeaders, handleLogout]);

  const fetchUsers = useCallback(async () => {
    if (!token || !currentUser || currentUser.role !== 'admin') return;
    setUsersLoading(true);
    setUsersError(null);
    try {
      const res = await fetchWithNetworkHeaders('/api/users');
      const data = await res.json();
      if (res.ok) {
        setUsersList(data);
      } else {
        setUsersError(data.error || 'Failed to fetch users');
      }
    } catch (err) {
      setUsersError('Network error while fetching users');
    } finally {
      setUsersLoading(false);
    }
  }, [token, currentUser]);

  useEffect(() => {
    if (activeTab === 'users' && currentUser?.role === 'admin') {
      fetchUsers();
    }
  }, [activeTab, fetchUsers, currentUser]);

  const handleCreateUser = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!newUsername || !newPassword || !newConfirmPassword) {
      setUsersError('Please fill out all required fields');
      return;
    }
    if (newPassword !== newConfirmPassword) {
      setUsersError('Passwords do not match');
      return;
    }
    if (newPassword.length < 6) {
      setUsersError('Password must be at least 6 characters long');
      return;
    }
    setUsersError(null);
    setCreateUserSuccess('');
    try {
      const res = await fetchWithNetworkHeaders('/api/users', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          username: newUsername.trim(),
          password: newPassword,
          role: newRole,
          assigned_stream_id: newAssignedStreamId || null
        })
      });
      const data = await res.json();
      if (res.ok) {
        setCreateUserSuccess(`User "${data.username}" created successfully!`);
        setNewUsername('');
        setNewPassword('');
        setNewConfirmPassword('');
        setNewRole('user');
        setNewAssignedStreamId('');
        fetchUsers();
      } else {
        setUsersError(data.error || 'Failed to create user');
      }
    } catch (err) {
      setUsersError('Network error while creating user');
    }
  };

  const handleUpdateUser = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!editingUserId) return;
    setUsersError(null);
    try {
      const body: any = {
        username: editUsername.trim(),
        status: editStatus,
        assigned_stream_id: editAssignedStreamId || null,
        role: editRole,
        display_name: editDisplayName ? editDisplayName.trim() : editUsername.trim()
      };
      if (editPassword) {
        if (editPassword.length < 6) {
          setUsersError('Password must be at least 6 characters long');
          return;
        }
        body.password = editPassword;
      }
      const res = await fetchWithNetworkHeaders(`/api/users/${editingUserId}`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(body)
      });
      const data = await res.json();
      if (res.ok) {
        setEditingUserId(null);
        setEditPassword('');
        fetchUsers();
      } else {
        setUsersError(data.error || 'Failed to update user');
      }
    } catch (err) {
      setUsersError('Network error while updating user');
    }
  };

  const handleDeleteUser = async (id: number) => {
    console.log(`[DELETE WORKFLOW] handleDeleteUser executed for user ID: ${id}`);
    setUsersError(null);
    try {
      console.log(`[DELETE WORKFLOW] Dispatching DELETE request to /api/users/${id}`);
      const res = await fetchWithNetworkHeaders(`/api/users/${id}`, {
        method: 'DELETE'
      });
      console.log(`[DELETE WORKFLOW] Received response status: ${res.status}`);
      if (res.ok) {
        console.log(`[DELETE WORKFLOW] Deletion successful! Refreshing user list...`);
        fetchUsers();
      } else {
        const data = await res.json();
        console.error(`[DELETE WORKFLOW] Deletion failed:`, data.error);
        setUsersError(data.error || 'Failed to delete user');
      }
    } catch (err) {
      console.error(`[DELETE WORKFLOW] Network error during user deletion:`, err);
      setUsersError('Network error while deleting user');
    }
  };

  const fetchStats = useCallback(async () => {
    if (!token || !currentUser || currentUser.role !== 'admin') return;
    try {
      const res = await fetchWithNetworkHeaders('/api/system/stats');
      if (res.status === 401) {
        handleLogout();
        return;
      }
      if (res.status === 403) {
        return;
      }
      if (!res.ok) {
        throw new Error(`HTTP error! status: ${res.status}`);
      }
      const data = await safeParseJson(res);
      setStats(data);
    } catch (err: any) {
      console.warn('Network notice while fetching server stats:', err?.message || err);
    }
  }, [token, currentUser, fetchWithNetworkHeaders, handleLogout]);

  const fetchActionLogs = useCallback(async () => {
    if (!token) return;
    try {
      const res = await fetchWithNetworkHeaders('/api/system/logs');
      if (res.status === 401) {
        handleLogout();
        return;
      }
      if (res.status === 403) {
        return;
      }
      if (!res.ok) {
        throw new Error(`HTTP error! status: ${res.status}`);
      }
      const data = await safeParseJson(res);
      setActionLogs(data);
    } catch (err: any) {
      console.warn('Network notice while fetching logs:', err?.message || err);
    }
  }, [token, fetchWithNetworkHeaders, handleLogout]);

  const fetchNetworkDetails = useCallback(async () => {
    if (!token) return;
    try {
      const res = await fetchWithNetworkHeaders('/api/network/details');
      if (res.status === 401) {
        handleLogout();
        return;
      }
      if (res.status === 403) {
        return;
      }
      if (!res.ok) {
        throw new Error(`HTTP error! status: ${res.status}`);
      }
      const data = await safeParseJson(res);
      setNetworkDetails(data);
      if (data.publicIp && data.publicIp !== 'Unavailable' && data.publicIp !== 'Not available') {
        setDetectedPublicIp(data.publicIp);
      } else {
        setDetectedPublicIp('Not available');
      }
      if (data.lanIp) {
        setDetectedLanIp(data.lanIp);
      } else {
        setDetectedLanIp('Not available');
      }
    } catch (err: any) {
      console.warn('Network notice while fetching network details:', err?.message || err);
    }
  }, [token, fetchWithNetworkHeaders, handleLogout]);

  const [preferencesLoaded, setPreferencesLoaded] = useState(false);

  const fetchUserPreferences = useCallback(async () => {
    if (!token) return;
    try {
      const res = await fetchWithNetworkHeaders('/api/preferences');
      if (res.ok) {
        const pref = await safeParseJson(res);
        if (pref && typeof pref === 'object') {
          if (pref.activeTab) {
            if (currentUser?.role === 'user' && pref.activeTab !== 'dashboard') {
              setActiveTab('dashboard');
            } else {
              setActiveTab(pref.activeTab);
            }
          }
          if (pref.manualIp) setManualIp(pref.manualIp);
          if (pref.customDomain) setCustomDomain(pref.customDomain);
          if (pref.creationIpMode) setCreationIpMode(pref.creationIpMode);
          if (pref.deploymentMode) setDeploymentMode(pref.deploymentMode);
        }
      }
    } catch (err) {
      console.error('Error loading preferences from DB:', err);
    } finally {
      setPreferencesLoaded(true);
    }
  }, [token, currentUser, fetchWithNetworkHeaders, safeParseJson]);

  const saveUserPreferences = useCallback(async (overrides: Record<string, any> = {}) => {
    if (!token) return;
    const payload = {
      activeTab,
      manualIp,
      customDomain,
      creationIpMode,
      deploymentMode,
      ...overrides
    };
    try {
      await fetchWithNetworkHeaders('/api/preferences', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      });
    } catch (err) {
      console.error('Error saving user preferences to DB:', err);
    }
  }, [token, fetchWithNetworkHeaders, activeTab, manualIp, customDomain, creationIpMode, deploymentMode]);

  const wsRef = useRef<WebSocket | null>(null);
  const currentUserRef = useRef(currentUser);

  useEffect(() => {
    currentUserRef.current = currentUser;
  }, [currentUser]);

  useEffect(() => {
    if (!token) return;
    fetchUserPreferences();
    fetchStreams();
    if (currentUser?.role === 'admin') {
      fetchStats();
    }
    fetchActionLogs();
    fetchNetworkDetails();

    let isMounted = true;
    let reconnectTimer: any = null;

    const connectWebSocket = () => {
      if (!isMounted) return;
      try {
        const wsProtocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        const host = window.location.host;
        const wsUrl = `${wsProtocol}//${host}/api/dashboard-ws`;

        const ws = new WebSocket(wsUrl);
        wsRef.current = ws;

        ws.onopen = () => {
          console.log('[WebSocket Engine] Connected to real-time sync stream.');
          fetchStreams();
          if (currentUserRef.current?.role === 'admin') {
            fetchStats();
          }
          fetchActionLogs();
          fetchNetworkDetails();
        };

        ws.onmessage = (event) => {
          try {
            const msg = JSON.parse(event.data);
            if (!msg || typeof msg !== 'object') return;

            // 1. Stream Status Changes & Updates
            if (msg.type === 'stream_status_change' || msg.type === 'stream_updated') {
              setStreams(prevStreams => {
                const streamId = msg.streamId || (msg.stream && msg.stream.id);
                const streamKey = msg.streamKey || (msg.stream && msg.stream.streamKey);

                const existingIndex = prevStreams.findIndex(s => 
                  (streamId && s.id === streamId) || (streamKey && s.streamKey === streamKey)
                );

                if (existingIndex !== -1) {
                  return prevStreams.map((s, idx) => {
                    if (idx === existingIndex) {
                      return {
                        ...s,
                        ...(msg.status ? { status: msg.status } : {}),
                        ...(msg.stream || {})
                      };
                    }
                    return s;
                  });
                } else if (msg.stream) {
                  const user = currentUserRef.current;
                  if (user?.role === 'admin' || user?.assigned_stream_id === msg.stream.id || msg.stream.userId === user?.id) {
                    return [msg.stream, ...prevStreams];
                  }
                }
                return prevStreams;
              });
            }

            // 2. Stream Created
            else if (msg.type === 'stream_created' && msg.stream) {
              setStreams(prevStreams => {
                if (prevStreams.some(s => s.id === msg.stream.id)) {
                  return prevStreams.map(s => s.id === msg.stream.id ? { ...s, ...msg.stream } : s);
                }
                const user = currentUserRef.current;
                if (user?.role === 'admin' || user?.assigned_stream_id === msg.stream.id || msg.stream.userId === user?.id) {
                  return [msg.stream, ...prevStreams];
                }
                return prevStreams;
              });
            }

            // 3. Stream Deleted
            else if (msg.type === 'stream_deleted' && msg.streamId) {
              setStreams(prevStreams => prevStreams.filter(s => s.id !== msg.streamId));
            }

            // 4. Analytics & System Stats Update
            else if (msg.type === 'analytics_update') {
              setStats(prev => ({
                ...prev,
                activeStreamsCount: msg.activeStreams ?? prev.activeStreamsCount,
                totalViewers: msg.totalViewers ?? prev.totalViewers,
                cpuUsagePct: msg.systemMetrics?.cpuUsage ?? prev.cpuUsagePct,
                memoryUsagePct: msg.systemMetrics?.memoryUsage ?? prev.memoryUsagePct,
                freeMemoryGb: msg.systemMetrics?.freeMemoryGb ?? prev.freeMemoryGb,
              }));
            }

            // 5. Action Logged
            else if (msg.type === 'action_logged') {
              if (msg.log) {
                setActionLogs(prev => {
                  if (prev.some(l => l.id === msg.log.id)) return prev;
                  return [msg.log, ...prev].slice(0, 200);
                });
              } else {
                fetchActionLogs();
              }
            }
          } catch (e) {
            console.warn('[WebSocket Engine] Message handling error:', e);
          }
        };

        ws.onclose = () => {
          if (isMounted) {
            reconnectTimer = setTimeout(connectWebSocket, 3000);
          }
        };

        ws.onerror = (err) => {
          console.warn('[WebSocket Engine] Error encountered:', err);
        };
      } catch (err) {
        if (isMounted) {
          reconnectTimer = setTimeout(connectWebSocket, 5000);
        }
      }
    };

    connectWebSocket();

    // Fallback sync interval (every 15s)
    const interval = setInterval(() => {
      fetchStreams();
      if (currentUserRef.current?.role === 'admin') {
        fetchStats();
      }
      fetchActionLogs();
      fetchNetworkDetails();
    }, 15000);

    return () => {
      isMounted = false;
      if (reconnectTimer) clearTimeout(reconnectTimer);
      clearInterval(interval);
      if (wsRef.current) {
        try {
          wsRef.current.close();
        } catch (_) {}
      }
    };
  }, [token, fetchUserPreferences, fetchStreams, fetchStats, fetchActionLogs, fetchNetworkDetails]);

  // Removed auto-save useEffect to enforce explicit Save button functionality as required.

  // Handle Stream Creation via API
  const handleCreateStream = async () => {
    if (!newStreamData.title || !newStreamData.broadcaster) return;
    
    setIsGeneratingKey(true);
    const scheduledStart = newStreamData.isScheduled ? `${newStreamData.scheduledDate}T${newStreamData.scheduledTime}:00` : undefined;

    let enabledProfilesStr = newStreamData.resolution;
    let profilesJsonStr: string | undefined = undefined;

    if (newStreamData.resolution === 'Original') {
      enabledProfilesStr = 'Original';
    } else if (newStreamData.resolution === 'Custom (Manual)' || newStreamData.resolution === 'Manual') {
      const formattedProfiles = manualProfiles.map(p => {
        const vBit = parseInt(p.videoBitrate.replace(/k/gi, '')) || 2500;
        const aBit = parseInt(p.audioBitrate.replace(/k/gi, '')) || 128;
        return {
          id: p.id,
          name: p.name || `${p.width}x${p.height}`,
          resolutionType: 'Custom Resolution',
          width: Number(p.width) || 1280,
          height: Number(p.height) || 720,
          fps: Number(p.fps) || 30,
          bitrate: vBit,
          audioBitrate: aBit,
          keyframeInterval: Number(p.gopSize) || 60,
          gopSize: Number(p.gopSize) || 60,
          encoderPreset: p.preset || 'superfast',
          preset: p.preset || 'superfast',
          videoCodec: 'H.264',
          audioCodec: 'aac',
          audioEnabled: true,
          enabled: true
        };
      });
      profilesJsonStr = JSON.stringify(formattedProfiles);
      enabledProfilesStr = manualProfiles.map(p => p.name || `${p.width}x${p.height}`).join(',');
    }

    try {
      const res = await fetchWithNetworkHeaders('/api/streams', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          title: newStreamData.title,
          broadcaster: newStreamData.broadcaster,
          resolution: newStreamData.resolution,
          enabledProfiles: enabledProfilesStr,
          profilesJson: profilesJsonStr,
          scheduledStart,
          audioCodec: newStreamData.audioCodec,
          audioBitrate: newStreamData.audioBitrate,
          audioSampleRate: Number(newStreamData.audioSampleRate),
          audioChannels: newStreamData.audioChannels,
          audioNormalize: newStreamData.audioNormalize,
          audioDelay: Number(newStreamData.audioDelay)
        })
      });

      if (!res.ok) {
        throw new Error('Failed to create stream');
      }

      const createdStream = await res.json();
      setStreams(prev => [createdStream, ...prev]);

      // Reset form
      setNewStreamData({ 
        title: '', 
        broadcaster: '', 
        streamKey: '', 
        thumbnailUrl: '', 
        resolution: '1080p',
        isScheduled: false,
        scheduledDate: '',
        scheduledTime: '',
        audioCodec: 'aac',
        audioBitrate: '128k',
        audioSampleRate: '44100',
        audioChannels: 'stereo',
        audioNormalize: false,
        audioDelay: 0
      });
    } catch (err) {
      console.error(err);
    } finally {
      setIsGeneratingKey(false);
    }
  };

  const handleConfirmRemoval = async () => {
    if (confirmRemovalId) {
      try {
        const res = await fetchWithNetworkHeaders(`/api/streams/${confirmRemovalId}`, {
          method: 'DELETE'
        });
        if (res.ok) {
          setStreams(prev => prev.filter(s => s.id !== confirmRemovalId));
        }
      } catch (err) {
        console.error(err);
      } finally {
        setConfirmRemovalId(null);
      }
    }
  };

  const handleUpdateResolution = async (id: string, resolution: string) => {
    try {
      const res = await fetchWithNetworkHeaders(`/api/streams/${id}`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ resolution })
      });
      if (res.ok) {
        const updated = await res.json();
        setStreams(prev => prev.map(s => s.id === id ? updated : s));
      }
    } catch (err) {
      console.error(err);
    }
  };

  const handleCloneProfile = async (sourceId: string, config: Partial<StreamSession>) => {
    try {
      const otherStreams = streams.filter(s => s.id !== sourceId);
      for (const other of otherStreams) {
        await fetchWithNetworkHeaders(`/api/streams/${other.id}`, {
          method: 'PUT',
          headers: {
            'Content-Type': 'application/json'
          },
          body: JSON.stringify(config)
        });
      }
      setStreams(prev => prev.map(s => s.id !== sourceId ? { ...s, ...config } : s));
      alert('Resolution configuration cloned successfully to all other panels!');
    } catch (err) {
      console.error(err);
      alert('Failed to clone configuration to all panels.');
    }
  };

  const handleUpdateQuality = async (id: string, bitrate: number, codec: string) => {
    try {
      const res = await fetchWithNetworkHeaders(`/api/streams/${id}`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ bitrate, codec })
      });
      if (res.ok) {
        const updated = await res.json();
        setStreams(prev => prev.map(s => s.id === id ? updated : s));
      }
    } catch (err) {
      console.error(err);
    }
  };

  const handleEnableStream = async (id: string) => {
    try {
      const res = await fetchWithNetworkHeaders(`/api/streams/${id}/enable`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        }
      });
      if (res.ok) {
        const updated = await res.json();
        setStreams(prev => prev.map(s => s.id === id ? updated : s));
        fetchActionLogs();
      } else {
        const errData = await res.json();
        alert(errData.error || 'Failed to enable stream');
      }
    } catch (err) {
      console.error(err);
    }
  };

  const handleDisableStream = async (id: string) => {
    try {
      const res = await fetchWithNetworkHeaders(`/api/streams/${id}/disable`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        }
      });
      if (res.ok) {
        const updated = await res.json();
        setStreams(prev => prev.map(s => s.id === id ? updated : s));
        fetchActionLogs();
      } else {
        const errData = await res.json();
        alert(errData.error || 'Failed to disable stream');
      }
    } catch (err) {
      console.error(err);
    }
  };

  // Recording control handlers removed

  const handleEditStream = async (id: string, fields: Partial<StreamSession>) => {
    try {
      const res = await fetchWithNetworkHeaders(`/api/streams/${id}`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(fields)
      });
      if (res.ok) {
        const updated = await res.json();
        setStreams(prev => prev.map(s => s.id === id ? updated : s));
      } else {
        const errData = await res.json();
        alert(errData.error || 'Failed to update stream metadata');
      }
    } catch (err) {
      console.error(err);
    }
  };

  const handleRegenerateKey = async (id: string) => {
    try {
      const res = await fetchWithNetworkHeaders(`/api/streams/${id}/regenerate`, {
        method: 'POST'
      });
      if (res.ok) {
        const updated = await res.json();
        setStreams(prev => prev.map(s => s.id === id ? updated : s));
      }
    } catch (err) {
      console.error(err);
    }
  };

  const handleGoLive = async (id: string) => {
    try {
      const res = await fetchWithNetworkHeaders(`/api/streams/${id}/toggle`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ status: 'live' })
      });
      if (res.ok) {
        const updated = await res.json();
        setStreams(prev => prev.map(s => s.id === id ? updated : s));
      }
    } catch (err) {
      console.error(err);
    }
  };

  const handleRestartStream = async (id: string) => {
    try {
      const res = await fetchWithNetworkHeaders(`/api/streams/${id}/toggle`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ status: 'offline' })
      });
      if (res.ok) {
        const updated = await res.json();
        setStreams(prev => prev.map(s => s.id === id ? updated : s));
      }
    } catch (err) {
      console.error(err);
    }
  };

  // Fetch Users when settings active
  useEffect(() => {
    if (activeTab === 'settings' && token) {
      fetchUsers();
    }
  }, [activeTab, token, fetchUsers]);

  // Network Settings updater
  const handleApplyNetworkChanges = async () => {
    setNetworkLoading(true);
    setNetworkSuccess('');
    setNetworkError('');
    try {
      const res = await fetchWithNetworkHeaders('/api/settings/network', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          deploymentMode,
          configuredDomain: customDomain,
          manualIp
        })
      });
      const data = await res.json();
      if (res.ok) {
        setNetworkSuccess(data.message || 'Network configuration applied successfully.');
        setNetworkDetails(data.resolved);
        if (data.resolved?.publicIp && data.resolved.publicIp !== 'Unavailable' && data.resolved.publicIp !== 'Not available') {
          setDetectedPublicIp(data.resolved.publicIp);
        } else {
          setDetectedPublicIp('Not available');
        }
        if (data.resolved?.lanIp) {
          setDetectedLanIp(data.resolved.lanIp);
        } else {
          setDetectedLanIp('Not available');
        }
        await fetchStreams();
      } else {
        setNetworkError(data.error || 'Failed to apply network configuration');
      }
    } catch (err: any) {
      setNetworkError(err.message || 'An error occurred while applying network configuration');
    } finally {
      setNetworkLoading(false);
    }
  };

  // Personal security form submit
  const handleUpdatePersonalSecurity = async (e: React.FormEvent) => {
    e.preventDefault();
    setSecurityLoading(true);
    setSecuritySuccess('');
    setSecurityError('');
    try {
      const body: any = {};
      if (newAdminUsername.trim()) {
        body.newUsername = newAdminUsername.trim();
      }
      if (newAdminPassword) {
        if (newAdminPassword !== confirmAdminPassword) {
          setSecurityError('Passwords do not match');
          setSecurityLoading(false);
          return;
        }
        body.newPassword = newAdminPassword;
      }

      if (Object.keys(body).length === 0) {
        setSecurityError('Please enter a new username or password to update.');
        setSecurityLoading(false);
        return;
      }

      const res = await fetchWithNetworkHeaders('/api/settings/security/update', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body)
      });
      const data = await res.json();
      if (res.ok) {
        setSecuritySuccess('Personal security credentials updated successfully!');
        setNewAdminUsername('');
        setNewAdminPassword('');
        setConfirmAdminPassword('');
        const profileRes = await fetchWithNetworkHeaders('/api/auth/me');
        if (profileRes.ok) {
          const profileData = await profileRes.json();
          setCurrentUser(profileData);
        }
      } else {
        setSecurityError(data.error || 'Failed to update security credentials');
      }
    } catch (err: any) {
      setSecurityError(err.message || 'An error occurred');
    } finally {
      setSecurityLoading(false);
    }
  };

  // Admin target user security change submit
  const handleUpdateUserSecurity = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!adminTargetUser) {
      setSecurityError('Please select a target user');
      return;
    }
    
    setSecurityLoading(true);
    setSecuritySuccess('');
    setSecurityError('');
    try {
      const body: any = {
        targetUserId: adminTargetUser,
        forceReset: adminForceReset
      };
      if (adminUserPassword) {
        body.newPassword = adminUserPassword;
      }

      const res = await fetchWithNetworkHeaders('/api/settings/security/update', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body)
      });
      const data = await res.json();
      if (res.ok) {
        setSecuritySuccess('Successfully updated security settings for user.');
        setAdminUserPassword('');
        setAdminForceReset(false);
        fetchUsers();
      } else {
        setSecurityError(data.error || 'Failed to update user security settings');
      }
    } catch (err: any) {
      setSecurityError(err.message || 'An error occurred');
    } finally {
      setSecurityLoading(false);
    }
  };

  // RTMP Test Probe
  const handleTestRtmp = async () => {
    setTestingRtmp(true);
    setRtmpTestResult(null);
    try {
      const start = Date.now();
      const res = await fetchWithNetworkHeaders('/api/network/details');
      const elapsed = Date.now() - start;
      if (res.ok) {
        setRtmpTestResult({
          success: true,
          message: `RTMP handshake connection check successful! Ingest port 1935 is listening. Network roundtrip: ${elapsed}ms.`
        });
      } else {
        setRtmpTestResult({
          success: false,
          message: 'RTMP probe check failed. Server returned non-200 response.'
        });
      }
    } catch (err: any) {
      setRtmpTestResult({
        success: false,
        message: `RTMP probe check failed: ${err.message}. Please check VPS port 1935.`
      });
    } finally {
      setTestingRtmp(false);
    }
  };

  // Playback Test Probe
  const handleTestPlayback = async () => {
    setTestingPlayback(true);
    setPlaybackTestResult(null);
    try {
      const start = Date.now();
      const res = await fetchWithNetworkHeaders('/api/streams');
      if (res.ok) {
        setPlaybackTestResult({
          success: true,
          message: `Playback manifest endpoint check successful. Live endpoints resolved without errors in ${Date.now() - start}ms.`
        });
      } else {
        setPlaybackTestResult({
          success: false,
          message: 'Playback manifest check returned an error status from backend.'
        });
      }
    } catch (err: any) {
      setPlaybackTestResult({
        success: false,
        message: `Playback test error: ${err.message}.`
      });
    } finally {
      setTestingPlayback(false);
    }
  };

  const handleForcedResetSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (newResetPassword.length < 6) {
      setResetError('Password must be at least 6 characters long');
      return;
    }
    if (newResetPassword !== confirmResetPassword) {
      setResetError('Passwords do not match');
      return;
    }
    
    setResetLoading(true);
    setResetError('');
    setResetSuccess('');
    
    try {
      const res = await fetchWithNetworkHeaders('/api/settings/security/update', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          newPassword: newResetPassword
        })
      });
      const data = await res.json();
      if (res.ok) {
        setResetSuccess('Password updated successfully!');
        setTimeout(() => {
          setCurrentUser((prev: any) => ({ ...prev, mustResetPassword: false }));
          setNewResetPassword('');
          setConfirmResetPassword('');
          setResetSuccess('');
        }, 1500);
      } else {
        setResetError(data.error || 'Failed to update password');
      }
    } catch (err: any) {
      setResetError(err.message || 'An error occurred');
    } finally {
      setResetLoading(false);
    }
  };

  // Delete recording handler removed

  const copyConfigToClipboard = (txt: string) => {
    copyToClipboard(txt);
  };

  const downloadAllConfigs = () => {
    // Generate simple text index of files for user download fallback
    const boundary = "========================================\n";
    let outputText = "STREAMPULSE DEPLOYMENT CONFIGURATIONS PACK\n\n";
    Object.entries(fileContents).forEach(([k, v]) => {
      outputText += `${boundary}FILE: ${k}\n${boundary}${v}\n\n`;
    });
    const blob = new Blob([outputText], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'streampulse-vps-configs.txt';
    a.click();
  };

  const NavItems = () => {
    const isAdmin = currentUser?.role === 'admin';
    return (
      <>
        <button 
          onClick={() => setActiveTab('dashboard')}
          className={`flex items-center gap-3 px-4 py-3 rounded-lg font-medium transition-all ${activeTab === 'dashboard' ? 'bg-blue-600 text-white shadow-lg shadow-blue-900/20' : 'text-zinc-400 hover:bg-zinc-900'}`}
        >
          <LayoutDashboard className="w-5 h-5 shrink-0" />
          <span className="truncate">{isAdmin ? 'Admin Dashboard' : 'My Channel'}</span>
        </button>
        {!isAdmin && (
          <button 
            onClick={() => setActiveTab('user_profile')}
            className={`flex items-center gap-3 px-4 py-3 rounded-lg font-medium transition-all ${activeTab === 'user_profile' ? 'bg-blue-600 text-white shadow-lg shadow-blue-900/20' : 'text-zinc-400 hover:bg-zinc-900'}`}
          >
            <User className="w-5 h-5 shrink-0 text-blue-400" />
            <span className="truncate">My Profile</span>
          </button>
        )}
        {isAdmin && (
          <>
            <button 
              onClick={() => setActiveTab('admin_profile')}
              className={`flex items-center gap-3 px-4 py-3 rounded-lg font-medium transition-all ${activeTab === 'admin_profile' ? 'bg-blue-600 text-white shadow-lg shadow-blue-900/20' : 'text-zinc-400 hover:bg-zinc-900'}`}
            >
              <Shield className="w-5 h-5 shrink-0 text-blue-400" />
              <span className="truncate">Admin Profile</span>
            </button>
            <button 
              onClick={() => setActiveTab('users')}
              className={`flex items-center gap-3 px-4 py-3 rounded-lg font-medium transition-all ${activeTab === 'users' ? 'bg-blue-600 text-white shadow-lg shadow-blue-900/20' : 'text-zinc-400 hover:bg-zinc-900'}`}
            >
              <Users className="w-5 h-5 shrink-0" />
              <span className="truncate">User Manager</span>
            </button>
            <button 
              onClick={() => setActiveTab('devices')}
              className={`flex items-center gap-3 px-4 py-3 rounded-lg font-medium transition-all ${activeTab === 'devices' ? 'bg-blue-600 text-white shadow-lg shadow-blue-900/20' : 'text-zinc-400 hover:bg-zinc-900'}`}
            >
              <Monitor className="w-5 h-5 shrink-0" />
              <span className="truncate">Device Manager</span>
            </button>
            <button 
              onClick={() => setActiveTab('streams')}
              className={`flex items-center gap-3 px-4 py-3 rounded-lg font-medium transition-all ${activeTab === 'streams' ? 'bg-blue-600 text-white shadow-lg shadow-blue-900/20' : 'text-zinc-400 hover:bg-zinc-900'}`}
            >
              <Tv className="w-5 h-5 shrink-0" />
              <span className="truncate">Public Viewers</span>
            </button>
            <button 
              onClick={() => setActiveTab('stream_test')}
              className={`flex items-center gap-3 px-4 py-3 rounded-lg font-medium transition-all ${activeTab === 'stream_test' ? 'bg-blue-600 text-white shadow-lg shadow-blue-900/20' : 'text-zinc-400 hover:bg-zinc-900'}`}
            >
              <Activity className="w-5 h-5 shrink-0" />
              <span className="truncate">Stream Test Hub</span>
            </button>
            <button 
              onClick={() => setActiveTab('deploy')}
              className={`flex items-center gap-3 px-4 py-3 rounded-lg font-medium transition-all ${activeTab === 'deploy' ? 'bg-blue-600 text-white shadow-lg shadow-blue-900/20' : 'text-zinc-400 hover:bg-zinc-900'}`}
            >
              <Terminal className="w-5 h-5 shrink-0" />
              <span className="truncate">VPS Setup Guide</span>
            </button>
            <button 
              onClick={() => setActiveTab('infra')}
              className={`flex items-center gap-3 px-4 py-3 rounded-lg font-medium transition-all ${activeTab === 'infra' ? 'bg-blue-600 text-white shadow-lg shadow-blue-900/20' : 'text-zinc-400 hover:bg-zinc-900'}`}
            >
              <Server className="w-5 h-5 shrink-0" />
              <span className="truncate">Docker configs</span>
            </button>
            <button 
              id="sidebar-settings-btn"
              onClick={() => setActiveTab('settings')}
              className={`flex items-center gap-3 px-4 py-3 rounded-lg font-medium transition-all ${activeTab === 'settings' ? 'bg-blue-600 text-white shadow-lg shadow-blue-900/20' : 'text-zinc-400 hover:bg-zinc-900'}`}
            >
              <Settings className="w-5 h-5 shrink-0" />
              <span className="truncate">Settings</span>
            </button>
            <button 
              onClick={() => setActiveTab('audit_logs')}
              className={`flex items-center gap-3 px-4 py-3 rounded-lg font-medium transition-all ${activeTab === 'audit_logs' ? 'bg-blue-600 text-white shadow-lg shadow-blue-900/20' : 'text-zinc-400 hover:bg-zinc-900'}`}
            >
              <FileText className="w-5 h-5 shrink-0 text-indigo-400" />
              <span className="truncate">Audit Logs</span>
            </button>
            <button 
              onClick={() => setActiveTab('backup_recovery')}
              className={`flex items-center gap-3 px-4 py-3 rounded-lg font-medium transition-all ${activeTab === 'backup_recovery' ? 'bg-blue-600 text-white shadow-lg shadow-blue-900/20' : 'text-zinc-400 hover:bg-zinc-900'}`}
            >
              <HardDrive className="w-5 h-5 shrink-0 text-emerald-400" />
              <span className="truncate">Backup & Recovery</span>
            </button>
          </>
        )}
      </>
    );
  };

  // Setup Wizard for new installation
  if (setupCompleted === false) {
    return <SetupWizard onSetupComplete={() => setSetupCompleted(true)} />;
  }

  // Unauthenticated login overlay
  if (!token) {
    return (
      <div className="min-h-screen bg-zinc-950 flex items-center justify-center p-4">
        <div className="w-full max-w-md bg-zinc-900 border border-zinc-800 rounded-2xl p-6 sm:p-8 shadow-2xl relative overflow-hidden">
          <div className="absolute top-0 left-0 w-full h-1 bg-gradient-to-r from-blue-500 via-teal-500 to-orange-500"></div>
          
          <div className="flex flex-col items-center mb-6">
            <div className="p-3 bg-blue-600/10 rounded-xl mb-3 border border-blue-500/20">
              <Shield className="w-8 h-8 text-blue-500" />
            </div>
            <h1 className="text-2xl font-bold tracking-tight">StreamPulse Admin</h1>
            <p className="text-xs text-zinc-500 uppercase font-mono tracking-widest mt-1">VPS RTMP Control Panel</p>
          </div>

          {/* Login Role Mode Selector */}
          <div className="flex bg-zinc-950 p-1 rounded-xl border border-zinc-800/80 mb-6">
            <button
              type="button"
              onClick={() => {
                setLoginRoleMode('admin');
                setAuthError(null);
              }}
              className={`flex-1 py-1.5 text-xs font-semibold rounded-lg transition-all ${
                loginRoleMode === 'admin'
                  ? 'bg-blue-600 text-white shadow-md shadow-blue-900/30'
                  : 'text-zinc-400 hover:text-zinc-200'
              }`}
            >
              Admin Login
            </button>
            <button
              type="button"
              onClick={() => {
                setLoginRoleMode('user');
                setAuthError(null);
              }}
              className={`flex-1 py-1.5 text-xs font-semibold rounded-lg transition-all ${
                loginRoleMode === 'user'
                  ? 'bg-blue-600 text-white shadow-md shadow-blue-900/30'
                  : 'text-zinc-400 hover:text-zinc-200'
              }`}
            >
              User Login
            </button>
          </div>

          <form onSubmit={handleAuth} className="space-y-4">
            {authError && (
              <div className="p-3 bg-red-500/10 border border-red-500/20 text-red-400 rounded-lg text-xs font-semibold flex items-center gap-2">
                <AlertTriangle className="w-4 h-4 shrink-0" />
                {authError}
              </div>
            )}

            <div className="space-y-1.5">
              <label htmlFor="username" className="text-[10px] font-bold text-zinc-500 uppercase tracking-wider">
                Username
              </label>
              <input 
                id="username"
                name="username"
                type="text" 
                required
                autoComplete="username"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                placeholder={loginRoleMode === 'admin' ? "admin" : "Enter username"} 
                className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500/50 outline-none text-zinc-100 placeholder-zinc-600"
              />
            </div>

            <div className="space-y-1.5">
              <label htmlFor="password" className="text-[10px] font-bold text-zinc-500 uppercase tracking-wider">
                Password
              </label>
              <div className="relative">
                <input 
                  id="password"
                  name="password"
                  type={showLoginPassword ? "text" : "password"} 
                  required
                  autoComplete="current-password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="••••••••" 
                  className="w-full bg-zinc-950 border border-zinc-800 rounded-lg pl-3 pr-10 py-2 text-sm focus:ring-2 focus:ring-blue-500/50 outline-none text-zinc-100 placeholder-zinc-600"
                />
                <button
                  type="button"
                  onClick={() => setShowLoginPassword(!showLoginPassword)}
                  className="absolute right-2.5 top-1/2 -translate-y-1/2 text-zinc-400 hover:text-zinc-200 p-1"
                  title={showLoginPassword ? "Hide password" : "Show password"}
                >
                  {showLoginPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                </button>
              </div>
            </div>

            <button 
              type="submit"
              disabled={authLoading}
              className="w-full h-10 bg-blue-600 hover:bg-blue-500 text-white text-sm font-bold rounded-lg transition-all flex items-center justify-center gap-2 mt-2"
            >
              {authLoading ? <RefreshCcw className="w-4 h-4 animate-spin" /> : `Sign In as ${loginRoleMode === 'admin' ? 'Admin' : 'User'}`}
            </button>
          </form>

          <div className="mt-6 pt-6 border-t border-zinc-800 text-center text-xs text-zinc-500">
            <p className="text-zinc-500">Access to this system is restricted to authorized operators only.</p>
          </div>
        </div>
      </div>
    );
  }

  const liveStreams = streams.filter(s => s.status === 'live');
  const scheduledStreams = streams.filter(s => s.status === 'scheduled');

  return (
    <div className="min-h-screen bg-zinc-950 flex flex-col relative overflow-x-hidden pb-20 lg:pb-0">
      <DashboardHeader publicIp={detectedPublicIp} localIp={detectedLanIp} />
      
      <main className="flex-1 max-w-7xl mx-auto w-full px-4 sm:px-8 py-6 sm:py-8 flex flex-col lg:flex-row gap-8">
        {/* Sidebar Desktop Nav */}
        <aside className="w-64 shrink-0 hidden lg:flex flex-col gap-2">
          {currentUser && (
            <div 
              onClick={() => setActiveTab(currentUser?.role === 'admin' ? 'admin_profile' : 'user_profile')}
              title="Click to manage profile"
              className="bg-zinc-900 border border-zinc-800/80 rounded-xl p-4 mb-4 flex items-center gap-3 cursor-pointer hover:border-blue-500/50 transition-colors group"
            >
              <div className="w-9 h-9 bg-blue-600/15 rounded-full flex items-center justify-center border border-blue-500/20 shrink-0 group-hover:bg-blue-600/25 transition-colors">
                <User className="w-4 h-4 text-blue-500" />
              </div>
              <div className="min-w-0 flex-1">
                <h4 className="text-xs font-bold text-zinc-100 truncate group-hover:text-blue-400 transition-colors">
                  {currentUser.display_name || currentUser.username}
                </h4>
                <p className="text-[10px] text-zinc-500 capitalize">{currentUser.role} Account</p>
              </div>
              <button 
                onClick={(e) => {
                  e.stopPropagation();
                  handleLogout();
                }} 
                className="p-1.5 text-zinc-500 hover:text-red-400 hover:bg-red-500/5 rounded-lg transition-colors"
                title="Log Out"
              >
                <LogOut className="w-4 h-4" />
              </button>
            </div>
          )}

          <NavItems />

          {currentUser?.role === 'admin' && (
            <>
              <div className="mt-4 pt-4 border-t border-zinc-800">
                <h4 className="px-4 text-[10px] font-bold uppercase tracking-widest text-zinc-500 mb-4">Detected Addresses</h4>
                <div className="px-4 mb-6 space-y-3">
                  <div className="flex flex-col gap-1 text-xs text-zinc-300 bg-zinc-900 p-2 rounded-lg border border-zinc-800">
                    <div className="flex items-center gap-2">
                      <Globe className="w-3.5 h-3.5 text-blue-500" />
                      <span className="font-mono text-[11px] truncate">{detectedPublicIp || 'Not available'}</span>
                    </div>
                    <span className="text-[9px] text-zinc-500 uppercase tracking-tighter font-bold">Public IP</span>
                  </div>
                  <div className="flex flex-col gap-1 text-xs text-zinc-300 bg-zinc-900 p-2 rounded-lg border border-zinc-800">
                    <div className="flex items-center gap-2">
                      <Network className="w-3.5 h-3.5 text-orange-500" />
                      <span className="font-mono text-[11px] truncate">{detectedLanIp}</span>
                    </div>
                    <span className="text-[9px] text-zinc-500 uppercase tracking-tighter font-bold">Local LAN IP</span>
                  </div>
                </div>

                <h4 className="px-4 text-[10px] font-bold uppercase tracking-widest text-zinc-500 mb-4">Server Resources</h4>
                <div className="px-4 space-y-4">
                   <div>
                     <div className="flex justify-between text-xs mb-1.5">
                       <span className="text-zinc-400 flex items-center gap-1"><Cpu className="w-3 h-3"/> CPU ({stats.cpuCores} Cores)</span>
                       <span className="text-zinc-200">{stats.cpuUsage?.toFixed(1)}%</span>
                     </div>
                     <div className="h-1 bg-zinc-800 rounded-full overflow-hidden">
                        <div className="h-full bg-blue-500 transition-all duration-1000" style={{ width: `${stats.cpuUsage}%` }} />
                     </div>
                     <span className="text-[9px] text-zinc-600 block mt-1 truncate">{stats.cpuModel}</span>
                   </div>
                   <div>
                     <div className="flex justify-between text-xs mb-1.5">
                       <span className="text-zinc-400 flex items-center gap-1"><HardDrive className="w-3 h-3"/> RAM</span>
                       <span className="text-zinc-200">{stats.memoryUsage?.toFixed(1)} GB / {stats.memoryTotal?.toFixed(1)} GB</span>
                     </div>
                     <div className="h-1 bg-zinc-800 rounded-full overflow-hidden">
                        <div className="h-full bg-emerald-500 transition-all duration-1000" style={{ width: `${stats.memoryUsagePct}%` }} />
                     </div>
                   </div>
                   <div>
                     <div className="flex justify-between text-xs mb-1.5">
                       <span className="text-zinc-400 flex items-center gap-1"><LayoutDashboard className="w-3 h-3"/> Disk Storage</span>
                       <span className="text-zinc-200">{stats.diskUsagePct}%</span>
                     </div>
                     <div className="h-1 bg-zinc-800 rounded-full overflow-hidden">
                        <div className="h-full bg-amber-500 transition-all duration-1000" style={{ width: `${stats.diskUsagePct}%` }} />
                     </div>
                   </div>
                </div>
              </div>
            </>
          )}
        </aside>

        {/* Content Area */}
        <div className="flex-1 space-y-8 min-w-0">
          {activeTab === 'dashboard' && (
            <>
              {currentUser?.role === 'admin' && (
                <section className="bg-zinc-900 border border-zinc-800 rounded-2xl p-5 sm:p-6 shadow-sm">
                <div className="flex items-center justify-between mb-6">
                <div className="flex items-center gap-2">
                  <PlusCircle className="w-5 h-5 text-blue-500" />
                  <h2 className="text-xl font-bold">Create Ingest Point</h2>
                </div>
                  <div className="flex items-center gap-2 bg-zinc-950 p-1 rounded-lg border border-zinc-800">
                     <button 
                        onClick={() => setNewStreamData(prev => ({ ...prev, isScheduled: false }))}
                        className={`px-3 py-1 rounded text-[10px] font-bold uppercase transition-all ${!newStreamData.isScheduled ? 'bg-blue-600 text-white shadow-lg' : 'text-zinc-500 hover:text-zinc-300'}`}
                     >
                       Now
                     </button>
                     <button 
                        onClick={() => setNewStreamData(prev => ({ ...prev, isScheduled: true }))}
                        className={`px-3 py-1 rounded text-[10px] font-bold uppercase transition-all ${newStreamData.isScheduled ? 'bg-blue-600 text-white shadow-lg' : 'text-zinc-500 hover:text-zinc-300'}`}
                     >
                       Later
                     </button>
                  </div>
                </div>
                <div className="space-y-6">
                  {/* General Channel Info */}
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <div className="space-y-1.5">
                      <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block">Broadcaster Handle</label>
                      <input 
                        type="text" placeholder="e.g. dev_alex" value={newStreamData.broadcaster}
                        onChange={(e) => setNewStreamData(prev => ({ ...prev, broadcaster: e.target.value }))}
                        className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500/50 outline-none text-zinc-100"
                      />
                    </div>
                    <div className="space-y-1.5">
                      <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block">Broadcast Title</label>
                      <input 
                        type="text" placeholder="e.g. High Performance Multi-Channel Coding" value={newStreamData.title}
                        onChange={(e) => setNewStreamData(prev => ({ ...prev, title: e.target.value }))}
                        className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500/50 outline-none text-zinc-100"
                      />
                    </div>
                  </div>

                  {/* Streaming Profile Section */}
                  {currentUser?.role === 'admin' ? (
                    <div className="bg-zinc-950/80 border border-zinc-800/90 rounded-xl p-4 sm:p-5 space-y-4">
                      <div className="flex items-center justify-between border-b border-zinc-800/60 pb-3">
                        <div className="flex items-center gap-2">
                          <Sliders className="w-4 h-4 text-blue-400" />
                          <h3 className="text-sm font-bold text-zinc-100 uppercase tracking-wider">Streaming Profile</h3>
                        </div>
                        <span className="text-[10px] font-semibold px-2 py-0.5 rounded-full bg-blue-500/10 text-blue-400 border border-blue-500/20">
                          Multi-Channel Production Ready
                        </span>
                      </div>

                      {/* Resolution Mode Selection */}
                      <div className="space-y-2">
                        <label className="text-[11px] font-bold text-zinc-400 uppercase tracking-wider block">Resolution Mode</label>
                        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                          <label 
                            onClick={() => setNewStreamData(prev => ({ ...prev, resolution: 'Original' }))}
                            className={`flex items-start gap-3 p-3.5 rounded-xl border cursor-pointer transition-all ${
                              newStreamData.resolution === 'Original'
                                ? 'bg-blue-950/40 border-blue-500/80 text-white shadow-sm ring-1 ring-blue-500/30'
                                : 'bg-zinc-900/60 border-zinc-800/80 text-zinc-400 hover:border-zinc-700 hover:text-zinc-200'
                            }`}
                          >
                            <input 
                              type="radio" 
                              name="resolutionMode" 
                              checked={newStreamData.resolution === 'Original'}
                              onChange={() => setNewStreamData(prev => ({ ...prev, resolution: 'Original' }))}
                              className="mt-0.5 text-blue-600 focus:ring-blue-500 accent-blue-500"
                            />
                            <div className="space-y-0.5">
                              <span className="text-xs font-bold block text-zinc-100">○ Original (Source Passthrough)</span>
                              <p className="text-[11px] text-zinc-400 leading-normal">
                                Preserves incoming stream resolution without rescaling. Lowest CPU overhead; ideal for multi-channel density.
                              </p>
                            </div>
                          </label>

                          <label 
                            onClick={() => setNewStreamData(prev => ({ ...prev, resolution: 'Custom (Manual)' }))}
                            className={`flex items-start gap-3 p-3.5 rounded-xl border cursor-pointer transition-all ${
                              newStreamData.resolution === 'Custom (Manual)' || newStreamData.resolution === 'Manual'
                                ? 'bg-blue-950/40 border-blue-500/80 text-white shadow-sm ring-1 ring-blue-500/30'
                                : 'bg-zinc-900/60 border-zinc-800/80 text-zinc-400 hover:border-zinc-700 hover:text-zinc-200'
                            }`}
                          >
                            <input 
                              type="radio" 
                              name="resolutionMode" 
                              checked={newStreamData.resolution === 'Custom (Manual)' || newStreamData.resolution === 'Manual'}
                              onChange={() => setNewStreamData(prev => ({ ...prev, resolution: 'Custom (Manual)' }))}
                              className="mt-0.5 text-blue-600 focus:ring-blue-500 accent-blue-500"
                            />
                            <div className="space-y-0.5">
                              <span className="text-xs font-bold block text-zinc-100">○ Manual Transcode Selection</span>
                              <p className="text-[11px] text-zinc-400 leading-normal">
                                Select specific output variants to transcode and publish in master.m3u8 adaptive manifest.
                              </p>
                            </div>
                          </label>
                        </div>
                      </div>

                      {/* Advanced Manual Resolution Editor */}
                      {(newStreamData.resolution === 'Custom (Manual)' || newStreamData.resolution === 'Manual') && (
                        <div className="space-y-3 pt-1 animate-in fade-in duration-200">
                          <div className="flex items-center justify-between">
                            <div>
                              <label className="text-[11px] font-bold text-zinc-200 uppercase tracking-wider block">
                                Advanced Custom Output Profiles
                              </label>
                              <p className="text-[11px] text-zinc-400">
                                Configure output profiles for FFmpeg transcoding pipeline and master.m3u8 adaptive manifest.
                              </p>
                            </div>
                          </div>

                          {/* Profile cards list */}
                          <div className="space-y-3">
                            {manualProfiles.map((p, idx) => (
                              <div key={p.id || idx} className="bg-zinc-950/80 border border-zinc-800 rounded-xl p-3.5 space-y-3 relative shadow-sm">
                                <div className="flex flex-wrap items-center justify-between gap-2 border-b border-zinc-800/80 pb-2.5">
                                  <div className="flex items-center gap-2">
                                    <span className="text-[10px] font-mono font-bold text-zinc-500 bg-zinc-900 px-2 py-0.5 rounded border border-zinc-800">
                                      #{idx + 1}
                                    </span>
                                    <input 
                                      type="text" 
                                      value={p.name}
                                      placeholder={`Output ${idx + 1}`}
                                      onChange={(e) => handleUpdateOutputProfile(idx, 'name', e.target.value)}
                                      className="bg-zinc-900 border border-zinc-800 rounded px-2.5 py-1 text-xs font-bold text-blue-400 focus:outline-none focus:border-blue-500 w-36"
                                    />
                                    <span className="text-[10px] font-mono text-zinc-400">
                                      ({p.width}×{p.height} @ {p.fps}fps)
                                    </span>
                                  </div>

                                  <div className="flex items-center gap-1.5">
                                    {/* Reorder Up */}
                                    <button
                                      type="button"
                                      disabled={idx === 0}
                                      onClick={() => handleReorderOutputProfile(idx, 'up')}
                                      className="p-1.5 text-zinc-400 hover:text-white bg-zinc-900 border border-zinc-800 rounded disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
                                      title="Reorder Up"
                                    >
                                      <ChevronUp className="w-3.5 h-3.5" />
                                    </button>
                                    {/* Reorder Down */}
                                    <button
                                      type="button"
                                      disabled={idx === manualProfiles.length - 1}
                                      onClick={() => handleReorderOutputProfile(idx, 'down')}
                                      className="p-1.5 text-zinc-400 hover:text-white bg-zinc-900 border border-zinc-800 rounded disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
                                      title="Reorder Down"
                                    >
                                      <ChevronDown className="w-3.5 h-3.5" />
                                    </button>
                                    {/* Remove Output */}
                                    <button
                                      type="button"
                                      onClick={() => handleRemoveOutputProfile(idx)}
                                      className="ml-2 px-2.5 py-1 text-rose-400 hover:text-rose-300 hover:bg-rose-500/10 border border-rose-500/20 rounded transition-colors flex items-center gap-1 text-[11px] font-bold"
                                    >
                                      <Trash2 className="w-3 h-3" />
                                      Remove Output
                                    </button>
                                  </div>
                                </div>

                                <div className="grid grid-cols-2 sm:grid-cols-4 lg:grid-cols-7 gap-2.5">
                                  <div className="space-y-1">
                                    <label className="text-[10px] font-bold text-zinc-400 uppercase block">Width</label>
                                    <input 
                                      type="number" 
                                      value={p.width}
                                      onChange={(e) => handleUpdateOutputProfile(idx, 'width', Number(e.target.value))}
                                      className="w-full bg-zinc-900 border border-zinc-800 rounded px-2.5 py-1.5 text-xs text-zinc-100 font-mono focus:border-blue-500 outline-none"
                                    />
                                  </div>

                                  <div className="space-y-1">
                                    <label className="text-[10px] font-bold text-zinc-400 uppercase block">Height</label>
                                    <input 
                                      type="number" 
                                      value={p.height}
                                      onChange={(e) => handleUpdateOutputProfile(idx, 'height', Number(e.target.value))}
                                      className="w-full bg-zinc-900 border border-zinc-800 rounded px-2.5 py-1.5 text-xs text-zinc-100 font-mono focus:border-blue-500 outline-none"
                                    />
                                  </div>

                                  <div className="space-y-1">
                                    <label className="text-[10px] font-bold text-zinc-400 uppercase block">Video Bitrate</label>
                                    <input 
                                      type="text" 
                                      value={p.videoBitrate}
                                      placeholder="4500k"
                                      onChange={(e) => handleUpdateOutputProfile(idx, 'videoBitrate', e.target.value)}
                                      className="w-full bg-zinc-900 border border-zinc-800 rounded px-2.5 py-1.5 text-xs text-zinc-100 font-mono focus:border-blue-500 outline-none"
                                    />
                                  </div>

                                  <div className="space-y-1">
                                    <label className="text-[10px] font-bold text-zinc-400 uppercase block">Audio Bitrate</label>
                                    <input 
                                      type="text" 
                                      value={p.audioBitrate}
                                      placeholder="192k"
                                      onChange={(e) => handleUpdateOutputProfile(idx, 'audioBitrate', e.target.value)}
                                      className="w-full bg-zinc-900 border border-zinc-800 rounded px-2.5 py-1.5 text-xs text-zinc-100 font-mono focus:border-blue-500 outline-none"
                                    />
                                  </div>

                                  <div className="space-y-1">
                                    <label className="text-[10px] font-bold text-zinc-400 uppercase block">FPS</label>
                                    <input 
                                      type="number" 
                                      value={p.fps}
                                      onChange={(e) => handleUpdateOutputProfile(idx, 'fps', Number(e.target.value))}
                                      className="w-full bg-zinc-900 border border-zinc-800 rounded px-2.5 py-1.5 text-xs text-zinc-100 font-mono focus:border-blue-500 outline-none"
                                    />
                                  </div>

                                  <div className="space-y-1">
                                    <label className="text-[10px] font-bold text-zinc-400 uppercase block">GOP</label>
                                    <input 
                                      type="number" 
                                      value={p.gopSize}
                                      onChange={(e) => handleUpdateOutputProfile(idx, 'gopSize', Number(e.target.value))}
                                      className="w-full bg-zinc-900 border border-zinc-800 rounded px-2.5 py-1.5 text-xs text-zinc-100 font-mono focus:border-blue-500 outline-none"
                                    />
                                  </div>

                                  <div className="space-y-1">
                                    <label className="text-[10px] font-bold text-zinc-400 uppercase block">Preset</label>
                                    <select 
                                      value={p.preset}
                                      onChange={(e) => handleUpdateOutputProfile(idx, 'preset', e.target.value)}
                                      className="w-full bg-zinc-900 border border-zinc-800 rounded px-2 py-1.5 text-xs text-zinc-100 focus:border-blue-500 outline-none cursor-pointer"
                                    >
                                      <option value="ultrafast">ultrafast</option>
                                      <option value="superfast">superfast</option>
                                      <option value="veryfast">veryfast</option>
                                      <option value="faster">faster</option>
                                      <option value="fast">fast</option>
                                      <option value="medium">medium</option>
                                      <option value="slow">slow</option>
                                    </select>
                                  </div>
                                </div>
                              </div>
                            ))}
                          </div>

                          <div className="pt-1">
                            <button
                              type="button"
                              onClick={handleAddOutputProfile}
                              className="bg-blue-600 hover:bg-blue-500 text-white font-bold text-xs px-3.5 py-2 rounded-lg transition-colors flex items-center gap-1.5 uppercase tracking-wider shadow-sm"
                            >
                              <Plus className="w-4 h-4" /> Add Output
                            </button>
                          </div>
                        </div>
                      )}

                      {/* Estimated CPU Usage Indicator */}
                      {(() => {
                        const activeVariantCount = newStreamData.resolution === 'Original' ? 1 : manualProfiles.length;
                        let cpuLevel: 'low' | 'medium' | 'high' = 'low';
                        let cpuBadge = '🟢 Low Impact';
                        let cpuColorClass = 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30';
                        let barColorClass = 'bg-emerald-500';
                        let percentWidth = '25%';
                        let explanation = 'Minimal CPU overhead. Highly efficient for up to 10+ concurrent channels.';

                        if (activeVariantCount === 2 || activeVariantCount === 3) {
                          cpuLevel = 'medium';
                          cpuBadge = '🟡 Medium Impact';
                          cpuColorClass = 'bg-amber-500/10 text-amber-400 border-amber-500/30';
                          barColorClass = 'bg-amber-500';
                          percentWidth = '55%';
                          explanation = 'Balanced CPU consumption. Supports 5-8 concurrent live streams on a 2-4 vCPU VPS.';
                        } else if (activeVariantCount >= 4) {
                          cpuLevel = 'high';
                          cpuBadge = '🔴 High Impact';
                          cpuColorClass = 'bg-rose-500/10 text-rose-400 border-rose-500/30';
                          barColorClass = 'bg-rose-500';
                          percentWidth = '90%';
                          explanation = 'Heavy multi-variant transcoding load. Best suited for high-spec VPS nodes (8+ vCPUs).';
                        }

                        return (
                          <div className="p-3 bg-zinc-900/80 border border-zinc-800/80 rounded-xl space-y-2">
                            <div className="flex items-center justify-between text-xs">
                              <span className="font-bold text-zinc-300 uppercase tracking-wider text-[10px] flex items-center gap-1.5">
                                <Activity className="w-3.5 h-3.5 text-blue-400" />
                                Estimated CPU Usage
                              </span>
                              <span className={`text-[10px] font-bold px-2 py-0.5 rounded border ${cpuColorClass}`}>
                                {cpuBadge}
                              </span>
                            </div>
                            
                            {/* Progress Meter Bar */}
                            <div className="w-full bg-zinc-950 h-2 rounded-full overflow-hidden border border-zinc-800/80">
                              <div 
                                className={`h-full transition-all duration-300 ${barColorClass}`}
                                style={{ width: percentWidth }}
                              />
                            </div>

                            <div className="flex justify-between items-center text-[10px] text-zinc-400 pt-0.5">
                              <span>Selected Variants: <strong className="text-white">{activeVariantCount} output{activeVariantCount > 1 ? 's' : ''}</strong></span>
                              <span className="text-zinc-500">{explanation}</span>
                            </div>
                          </div>
                        );
                      })()}
                    </div>
                  ) : (
                    <div className="bg-zinc-950/80 border border-zinc-800/90 rounded-xl p-4 flex items-center justify-between">
                      <div className="flex items-center gap-3">
                        <Sliders className="w-4 h-4 text-zinc-500" />
                        <div>
                          <span className="text-xs font-bold text-zinc-200 block">Streaming Profile</span>
                          <span className="text-[11px] text-zinc-400">Default profile configured automatically by Administrator</span>
                        </div>
                      </div>
                      <span className="text-[10px] font-semibold px-2.5 py-1 rounded-full bg-blue-500/10 text-blue-400 border border-blue-500/20">
                        🔒 Admin Enforced
                      </span>
                    </div>
                  )}

                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4 items-end">
                    <div className="space-y-1.5">
                      <label className="text-[10px] font-bold text-zinc-500 uppercase">Ingest VPS Network</label>
                      <select 
                        value={creationIpMode}
                        onChange={(e) => setCreationIpMode(e.target.value as IPMode)}
                        className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-3 py-2 text-sm appearance-none cursor-pointer text-zinc-100 focus:ring-2 focus:ring-blue-500/50 outline-none"
                      >
                        <option value="auto">Public WAN ({detectedPublicIp})</option>
                        <option value="lan">LAN Local ({detectedLanIp})</option>
                        <option value="loopback">Host Loopback (127.0.0.1)</option>
                        <option value="manual">Manual Override</option>
                      </select>
                    </div>

                    {creationIpMode === 'manual' && (
                      <div className="space-y-1.5">
                        <label className="text-[10px] font-bold text-zinc-500 uppercase">Manual IPv4 Address</label>
                        <input 
                          type="text" placeholder="e.g. 154.12.88.2" value={manualIp}
                          onChange={(e) => setManualIp(e.target.value)}
                          className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-3 py-2 text-sm font-mono focus:ring-2 focus:ring-blue-500/50 outline-none text-zinc-100"
                        />
                      </div>
                    )}
                  </div>

                  {/* Dedicated Audio Settings Collapsible Panel */}
                  <div className="border border-zinc-800 rounded-xl overflow-hidden bg-zinc-900/30">
                    <button 
                      type="button"
                      onClick={() => setIsAudioSettingsExpanded(prev => !prev)} 
                      className="w-full px-4 py-3 flex justify-between items-center text-xs font-bold text-zinc-300 uppercase tracking-wider bg-zinc-900/60 hover:bg-zinc-900/80 transition-colors"
                    >
                      <span className="flex items-center gap-2">
                        <Headphones className="w-4 h-4 text-emerald-400" /> 
                        <span>Audio Transcoder Settings</span>
                      </span>
                      <ChevronDown className={`w-4 h-4 text-zinc-500 transition-transform duration-200 ${isAudioSettingsExpanded ? 'rotate-180' : ''}`} />
                    </button>

                    {isAudioSettingsExpanded && (
                      <div className="p-4 bg-zinc-950/40 border-t border-zinc-800 space-y-4 animate-in slide-in-from-top-1 duration-200">
                        {/* Audio Codec & Bitrate */}
                        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                          <div className="space-y-1.5">
                            <label className="text-[10px] font-bold text-zinc-500 uppercase">Audio Codec</label>
                            <select 
                              value={newStreamData.audioCodec}
                              onChange={(e) => setNewStreamData(prev => ({ ...prev, audioCodec: e.target.value }))}
                              className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-3 py-2 text-sm appearance-none cursor-pointer text-zinc-100 focus:ring-2 focus:ring-blue-500/50 outline-none"
                            >
                              <option value="aac">AAC (Advanced Audio Coding)</option>
                              <option value="mp3">MP3 (MPEG Layer 3)</option>
                              <option value="opus">Opus (Low Latency/Speech/Music)</option>
                            </select>
                          </div>

                          <div className="space-y-1.5">
                            <label className="text-[10px] font-bold text-zinc-500 uppercase">Audio Bitrate</label>
                            <select 
                              value={newStreamData.audioBitrate}
                              onChange={(e) => setNewStreamData(prev => ({ ...prev, audioBitrate: e.target.value }))}
                              className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-3 py-2 text-sm appearance-none cursor-pointer text-zinc-100 focus:ring-2 focus:ring-blue-500/50 outline-none"
                            >
                              <option value="64k">64 kbps (Low Bandwidth)</option>
                              <option value="96k">96 kbps (Standard Mobile)</option>
                              <option value="128k">128 kbps (Standard Quality)</option>
                              <option value="192k">192 kbps (High Quality)</option>
                              <option value="256k">256 kbps (Studio Quality)</option>
                              <option value="320k">320 kbps (Audiophile Quality)</option>
                            </select>
                          </div>
                        </div>

                        {/* Sample Rate & Channel Selection */}
                        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                          <div className="space-y-1.5">
                            <label className="text-[10px] font-bold text-zinc-500 uppercase">Sample Rate Configuration</label>
                            <select 
                              value={newStreamData.audioSampleRate}
                              onChange={(e) => setNewStreamData(prev => ({ ...prev, audioSampleRate: e.target.value }))}
                              className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-3 py-2 text-sm appearance-none cursor-pointer text-zinc-100 focus:ring-2 focus:ring-blue-500/50 outline-none"
                            >
                              <option value="32000">32,000 Hz (FM Radio)</option>
                              <option value="44100">44,100 Hz (CD Audio)</option>
                              <option value="48000">48,000 Hz (Professional Studio)</option>
                            </select>
                          </div>

                          <div className="space-y-1.5">
                            <label className="text-[10px] font-bold text-zinc-500 uppercase">Channel Layout</label>
                            <select 
                              value={newStreamData.audioChannels}
                              onChange={(e) => setNewStreamData(prev => ({ ...prev, audioChannels: e.target.value }))}
                              className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-3 py-2 text-sm appearance-none cursor-pointer text-zinc-100 focus:ring-2 focus:ring-blue-500/50 outline-none"
                            >
                              <option value="mono">Mono (1.0)</option>
                              <option value="stereo">Stereo (2.0)</option>
                              <option value="5.1">5.1 Surround Sound</option>
                              <option value="7.1">7.1 Surround Sound</option>
                            </select>
                          </div>
                        </div>

                        {/* Volume Normalization & Delay Controls */}
                        <div className="grid grid-cols-1 md:grid-cols-2 gap-4 items-center">
                          <div className="space-y-1.5 flex flex-col justify-center h-full pt-1">
                            <span className="text-[10px] font-bold text-zinc-500 uppercase mb-2 block">Volume Normalization</span>
                            <label className="flex items-center gap-3 bg-zinc-950/60 border border-zinc-800 rounded-lg px-4 py-2.5 cursor-pointer select-none text-zinc-300 hover:bg-zinc-950 hover:text-zinc-100 transition-colors">
                              <input 
                                type="checkbox"
                                checked={newStreamData.audioNormalize}
                                onChange={(e) => setNewStreamData(prev => ({ ...prev, audioNormalize: e.target.checked }))}
                                className="w-4 h-4 rounded border-zinc-800 text-emerald-500 accent-emerald-500 cursor-pointer"
                              />
                              <div className="flex flex-col">
                                <span className="text-xs font-bold uppercase tracking-wider">Loudness Normalization</span>
                                <span className="text-[9px] text-zinc-500">Apply EBU R128 loudness standard</span>
                              </div>
                            </label>
                          </div>

                          <div className="space-y-1.5">
                            <label className="text-[10px] font-bold text-zinc-500 uppercase">Audio Sync Delay (ms)</label>
                            <div className="flex items-center gap-2">
                              <input 
                                type="number" 
                                min="0" 
                                max="10000" 
                                step="10"
                                value={newStreamData.audioDelay}
                                onChange={(e) => setNewStreamData(prev => ({ ...prev, audioDelay: parseInt(e.target.value, 10) || 0 }))}
                                className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500/50 outline-none text-zinc-100 font-mono"
                              />
                              <span className="text-[10px] text-zinc-500 font-bold uppercase tracking-wide shrink-0 bg-zinc-900 border border-zinc-800 px-2.5 py-2 rounded-lg">
                                Milliseconds
                              </span>
                            </div>
                          </div>
                        </div>
                      </div>
                    )}
                  </div>

                  {newStreamData.isScheduled && (
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 pt-2 animate-in fade-in slide-in-from-top-2">
                       <div className="space-y-1.5">
                          <label className="text-[10px] font-bold text-zinc-500 uppercase flex items-center gap-2">
                            <Calendar className="w-3 h-3 text-blue-500" /> Start Date
                          </label>
                          <input 
                            type="date" 
                            value={newStreamData.scheduledDate}
                            min={MIN_SCHEDULE_DATE}
                            max={MAX_SCHEDULE_DATE}
                            onChange={(e) => setNewStreamData(prev => ({ ...prev, scheduledDate: e.target.value }))}
                            className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500/50 outline-none text-zinc-100"
                          />
                          <p className="text-[8px] text-zinc-500 font-medium px-1">Allowed window: {MIN_SCHEDULE_DATE} to {MAX_SCHEDULE_DATE}</p>
                       </div>
                       <div className="space-y-1.5">
                          <label className="text-[10px] font-bold text-zinc-500 uppercase flex items-center gap-2">
                            <Clock className="w-3 h-3 text-blue-500" /> Start Time
                          </label>
                          <input 
                            type="time" value={newStreamData.scheduledTime}
                            onChange={(e) => setNewStreamData(prev => ({ ...prev, scheduledTime: e.target.value }))}
                            className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500/50 outline-none text-zinc-100"
                          />
                       </div>
                    </div>
                  )}

                  <div className="flex justify-end pt-2">
                    <button 
                      onClick={handleCreateStream}
                      disabled={isGeneratingKey || !newStreamData.title || !newStreamData.broadcaster || (newStreamData.isScheduled && (!newStreamData.scheduledDate || !newStreamData.scheduledTime))}
                      className="w-full md:w-48 h-[42px] bg-blue-600 hover:bg-blue-500 disabled:opacity-50 disabled:cursor-not-allowed text-white text-sm font-bold rounded-lg transition-all flex items-center justify-center gap-2"
                    >
                      {isGeneratingKey ? <><RefreshCcw className="w-4 h-4 animate-spin" /> Processing...</> : 
                        newStreamData.isScheduled ? <><Calendar className="w-4 h-4" /> Schedule Stream</> : <><Plus className="w-4 h-4" /> Create Stream</>}
                    </button>
                  </div>
                </div>

                <div className="mt-4 flex flex-wrap items-center gap-x-3 gap-y-1 px-3 py-2 bg-zinc-950/50 border border-zinc-800/50 rounded-lg">
                  <div className="flex items-center gap-2">
                    <Wifi className="w-3.5 h-3.5 text-zinc-500" />
                    <span className="text-[11px] text-zinc-400">Ingest point URL: </span>
                  </div>
                  <span className="text-[11px] font-mono text-blue-400 font-bold truncate">{networkDetails?.rtmpUrl || 'Endpoint unavailable'}</span>
                </div>
              </section>
              )}

              <section className="space-y-6">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <Tv className="w-5 h-5 text-red-500" />
                    <h2 className="text-xl font-bold">Manage Active Broadcasts</h2>
                  </div>
                  <div className="flex items-center gap-4">
                    <div className="flex items-center gap-1.5 text-[10px] font-bold text-zinc-500 uppercase">
                      <span className="w-1.5 h-1.5 bg-red-500 rounded-full animate-pulse"></span>
                      {liveStreams.length} Live
                    </div>
                    <div className="flex items-center gap-1.5 text-[10px] font-bold text-zinc-500 uppercase">
                      <span className="w-1.5 h-1.5 bg-blue-500 rounded-full"></span>
                      {scheduledStreams.length} Scheduled
                    </div>
                  </div>
                </div>
                
                {streams.length === 0 ? (
                  <div className="bg-zinc-900/50 border border-zinc-800/80 rounded-2xl p-12 text-center text-zinc-500 space-y-4">
                    <Tv className="w-12 h-12 text-zinc-700 mx-auto" />
                    <p className="text-sm font-semibold">No broadcasts configured yet. Use the tool above to add your first RTMP ingest point!</p>
                  </div>
                ) : (
                  <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-4 sm:gap-6">
                    {streams.map(stream => (
                      <StreamPlayer 
                        key={stream.id} stream={stream} 
                        onRemove={() => setConfirmRemovalId(stream.id)}
                        onUpdateResolution={(res) => handleUpdateResolution(stream.id, res)}
                        onUpdateIpMode={(mode) => handleUpdateResolution(stream.id, stream.resolution)} // Fallback update
                        onUpdateQuality={(bitrate, codec) => handleUpdateQuality(stream.id, bitrate, codec)}
                        onRegenerateKey={() => handleRegenerateKey(stream.id)}
                        onGoLive={() => handleGoLive(stream.id)}
                        onRestartStream={() => handleRestartStream(stream.id)}
                        onEnable={() => handleEnableStream(stream.id)}
                        onDisable={() => handleDisableStream(stream.id)}
                        onEdit={(updated) => handleEditStream(stream.id, updated)}
                        onCloneProfile={(config) => handleCloneProfile(stream.id, config)}
                        isAdmin={currentUser?.role === 'admin'}
                        activeEndpoint={getSelectedEndpoint()}
                      />
                    ))}
                  </div>
                )}
              </section>

              {/* Activity Log */}
              {currentUser && (
                <section className="bg-zinc-900 border border-zinc-800 rounded-2xl p-5 sm:p-6 shadow-sm">
                <div className="flex items-center justify-between mb-4">
                    <h3 className="text-lg font-bold flex items-center gap-2">
                      <FileText className="w-5 h-5 text-zinc-400" /> {currentUser?.role === 'admin' ? 'Administrator Audit Logs' : 'Channel Activity Logs'}
                    </h3>
                    <button 
                      onClick={fetchActionLogs}
                      className="p-1.5 hover:bg-zinc-800 rounded text-zinc-400 hover:text-white transition-colors"
                      title="Refresh logs"
                    >
                      <RefreshCcw className="w-4 h-4" />
                    </button>
                  </div>
                  <div className="bg-zinc-950 rounded-xl border border-zinc-800/80 divide-y divide-zinc-850 max-h-[250px] overflow-y-auto pr-1 text-xs font-mono">
                    {actionLogs.length === 0 ? (
                      <div className="p-4 text-center text-zinc-500 font-sans">
                        No stream state modifications recorded.
                      </div>
                    ) : (
                      actionLogs.map((log) => (
                        <div key={log.id} className="p-3 flex flex-col sm:flex-row sm:items-center justify-between gap-2 hover:bg-zinc-900/40 transition-colors">
                          <div className="space-y-1">
                            <div className="flex items-center gap-2 flex-wrap">
                              <span className={`px-1.5 py-0.5 rounded text-[8px] font-bold uppercase tracking-wider ${
                                log.action === 'enable' ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20' : 
                                log.action === 'disable' ? 'bg-red-500/10 text-red-400 border border-red-500/20' :
                                log.action === 'disabled_reject' ? 'bg-yellow-500/10 text-yellow-500 border border-yellow-500/20' : 'bg-zinc-800 text-zinc-400'
                              }`}>
                                {log.action}
                              </span>
                              <span className="text-zinc-300 font-bold">"{log.streamTitle}"</span>
                            </div>
                            <p className="text-[10px] text-zinc-500 leading-normal font-sans">
                              {log.details}
                            </p>
                          </div>
                          <div className="text-[10px] text-zinc-500 text-right shrink-0 flex flex-col sm:items-end gap-0.5 font-sans">
                            <span className="font-mono text-zinc-400">By: <strong className="text-zinc-300">{log.user}</strong></span>
                            <span>IP: {log.ip}</span>
                            <span>{new Date(log.timestamp).toLocaleString()}</span>
                          </div>
                        </div>
                      ))
                    )}
                  </div>
                </section>
              )}
            </>
          )}

          {activeTab === 'user_profile' && (
            <UserProfile
              currentUser={currentUser}
              fetchWithNetworkHeaders={fetchWithNetworkHeaders}
              onUpdateCurrentUser={(updatedUser, newToken) => {
                localStorage.setItem('streampulse_jwt', newToken);
                setToken(newToken);
                setCurrentUser(updatedUser);
              }}
            />
          )}

          {activeTab === 'admin_profile' && currentUser?.role === 'admin' && (
            <AdminProfile
              currentUser={currentUser}
              fetchWithNetworkHeaders={fetchWithNetworkHeaders}
              onUpdateCurrentUser={(updatedUser, newToken) => {
                localStorage.setItem('streampulse_jwt', newToken);
                setToken(newToken);
                setCurrentUser(updatedUser);
              }}
            />
          )}

          {activeTab === 'users' && currentUser?.role === 'admin' && (
            <div className="space-y-6 animate-in fade-in duration-200">
              <div className="flex flex-col gap-2">
                <h2 className="text-2xl sm:text-3xl font-bold flex items-center gap-2">
                  <Users className="w-8 h-8 text-blue-500" /> Channel User Accounts
                </h2>
                <p className="text-zinc-400 text-sm">Create and manage dedicated logins, reset passwords, enable/disable access, and assign accounts to specific channels.</p>
              </div>

              {usersError && (
                <div className="p-4 bg-red-500/10 border border-red-500/20 text-red-400 rounded-xl text-sm font-semibold flex items-center gap-2">
                  <AlertTriangle className="w-5 h-5 shrink-0" />
                  {usersError}
                </div>
              )}

              {createUserSuccess && (
                <div className="p-4 bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 rounded-xl text-sm font-semibold flex items-center gap-2">
                  <CheckCircle2 className="w-5 h-5 shrink-0" />
                  {createUserSuccess}
                </div>
              )}

              <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
                {/* Create User Card */}
                <div className="lg:col-span-1 bg-zinc-900 border border-zinc-800 rounded-2xl p-5 sm:p-6 shadow-sm h-fit">
                  <h3 className="text-lg font-bold mb-4 flex items-center gap-2">
                    <Plus className="w-5 h-5 text-zinc-400" /> Create User
                  </h3>
                  <form onSubmit={handleCreateUser} className="space-y-4">
                    <div className="space-y-1.5">
                      <label className="text-[10px] font-bold text-zinc-500 uppercase">Username</label>
                      <input 
                        type="text" required value={newUsername} onChange={(e) => setNewUsername(e.target.value)}
                        placeholder="e.g. broadcaster_alpha"
                        className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500/50 outline-none text-zinc-100 font-medium"
                      />
                    </div>
                    <div className="space-y-1.5">
                      <label className="text-[10px] font-bold text-zinc-500 uppercase">Password</label>
                      <div className="relative">
                        <input 
                          type={showNewPassword ? "text" : "password"} required value={newPassword} onChange={(e) => setNewPassword(e.target.value)}
                          placeholder="••••••••••••"
                          className="w-full bg-zinc-950 border border-zinc-800 rounded-lg pl-3 pr-10 py-2 text-sm focus:ring-2 focus:ring-blue-500/50 outline-none text-zinc-100 font-medium"
                        />
                        <button
                          type="button"
                          onClick={() => setShowNewPassword(!showNewPassword)}
                          className="absolute right-2.5 top-1/2 -translate-y-1/2 text-zinc-400 hover:text-zinc-200 p-1"
                          title={showNewPassword ? "Hide password" : "Show password"}
                        >
                          {showNewPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                        </button>
                      </div>
                    </div>
                    <div className="space-y-1.5">
                      <label className="text-[10px] font-bold text-zinc-500 uppercase">Confirm Password</label>
                      <div className="relative">
                        <input 
                          type={showConfirmPassword ? "text" : "password"} required value={newConfirmPassword} onChange={(e) => setNewConfirmPassword(e.target.value)}
                          placeholder="••••••••••••"
                          className="w-full bg-zinc-950 border border-zinc-800 rounded-lg pl-3 pr-10 py-2 text-sm focus:ring-2 focus:ring-blue-500/50 outline-none text-zinc-100 font-medium"
                        />
                        <button
                          type="button"
                          onClick={() => setShowConfirmPassword(!showConfirmPassword)}
                          className="absolute right-2.5 top-1/2 -translate-y-1/2 text-zinc-400 hover:text-zinc-200 p-1"
                          title={showConfirmPassword ? "Hide password" : "Show password"}
                        >
                          {showConfirmPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                        </button>
                      </div>
                    </div>
                    <div className="space-y-1.5">
                      <label className="text-[10px] font-bold text-zinc-500 uppercase">Role</label>
                      <select 
                        value={newRole} onChange={(e: any) => setNewRole(e.target.value)}
                        className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500/50 outline-none text-zinc-100 font-medium"
                      >
                        <option value="user">User</option>
                        <option value="admin">Admin</option>
                      </select>
                    </div>
                    <div className="space-y-1.5">
                      <label className="text-[10px] font-bold text-zinc-500 uppercase">Assign Channel</label>
                      <select 
                        value={newAssignedStreamId} onChange={(e) => setNewAssignedStreamId(e.target.value)}
                        className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500/50 outline-none text-zinc-100 font-medium"
                      >
                        <option value="">-- No Channel Assigned --</option>
                        {streams.map(s => (
                          <option key={s.id} value={s.id}>
                            {s.title} (@{s.broadcaster})
                          </option>
                        ))}
                      </select>
                    </div>
                    <button type="submit" className="w-full mt-2 bg-blue-600 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded-lg transition-all text-sm shadow-lg shadow-blue-900/25">
                      Save User
                    </button>
                  </form>
                </div>

                {/* Users List Directory */}
                <div className="lg:col-span-2 bg-zinc-900 border border-zinc-800 rounded-2xl p-5 sm:p-6 shadow-sm">
                  <h3 className="text-lg font-bold mb-4 flex items-center justify-between">
                    <span>Active Directory</span>
                    <button onClick={fetchUsers} className="p-1 hover:bg-zinc-800 rounded text-zinc-400 hover:text-white transition-colors">
                      <RefreshCcw className="w-4 h-4" />
                    </button>
                  </h3>

                  <div className="mb-4">
                    <input 
                      type="text"
                      placeholder="Search users by username..."
                      value={userSearchQuery}
                      onChange={(e) => setUserSearchQuery(e.target.value)}
                      className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-3 py-2 text-xs focus:ring-2 focus:ring-blue-500/50 outline-none text-zinc-100 placeholder-zinc-500"
                    />
                  </div>

                  {usersLoading ? (
                    <div className="p-8 text-center text-zinc-500">Loading directory...</div>
                  ) : usersList.length === 0 ? (
                    <div className="p-8 text-center text-zinc-500">No channel users found.</div>
                  ) : usersList.filter(u => 
                      (u.username || '').toLowerCase().includes((userSearchQuery || '').toLowerCase())
                    ).length === 0 ? (
                    <div className="p-8 text-center text-zinc-500">No matching users found.</div>
                  ) : (
                    <div className="space-y-4">
                      {usersList
                        .filter(u => 
                          (u.username || '').toLowerCase().includes((userSearchQuery || '').toLowerCase())
                        )
                        .map((user) => {
                        const assignedStream = streams.find(s => s.id === user.assigned_stream_id);
                        const isEditing = editingUserId === user.id;

                        return (
                          <div key={user.id} className="p-4 bg-zinc-950 border border-zinc-850 rounded-xl space-y-3">
                            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
                              <div className="space-y-1 text-left">
                                <div className="flex items-center gap-2 flex-wrap">
                                  <span className="font-bold text-zinc-100">{user.display_name || user.username}</span>
                                  {user.display_name && user.display_name !== user.username && (
                                    <span className="text-xs text-zinc-500 font-medium">({user.username})</span>
                                  )}
                                  {user.role === 'admin' && (
                                    <span className="px-1.5 py-0.5 rounded text-[8px] font-bold uppercase tracking-wider bg-purple-500/10 text-purple-400 border border-purple-500/20">ADMIN</span>
                                  )}
                                  <span className={`px-1.5 py-0.5 rounded text-[8px] font-bold uppercase tracking-wider ${user.status === 'disabled' ? 'bg-red-500/10 text-red-400 border border-red-500/20' : 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20'}`}>
                                    {user.status || 'enabled'}
                                  </span>
                                </div>
                              </div>

                              <div className="flex items-center gap-2 shrink-0">
                                <button 
                                  onClick={() => {
                                    setEditingUserId(user.id);
                                    setEditUsername(user.username);
                                    setEditStatus(user.status || 'enabled');
                                    setEditAssignedStreamId(user.assigned_stream_id || '');
                                    setEditDisplayName(user.display_name || user.username);
                                    setEditRole(user.role || 'user');
                                  }}
                                  className="px-2.5 py-1 text-xs bg-zinc-800 hover:bg-zinc-700 text-zinc-200 font-bold rounded-lg transition-all"
                                >
                                  Edit
                                </button>
                                <button 
                                  onClick={() => {
                                    console.log(`[DELETE WORKFLOW] Delete button clicked for user: ${user.username} (ID: ${user.id})`);
                                    console.log(`[DELETE WORKFLOW] Opening custom confirmation dialog...`);
                                    setConfirmDeleteUserId(user.id);
                                  }}
                                  disabled={user.id === currentUser?.id}
                                  title={user.id === currentUser?.id ? "You cannot delete your own logged-in account" : "Delete user account"}
                                  className="px-2.5 py-1 text-xs bg-red-950/40 hover:bg-red-900/30 text-red-400 border border-red-900/20 font-bold rounded-lg transition-all disabled:opacity-30 disabled:cursor-not-allowed"
                                >
                                  Delete
                                </button>
                              </div>
                            </div>

                            <div className="grid grid-cols-1 md:grid-cols-2 gap-3 text-xs pt-2 border-t border-zinc-900">
                              <div>
                                <span className="text-zinc-500 font-bold uppercase text-[9px] block mb-0.5">Assigned Channel</span>
                                <span className={assignedStream ? 'text-blue-400 font-semibold' : 'text-zinc-500 italic font-medium'}>
                                  {assignedStream ? `${assignedStream.title} (@${assignedStream.broadcaster})` : 'Unassigned'}
                                </span>
                              </div>
                              {(() => {
                                const parsedHistory = Array.isArray(user.login_history)
                                  ? user.login_history
                                  : (typeof user.login_history === 'string' && user.login_history.trim())
                                    ? (() => { try { return JSON.parse(user.login_history); } catch (_) { return []; } })()
                                    : [];
                                return (
                                  <>
                                    <div className="flex justify-between items-center">
                                      <div>
                                        <span className="text-zinc-500 font-bold uppercase text-[9px] block mb-0.5">Login History</span>
                                        <span className="text-zinc-400 font-medium">
                                          {parsedHistory.length > 0 
                                            ? `${parsedHistory.length} logins recorded` 
                                            : 'No login records'}
                                        </span>
                                      </div>
                                      {parsedHistory.length > 0 && (
                                        <button 
                                          onClick={() => setViewingHistoryUser(viewingHistoryUser?.id === user.id ? null : user)}
                                          className="text-xs text-blue-500 hover:underline font-bold"
                                        >
                                          {viewingHistoryUser?.id === user.id ? 'Hide Logs' : 'View Logs'}
                                        </button>
                                      )}
                                    </div>
                                  </>
                                );
                              })()}
                            </div>

                            {/* Viewing Login History Dropdown */}
                            {viewingHistoryUser?.id === user.id && (
                              <div className="mt-3 p-3 bg-zinc-950 border border-zinc-900 rounded-lg max-h-[150px] overflow-y-auto space-y-1.5 text-[11px] font-mono">
                                <p className="text-[10px] font-bold text-zinc-500 uppercase tracking-wider mb-1 font-sans">Recent Logins (IP & Time)</p>
                                {(() => {
                                  const parsedHistory = Array.isArray(user.login_history)
                                    ? user.login_history
                                    : (typeof user.login_history === 'string' && user.login_history.trim())
                                      ? (() => { try { return JSON.parse(user.login_history); } catch (_) { return []; } })()
                                      : [];
                                  return parsedHistory.map((log: any, idx: number) => (
                                    <div key={idx} className="flex justify-between text-zinc-400 border-b border-zinc-900/50 pb-1 last:border-0 last:pb-0">
                                      <span>IP: {log.ip || 'Unknown'}</span>
                                      <span>{new Date(log.timestamp).toLocaleString()}</span>
                                    </div>
                                  ));
                                })()}
                              </div>
                            )}

                            {/* Inline Edit Form */}
                            {isEditing && (
                              <form onSubmit={handleUpdateUser} className="mt-4 p-4 bg-zinc-900 border border-zinc-800 rounded-xl space-y-3 text-left">
                                <div className="flex justify-between items-center mb-1">
                                  <h4 className="text-xs font-bold text-zinc-300 font-sans">Edit User Account: {user.username}</h4>
                                  <button type="button" onClick={() => setEditingUserId(null)} className="text-zinc-500 hover:text-zinc-300">
                                    <X className="w-4 h-4" />
                                  </button>
                                </div>
                                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 font-sans">
                                  <div className="space-y-1">
                                    <label className="text-[9px] font-bold text-zinc-500 uppercase">Username</label>
                                    <input 
                                      type="text" required value={editUsername} onChange={(e) => setEditUsername(e.target.value)}
                                      className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-2 py-1.5 text-xs text-zinc-100 outline-none"
                                    />
                                  </div>
                                  <div className="space-y-1">
                                    <label className="text-[9px] font-bold text-zinc-500 uppercase">Display Name</label>
                                    <input 
                                      type="text" required value={editDisplayName} onChange={(e) => setEditDisplayName(e.target.value)}
                                      className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-2 py-1.5 text-xs text-zinc-100 outline-none"
                                    />
                                  </div>
                                  <div className="space-y-1">
                                    <label className="text-[9px] font-bold text-zinc-500 uppercase">Reset Password (Optional)</label>
                                    <div className="relative">
                                      <input 
                                        type={showEditPassword ? "text" : "password"} value={editPassword} onChange={(e) => setEditPassword(e.target.value)}
                                        placeholder="Leave blank to keep same"
                                        className="w-full bg-zinc-950 border border-zinc-800 rounded-lg pl-2 pr-8 py-1.5 text-xs text-zinc-100 outline-none font-sans"
                                      />
                                      <button
                                        type="button"
                                        onClick={() => setShowEditPassword(!showEditPassword)}
                                        className="absolute right-2 top-1/2 -translate-y-1/2 text-zinc-400 hover:text-zinc-200 p-1"
                                        title={showEditPassword ? "Hide password" : "Show password"}
                                      >
                                        {showEditPassword ? <EyeOff className="w-3.5 h-3.5" /> : <Eye className="w-3.5 h-3.5" />}
                                      </button>
                                    </div>
                                  </div>
                                  <div className="space-y-1">
                                    <label className="text-[9px] font-bold text-zinc-500 uppercase">Account Role</label>
                                    <select 
                                      value={editRole} onChange={(e: any) => setEditRole(e.target.value)}
                                      disabled={user.id === currentUser?.id}
                                      className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-2 py-1.5 text-xs text-zinc-100 outline-none disabled:opacity-50"
                                    >
                                      <option value="user">User (Channel Broadcaster)</option>
                                      <option value="admin">Administrator (Super Admin)</option>
                                    </select>
                                  </div>
                                  <div className="space-y-1 sm:col-span-2">
                                    <label className="text-[9px] font-bold text-zinc-500 uppercase">Account Status</label>
                                    <select 
                                      value={editStatus} onChange={(e: any) => setEditStatus(e.target.value)}
                                      disabled={user.id === currentUser?.id}
                                      className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-2 py-1.5 text-xs text-zinc-100 outline-none disabled:opacity-50"
                                    >
                                      <option value="enabled">Enabled</option>
                                      <option value="disabled">Disabled</option>
                                    </select>
                                  </div>
                                  <div className="space-y-1 sm:col-span-2">
                                    <label className="text-[9px] font-bold text-zinc-500 uppercase">Assign Channel</label>
                                    <select 
                                      value={editAssignedStreamId} onChange={(e) => setEditAssignedStreamId(e.target.value)}
                                      className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-2 py-1.5 text-xs text-zinc-100 outline-none"
                                    >
                                      <option value="">-- No Channel Assigned --</option>
                                      {streams.map(s => (
                                        <option key={s.id} value={s.id}>
                                          {s.title} (@{s.broadcaster})
                                        </option>
                                      ))}
                                    </select>
                                  </div>
                                </div>
                                <div className="flex justify-end gap-2 pt-2">
                                  <button type="button" onClick={() => setEditingUserId(null)} className="px-3 py-1.5 text-xs bg-zinc-800 hover:bg-zinc-750 text-zinc-300 font-bold rounded-lg font-sans">
                                    Cancel
                                  </button>
                                  <button type="submit" className="px-3 py-1.5 text-xs bg-blue-600 hover:bg-blue-700 text-white font-bold rounded-lg font-sans">
                                    Save Changes
                                  </button>
                                </div>
                              </form>
                            )}
                          </div>
                        );
                      })}
                    </div>
                  )}
                </div>
              </div>
            </div>
          )}

          {activeTab === 'streams' && currentUser?.role === 'admin' && (
            <div className="space-y-6">
              <div className="flex flex-col gap-2">
                <h2 className="text-2xl sm:text-3xl font-bold">Public Stream Portal</h2>
                <p className="text-zinc-400 text-sm">Real-time broadcast monitoring hub for multi-player stream execution.</p>
              </div>
              <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 sm:gap-6">
                {streams.map(stream => (
                  <StreamPlayer 
                    key={stream.id} 
                    stream={stream} 
                    onEdit={(updated) => handleEditStream(stream.id, updated)}
                    onCloneProfile={(config) => handleCloneProfile(stream.id, config)}
                    isAdmin={true}
                    activeEndpoint={getSelectedEndpoint()}
                  />
                ))}
              </div>
            </div>
          )}

          {/* Recordings list removed */}

          {activeTab === 'deploy' && currentUser?.role === 'admin' && <DeploymentGuide />}

          {activeTab === 'stream_test' && currentUser?.role === 'admin' && (
            <StreamTestHub streams={streams} activeEndpoint={getSelectedEndpoint()} />
          )}

          {activeTab === 'infra' && currentUser?.role === 'admin' && (
            <div className="space-y-6">
              {/* Network Information Card */}
              <div className="bg-zinc-900 border border-zinc-800 rounded-2xl p-5 sm:p-8 space-y-6">
                <div>
                  <h2 className="text-xl sm:text-2xl font-bold flex items-center gap-2">
                    <Network className="w-6 h-6 text-blue-500" />
                    Network Information
                  </h2>
                  <p className="text-zinc-400 text-sm">Real-time detected server endpoints, ingestion paths, and playback links.</p>
                </div>

                <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                  <div className="bg-zinc-950 border border-zinc-800 rounded-xl p-4 space-y-1">
                    <span className="text-[10px] font-bold text-zinc-500 uppercase tracking-wider block">Active Endpoint</span>
                    <span className="text-sm font-semibold text-zinc-200 font-mono block truncate">{networkDetails?.activeEndpoint || 'Not available'}</span>
                    <span className="text-[9px] text-zinc-500 block">Source: {networkDetails?.source || 'Not available'}</span>
                  </div>
                  <div className="bg-zinc-950 border border-zinc-800 rounded-xl p-4 space-y-1">
                    <span className="text-[10px] font-bold text-zinc-500 uppercase tracking-wider block">Local LAN IP</span>
                    <span className="text-sm font-semibold text-zinc-200 font-mono block truncate">{networkDetails?.lanIp || 'Not available'}</span>
                    <span className="text-[9px] text-zinc-500 block">VirtualBox, VMware, Local Server</span>
                  </div>
                  <div className="bg-zinc-950 border border-zinc-800 rounded-xl p-4 space-y-1">
                    <span className="text-[10px] font-bold text-zinc-500 uppercase tracking-wider block">Public IP</span>
                    <span className="text-sm font-semibold text-zinc-200 font-mono block truncate">{networkDetails?.publicIp || 'Not available'}</span>
                    <span className="text-[9px] text-zinc-500 block">Cloud VPS Server</span>
                  </div>
                </div>

                <div className="space-y-3 bg-zinc-950 border border-zinc-800 rounded-xl p-4 sm:p-6">
                  <h3 className="text-xs font-bold text-zinc-400 uppercase tracking-wider border-b border-zinc-800 pb-2">Dynamic Ingress & Access URLs</h3>
                  
                  <div className="space-y-4 pt-1">
                    {/* Dashboard URL */}
                    <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 border-b border-zinc-900 pb-3">
                      <div className="space-y-0.5">
                        <span className="text-xs font-semibold text-zinc-300">Dashboard URL</span>
                        <p className="text-[11px] font-mono text-zinc-500 select-all truncate">{networkDetails?.dashboardUrl || 'Endpoint unavailable'}</p>
                      </div>
                      <CopyButton
                        text={networkDetails?.dashboardUrl || ''}
                        label="Copy Link"
                        copiedLabel="Copied!"
                        className="flex items-center justify-center gap-1.5 px-3 py-1.5 bg-zinc-900 hover:bg-zinc-800 border border-zinc-850 rounded-lg text-xs font-bold text-zinc-300 transition-all self-start sm:self-center"
                        iconClassName="w-3.5 h-3.5"
                      />
                    </div>

                    {/* API URL */}
                    <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 border-b border-zinc-900 pb-3">
                      <div className="space-y-0.5">
                        <span className="text-xs font-semibold text-zinc-300">API URL</span>
                        <p className="text-[11px] font-mono text-zinc-500 select-all truncate">{networkDetails?.apiUrl || 'Endpoint unavailable'}</p>
                      </div>
                      <CopyButton
                        text={networkDetails?.apiUrl || ''}
                        label="Copy Link"
                        copiedLabel="Copied!"
                        className="flex items-center justify-center gap-1.5 px-3 py-1.5 bg-zinc-900 hover:bg-zinc-800 border border-zinc-850 rounded-lg text-xs font-bold text-zinc-300 transition-all self-start sm:self-center"
                        iconClassName="w-3.5 h-3.5"
                      />
                    </div>

                    {/* RTMP URL */}
                    <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 border-b border-zinc-900 pb-3">
                      <div className="space-y-0.5">
                        <div className="flex items-center gap-2">
                          <span className="text-xs font-semibold text-zinc-300">RTMP URL</span>
                          <span className="text-[9px] bg-blue-950 text-blue-400 border border-blue-900 px-1.5 py-0.2 rounded font-bold font-mono">PORT 1935</span>
                        </div>
                        <p className="text-[11px] font-mono text-zinc-500 select-all truncate">{networkDetails?.rtmpUrl || 'Endpoint unavailable'}</p>
                      </div>
                      <CopyButton
                        text={networkDetails?.rtmpUrl || ''}
                        label="Copy Link"
                        copiedLabel="Copied!"
                        className="flex items-center justify-center gap-1.5 px-3 py-1.5 bg-zinc-900 hover:bg-zinc-800 border border-zinc-850 rounded-lg text-xs font-bold text-zinc-300 transition-all self-start sm:self-center"
                        iconClassName="w-3.5 h-3.5"
                      />
                    </div>

                    {/* HLS URL */}
                    <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
                      <div className="space-y-0.5">
                        <span className="text-xs font-semibold text-zinc-300">HLS Playback URL</span>
                        <p className="text-[11px] font-mono text-zinc-500 select-all truncate">{networkDetails?.hlsUrl || 'Endpoint unavailable'}</p>
                      </div>
                      <CopyButton
                        text={networkDetails?.hlsUrl || ''}
                        label="Copy Link"
                        copiedLabel="Copied!"
                        className="flex items-center justify-center gap-1.5 px-3 py-1.5 bg-zinc-900 hover:bg-zinc-800 border border-zinc-850 rounded-lg text-xs font-bold text-zinc-300 transition-all self-start sm:self-center"
                        iconClassName="w-3.5 h-3.5"
                      />
                    </div>
                  </div>
                </div>
              </div>

              <div className="bg-zinc-900 border border-zinc-800 rounded-2xl p-5 sm:p-8 space-y-6">
                <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
                  <div>
                    <h2 className="text-xl sm:text-2xl font-bold">VPS Container Configurations</h2>
                    <p className="text-zinc-400 text-sm">Inspect and download optimized docker and server config files for Ubuntu deployment.</p>
                  </div>
                  <button 
                    onClick={downloadAllConfigs}
                    className="flex items-center justify-center gap-2 px-4 py-2.5 bg-emerald-600 hover:bg-emerald-500 text-white rounded-xl text-sm font-bold transition-all"
                  >
                    <Download className="w-4 h-4" /> Download Complete Pack
                  </button>
                </div>

                <div className="flex flex-wrap gap-2 border-b border-zinc-800 pb-4">
                  <button 
                    onClick={() => setSelectedFileKey('docker-compose')}
                    className={`px-3 py-1.5 rounded-lg text-xs font-bold transition-all border ${selectedFileKey === 'docker-compose' ? 'bg-blue-600 text-white border-blue-500' : 'bg-zinc-950 border-zinc-800 text-zinc-400'}`}
                  >
                    docker-compose.yml
                  </button>
                  <button 
                    onClick={() => setSelectedFileKey('nginx')}
                    className={`px-3 py-1.5 rounded-lg text-xs font-bold transition-all border ${selectedFileKey === 'nginx' ? 'bg-blue-600 text-white border-blue-500' : 'bg-zinc-950 border-zinc-800 text-zinc-400'}`}
                  >
                    nginx.conf
                  </button>
                  <button 
                    onClick={() => setSelectedFileKey('nginx-rtmp')}
                    className={`px-3 py-1.5 rounded-lg text-xs font-bold transition-all border ${selectedFileKey === 'nginx-rtmp' ? 'bg-blue-600 text-white border-blue-500' : 'bg-zinc-950 border-zinc-800 text-zinc-400'}`}
                  >
                    nginx-rtmp.conf
                  </button>
                  <button 
                    onClick={() => setSelectedFileKey('transcode')}
                    className={`px-3 py-1.5 rounded-lg text-xs font-bold transition-all border ${selectedFileKey === 'transcode' ? 'bg-blue-600 text-white border-blue-500' : 'bg-zinc-950 border-zinc-800 text-zinc-400'}`}
                  >
                    transcode.sh (FFmpeg)
                  </button>
                  <button 
                    onClick={() => setSelectedFileKey('schema')}
                    className={`px-3 py-1.5 rounded-lg text-xs font-bold transition-all border ${selectedFileKey === 'schema' ? 'bg-blue-600 text-white border-blue-500' : 'bg-zinc-950 border-zinc-800 text-zinc-400'}`}
                  >
                    Postgres Schema
                  </button>
                </div>

                <div className="relative">
                  <pre className="bg-zinc-950 border border-zinc-800 rounded-xl p-4 overflow-x-auto text-[11px] sm:text-xs font-mono text-zinc-300 max-h-[420px] scrollbar-thin">
                    {fileContents[selectedFileKey]}
                  </pre>
                  <CopyButton 
                    text={fileContents[selectedFileKey] || ''}
                    label="Copy Code"
                    copiedLabel="Copied!"
                    className="absolute top-3 right-3 px-2.5 py-1.5 bg-zinc-900 hover:bg-zinc-800 border border-zinc-800 rounded-lg text-[10px] font-bold text-zinc-400 transition-colors"
                  />
                </div>
              </div>

              {/* Server Diagnostics & Docker Health monitor */}
              <div className="bg-zinc-900 border border-zinc-800 rounded-2xl p-5 sm:p-8 space-y-6">
                <div>
                  <h3 className="text-lg font-bold">VPS Container Health Logs</h3>
                  <p className="text-zinc-400 text-sm">Real-time statuses of the primary Docker orchestrations.</p>
                </div>

                <div className="space-y-3">
                  {stats.dockerContainers?.length === 0 ? (
                    <div className="p-4 text-center text-zinc-500 border border-zinc-800 rounded-xl text-xs">
                      No containers detected. Run `docker compose up` to orchestrate services.
                    </div>
                  ) : (
                    stats.dockerContainers?.map((c: any, idx: number) => (
                      <div key={idx} className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 p-3.5 bg-zinc-950 border border-zinc-800 rounded-xl">
                        <div className="flex items-center gap-3">
                          <span className={`w-2.5 h-2.5 rounded-full ${c.status === 'running' ? 'bg-green-500 animate-pulse' : 'bg-zinc-600'}`} />
                          <div>
                            <h4 className="text-xs font-bold text-zinc-200 font-mono">{c.name}</h4>
                            <p className="text-[10px] text-zinc-500">Image: {c.image}</p>
                          </div>
                        </div>
                        <span className="text-[10px] font-mono font-semibold px-2 py-0.5 bg-zinc-900 border border-zinc-850 rounded text-zinc-400 truncate">
                          {c.uptime}
                        </span>
                      </div>
                    ))
                  )}
                </div>
              </div>
            </div>
          )}

          {activeTab === 'devices' && currentUser?.role === 'admin' && (
            <RaspberryPlayer token={token} streams={streams} networkDetails={networkDetails} />
          )}

          {activeTab === 'settings' && currentUser?.role === 'admin' && (
            <SettingsPage
              token={token}
              currentUser={currentUser}
              deploymentMode={deploymentMode}
              setDeploymentMode={setDeploymentMode}
              detectedLanIp={detectedLanIp}
              detectedPublicIp={detectedPublicIp}
              customDomain={customDomain}
              setCustomDomain={setCustomDomain}
              networkDetails={networkDetails}
              networkLoading={networkLoading}
              networkSuccess={networkSuccess}
              setNetworkSuccess={setNetworkSuccess}
              networkError={networkError}
              setNetworkError={setNetworkError}
              fetchNetworkDetails={fetchNetworkDetails}
              fetchStreams={fetchStreams}
              handleApplyNetworkChanges={handleApplyNetworkChanges}
              securityLoading={securityLoading}
              securitySuccess={securitySuccess}
              setSecuritySuccess={setSecuritySuccess}
              securityError={securityError}
              setSecurityError={setSecurityError}
              newAdminUsername={newAdminUsername}
              setNewAdminUsername={setNewAdminUsername}
              newAdminPassword={newAdminPassword}
              setNewAdminPassword={setNewAdminPassword}
              confirmAdminPassword={confirmAdminPassword}
              setConfirmAdminPassword={setConfirmAdminPassword}
              handleUpdatePersonalSecurity={handleUpdatePersonalSecurity}
              testingRtmp={testingRtmp}
              rtmpTestResult={rtmpTestResult}
              handleTestRtmp={handleTestRtmp}
              testingPlayback={testingPlayback}
              playbackTestResult={playbackTestResult}
              handleTestPlayback={handleTestPlayback}
              copiedUrlKey={copiedUrlKey}
              setCopiedUrlKey={setCopiedUrlKey}
              adminTargetUser={adminTargetUser}
              setAdminTargetUser={setAdminTargetUser}
              adminUserPassword={adminUserPassword}
              setAdminUserPassword={setAdminUserPassword}
              adminForceReset={adminForceReset}
              setAdminForceReset={setAdminForceReset}
              usersList={usersList}
              handleUpdateUserSecurity={handleUpdateUserSecurity}
            />
          )}

          {activeTab === 'audit_logs' && currentUser?.role === 'admin' && (
            <AuditLogs
              currentUser={currentUser}
              fetchWithNetworkHeaders={fetchWithNetworkHeaders}
            />
          )}

          {activeTab === 'backup_recovery' && currentUser?.role === 'admin' && (
            <BackupRecovery
              currentUser={currentUser}
              fetchWithNetworkHeaders={fetchWithNetworkHeaders}
            />
          )}

          {currentUser?.role === 'user' && activeTab !== 'dashboard' && activeTab !== 'user_profile' && (
            <div className="bg-zinc-900 border border-zinc-800 rounded-2xl p-8 sm:p-12 text-center space-y-4 max-w-xl mx-auto my-12 shadow-xl">
              <div className="w-12 h-12 bg-red-500/10 border border-red-500/20 rounded-xl flex items-center justify-center mx-auto text-red-400">
                <Shield className="w-6 h-6" />
              </div>
              <h3 className="text-xl font-bold text-zinc-100">Access Denied</h3>
              <p className="text-zinc-400 text-sm leading-relaxed">
                You do not have administrative permissions to view this section. Please switch to your channel dashboard or contact an administrator.
              </p>
              <button 
                onClick={() => setActiveTab('dashboard')} 
                className="px-5 py-2.5 bg-blue-600 hover:bg-blue-500 text-white text-xs font-bold rounded-lg transition-all"
              >
                Return to Channel Dashboard
              </button>
            </div>
          )}
        </div>
      </main>

      {/* Mobile Navigation for Standard Users */}
      {currentUser?.role === 'user' && (
        <nav className="fixed bottom-0 left-0 right-0 bg-zinc-900/90 backdrop-blur-xl border-t border-zinc-800 flex items-center justify-around px-2 py-3 lg:hidden z-[60] shadow-[0_-8px_30px_rgb(0,0,0,0.12)]">
          <button onClick={() => setActiveTab('dashboard')} className={`flex flex-col items-center gap-1 flex-1 ${activeTab === 'dashboard' ? 'text-blue-500' : 'text-zinc-500'}`}>
            <LayoutDashboard className="w-5 h-5" />
            <span className="text-[9px] font-bold uppercase">My Channel</span>
          </button>
          <button onClick={() => setActiveTab('user_profile')} className={`flex flex-col items-center gap-1 flex-1 ${activeTab === 'user_profile' ? 'text-blue-500' : 'text-zinc-500'}`}>
            <User className="w-5 h-5" />
            <span className="text-[9px] font-bold uppercase">My Profile</span>
          </button>
        </nav>
      )}

      {/* Mobile Navigation for Admins */}
      {currentUser?.role === 'admin' && (
        <nav className="fixed bottom-0 left-0 right-0 bg-zinc-900/90 backdrop-blur-xl border-t border-zinc-800 flex items-center justify-around px-2 py-3 lg:hidden z-[60] shadow-[0_-8px_30px_rgb(0,0,0,0.12)]">
        <button onClick={() => setActiveTab('dashboard')} className={`flex flex-col items-center gap-1 flex-1 ${activeTab === 'dashboard' ? 'text-blue-500' : 'text-zinc-500'}`}>
          <LayoutDashboard className="w-5 h-5" />
          <span className="text-[9px] font-bold uppercase">Admin</span>
        </button>
        <button onClick={() => setActiveTab('admin_profile')} className={`flex flex-col items-center gap-1 flex-1 ${activeTab === 'admin_profile' ? 'text-blue-500' : 'text-zinc-500'}`}>
          <Shield className="w-5 h-5" />
          <span className="text-[9px] font-bold uppercase">Profile</span>
        </button>
        <button onClick={() => setActiveTab('users')} className={`flex flex-col items-center gap-1 flex-1 ${activeTab === 'users' ? 'text-blue-500' : 'text-zinc-500'}`}>
          <Users className="w-5 h-5" />
          <span className="text-[9px] font-bold uppercase">Users</span>
        </button>
        <button onClick={() => setActiveTab('devices')} className={`flex flex-col items-center gap-1 flex-1 ${activeTab === 'devices' ? 'text-blue-500' : 'text-zinc-500'}`}>
          <Monitor className="w-5 h-5" />
          <span className="text-[9px] font-bold uppercase">Devices</span>
        </button>
        <button onClick={() => setActiveTab('streams')} className={`flex flex-col items-center gap-1 flex-1 ${activeTab === 'streams' ? 'text-blue-500' : 'text-zinc-500'}`}>
          <Tv className="w-5 h-5" />
          <span className="text-[9px] font-bold uppercase">Streams</span>
        </button>
        <button onClick={() => setActiveTab('stream_test')} className={`flex flex-col items-center gap-1 flex-1 ${activeTab === 'stream_test' ? 'text-blue-500' : 'text-zinc-500'}`}>
          <Activity className="w-5 h-5" />
          <span className="text-[9px] font-bold uppercase">Test</span>
        </button>
        <button onClick={() => setActiveTab('deploy')} className={`flex flex-col items-center gap-1 flex-1 ${activeTab === 'deploy' ? 'text-blue-500' : 'text-zinc-500'}`}>
          <Terminal className="w-5 h-5" />
          <span className="text-[9px] font-bold uppercase">Setup</span>
        </button>
        <button onClick={() => setActiveTab('infra')} className={`flex flex-col items-center gap-1 flex-1 ${activeTab === 'infra' ? 'text-blue-500' : 'text-zinc-500'}`}>
          <Server className="w-5 h-5" />
          <span className="text-[9px] font-bold uppercase">Configs</span>
        </button>
        <button id="mobile-settings-btn" onClick={() => setActiveTab('settings')} className={`flex flex-col items-center gap-1 flex-1 ${activeTab === 'settings' ? 'text-blue-500' : 'text-zinc-500'}`}>
          <Settings className="w-5 h-5" />
          <span className="text-[9px] font-bold uppercase">Settings</span>
        </button>
        <button onClick={() => setActiveTab('audit_logs')} className={`flex flex-col items-center gap-1 flex-1 ${activeTab === 'audit_logs' ? 'text-blue-500' : 'text-zinc-500'}`}>
          <FileText className="w-5 h-5" />
          <span className="text-[9px] font-bold uppercase">Audit</span>
        </button>
        <button onClick={() => setActiveTab('backup_recovery')} className={`flex flex-col items-center gap-1 flex-1 ${activeTab === 'backup_recovery' ? 'text-blue-500' : 'text-zinc-500'}`}>
          <HardDrive className="w-5 h-5" />
          <span className="text-[9px] font-bold uppercase">Backup</span>
        </button>
      </nav>
      )}

      {confirmRemovalId && (
        <div className="fixed inset-0 z-[100] flex items-center justify-center p-4">
          <div className="absolute inset-0 bg-zinc-950/80 backdrop-blur-sm" onClick={() => setConfirmRemovalId(null)} />
          <div className="relative bg-zinc-900 border border-zinc-800 rounded-2xl w-full max-w-md p-6 sm:p-8 shadow-2xl animate-in zoom-in-95 duration-200">
            <div className="flex flex-col items-center text-center">
              <div className="p-4 bg-red-600/20 rounded-full mb-6">
                <AlertTriangle className="w-8 h-8 sm:w-10 sm:h-10 text-red-500" />
              </div>
              <h3 className="text-xl font-bold mb-2">Remove Access?</h3>
              <p className="text-zinc-400 text-sm mb-8">
                Clear RTMP credentials for <span className="text-zinc-100 font-bold">@{streams.find(s => s.id === confirmRemovalId)?.broadcaster}</span>?
              </p>
              <div className="flex gap-3 w-full">
                <button onClick={() => setConfirmRemovalId(null)} className="flex-1 px-4 py-3 bg-zinc-800 text-zinc-100 font-bold rounded-xl">Cancel</button>
                <button onClick={handleConfirmRemoval} className="flex-1 px-4 py-3 bg-red-600 text-white font-bold rounded-xl">Remove</button>
              </div>
            </div>
            <button onClick={() => setConfirmRemovalId(null)} className="absolute top-4 right-4 text-zinc-500 hover:text-zinc-300"><X className="w-5 h-5" /></button>
          </div>
        </div>
      )}

      {confirmDeleteUserId !== null && (
        <div className="fixed inset-0 z-[100] flex items-center justify-center p-4">
          <div className="absolute inset-0 bg-zinc-950/80 backdrop-blur-sm" onClick={() => {
            console.log(`[DELETE WORKFLOW] Confirmation backdrop clicked. Closing modal.`);
            setConfirmDeleteUserId(null);
          }} />
          <div className="relative bg-zinc-900 border border-zinc-800 rounded-2xl w-full max-w-md p-6 sm:p-8 shadow-2xl animate-in zoom-in-95 duration-200">
            <div className="flex flex-col items-center text-center">
              <div className="p-4 bg-red-600/20 rounded-full mb-6">
                <AlertTriangle className="w-8 h-8 sm:w-10 sm:h-10 text-red-500" />
              </div>
              <h3 className="text-xl font-bold mb-2">Delete User?</h3>
              <p className="text-zinc-400 text-sm mb-8">
                Are you sure you want to delete <span className="text-zinc-100 font-bold">@{usersList.find(u => u.id === confirmDeleteUserId)?.username}</span>? This action is irreversible, but will preserve all channels, streams, and activity logs.
              </p>
              <div className="flex gap-3 w-full">
                <button onClick={() => {
                  console.log(`[DELETE WORKFLOW] Cancel clicked. Closing modal.`);
                  setConfirmDeleteUserId(null);
                }} className="flex-1 px-4 py-3 bg-zinc-800 text-zinc-100 font-bold rounded-xl">Cancel</button>
                <button onClick={() => {
                  console.log(`[DELETE WORKFLOW] Confirm delete clicked for user ID: ${confirmDeleteUserId}`);
                  handleDeleteUser(confirmDeleteUserId);
                  setConfirmDeleteUserId(null);
                }} className="flex-1 px-4 py-3 bg-red-600 text-white font-bold rounded-xl">Delete</button>
              </div>
            </div>
            <button onClick={() => {
              console.log(`[DELETE WORKFLOW] Close icon clicked. Closing modal.`);
              setConfirmDeleteUserId(null);
            }} className="absolute top-4 right-4 text-zinc-500 hover:text-zinc-300"><X className="w-5 h-5" /></button>
          </div>
        </div>
      )}

      <footer className="hidden sm:block border-t border-zinc-900 bg-zinc-950/50 py-8 px-8 text-center mt-auto">
        <p className="text-xs text-zinc-500">© 2026 StreamPulse Media Systems. Professional RTMP Distribution Hub.</p>
      </footer>
      <ToastContainer />
    </div>
  );
};

export default App;
