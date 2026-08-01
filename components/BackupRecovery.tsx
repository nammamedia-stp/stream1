import React, { useState, useEffect } from 'react';
import {
  ShieldAlert,
  Database,
  RefreshCw,
  Download,
  Upload,
  CheckCircle2,
  XCircle,
  AlertTriangle,
  FileArchive,
  Clock,
  HardDrive,
  Settings,
  Calendar,
  Trash2,
  Copy,
  Check,
  Search,
  Lock,
  ArrowUpRight,
  ShieldCheck,
  Activity,
  Layers,
  Info
} from 'lucide-react';

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

export interface ScheduleConfig {
  frequency: 'daily' | 'weekly' | 'monthly' | 'disabled';
  retentionCount: number;
  lastRun: string | null;
  nextRun: string | null;
}

interface BackupRecoveryProps {
  currentUser: any;
  fetchWithNetworkHeaders: (url: string, options?: RequestInit) => Promise<Response>;
}

export const BackupRecovery: React.FC<BackupRecoveryProps> = ({
  currentUser,
  fetchWithNetworkHeaders
}) => {
  const [backups, setBackups] = useState<BackupItem[]>([]);
  const [schedule, setSchedule] = useState<ScheduleConfig>({
    frequency: 'daily',
    retentionCount: 10,
    lastRun: null,
    nextRun: null
  });
  const [totalBytes, setTotalBytes] = useState<number>(0);
  const [loading, setLoading] = useState<boolean>(true);
  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [successMsg, setSuccessMsg] = useState<string | null>(null);

  // Search & Filter
  const [searchQuery, setSearchQuery] = useState<string>('');
  const [typeFilter, setTypeFilter] = useState<string>('all');

  // Modals
  const [restoreModalFile, setRestoreModalFile] = useState<BackupItem | null>(null);
  const [deleteModalFile, setDeleteModalFile] = useState<BackupItem | null>(null);
  const [verifyResultModal, setVerifyResultModal] = useState<any | null>(null);

  // Schedule Form State
  const [scheduleForm, setScheduleForm] = useState<{
    frequency: 'daily' | 'weekly' | 'monthly' | 'disabled';
    retentionCount: number;
  }>({
    frequency: 'daily',
    retentionCount: 10
  });

  const [copiedSha, setCopiedSha] = useState<string | null>(null);
  const [uploading, setUploading] = useState<boolean>(false);

  // Load Backups and Schedule settings
  const loadBackupsData = async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetchWithNetworkHeaders('/api/admin/backups');
      if (!res.ok) throw new Error(`HTTP ${res.status}: Failed to load backups`);
      const data = await res.json();
      setBackups(data.backups || []);
      setSchedule(data.schedule || { frequency: 'daily', retentionCount: 10, lastRun: null, nextRun: null });
      setScheduleForm({
        frequency: data.schedule?.frequency || 'daily',
        retentionCount: data.schedule?.retentionCount || 10
      });
      setTotalBytes(data.totalBytes || 0);
    } catch (err: any) {
      setError(err.message || 'Failed to load backup history');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadBackupsData();
  }, []);

  const handleCopySha = (sha: string) => {
    navigator.clipboard.writeText(sha);
    setCopiedSha(sha);
    setTimeout(() => setCopiedSha(null), 2000);
  };

  // Trigger Manual Backup
  const handleCreateManualBackup = async () => {
    setActionLoading('creating_manual');
    setError(null);
    setSuccessMsg(null);
    try {
      const res = await fetchWithNetworkHeaders('/api/admin/backup/now', { method: 'POST' });
      if (!res.ok) {
        const errData = await res.json().catch(() => ({}));
        throw new Error(errData.error || 'Failed to create manual backup');
      }
      const data = await res.json();
      setSuccessMsg(data.message || 'Manual backup created successfully');
      await loadBackupsData();
    } catch (err: any) {
      setError(err.message);
    } finally {
      setActionLoading(null);
    }
  };

  // Trigger Scheduled Backup On-Demand
  const handleRunScheduledNow = async () => {
    setActionLoading('creating_scheduled');
    setError(null);
    setSuccessMsg(null);
    try {
      const res = await fetchWithNetworkHeaders('/api/admin/backup/scheduled-now', { method: 'POST' });
      if (!res.ok) {
        const errData = await res.json().catch(() => ({}));
        throw new Error(errData.error || 'Failed to run scheduled backup');
      }
      const data = await res.json();
      setSuccessMsg(data.message || 'Scheduled backup completed successfully');
      await loadBackupsData();
    } catch (err: any) {
      setError(err.message);
    } finally {
      setActionLoading(null);
    }
  };

  // Save Schedule & Retention Settings
  const handleSaveScheduleSettings = async () => {
    setActionLoading('saving_schedule');
    setError(null);
    setSuccessMsg(null);
    try {
      const res = await fetchWithNetworkHeaders('/api/admin/backup/settings', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(scheduleForm)
      });
      if (!res.ok) {
        const errData = await res.json().catch(() => ({}));
        throw new Error(errData.error || 'Failed to update schedule settings');
      }
      const data = await res.json();
      setSuccessMsg(data.message || 'Schedule & retention settings updated');
      setSchedule(data.schedule);
      await loadBackupsData();
    } catch (err: any) {
      setError(err.message);
    } finally {
      setActionLoading(null);
    }
  };

  // Verify Backup Archive
  const handleVerifyBackup = async (filename: string) => {
    setActionLoading(`verify_${filename}`);
    try {
      const res = await fetchWithNetworkHeaders(`/api/admin/backup/verify/${encodeURIComponent(filename)}`, { method: 'POST' });
      const data = await res.json();
      setVerifyResultModal(data);
      await loadBackupsData();
    } catch (err: any) {
      setError('Verification check failed: ' + err.message);
    } finally {
      setActionLoading(null);
    }
  };

  // Execute Disaster Restore
  const handleExecuteRestore = async () => {
    if (!restoreModalFile) return;
    const filename = restoreModalFile.filename;
    setActionLoading('restoring');
    setError(null);
    setSuccessMsg(null);
    try {
      const res = await fetchWithNetworkHeaders('/api/admin/backup/restore', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ filename })
      });
      if (!res.ok) {
        const errData = await res.json().catch(() => ({}));
        throw new Error(errData.error || 'Disaster recovery restore failed');
      }
      const data = await res.json();
      setSuccessMsg(data.message || 'Disaster recovery restore executed successfully!');
      setRestoreModalFile(null);
      await loadBackupsData();
    } catch (err: any) {
      setError(err.message);
    } finally {
      setActionLoading(null);
    }
  };

  // Execute Delete
  const handleExecuteDelete = async () => {
    if (!deleteModalFile) return;
    const filename = deleteModalFile.filename;
    setActionLoading('deleting');
    setError(null);
    setSuccessMsg(null);
    try {
      const res = await fetchWithNetworkHeaders(`/api/admin/backup/${encodeURIComponent(filename)}`, { method: 'DELETE' });
      if (!res.ok) {
        const errData = await res.json().catch(() => ({}));
        throw new Error(errData.error || 'Failed to delete backup archive');
      }
      const data = await res.json();
      setSuccessMsg(data.message || 'Backup archive deleted');
      setDeleteModalFile(null);
      await loadBackupsData();
    } catch (err: any) {
      setError(err.message);
    } finally {
      setActionLoading(null);
    }
  };

  // Download Backup Archive
  const handleDownloadBackup = (filename: string) => {
    const downloadUrl = `/api/admin/backup/download/${encodeURIComponent(filename)}`;
    const link = document.createElement('a');
    link.href = downloadUrl;
    link.setAttribute('download', filename);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

  // Handle File Upload
  const handleFileUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = e.target.files;
    if (!files || files.length === 0) return;
    const file = files[0];

    setUploading(true);
    setError(null);
    setSuccessMsg(null);

    try {
      const buffer = await file.arrayBuffer();
      const res = await fetchWithNetworkHeaders('/api/admin/backup/upload', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-gzip',
          'X-Filename': file.name
        },
        body: buffer
      });

      if (!res.ok) {
        const errData = await res.json().catch(() => ({}));
        throw new Error(errData.error || 'Failed to upload backup archive');
      }

      const data = await res.json();
      setSuccessMsg(data.message || `Uploaded and verified ${file.name}`);
      await loadBackupsData();
    } catch (err: any) {
      setError(err.message);
    } finally {
      setUploading(false);
      if (e.target) e.target.value = '';
    }
  };

  // Format Bytes helper
  const formatBytes = (bytes: number): string => {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  };

  // Filtered backups list
  const filteredBackups = backups.filter(b => {
    const matchesSearch = b.filename.toLowerCase().includes(searchQuery.toLowerCase()) ||
                          b.sha256.toLowerCase().includes(searchQuery.toLowerCase()) ||
                          b.created_by.toLowerCase().includes(searchQuery.toLowerCase());
    const matchesType = typeFilter === 'all' || b.type === typeFilter;
    return matchesSearch && matchesType;
  });

  return (
    <div className="space-y-6 max-w-7xl mx-auto pb-12">
      {/* Header Banner */}
      <div className="bg-zinc-900/80 border border-zinc-800 rounded-2xl p-6 sm:p-8 backdrop-blur-md relative overflow-hidden shadow-2xl">
        <div className="absolute -right-12 -top-12 w-64 h-64 bg-blue-600/10 rounded-full blur-3xl pointer-events-none" />
        <div className="absolute -left-12 -bottom-12 w-64 h-64 bg-indigo-600/10 rounded-full blur-3xl pointer-events-none" />

        <div className="flex flex-col lg:flex-row lg:items-center justify-between gap-6 relative z-10">
          <div>
            <div className="flex items-center gap-3 mb-2">
              <span className="px-3 py-1 bg-blue-500/10 border border-blue-500/20 text-blue-400 text-xs font-semibold rounded-full uppercase tracking-wider flex items-center gap-1.5">
                <ShieldCheck className="w-3.5 h-3.5" /> Disaster Recovery Enabled
              </span>
              <span className="px-3 py-1 bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 text-xs font-semibold rounded-full uppercase tracking-wider flex items-center gap-1.5">
                <Activity className="w-3.5 h-3.5" /> Retention Active ({schedule.retentionCount} Max)
              </span>
            </div>
            <h1 className="text-2xl sm:text-3xl font-extrabold text-white tracking-tight flex items-center gap-3">
              <HardDrive className="w-8 h-8 text-blue-500 shrink-0" />
              Backup & Disaster Recovery
            </h1>
            <p className="text-zinc-400 text-sm sm:text-base mt-1 max-w-2xl">
              System → Backup & Recovery • Automated PostgreSQL database dumps, user accounts, stream keys, SSL configuration, and server settings disaster protection.
            </p>
          </div>

          <div className="flex flex-wrap items-center gap-3">
            <button
              onClick={loadBackupsData}
              disabled={loading}
              className="px-4 py-2.5 bg-zinc-800 hover:bg-zinc-700 text-zinc-200 border border-zinc-700 rounded-xl font-medium text-sm transition-all flex items-center gap-2 active:scale-95 disabled:opacity-50"
            >
              <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
              Refresh
            </button>

            <button
              onClick={handleCreateManualBackup}
              disabled={actionLoading === 'creating_manual'}
              className="px-5 py-2.5 bg-blue-600 hover:bg-blue-500 text-white rounded-xl font-semibold text-sm transition-all shadow-lg shadow-blue-600/20 flex items-center gap-2 active:scale-95 disabled:opacity-50"
            >
              {actionLoading === 'creating_manual' ? (
                <RefreshCw className="w-4 h-4 animate-spin" />
              ) : (
                <Database className="w-4 h-4" />
              )}
              Backup Now
            </button>

            <label className={`px-5 py-2.5 bg-indigo-600/20 hover:bg-indigo-600/30 border border-indigo-500/30 text-indigo-300 rounded-xl font-semibold text-sm cursor-pointer transition-all flex items-center gap-2 active:scale-95 ${uploading ? 'opacity-50 pointer-events-none' : ''}`}>
              {uploading ? (
                <RefreshCw className="w-4 h-4 animate-spin" />
              ) : (
                <Upload className="w-4 h-4" />
              )}
              Upload Archive
              <input
                type="file"
                accept=".tar.gz,.gz"
                className="hidden"
                onChange={handleFileUpload}
                disabled={uploading}
              />
            </label>
          </div>
        </div>
      </div>

      {/* Error & Success Banners */}
      {error && (
        <div className="bg-red-500/10 border border-red-500/20 rounded-xl p-4 flex items-center justify-between gap-3 text-red-400 text-sm">
          <div className="flex items-center gap-3">
            <XCircle className="w-5 h-5 shrink-0" />
            <span>{error}</span>
          </div>
          <button onClick={() => setError(null)} className="text-zinc-400 hover:text-white">
            <XCircle className="w-4 h-4" />
          </button>
        </div>
      )}

      {successMsg && (
        <div className="bg-emerald-500/10 border border-emerald-500/20 rounded-xl p-4 flex items-center justify-between gap-3 text-emerald-400 text-sm">
          <div className="flex items-center gap-3">
            <CheckCircle2 className="w-5 h-5 shrink-0" />
            <span>{successMsg}</span>
          </div>
          <button onClick={() => setSuccessMsg(null)} className="text-zinc-400 hover:text-white">
            <XCircle className="w-4 h-4" />
          </button>
        </div>
      )}

      {/* System Status Metrics Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <div className="bg-zinc-900 border border-zinc-800 rounded-xl p-5 flex items-center gap-4">
          <div className="w-12 h-12 rounded-xl bg-blue-500/10 border border-blue-500/20 flex items-center justify-center text-blue-400 shrink-0">
            <FileArchive className="w-6 h-6" />
          </div>
          <div>
            <div className="text-xs font-semibold text-zinc-400 uppercase tracking-wider">Total Archives</div>
            <div className="text-2xl font-black text-white mt-0.5">{backups.length}</div>
            <div className="text-xs text-zinc-500 mt-1">Stored in ./backups/</div>
          </div>
        </div>

        <div className="bg-zinc-900 border border-zinc-800 rounded-xl p-5 flex items-center gap-4">
          <div className="w-12 h-12 rounded-xl bg-emerald-500/10 border border-emerald-500/20 flex items-center justify-center text-emerald-400 shrink-0">
            <HardDrive className="w-6 h-6" />
          </div>
          <div>
            <div className="text-xs font-semibold text-zinc-400 uppercase tracking-wider">Storage Consumption</div>
            <div className="text-2xl font-black text-white mt-0.5">{formatBytes(totalBytes)}</div>
            <div className="text-xs text-zinc-500 mt-1">Compressed .tar.gz format</div>
          </div>
        </div>

        <div className="bg-zinc-900 border border-zinc-800 rounded-xl p-5 flex items-center gap-4">
          <div className="w-12 h-12 rounded-xl bg-amber-500/10 border border-amber-500/20 flex items-center justify-center text-amber-400 shrink-0">
            <Clock className="w-6 h-6" />
          </div>
          <div>
            <div className="text-xs font-semibold text-zinc-400 uppercase tracking-wider">Last Backup Date</div>
            <div className="text-base font-bold text-white mt-0.5 truncate max-w-[180px]">
              {backups.length > 0 ? new Date(backups[0].timestamp).toLocaleString() : 'No Backups Yet'}
            </div>
            <div className="text-xs text-zinc-500 mt-1">
              {backups.length > 0 ? `Type: ${backups[0].type.toUpperCase()}` : 'Ready for protection'}
            </div>
          </div>
        </div>

        <div className="bg-zinc-900 border border-zinc-800 rounded-xl p-5 flex items-center gap-4">
          <div className="w-12 h-12 rounded-xl bg-purple-500/10 border border-purple-500/20 flex items-center justify-center text-purple-400 shrink-0">
            <Calendar className="w-6 h-6" />
          </div>
          <div>
            <div className="text-xs font-semibold text-zinc-400 uppercase tracking-wider">Auto Schedule</div>
            <div className="text-base font-bold text-white mt-0.5 capitalize">
              {schedule.frequency !== 'disabled' ? schedule.frequency : 'Disabled'}
            </div>
            <div className="text-xs text-purple-400 mt-1 truncate max-w-[180px]">
              {schedule.nextRun ? `Next: ${new Date(schedule.nextRun).toLocaleDateString()}` : 'Manual mode active'}
            </div>
          </div>
        </div>
      </div>

      {/* Included & Excluded Specifications Box */}
      <div className="bg-zinc-900/60 border border-zinc-800 rounded-xl p-5 grid grid-cols-1 md:grid-cols-2 gap-6">
        <div className="space-y-2">
          <div className="flex items-center gap-2 text-xs font-bold text-emerald-400 uppercase tracking-wider">
            <CheckCircle2 className="w-4 h-4" /> Included Components in .tar.gz Archive
          </div>
          <div className="flex flex-wrap gap-1.5 text-xs">
            {[
              'PostgreSQL Database',
              'User Accounts & Hashes',
              'Stream Settings',
              'Stream Keys',
              'Server Settings',
              'Domain Settings',
              'SSL Certificates',
              'Analytics History',
              'Audit Logs',
              'Recording Metadata',
              'Resolution Profiles',
              'Deployment Config'
            ].map(item => (
              <span key={item} className="px-2.5 py-1 bg-emerald-500/10 border border-emerald-500/20 text-emerald-300 rounded-md">
                {item}
              </span>
            ))}
          </div>
        </div>

        <div className="space-y-2">
          <div className="flex items-center gap-2 text-xs font-bold text-zinc-400 uppercase tracking-wider">
            <Info className="w-4 h-4 text-amber-400" /> Excluded Non-Critical Runtime Files
          </div>
          <div className="flex flex-wrap gap-1.5 text-xs">
            {[
              'HLS segments (*.ts, *.m3u8)',
              'Temporary files (/tmp/*)',
              'Cache directories',
              'FFmpeg active memory buffers'
            ].map(item => (
              <span key={item} className="px-2.5 py-1 bg-zinc-800/80 border border-zinc-700/50 text-zinc-400 rounded-md">
                {item}
              </span>
            ))}
          </div>
        </div>
      </div>

      {/* Automated Scheduler & Retention Configuration Panel */}
      <div className="bg-zinc-900 border border-zinc-800 rounded-xl p-6 space-y-6">
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 pb-4 border-b border-zinc-800">
          <div>
            <h3 className="text-lg font-bold text-white flex items-center gap-2">
              <Calendar className="w-5 h-5 text-blue-500" />
              Automated Scheduler & Retention Policy
            </h3>
            <p className="text-xs text-zinc-400 mt-0.5">
              Configure background automated backups and automated cleanup of expired archives.
            </p>
          </div>

          <div className="flex items-center gap-3">
            <button
              onClick={handleRunScheduledNow}
              disabled={actionLoading === 'creating_scheduled'}
              className="px-4 py-2 bg-zinc-800 hover:bg-zinc-700 text-zinc-200 border border-zinc-700 rounded-lg text-xs font-semibold transition-all flex items-center gap-2 active:scale-95 disabled:opacity-50"
            >
              {actionLoading === 'creating_scheduled' ? (
                <RefreshCw className="w-3.5 h-3.5 animate-spin" />
              ) : (
                <Clock className="w-3.5 h-3.5 text-purple-400" />
              )}
              Run Scheduled Backup Now
            </button>

            <button
              onClick={handleSaveScheduleSettings}
              disabled={actionLoading === 'saving_schedule'}
              className="px-4 py-2 bg-blue-600 hover:bg-blue-500 text-white rounded-lg text-xs font-semibold transition-all shadow-md shadow-blue-600/20 flex items-center gap-2 active:scale-95 disabled:opacity-50"
            >
              {actionLoading === 'saving_schedule' ? (
                <RefreshCw className="w-3.5 h-3.5 animate-spin" />
              ) : (
                <Settings className="w-3.5 h-3.5" />
              )}
              Save Schedule Settings
            </button>
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div>
            <label className="block text-xs font-semibold text-zinc-300 uppercase tracking-wider mb-2">
              Backup Schedule Frequency
            </label>
            <select
              value={scheduleForm.frequency}
              onChange={(e: any) => setScheduleForm({ ...scheduleForm, frequency: e.target.value })}
              className="w-full bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2.5 text-sm text-zinc-200 focus:outline-none focus:border-blue-500"
            >
              <option value="daily">Daily - Every 24 Hours</option>
              <option value="weekly">Weekly - Every 7 Days</option>
              <option value="monthly">Monthly - Every 30 Days</option>
              <option value="disabled">Disabled - Manual Backups Only</option>
            </select>
            <p className="text-xs text-zinc-500 mt-1.5">
              Automated backups run silently in the background and generate compressed .tar.gz archives.
            </p>
          </div>

          <div>
            <label className="block text-xs font-semibold text-zinc-300 uppercase tracking-wider mb-2">
              Retention Policy (Max Archives Kept)
            </label>
            <select
              value={scheduleForm.retentionCount}
              onChange={(e: any) => setScheduleForm({ ...scheduleForm, retentionCount: parseInt(e.target.value, 10) })}
              className="w-full bg-zinc-950 border border-zinc-800 rounded-xl px-4 py-2.5 text-sm text-zinc-200 focus:outline-none focus:border-blue-500"
            >
              <option value={5}>Keep Last 5 Backups</option>
              <option value={10}>Keep Last 10 Backups (Recommended)</option>
              <option value={30}>Keep Last 30 Backups</option>
            </select>
            <p className="text-xs text-zinc-500 mt-1.5">
              Expired backups exceeding this limit are automatically purged to prevent disk overflow.
            </p>
          </div>
        </div>

        <div className="bg-zinc-950/60 border border-zinc-800/80 rounded-xl p-4 grid grid-cols-1 sm:grid-cols-2 gap-4 text-xs">
          <div>
            <span className="text-zinc-500 block">Last Automated Run:</span>
            <span className="font-semibold text-zinc-300">
              {schedule.lastRun ? new Date(schedule.lastRun).toLocaleString() : 'Never Executed'}
            </span>
          </div>
          <div>
            <span className="text-zinc-500 block">Next Scheduled Run:</span>
            <span className="font-semibold text-blue-400">
              {schedule.nextRun ? new Date(schedule.nextRun).toLocaleString() : 'Schedule Disabled'}
            </span>
          </div>
        </div>
      </div>

      {/* Backup History Table & Filter Bar */}
      <div className="bg-zinc-900 border border-zinc-800 rounded-xl p-6 space-y-4">
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div>
            <h3 className="text-lg font-bold text-white flex items-center gap-2">
              <FileArchive className="w-5 h-5 text-blue-500" />
              Backup History & Archives
            </h3>
            <p className="text-xs text-zinc-400 mt-0.5">
              Manage, verify, download, and restore system backups.
            </p>
          </div>

          <div className="flex flex-col sm:flex-row items-center gap-3">
            {/* Search Input */}
            <div className="relative w-full sm:w-64">
              <Search className="w-4 h-4 text-zinc-500 absolute left-3 top-2.5" />
              <input
                type="text"
                placeholder="Search archive or SHA256..."
                value={searchQuery}
                onChange={e => setSearchQuery(e.target.value)}
                className="w-full bg-zinc-950 border border-zinc-800 rounded-lg pl-9 pr-3 py-1.5 text-xs text-zinc-200 placeholder-zinc-500 focus:outline-none focus:border-blue-500"
              />
            </div>

            {/* Type Filter */}
            <select
              value={typeFilter}
              onChange={e => setTypeFilter(e.target.value)}
              className="w-full sm:w-auto bg-zinc-950 border border-zinc-800 rounded-lg px-3 py-1.5 text-xs text-zinc-200 focus:outline-none focus:border-blue-500"
            >
              <option value="all">All Types</option>
              <option value="manual">Manual</option>
              <option value="scheduled">Scheduled</option>
              <option value="safety">Safety</option>
            </select>
          </div>
        </div>

        {/* Table / List */}
        <div className="overflow-x-auto">
          <table className="w-full text-left border-collapse">
            <thead>
              <tr className="border-b border-zinc-800 text-[11px] font-bold text-zinc-400 uppercase tracking-wider bg-zinc-950/40">
                <th className="py-3 px-4">Archive / Type</th>
                <th className="py-3 px-4">Size</th>
                <th className="py-3 px-4">Created Date</th>
                <th className="py-3 px-4">SHA256 Checksum</th>
                <th className="py-3 px-4">Status</th>
                <th className="py-3 px-4 text-right">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-zinc-800/60 text-xs">
              {filteredBackups.length === 0 ? (
                <tr>
                  <td colSpan={6} className="py-12 text-center text-zinc-500">
                    <Database className="w-8 h-8 mx-auto mb-2 text-zinc-600" />
                    No backup archives match the criteria. Click "Backup Now" to create your first backup.
                  </td>
                </tr>
              ) : (
                filteredBackups.map(item => (
                  <tr key={item.filename} className="hover:bg-zinc-800/30 transition-colors">
                    {/* Archive Name & Type */}
                    <td className="py-3.5 px-4 font-mono font-medium text-white">
                      <div className="flex items-center gap-2.5">
                        <FileArchive className="w-4 h-4 text-blue-400 shrink-0" />
                        <span className="truncate max-w-[220px]" title={item.filename}>
                          {item.filename}
                        </span>
                        <span className={`px-2 py-0.5 text-[10px] font-bold uppercase rounded-md shrink-0 ${
                          item.type === 'manual'
                            ? 'bg-blue-500/10 text-blue-400 border border-blue-500/20'
                            : item.type === 'scheduled'
                            ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20'
                            : 'bg-amber-500/10 text-amber-400 border border-amber-500/20'
                        }`}>
                          {item.type}
                        </span>
                      </div>
                    </td>

                    {/* Size */}
                    <td className="py-3.5 px-4 text-zinc-300 font-medium">
                      {item.size_formatted}
                    </td>

                    {/* Creation Date */}
                    <td className="py-3.5 px-4 text-zinc-400">
                      {new Date(item.timestamp).toLocaleString()}
                    </td>

                    {/* SHA256 snippet */}
                    <td className="py-3.5 px-4 font-mono text-[11px] text-zinc-400">
                      <div className="flex items-center gap-1.5">
                        <span className="truncate max-w-[100px]" title={item.sha256}>
                          {item.sha256.substring(0, 10)}...
                        </span>
                        <button
                          onClick={() => handleCopySha(item.sha256)}
                          className="text-zinc-500 hover:text-zinc-300 transition-colors"
                          title="Copy Full SHA256 Checksum"
                        >
                          {copiedSha === item.sha256 ? (
                            <Check className="w-3.5 h-3.5 text-emerald-400" />
                          ) : (
                            <Copy className="w-3.5 h-3.5" />
                          )}
                        </button>
                      </div>
                    </td>

                    {/* Verification Status */}
                    <td className="py-3.5 px-4">
                      {item.verified ? (
                        <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded bg-emerald-500/10 text-emerald-400 text-[10px] font-semibold border border-emerald-500/20">
                          <CheckCircle2 className="w-3 h-3" /> Verified
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded bg-red-500/10 text-red-400 text-[10px] font-semibold border border-red-500/20">
                          <AlertTriangle className="w-3 h-3" /> Unverified
                        </span>
                      )}
                    </td>

                    {/* Actions */}
                    <td className="py-3.5 px-4 text-right">
                      <div className="flex items-center justify-end gap-1.5">
                        {/* Verify Button */}
                        <button
                          onClick={() => handleVerifyBackup(item.filename)}
                          disabled={actionLoading === `verify_${item.filename}`}
                          className="p-1.5 bg-zinc-800 hover:bg-zinc-700 text-zinc-300 rounded-lg transition-colors text-xs flex items-center gap-1"
                          title="Verify SHA256 Checksum & Integrity"
                        >
                          {actionLoading === `verify_${item.filename}` ? (
                            <RefreshCw className="w-3.5 h-3.5 animate-spin text-blue-400" />
                          ) : (
                            <ShieldCheck className="w-3.5 h-3.5 text-blue-400" />
                          )}
                        </button>

                        {/* Download Button */}
                        <button
                          onClick={() => handleDownloadBackup(item.filename)}
                          className="p-1.5 bg-zinc-800 hover:bg-zinc-700 text-zinc-300 rounded-lg transition-colors text-xs flex items-center gap-1"
                          title="Download .tar.gz Archive"
                        >
                          <Download className="w-3.5 h-3.5 text-emerald-400" />
                        </button>

                        {/* Restore Button */}
                        <button
                          onClick={() => setRestoreModalFile(item)}
                          className="px-2.5 py-1 bg-amber-500/10 hover:bg-amber-500/20 text-amber-400 border border-amber-500/20 rounded-lg text-xs font-semibold transition-colors flex items-center gap-1"
                          title="Restore System from this Backup"
                        >
                          <RefreshCw className="w-3 h-3" />
                          Restore
                        </button>

                        {/* Delete Button */}
                        <button
                          onClick={() => setDeleteModalFile(item)}
                          className="p-1.5 bg-red-500/10 hover:bg-red-500/20 text-red-400 border border-red-500/20 rounded-lg transition-colors text-xs"
                          title="Delete Backup Archive"
                        >
                          <Trash2 className="w-3.5 h-3.5" />
                        </button>
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* DISASTER RECOVERY RESTORE CONFIRMATION MODAL */}
      {restoreModalFile && (
        <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="bg-zinc-900 border border-red-500/30 rounded-2xl p-6 sm:p-8 max-w-xl w-full shadow-2xl space-y-6">
            <div className="flex items-start gap-4">
              <div className="w-12 h-12 rounded-2xl bg-red-500/10 border border-red-500/20 flex items-center justify-center text-red-400 shrink-0">
                <ShieldAlert className="w-7 h-7" />
              </div>
              <div>
                <h3 className="text-xl font-extrabold text-white">Confirm Disaster Recovery Restore</h3>
                <p className="text-xs text-zinc-400 mt-1">
                  System → Backup & Recovery • Full Database & Configuration Overwrite
                </p>
              </div>
            </div>

            <div className="bg-red-500/10 border border-red-500/20 rounded-xl p-4 space-y-2 text-xs text-red-300">
              <div className="font-bold flex items-center gap-1.5 text-red-400 uppercase tracking-wider">
                <AlertTriangle className="w-4 h-4 shrink-0" /> Important Warning
              </div>
              <p>
                Restoring this archive will overwrite current PostgreSQL database records, user accounts, stream keys, and system configuration.
              </p>
              <p className="text-emerald-400 font-medium pt-1">
                An automatic SAFETY backup will be created immediately before restore begins.
              </p>
            </div>

            <div className="bg-zinc-950 border border-zinc-800 rounded-xl p-4 space-y-2 text-xs font-mono text-zinc-300">
              <div className="flex justify-between">
                <span className="text-zinc-500">Target Archive:</span>
                <span className="text-white font-bold">{restoreModalFile.filename}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-zinc-500">Archive Size:</span>
                <span>{restoreModalFile.size_formatted}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-zinc-500">Created Date:</span>
                <span>{new Date(restoreModalFile.timestamp).toLocaleString()}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-zinc-500">SHA256 Checksum:</span>
                <span className="text-zinc-400 truncate max-w-[200px]">{restoreModalFile.sha256}</span>
              </div>
            </div>

            <div className="flex items-center justify-end gap-3 pt-2">
              <button
                onClick={() => setRestoreModalFile(null)}
                disabled={actionLoading === 'restoring'}
                className="px-5 py-2.5 bg-zinc-800 hover:bg-zinc-700 text-zinc-300 rounded-xl font-medium text-sm transition-all"
              >
                Cancel
              </button>
              <button
                onClick={handleExecuteRestore}
                disabled={actionLoading === 'restoring'}
                className="px-6 py-2.5 bg-red-600 hover:bg-red-500 text-white rounded-xl font-bold text-sm transition-all shadow-lg shadow-red-600/20 flex items-center gap-2"
              >
                {actionLoading === 'restoring' ? (
                  <>
                    <RefreshCw className="w-4 h-4 animate-spin" /> Restoring System...
                  </>
                ) : (
                  <>
                    <RefreshCw className="w-4 h-4" /> Confirm & Execute Restore
                  </>
                )}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* DELETE CONFIRMATION MODAL */}
      {deleteModalFile && (
        <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="bg-zinc-900 border border-zinc-800 rounded-2xl p-6 sm:p-8 max-w-md w-full shadow-2xl space-y-6">
            <div className="flex items-start gap-4">
              <div className="w-12 h-12 rounded-2xl bg-red-500/10 border border-red-500/20 flex items-center justify-center text-red-400 shrink-0">
                <Trash2 className="w-6 h-6" />
              </div>
              <div>
                <h3 className="text-lg font-bold text-white">Delete Backup Archive</h3>
                <p className="text-xs text-zinc-400 mt-1">
                  Are you sure you want to permanently delete this backup archive?
                </p>
              </div>
            </div>

            <div className="bg-zinc-950 border border-zinc-800 rounded-xl p-3 text-xs font-mono text-zinc-300">
              <div className="text-white font-bold">{deleteModalFile.filename}</div>
              <div className="text-zinc-500 mt-1">{deleteModalFile.size_formatted} • {new Date(deleteModalFile.timestamp).toLocaleString()}</div>
            </div>

            <div className="flex items-center justify-end gap-3">
              <button
                onClick={() => setDeleteModalFile(null)}
                disabled={actionLoading === 'deleting'}
                className="px-4 py-2 bg-zinc-800 hover:bg-zinc-700 text-zinc-300 rounded-xl font-medium text-xs transition-all"
              >
                Cancel
              </button>
              <button
                onClick={handleExecuteDelete}
                disabled={actionLoading === 'deleting'}
                className="px-5 py-2 bg-red-600 hover:bg-red-500 text-white rounded-xl font-bold text-xs transition-all shadow-md shadow-red-600/20 flex items-center gap-2"
              >
                {actionLoading === 'deleting' ? (
                  <RefreshCw className="w-3.5 h-3.5 animate-spin" />
                ) : (
                  <Trash2 className="w-3.5 h-3.5" />
                )}
                Confirm Delete
              </button>
            </div>
          </div>
        </div>
      )}

      {/* VERIFICATION RESULT MODAL */}
      {verifyResultModal && (
        <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="bg-zinc-900 border border-zinc-800 rounded-2xl p-6 sm:p-8 max-w-lg w-full shadow-2xl space-y-6">
            <div className="flex items-center gap-3">
              {verifyResultModal.valid ? (
                <div className="w-10 h-10 rounded-xl bg-emerald-500/10 border border-emerald-500/20 flex items-center justify-center text-emerald-400">
                  <CheckCircle2 className="w-6 h-6" />
                </div>
              ) : (
                <div className="w-10 h-10 rounded-xl bg-red-500/10 border border-red-500/20 flex items-center justify-center text-red-400">
                  <XCircle className="w-6 h-6" />
                </div>
              )}
              <div>
                <h3 className="text-lg font-bold text-white">Backup Verification Results</h3>
                <p className="text-xs text-zinc-400 font-mono">{verifyResultModal.filename}</p>
              </div>
            </div>

            <div className="bg-zinc-950 border border-zinc-800 rounded-xl p-4 space-y-3 text-xs">
              <div>
                <span className="text-zinc-500 block">Status:</span>
                <span className={`font-bold ${verifyResultModal.valid ? 'text-emerald-400' : 'text-red-400'}`}>
                  {verifyResultModal.valid ? 'VERIFIED PASSED' : 'VERIFICATION FAILED'}
                </span>
              </div>

              <div>
                <span className="text-zinc-500 block">SHA256 Checksum:</span>
                <span className="font-mono text-zinc-300 break-all">{verifyResultModal.sha256 || 'N/A'}</span>
              </div>

              <div>
                <span className="text-zinc-500 block">Details:</span>
                <span className="text-zinc-300">{verifyResultModal.details}</span>
              </div>

              {verifyResultModal.manifest?.record_counts && (
                <div className="pt-2 border-t border-zinc-800">
                  <span className="text-zinc-500 block mb-1">Payload Records:</span>
                  <div className="grid grid-cols-2 gap-2 text-[11px] font-mono">
                    <div>Users: {verifyResultModal.manifest.record_counts.users}</div>
                    <div>Streams: {verifyResultModal.manifest.record_counts.streams}</div>
                    <div>Devices: {verifyResultModal.manifest.record_counts.devices}</div>
                    <div>Audit Logs: {verifyResultModal.manifest.record_counts.auditLogs}</div>
                  </div>
                </div>
              )}
            </div>

            <div className="flex justify-end">
              <button
                onClick={() => setVerifyResultModal(null)}
                className="px-5 py-2 bg-blue-600 hover:bg-blue-500 text-white rounded-xl text-xs font-semibold"
              >
                Close
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
