import React, { useState, useEffect, useRef, useMemo } from 'react';
import { CopyButton } from './CopyButton';
import { 
  RefreshCcw, 
  Save, 
  CheckCircle2, 
  AlertCircle, 
  Network, 
  Tv, 
  Check, 
  Copy, 
  Terminal, 
  PlayCircle, 
  User, 
  Shield, 
  Globe,
  Database,
  Lock,
  Settings,
  Cpu,
  Download,
  Upload,
  ArrowUpCircle,
  HardDrive,
  Activity,
  Layers
} from 'lucide-react';

interface SettingsPageProps {
  token: string | null;
  currentUser: any;
  deploymentMode: 'auto' | 'lan' | 'public' | 'domain';
  setDeploymentMode: (mode: 'auto' | 'lan' | 'public' | 'domain') => void;
  detectedLanIp: string;
  detectedPublicIp: string;
  customDomain: string;
  setCustomDomain: (domain: string) => void;
  networkDetails: any;
  networkLoading: boolean;
  networkSuccess: string;
  setNetworkSuccess: (msg: string) => void;
  networkError: string;
  setNetworkError: (msg: string) => void;
  fetchNetworkDetails: () => Promise<void>;
  fetchStreams: () => Promise<void>;
  handleApplyNetworkChanges: () => Promise<void>;
  
  securityLoading: boolean;
  securitySuccess: string;
  setSecuritySuccess: (msg: string) => void;
  securityError: string;
  setSecurityError: (msg: string) => void;
  newAdminUsername: string;
  setNewAdminUsername: (username: string) => void;
  newAdminPassword: string;
  setNewAdminPassword: (password: string) => void;
  confirmAdminPassword: string;
  setConfirmAdminPassword: (password: string) => void;
  handleUpdatePersonalSecurity: (e: React.FormEvent) => Promise<void>;

  testingRtmp: boolean;
  rtmpTestResult: { success: boolean; message: string } | null;
  handleTestRtmp: () => Promise<void>;
  testingPlayback: boolean;
  playbackTestResult: { success: boolean; message: string } | null;
  handleTestPlayback: () => Promise<void>;

  copiedUrlKey: string | null;
  setCopiedUrlKey: (key: string | null) => void;

  // Admin section:
  adminTargetUser: string;
  setAdminTargetUser: (id: string) => void;
  adminUserPassword: string;
  setAdminUserPassword: (password: string) => void;
  adminForceReset: boolean;
  setAdminForceReset: (val: boolean) => void;
  usersList: any[];
  handleUpdateUserSecurity: (e: React.FormEvent) => Promise<void>;
}

export const SettingsPage: React.FC<SettingsPageProps> = ({
  token,
  currentUser,
  deploymentMode,
  setDeploymentMode,
  detectedLanIp,
  detectedPublicIp,
  customDomain,
  setCustomDomain,
  networkDetails,
  networkLoading,
  networkSuccess,
  setNetworkSuccess,
  networkError,
  setNetworkError,
  fetchNetworkDetails,
  fetchStreams,
  handleApplyNetworkChanges,
  securityLoading,
  securitySuccess,
  setSecuritySuccess,
  securityError,
  setSecurityError,
  newAdminUsername,
  setNewAdminUsername,
  newAdminPassword,
  setNewAdminPassword,
  confirmAdminPassword,
  setConfirmAdminPassword,
  handleUpdatePersonalSecurity,
  testingRtmp,
  rtmpTestResult,
  handleTestRtmp,
  testingPlayback,
  playbackTestResult,
  handleTestPlayback,
  copiedUrlKey,
  setCopiedUrlKey,
  adminTargetUser,
  setAdminTargetUser,
  adminUserPassword,
  setAdminUserPassword,
  adminForceReset,
  setAdminForceReset,
  usersList,
  handleUpdateUserSecurity
}) => {
  // Navigation Tabs for settings bento dashboard
  const [activeTab, setActiveTab] = useState<'network' | 'ssl' | 'security' | 'streaming' | 'system' | 'backup' | 'updates' | 'diagnostics'>('network');
  
  // Status feedback states
  const [actionSuccess, setActionSuccess] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [actionLoading, setActionLoading] = useState(false);

  // 1. SSL Status
  const [sslStatus, setSslStatus] = useState<any>(null);

  // 2. Streaming Parameters
  const [streamingParams, setStreamingParams] = useState({
    rtmpPort: 1935,
    httpPort: 3000,
    httpsPort: 443,
    hlsSegmentDuration: 4,
    playlistLength: 5,
    recordingEnabled: false,
    ffmpegProfiles: {
      '1080p': true,
      '720p': true,
      '480p': true,
      '360p': true
    }
  });

  // 3. Diagnostics results
  const [diagnosticResults, setDiagnosticResults] = useState<Record<string, { status: 'pass' | 'warning' | 'fail'; message: string }> | null>(null);
  const [runningDiagnostics, setRunningDiagnostics] = useState(false);

  // Domain Verification States
  const [verificationResult, setVerificationResult] = useState<any>(null);
  const [verifyingDomain, setVerifyingDomain] = useState(false);

  const handleRunDomainVerification = async () => {
    if (!token || !currentUser || currentUser.role !== 'admin') return;
    setVerifyingDomain(true);
    try {
      const res = await fetchWithAuth('/api/settings/domain/verify');
      if (res.ok) {
        const data = await res.json();
        setVerificationResult(data);
      } else {
        console.error('Failed to run domain verification');
      }
    } catch (e) {
      console.error('Domain verification error:', e);
    } finally {
      setVerifyingDomain(false);
    }
  };

  // 4. Update check status
  const [updateDetails, setUpdateDetails] = useState<any>(null);

  // Fetch configs on component mount & tab switch
  useEffect(() => {
    fetchSslStatus();
    fetchStreamingParams();
    checkSoftwareUpdates();
  }, [token]);

  useEffect(() => {
    if (activeTab === 'network' && token && currentUser?.role === 'admin') {
      handleRunDomainVerification();
    }
  }, [activeTab, token, currentUser]);

  const fetchWithAuth = async (url: string, init?: RequestInit) => {
    return fetch(url, {
      ...init,
      headers: {
        ...init?.headers,
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
      }
    });
  };

  const showBannerMessage = (success: string | null, error: string | null = null) => {
    setActionSuccess(success);
    setActionError(error);
    setTimeout(() => {
      setActionSuccess(null);
      setActionError(null);
    }, 4000);
  };

  const fetchSslStatus = async () => {
    try {
      const res = await fetchWithAuth('/api/settings/ssl/status');
      if (res.ok) {
        const data = await res.json();
        setSslStatus(data);
      }
    } catch (e) {
      console.error('Failed to load SSL status:', e);
    }
  };

  // Saved baseline refs for tracking unsaved/dirty state across tabs
  const initialNetworkRef = useRef<{ deploymentMode: string; customDomain: string } | null>(null);
  const initialStreamingRef = useRef<any>(null);

  // Initialize network baseline on first render/prop load
  useEffect(() => {
    if (initialNetworkRef.current === null) {
      initialNetworkRef.current = {
        deploymentMode: deploymentMode || 'auto',
        customDomain: customDomain || ''
      };
    }
  }, [deploymentMode, customDomain]);

  // Dirty state checks for configuration categories
  const isNetworkDirty = useMemo(() => {
    if (!initialNetworkRef.current) return false;
    return (
      deploymentMode !== initialNetworkRef.current.deploymentMode ||
      customDomain !== initialNetworkRef.current.customDomain
    );
  }, [deploymentMode, customDomain]);

  const isStreamingDirty = useMemo(() => {
    if (!initialStreamingRef.current) return false;
    return JSON.stringify(streamingParams) !== JSON.stringify(initialStreamingRef.current);
  }, [streamingParams]);

  const isAdminSecurityDirty = useMemo(() => {
    return Boolean(newAdminUsername.trim() || newAdminPassword.trim() || confirmAdminPassword.trim());
  }, [newAdminUsername, newAdminPassword, confirmAdminPassword]);

  const isTeamSecurityDirty = useMemo(() => {
    return Boolean(adminTargetUser && (adminUserPassword.trim() || adminForceReset));
  }, [adminTargetUser, adminUserPassword, adminForceReset]);

  // Explicit Save handlers
  const onSaveNetworkClick = async () => {
    setActionLoading(true);
    try {
      await handleApplyNetworkChanges();
      initialNetworkRef.current = {
        deploymentMode,
        customDomain
      };
      setNetworkSuccess('Settings Saved Successfully');
      showBannerMessage('Settings Saved Successfully');
    } catch (err: any) {
      showBannerMessage(null, err.message || 'Failed to save network configuration');
    } finally {
      setActionLoading(false);
    }
  };

  const onSaveStreamingClick = async () => {
    setActionLoading(true);
    try {
      const res = await fetchWithAuth('/api/settings/streaming', {
        method: 'POST',
        body: JSON.stringify(streamingParams)
      });
      const data = await res.json();
      if (res.ok && data.success) {
        initialStreamingRef.current = JSON.parse(JSON.stringify(streamingParams));
        showBannerMessage('Settings Saved Successfully');
      } else {
        showBannerMessage(null, data.error || 'Failed to save streaming configuration.');
      }
    } catch (e: any) {
      showBannerMessage(null, 'Streaming parameters upload failed: ' + e.message);
    } finally {
      setActionLoading(false);
    }
  };

  const fetchStreamingParams = async () => {
    try {
      const res = await fetchWithAuth('/api/settings/streaming');
      if (res.ok) {
        const data = await res.json();
        setStreamingParams(data);
        initialStreamingRef.current = JSON.parse(JSON.stringify(data));
      }
    } catch (e) {
      console.error('Failed to load Streaming properties:', e);
    }
  };

  const checkSoftwareUpdates = async () => {
    try {
      const res = await fetchWithAuth('/api/update/check');
      if (res.ok) {
        const data = await res.json();
        setUpdateDetails(data);
      }
    } catch (e) {
      console.error('Failed to check software updates:', e);
    }
  };

  // Actions
  const handleValidateDomain = async () => {
    if (!customDomain) {
      showBannerMessage(null, 'Please provide a valid domain to validate.');
      return;
    }
    setActionLoading(true);
    try {
      const res = await fetchWithAuth('/api/settings/domain/validate', {
        method: 'POST',
        body: JSON.stringify({ domain: customDomain })
      });
      const data = await res.json();
      if (data.success) {
        showBannerMessage(data.message);
      } else {
        showBannerMessage(null, data.message);
      }
    } catch (err: any) {
      showBannerMessage(null, 'Domain verification request failed: ' + err.message);
    } finally {
      setActionLoading(false);
    }
  };

  const handleRemoveDomain = async () => {
    setCustomDomain('');
    showBannerMessage('Domain removed. Remember to apply changes to save configuration.');
  };

  const handleInstallLetsEncrypt = async () => {
    if (!customDomain) {
      showBannerMessage(null, 'Let\'s Encrypt SSL installation requires a configured custom domain.');
      return;
    }
    setActionLoading(true);
    try {
      const res = await fetchWithAuth('/api/settings/ssl/letsencrypt', {
        method: 'POST',
        body: JSON.stringify({ domain: customDomain })
      });
      const data = await res.json();
      if (res.ok && data.success) {
        showBannerMessage(data.message);
        fetchSslStatus();
      } else {
        showBannerMessage(null, data.error || 'Failed to install Let\'s Encrypt certificate.');
      }
    } catch (err: any) {
      showBannerMessage(null, 'SSL request failed: ' + err.message);
    } finally {
      setActionLoading(false);
    }
  };

  const handleRenewSsl = async () => {
    setActionLoading(true);
    try {
      const res = await fetchWithAuth('/api/settings/ssl/renew', { method: 'POST' });
      const data = await res.json();
      if (res.ok && data.success) {
        showBannerMessage(data.message);
        fetchSslStatus();
      } else {
        showBannerMessage(null, data.error || 'Failed to trigger certificate renewal.');
      }
    } catch (e: any) {
      showBannerMessage(null, 'SSL renewal query failed: ' + e.message);
    } finally {
      setActionLoading(false);
    }
  };

  const handleReissueSsl = async () => {
    setActionLoading(true);
    try {
      const res = await fetchWithAuth('/api/settings/ssl/reissue', { method: 'POST' });
      const data = await res.json();
      if (res.ok && data.success) {
        showBannerMessage(data.message);
        fetchSslStatus();
      } else {
        showBannerMessage(null, data.error || 'Failed to reissue certificate.');
      }
    } catch (e: any) {
      showBannerMessage(null, 'SSL reissue query failed: ' + e.message);
    } finally {
      setActionLoading(false);
    }
  };

  const handleRemoveSsl = async () => {
    setActionLoading(true);
    try {
      const res = await fetchWithAuth('/api/settings/ssl/remove', { method: 'POST' });
      const data = await res.json();
      if (res.ok && data.success) {
        showBannerMessage(data.message);
        fetchSslStatus();
      } else {
        showBannerMessage(null, data.error || 'Failed to remove SSL certificate.');
      }
    } catch (e: any) {
      showBannerMessage(null, 'SSL removal process failed: ' + e.message);
    } finally {
      setActionLoading(false);
    }
  };

  const handleSaveStreaming = async () => {
    setActionLoading(true);
    try {
      const res = await fetchWithAuth('/api/settings/streaming', {
        method: 'POST',
        body: JSON.stringify(streamingParams)
      });
      const data = await res.json();
      if (res.ok && data.success) {
        showBannerMessage(data.message);
      } else {
        showBannerMessage(null, data.error || 'Failed to save streaming profiles.');
      }
    } catch (e: any) {
      showBannerMessage(null, 'Streaming parameters upload failed: ' + e.message);
    } finally {
      setActionLoading(false);
    }
  };

  const handleSystemControl = async (action: string) => {
    setActionLoading(true);
    try {
      const res = await fetchWithAuth('/api/system/control', {
        method: 'POST',
        body: JSON.stringify({ action })
      });
      const data = await res.json();
      if (res.ok && data.success) {
        showBannerMessage(data.message);
      } else {
        showBannerMessage(null, data.error || 'System action trigger failed.');
      }
    } catch (e: any) {
      showBannerMessage(null, 'System action execution failed: ' + e.message);
    } finally {
      setActionLoading(false);
    }
  };

  const handleBackupDb = async () => {
    setActionLoading(true);
    try {
      const res = await fetchWithAuth('/api/backup/db', { method: 'POST' });
      const data = await res.json();
      if (res.ok && data.success) {
        showBannerMessage(data.message + ` File saved: ${data.file}`);
      } else {
        showBannerMessage(null, data.error || 'Database backup compile failed.');
      }
    } catch (e: any) {
      showBannerMessage(null, 'Backup process query error: ' + e.message);
    } finally {
      setActionLoading(false);
    }
  };

  const handleRestoreDb = async () => {
    setActionLoading(true);
    try {
      const res = await fetchWithAuth('/api/backup/restore', { method: 'POST' });
      const data = await res.json();
      if (res.ok && data.success) {
        showBannerMessage(data.message);
      } else {
        showBannerMessage(null, data.error || 'Restoration failed.');
      }
    } catch (e: any) {
      showBannerMessage(null, 'Restore process error: ' + e.message);
    } finally {
      setActionLoading(false);
    }
  };

  const handleExportConfig = async () => {
    try {
      const res = await fetchWithAuth('/api/backup/export');
      if (res.ok) {
        const blob = await res.blob();
        const url = window.URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = 'streampulse_config.json';
        document.body.appendChild(a);
        a.click();
        a.remove();
        showBannerMessage('Configuration JSON file downloaded successfully.');
      } else {
        showBannerMessage(null, 'Configuration export failed.');
      }
    } catch (e: any) {
      showBannerMessage(null, 'Configuration download error: ' + e.message);
    }
  };

  const handleImportConfig = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    
    setActionLoading(true);
    const reader = new FileReader();
    reader.onload = async (event) => {
      try {
        const config = JSON.parse(event.target?.result as string);
        const res = await fetchWithAuth('/api/backup/import', {
          method: 'POST',
          body: JSON.stringify({ config })
        });
        const data = await res.json();
        if (res.ok && data.success) {
          showBannerMessage(data.message);
          fetchSslStatus();
          fetchStreamingParams();
        } else {
          showBannerMessage(null, data.error || 'Configuration import failed.');
        }
      } catch (err: any) {
        showBannerMessage(null, 'JSON parse failure: ' + err.message);
      } finally {
        setActionLoading(false);
      }
    };
    reader.readAsText(file);
  };

  const handleCreateModuleBackup = async (type: 'stream-settings' | 'users' | 'channels') => {
    setActionLoading(true);
    try {
      const res = await fetchWithAuth(`/api/backup/${type}`, { method: 'POST' });
      const data = await res.json();
      if (res.ok && data.success) {
        showBannerMessage(data.message);
      } else {
        showBannerMessage(null, data.error || 'Backup failed.');
      }
    } catch (e: any) {
      showBannerMessage(null, 'Module backup query error: ' + e.message);
    } finally {
      setActionLoading(false);
    }
  };

  const handleExecuteUpdate = async (target: 'streampulse' | 'docker' | 'system') => {
    setActionLoading(true);
    try {
      const res = await fetchWithAuth('/api/update/execute', {
        method: 'POST',
        body: JSON.stringify({ target })
      });
      const data = await res.json();
      if (res.ok && data.success) {
        showBannerMessage(data.message + ` (${data.details})`);
        checkSoftwareUpdates();
      } else {
        showBannerMessage(null, data.error || 'Update execution aborted.');
      }
    } catch (e: any) {
      showBannerMessage(null, 'Update command failed: ' + e.message);
    } finally {
      setActionLoading(false);
    }
  };

  const handleRunDiagnostics = async () => {
    setRunningDiagnostics(true);
    try {
      const res = await fetchWithAuth('/api/diagnostics/run');
      if (res.ok) {
        const data = await res.json();
        setDiagnosticResults(data);
        showBannerMessage('System diagnostic integrity check completed successfully.');
      } else {
        showBannerMessage(null, 'Diagnostic suite query returned an error.');
      }
    } catch (e: any) {
      showBannerMessage(null, 'Diagnostic engine failed: ' + e.message);
    } finally {
      setRunningDiagnostics(false);
    }
  };

  return (
    <div className="space-y-8" id="settings-page-container">
      {/* Settings Header */}
      <div className="bg-zinc-900 border border-zinc-800 rounded-2xl p-6 flex flex-col md:flex-row justify-between items-start md:items-center gap-4 animate-fadeIn" id="settings-header">
        <div>
          <h2 className="text-xl sm:text-2xl font-bold mb-1 text-zinc-100">Settings & System Management</h2>
          <p className="text-zinc-400 text-sm">Configure routing nodes, manage secure SSL certs, update stream profiles, execute backups, and inspect diagnostic layers.</p>
        </div>
        <div className="flex gap-2">
          <button
            id="refresh-network-btn"
            onClick={fetchNetworkDetails}
            disabled={networkLoading || actionLoading}
            className="flex items-center gap-2 px-4 py-2 bg-zinc-800 hover:bg-zinc-750 text-zinc-100 rounded-xl text-xs font-semibold border border-zinc-700 transition disabled:opacity-50"
          >
            <RefreshCcw className={`w-3.5 h-3.5 ${(networkLoading || actionLoading) ? 'animate-spin' : ''}`} />
            Refresh Network Information
          </button>
          <button
            id="save-network-changes-btn"
            onClick={onSaveNetworkClick}
            disabled={!isNetworkDirty || networkLoading || actionLoading}
            className={`flex items-center gap-2 px-4 py-2 rounded-xl text-xs font-semibold transition-all ${
              isNetworkDirty 
                ? 'bg-blue-600 hover:bg-blue-500 text-white cursor-pointer shadow-md ring-1 ring-blue-400' 
                : 'bg-zinc-800 text-zinc-500 cursor-not-allowed opacity-50'
            }`}
            title={isNetworkDirty ? "Save Network Settings" : "No unsaved network changes"}
          >
            <Save className="w-3.5 h-3.5" />
            {isNetworkDirty ? 'Save Network Settings' : 'Settings Saved'}
          </button>
        </div>
      </div>

      {/* Interactive Message Banners */}
      {(networkSuccess || actionSuccess) && (
        <div className="bg-emerald-500/10 border border-emerald-500/20 rounded-xl p-4 text-xs text-emerald-400 flex items-center gap-2 animate-pulse" id="settings-success-banner">
          <CheckCircle2 className="w-4 h-4 flex-shrink-0" />
          <span>{networkSuccess || actionSuccess}</span>
        </div>
      )}
      {(networkError || actionError) && (
        <div className="bg-red-500/10 border border-red-500/20 rounded-xl p-4 text-xs text-red-400 flex items-center gap-2 animate-pulse" id="settings-error-banner">
          <AlertCircle className="w-4 h-4 flex-shrink-0" />
          <span>{networkError || actionError}</span>
        </div>
      )}

      {/* Navigation Tabs Grid */}
      <div className="flex flex-wrap gap-1.5 p-1 bg-zinc-900 border border-zinc-800 rounded-xl overflow-x-auto">
        {[
          { id: 'network', label: 'Network & Domain', icon: Network },
          { id: 'ssl', label: 'SSL Certificates', icon: Globe },
          { id: 'security', label: 'Account Security', icon: Shield },
          { id: 'streaming', label: 'Streaming Profiles', icon: Tv },
          { id: 'system', label: 'System Controls', icon: Layers },
          { id: 'backup', label: 'Backup & Restore', icon: Database },
          { id: 'updates', label: 'Software Updates', icon: ArrowUpCircle },
          { id: 'diagnostics', label: 'Integrity Check', icon: Activity }
        ].map(tab => {
          const Icon = tab.icon;
          return (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id as any)}
              className={`flex items-center gap-2 px-3 py-2 text-xs font-semibold rounded-lg transition-colors whitespace-nowrap ${activeTab === tab.id ? 'bg-blue-600 text-white shadow-md' : 'text-zinc-400 hover:text-zinc-100 hover:bg-zinc-850'}`}
            >
              <Icon className="w-4 h-4 shrink-0" />
              {tab.label}
            </button>
          );
        })}
      </div>

      {/* Active Tab View Panels */}
      <div className="bg-zinc-900 border border-zinc-800 rounded-2xl p-6 min-h-[350px]">
        {/* TAB 1: NETWORK & DOMAIN */}
        {activeTab === 'network' && (
          <div className="space-y-6 animate-fadeIn">
            <div>
              <h3 className="text-base font-bold text-zinc-100 flex items-center gap-2">
                <Network className="w-5 h-5 text-blue-500" /> Network Resolution & Routing Nodes
              </h3>
              <p className="text-xs text-zinc-400 mt-1">Configure VPS deployment parameters to coordinate players and external RTMP push sources.</p>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div className="space-y-4">
                <div className="space-y-1.5">
                  <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider">Deployment Mode</label>
                  <div className="grid grid-cols-2 gap-2">
                    {([
                      { id: 'auto', label: 'Auto Detect', desc: 'Domain → WAN → LAN IP' },
                      { id: 'lan', label: 'Local LAN Only', desc: 'Lock endpoints to LAN' },
                      { id: 'public', label: 'Public IP Only', desc: 'Lock endpoints to WAN' },
                      { id: 'domain', label: 'Domain Mode', desc: 'Lock endpoints to FQDN' }
                    ] as const).map(mode => (
                      <button
                        key={mode.id}
                        onClick={() => setDeploymentMode(mode.id)}
                        className={`flex flex-col items-center justify-center p-3 rounded-xl border text-center transition ${deploymentMode === mode.id ? 'bg-blue-600/15 border-blue-500 text-blue-400' : 'bg-zinc-950 border-zinc-850 hover:border-zinc-700 text-zinc-400'}`}
                      >
                        <span className="text-xs font-bold">{mode.label}</span>
                        <span className="text-[8px] leading-tight text-zinc-500 mt-0.5">{mode.desc}</span>
                      </button>
                    ))}
                  </div>
                </div>

                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-1.5">
                    <label className="text-[10px] font-bold text-zinc-500 uppercase tracking-wider">Local LAN IP</label>
                    <div className="bg-zinc-950 border border-zinc-850 rounded-lg px-3 py-2 text-xs font-mono text-zinc-300">
                      {detectedLanIp || 'Detecting...'}
                    </div>
                  </div>
                  <div className="space-y-1.5">
                    <label className="text-[10px] font-bold text-zinc-500 uppercase tracking-wider">Public IP</label>
                    <div className="bg-zinc-950 border border-zinc-850 rounded-lg px-3 py-2 text-xs font-mono text-zinc-300">
                      {detectedPublicIp || 'Detecting...'}
                    </div>
                  </div>
                </div>

                <div className="space-y-1.5">
                  <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider">Custom Domain Name</label>
                  <div className="flex gap-2">
                    <input
                      type="text"
                      value={customDomain}
                      onChange={(e) => setCustomDomain(e.target.value)}
                      placeholder="e.g. live.streampulse.io"
                      className="flex-1 bg-zinc-950 border border-zinc-800 rounded-lg px-3 py-2 text-xs font-mono text-emerald-400 outline-none focus:ring-1 focus:ring-emerald-500"
                    />
                    <button
                      onClick={handleValidateDomain}
                      disabled={actionLoading}
                      className="px-3 py-2 bg-zinc-850 hover:bg-zinc-800 border border-zinc-750 text-zinc-300 hover:text-white rounded-lg text-xs font-semibold transition"
                    >
                      Verify DNS
                    </button>
                    <button
                      onClick={handleRemoveDomain}
                      className="px-2.5 py-2 bg-red-950/20 hover:bg-red-900/20 border border-red-900/30 text-red-400 rounded-lg text-xs font-semibold transition"
                    >
                      Clear
                    </button>
                  </div>
                </div>
              </div>

              {/* Resolved Endpoints Card */}
              <div className="space-y-4">
                <div className="bg-zinc-950 border border-zinc-850 rounded-xl p-4.5 space-y-3.5">
                  <h4 className="text-xs font-bold text-zinc-400 uppercase tracking-wider">Active Resolved Endpoints</h4>
                  
                  <div className="space-y-2.5">
                    <div className="space-y-1">
                      <div className="flex justify-between items-center text-[9px] font-bold text-zinc-500 uppercase">
                        <span>Dashboard URL</span>
                        <a href={networkDetails?.dashboardUrl || '#'} target="_blank" rel="noreferrer" className="text-blue-400 hover:underline">Open</a>
                      </div>
                      <div className="bg-zinc-900 border border-zinc-855 rounded-lg px-2.5 py-1.5 text-xs font-mono text-zinc-300 truncate">
                        {networkDetails?.dashboardUrl || 'Endpoint unavailable'}
                      </div>
                    </div>

                    <div className="space-y-1">
                      <div className="text-[9px] font-bold text-zinc-500 uppercase">API Endpoint</div>
                      <div className="bg-zinc-900 border border-zinc-855 rounded-lg px-2.5 py-1.5 text-xs font-mono text-zinc-300 truncate">
                        {networkDetails?.apiUrl || 'Endpoint unavailable'}
                      </div>
                    </div>

                    <div className="space-y-1">
                      <div className="text-[9px] font-bold text-zinc-500 uppercase">RTMP Ingest Address</div>
                      <div className="bg-zinc-900 border border-zinc-855 rounded-lg px-2.5 py-1.5 text-xs font-mono text-blue-400 truncate flex justify-between items-center">
                        <span>{networkDetails?.rtmpUrl || 'Endpoint unavailable'}</span>
                        <CopyButton
                          text={networkDetails?.rtmpUrl || ''}
                          className="text-zinc-500 hover:text-white transition"
                          iconClassName="w-3.5 h-3.5"
                          showIconOnly={true}
                        />
                      </div>
                    </div>

                    <div className="space-y-1">
                      <div className="text-[9px] font-bold text-zinc-500 uppercase">HLS Playback Playlist (M3U8)</div>
                      <div className="bg-zinc-900 border border-zinc-855 rounded-lg px-2.5 py-1.5 text-xs font-mono text-purple-400 truncate">
                        {networkDetails?.hlsUrl ? networkDetails.hlsUrl.replace('{stream_key}', '••••••••') : 'Endpoint unavailable'}
                      </div>
                    </div>
                  </div>
                </div>

                <div className="grid grid-cols-2 gap-3">
                  <button
                    onClick={handleTestRtmp}
                    disabled={testingRtmp}
                    className="flex items-center justify-center gap-2 px-3 py-2 bg-zinc-950 border border-zinc-850 hover:border-zinc-700 text-zinc-300 hover:text-white rounded-xl text-xs font-semibold transition"
                  >
                    {testingRtmp ? <RefreshCcw className="w-3.5 h-3.5 animate-spin" /> : <Terminal className="w-3.5 h-3.5 text-blue-500" />}
                    Test RTMP Port
                  </button>
                  <button
                    onClick={handleTestPlayback}
                    disabled={testingPlayback}
                    className="flex items-center justify-center gap-2 px-3 py-2 bg-zinc-950 border border-zinc-850 hover:border-zinc-700 text-zinc-300 hover:text-white rounded-xl text-xs font-semibold transition"
                  >
                    {testingPlayback ? <RefreshCcw className="w-3.5 h-3.5 animate-spin" /> : <PlayCircle className="w-3.5 h-3.5 text-purple-500" />}
                    Test Playback M3U8
                  </button>
                </div>
              </div>
            </div>

            {/* Domain Verification Diagnostic Card */}
            <div className="border-t border-zinc-800 pt-6 mt-6">
              <div className="bg-zinc-950 border border-zinc-850 rounded-xl p-5 space-y-4">
                <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
                  <div>
                    <h4 className="text-sm font-bold text-zinc-100 flex items-center gap-2">
                      <Shield className="w-4 h-4 text-emerald-500" /> Domain & Production Verification Diagnostics
                    </h4>
                    <p className="text-xs text-zinc-400 mt-0.5">Real-time dynamic system health and routing verification suite.</p>
                  </div>
                  <div className="flex items-center gap-2.5 shrink-0">
                    <button
                      onClick={handleRunDomainVerification}
                      disabled={verifyingDomain}
                      className="flex items-center gap-1.5 px-3 py-1.5 bg-zinc-900 hover:bg-zinc-800 border border-zinc-800 text-zinc-300 hover:text-white rounded-lg text-xs font-semibold transition disabled:opacity-50"
                    >
                      <RefreshCcw className={`w-3.5 h-3.5 ${verifyingDomain ? 'animate-spin' : ''}`} />
                      {verifyingDomain ? 'Verifying...' : 'Re-Run Verification'}
                    </button>
                    {verificationResult && (
                      <span className={`px-2.5 py-1 text-[10px] font-bold uppercase tracking-wider rounded-lg border shadow-sm ${verificationResult.overallStatus === 'Production Ready' ? 'bg-emerald-500/10 border-emerald-500/30 text-emerald-400 shadow-emerald-950/20' : 'bg-red-500/10 border-red-500/30 text-red-400 shadow-red-950/20'}`}>
                        {verificationResult.overallStatus}
                      </span>
                    )}
                  </div>
                </div>

                {verificationResult ? (
                  <div className="space-y-4 animate-fadeIn">
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 bg-zinc-900 border border-zinc-850 p-3.5 rounded-xl text-xs font-mono">
                      <div className="flex justify-between items-center py-0.5">
                        <span className="text-zinc-500">Expected Public IP (VPS)</span>
                        <span className="text-zinc-300 font-bold">{verificationResult.expectedPublicIp}</span>
                      </div>
                      <div className="flex justify-between items-center py-0.5">
                        <span className="text-zinc-500">Detected DNS Resolution IP</span>
                        <span className="text-zinc-300 font-bold">{verificationResult.detectedDnsIp}</span>
                      </div>
                    </div>

                    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
                      {[
                        { label: 'DNS A Record Resolution', status: verificationResult.checks.dnsARecord },
                        { label: 'Public IP Matches VPS', status: verificationResult.checks.publicIpMatches },
                        { label: 'Port 80 (HTTP Listener)', status: verificationResult.checks.port80 },
                        { label: 'Port 443 (HTTPS Listener)', status: verificationResult.checks.port443 },
                        { label: 'Port 1935 (RTMP Ingest)', status: verificationResult.checks.port1935 },
                        { label: 'Docker Container Daemon', status: verificationResult.checks.dockerRunning },
                        { label: 'Nginx Reverse Proxy Process', status: verificationResult.checks.nginxRunning },
                        { label: 'RTMP Streaming Server', status: verificationResult.checks.rtmpRunning },
                        { label: 'HLS Directory Reachable', status: verificationResult.checks.hlsReachable },
                        { label: 'Management Dashboard Port', status: verificationResult.checks.dashboardReachable },
                        { label: 'SSL Certificate Installed', status: verificationResult.checks.sslInstalled },
                      ].map((check, index) => (
                        <div key={index} className="flex items-center justify-between p-3 bg-zinc-900/50 border border-zinc-900 rounded-xl">
                          <span className="text-xs text-zinc-400">{check.label}</span>
                          <span className="flex items-center gap-1.5 shrink-0">
                            {check.status ? (
                              <span className="text-xs font-bold text-emerald-400 flex items-center gap-1">
                                <CheckCircle2 className="w-3.5 h-3.5 text-emerald-500" /> Active
                              </span>
                            ) : (
                              <span className="text-xs font-bold text-zinc-500 flex items-center gap-1">
                                <AlertCircle className="w-3.5 h-3.5 text-zinc-600" /> Inactive
                              </span>
                            )}
                          </span>
                        </div>
                      ))}
                    </div>
                  </div>
                ) : (
                  <div className="flex flex-col items-center justify-center py-6 text-zinc-500 space-y-2">
                    <RefreshCcw className="w-6 h-6 animate-spin text-blue-500" />
                    <span className="text-xs">Initializing dynamic diagnostic check card...</span>
                  </div>
                )}
              </div>
            </div>
          </div>
        )}

        {/* TAB 2: SSL CERTIFICATE MANAGEMENT */}
        {activeTab === 'ssl' && (
          <div className="space-y-6 animate-fadeIn">
            <div>
              <h3 className="text-base font-bold text-zinc-100 flex items-center gap-2">
                <Globe className="w-5 h-5 text-purple-500" /> Let's Encrypt SSL Certificate Center
              </h3>
              <p className="text-xs text-zinc-400 mt-1">Acquire and configure standalone public trusted SSL credentials to route player streams on secure HTTPS and RTMPS networks.</p>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              {/* SSL Details Card */}
              <div className="bg-zinc-950 border border-zinc-850 rounded-xl p-5 space-y-4">
                <div className="flex justify-between items-center">
                  <span className="text-xs font-bold text-zinc-400 uppercase tracking-wide">SSL Certificate Status</span>
                  <span className={`px-2.5 py-0.5 rounded text-[10px] font-mono uppercase font-bold tracking-wider ${sslStatus?.installed ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20' : 'bg-amber-500/10 text-amber-400 border border-amber-500/20'}`}>
                    {sslStatus?.installed ? 'Installed & Secure' : 'HTTP Mode Active'}
                  </span>
                </div>

                <div className="space-y-2.5 font-mono text-xs text-zinc-300">
                  <div className="flex justify-between border-b border-zinc-900 pb-2">
                    <span className="text-zinc-500">Security Issuer</span>
                    <span className="text-zinc-200">{sslStatus?.issuer || 'None (Self-Signed / Untrusted)'}</span>
                  </div>
                  <div className="flex justify-between border-b border-zinc-900 pb-2">
                    <span className="text-zinc-500">HTTPS Transport</span>
                    <span className={`capitalize ${sslStatus?.httpsStatus === 'enabled' ? 'text-emerald-400' : 'text-zinc-500'}`}>
                      {sslStatus?.httpsStatus || 'disabled'}
                    </span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-zinc-500">Expiration Date</span>
                    <span className="text-amber-400">{sslStatus?.expirationDate || 'N/A'}</span>
                  </div>
                </div>

                <div className="pt-2">
                  <p className="text-[10px] text-zinc-500 leading-normal">
                    Let's Encrypt certificates remain valid for 90 days. StreamPulse handles renewal calls in the background automatically when configured.
                  </p>
                </div>
              </div>

              {/* SSL Actions Center */}
              <div className="space-y-4">
                <div className="p-4.5 bg-zinc-950 border border-zinc-850 rounded-xl space-y-3">
                  <h4 className="text-xs font-bold text-zinc-200">Request New SSL Certificate</h4>
                  <p className="text-[11px] text-zinc-400">Attempts a standalone HTTP challenge request on Nginx to generate standard root-level authority files.</p>
                  
                  <button
                    onClick={handleInstallLetsEncrypt}
                    disabled={actionLoading}
                    className="w-full bg-emerald-600 hover:bg-emerald-500 text-white text-xs font-semibold py-2 rounded-lg transition disabled:opacity-50"
                  >
                    Request Let's Encrypt SSL
                  </button>
                </div>

                <div className="grid grid-cols-3 gap-2">
                  <button
                    onClick={handleRenewSsl}
                    disabled={actionLoading}
                    className="px-3 py-2 bg-zinc-950 border border-zinc-850 hover:border-zinc-700 text-zinc-300 text-xs font-medium rounded-lg transition"
                  >
                    Renew
                  </button>
                  <button
                    onClick={handleReissueSsl}
                    disabled={actionLoading}
                    className="px-3 py-2 bg-zinc-950 border border-zinc-850 hover:border-zinc-700 text-zinc-300 text-xs font-medium rounded-lg transition"
                  >
                    Reissue
                  </button>
                  <button
                    onClick={handleRemoveSsl}
                    disabled={actionLoading}
                    className="px-3 py-2 bg-red-950/20 hover:bg-red-900/20 border border-red-900/20 text-red-400 text-xs font-medium rounded-lg transition"
                  >
                    Remove SSL
                  </button>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* TAB 3: ACCOUNT & USER SECURITY */}
        {activeTab === 'security' && (
          <div className="space-y-6 animate-fadeIn">
            <div>
              <h3 className="text-base font-bold text-zinc-100 flex items-center gap-2">
                <Shield className="w-5 h-5 text-emerald-500" /> Account Security & Role-Based Access Control
              </h3>
              <p className="text-xs text-zinc-400 mt-1">Configure user login permissions, rotate administrator secret passwords, or override team security tokens.</p>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              {/* Personal Security */}
              <div className="p-5 bg-zinc-950 border border-zinc-850 rounded-xl space-y-4">
                <h4 className="text-xs font-bold text-zinc-200 uppercase tracking-wider flex items-center gap-2">
                  <User className="w-4 h-4 text-emerald-400" /> Rotate Admin Password
                </h4>
                
                <form onSubmit={handleUpdatePersonalSecurity} className="space-y-3">
                  <div className="space-y-1">
                    <label className="text-[9px] font-bold text-zinc-500 uppercase">Change Username</label>
                    <input
                      type="text"
                      placeholder={currentUser?.username || 'admin'}
                      value={newAdminUsername}
                      onChange={(e) => setNewAdminUsername(e.target.value)}
                      className="w-full bg-zinc-900 border border-zinc-800 rounded-lg px-2.5 py-1.5 text-xs text-zinc-200 outline-none focus:ring-1 focus:ring-emerald-500"
                    />
                  </div>
                  <div className="space-y-1">
                    <label className="text-[9px] font-bold text-zinc-500 uppercase">New Master Password</label>
                    <input
                      type="password"
                      placeholder="••••••••"
                      value={newAdminPassword}
                      onChange={(e) => setNewAdminPassword(e.target.value)}
                      className="w-full bg-zinc-900 border border-zinc-800 rounded-lg px-2.5 py-1.5 text-xs text-zinc-200 outline-none focus:ring-1 focus:ring-emerald-500"
                    />
                  </div>
                  <div className="space-y-1">
                    <label className="text-[9px] font-bold text-zinc-500 uppercase">Confirm Password</label>
                    <input
                      type="password"
                      placeholder="••••••••"
                      value={confirmAdminPassword}
                      onChange={(e) => setConfirmAdminPassword(e.target.value)}
                      className="w-full bg-zinc-900 border border-zinc-800 rounded-lg px-2.5 py-1.5 text-xs text-zinc-200 outline-none focus:ring-1 focus:ring-emerald-500"
                    />
                  </div>
                  <button
                    type="submit"
                    disabled={!isAdminSecurityDirty || securityLoading}
                    className={`w-full text-xs font-semibold py-2 rounded-lg transition-all ${
                      isAdminSecurityDirty && (!newAdminPassword || newAdminPassword === confirmAdminPassword)
                        ? 'bg-emerald-600 hover:bg-emerald-500 text-white cursor-pointer shadow-md' 
                        : 'bg-zinc-800 text-zinc-500 cursor-not-allowed opacity-50'
                    }`}
                  >
                    {securityLoading ? 'Updating...' : isAdminSecurityDirty ? 'Save Security Changes' : 'No Unsaved Security Changes'}
                  </button>
                </form>
              </div>

              {/* Force password resets & team credentials overrides */}
              {currentUser?.role === 'admin' && (
                <div className="p-5 bg-zinc-950 border border-zinc-850 rounded-xl space-y-4">
                  <h4 className="text-xs font-bold text-zinc-200 uppercase tracking-wider flex items-center gap-2">
                    <Lock className="w-4 h-4 text-red-500" /> User Force Reset Policies
                  </h4>
                  
                  <form onSubmit={handleUpdateUserSecurity} className="space-y-3">
                    <div className="space-y-1">
                      <label className="text-[9px] font-bold text-zinc-500 uppercase">Target Team Member</label>
                      <select
                        value={adminTargetUser}
                        onChange={(e) => setAdminTargetUser(e.target.value)}
                        className="w-full bg-zinc-900 border border-zinc-800 rounded-lg px-2.5 py-1.5 text-xs text-zinc-200 outline-none"
                      >
                        <option value="">-- Select Target User --</option>
                        {usersList
                          .filter(u => u.id !== currentUser?.id)
                          .map(u => (
                            <option key={u.id} value={u.id}>{u.username} ({u.role})</option>
                          ))}
                      </select>
                    </div>

                    <div className="space-y-1">
                      <label className="text-[9px] font-bold text-zinc-500 uppercase">Override Password</label>
                      <input
                        type="password"
                        placeholder="Master override credential string"
                        value={adminUserPassword}
                        onChange={(e) => setAdminUserPassword(e.target.value)}
                        className="w-full bg-zinc-900 border border-zinc-800 rounded-lg px-2.5 py-1.5 text-xs text-zinc-200 outline-none focus:ring-1 focus:ring-red-500"
                      />
                    </div>

                    <div className="flex items-center gap-2 py-1">
                      <input
                        id="admin-reset-check"
                        type="checkbox"
                        checked={adminForceReset}
                        onChange={(e) => setAdminForceReset(e.target.checked)}
                        className="rounded bg-zinc-900 border-zinc-800 text-red-600 focus:ring-0"
                      />
                      <label htmlFor="admin-reset-check" className="text-xs text-zinc-400 font-medium select-none">
                        Force change on next authentication
                      </label>
                    </div>

                    <button
                      type="submit"
                      disabled={!isTeamSecurityDirty || securityLoading}
                      className={`w-full text-xs font-semibold py-2 rounded-lg transition-all ${
                        isTeamSecurityDirty
                          ? 'bg-red-600 hover:bg-red-500 text-white cursor-pointer shadow-md' 
                          : 'bg-zinc-800 text-zinc-500 cursor-not-allowed opacity-50'
                      }`}
                    >
                      {securityLoading ? 'Saving...' : isTeamSecurityDirty ? 'Save Security Lock' : 'No User Changes'}
                    </button>
                  </form>
                </div>
              )}
            </div>
          </div>
        )}

        {/* TAB 4: STREAMING & QUALITY */}
        {activeTab === 'streaming' && (
          <div className="space-y-6 animate-fadeIn">
            <div>
              <h3 className="text-base font-bold text-zinc-100 flex items-center gap-2">
                <Tv className="w-5 h-5 text-amber-500" /> Streaming Engine Port & Profile Parameters
              </h3>
              <p className="text-xs text-zinc-400 mt-1">Configure active transcoding resolutions, HLS manifest chunk specifications, or video record flags.</p>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div className="space-y-4">
                <div className="grid grid-cols-3 gap-3">
                  <div className="space-y-1.5">
                    <label className="text-[9px] font-bold text-zinc-500 uppercase">RTMP Ingest Port</label>
                    <input
                      type="number"
                      value={streamingParams.rtmpPort}
                      onChange={(e) => setStreamingParams({ ...streamingParams, rtmpPort: Number(e.target.value) })}
                      className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-2.5 py-1.5 text-xs font-mono text-zinc-200 outline-none"
                    />
                  </div>
                  <div className="space-y-1.5">
                    <label className="text-[9px] font-bold text-zinc-500 uppercase">HTTP Port</label>
                    <input
                      type="number"
                      value={streamingParams.httpPort}
                      onChange={(e) => setStreamingParams({ ...streamingParams, httpPort: Number(e.target.value) })}
                      className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-2.5 py-1.5 text-xs font-mono text-zinc-200 outline-none"
                    />
                  </div>
                  <div className="space-y-1.5">
                    <label className="text-[9px] font-bold text-zinc-500 uppercase">HTTPS Port</label>
                    <input
                      type="number"
                      value={streamingParams.httpsPort}
                      onChange={(e) => setStreamingParams({ ...streamingParams, httpsPort: Number(e.target.value) })}
                      className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-2.5 py-1.5 text-xs font-mono text-zinc-200 outline-none"
                    />
                  </div>
                </div>

                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-1.5">
                    <label className="text-[9px] font-bold text-zinc-500 uppercase">HLS Chunk Duration (Secs)</label>
                    <input
                      type="number"
                      value={streamingParams.hlsSegmentDuration}
                      onChange={(e) => setStreamingParams({ ...streamingParams, hlsSegmentDuration: Number(e.target.value) })}
                      className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-2.5 py-1.5 text-xs font-mono text-zinc-200 outline-none"
                    />
                  </div>
                  <div className="space-y-1.5">
                    <label className="text-[9px] font-bold text-zinc-500 uppercase">Playlist Max Length</label>
                    <input
                      type="number"
                      value={streamingParams.playlistLength}
                      onChange={(e) => setStreamingParams({ ...streamingParams, playlistLength: Number(e.target.value) })}
                      className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-2.5 py-1.5 text-xs font-mono text-zinc-200 outline-none"
                    />
                  </div>
                </div>

                <div className="flex items-center gap-2 py-2">
                  <input
                    id="rec-enable-check"
                    type="checkbox"
                    checked={streamingParams.recordingEnabled}
                    onChange={(e) => setStreamingParams({ ...streamingParams, recordingEnabled: e.target.checked })}
                    className="rounded bg-zinc-950 border-zinc-800 text-blue-600 focus:ring-0"
                  />
                  <label htmlFor="rec-enable-check" className="text-xs text-zinc-300 font-semibold select-none">
                    Enable Continuous Streaming Video Recording (Save to HLS root)
                  </label>
                </div>
              </div>

              {/* FFMPEG profiles configuration */}
              <div className="bg-zinc-950 border border-zinc-850 rounded-xl p-4.5 space-y-4">
                <h4 className="text-xs font-bold text-zinc-200 uppercase tracking-wider">Active FFmpeg Transcode Quality Profiles</h4>
                <p className="text-[11px] text-zinc-500 leading-normal">
                  Toggle output transcoding pipelines to compile distinct streams adaptively. Removing configurations decreases server resource load.
                </p>

                <div className="grid grid-cols-2 gap-2">
                  {Object.keys(streamingParams.ffmpegProfiles).map((profile) => {
                    const active = (streamingParams.ffmpegProfiles as any)[profile];
                    return (
                      <button
                        key={profile}
                        onClick={() => {
                          const updatedProfiles = { ...streamingParams.ffmpegProfiles, [profile]: !active };
                          setStreamingParams({ ...streamingParams, ffmpegProfiles: updatedProfiles });
                        }}
                        className={`flex items-center justify-between p-2.5 rounded-lg border text-xs font-mono font-bold transition ${active ? 'bg-blue-600/10 border-blue-500 text-blue-400' : 'bg-zinc-900 border-zinc-800 text-zinc-500'}`}
                      >
                        <span>{profile}</span>
                        <span className={`text-[10px] uppercase font-bold ${active ? 'text-emerald-400 font-bold' : 'text-zinc-600'}`}>
                          {active ? 'Active' : 'Disabled'}
                        </span>
                      </button>
                    );
                  })}
                </div>

                <div className="pt-2">
                  <button
                    onClick={onSaveStreamingClick}
                    disabled={!isStreamingDirty || actionLoading}
                    className={`w-full text-xs font-semibold py-2 rounded-lg transition-all ${
                      isStreamingDirty 
                        ? 'bg-blue-600 hover:bg-blue-500 text-white cursor-pointer shadow-md ring-1 ring-blue-400' 
                        : 'bg-zinc-800 text-zinc-500 cursor-not-allowed opacity-50'
                    }`}
                    title={isStreamingDirty ? "Save Streaming Engine Configuration" : "No unsaved streaming changes"}
                  >
                    {isStreamingDirty ? 'Save Streaming Engine Configuration' : 'Streaming Settings Saved'}
                  </button>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* TAB 5: SYSTEM CONTROL OPERATIONS */}
        {activeTab === 'system' && (
          <div className="space-y-6 animate-fadeIn">
            <div>
              <h3 className="text-base font-bold text-zinc-100 flex items-center gap-2">
                <Layers className="w-5 h-5 text-blue-400" /> Infrastructure & Orchestrator Restart Panel
              </h3>
              <p className="text-xs text-zinc-400 mt-1">Directly trigger reboots across modular services, clear server HLS file cache, or restart host orchestrators safely.</p>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
              {[
                { action: 'restart_streampulse', label: 'Restart StreamPulse', desc: 'Restarts the primary Node API and manager application container process.', color: 'text-blue-500' },
                { action: 'restart_docker', label: 'Reboot Docker Compose', desc: 'Runs docker-compose down & up to hard reboot the entire network infrastructure.', color: 'text-blue-500' },
                { action: 'reload_nginx', label: 'Reload Nginx Engine', desc: 'Performs a hot config reload on the reverse proxy without dropping sessions.', color: 'text-teal-400' },
                { action: 'restart_ffmpeg', label: 'Kill Running Transcoders', desc: 'Abruptly kills all spawned FFmpeg pipelines, allowing automated recovery loops.', color: 'text-amber-500' },
                { action: 'restart_postgres', label: 'Restart Database Stack', desc: 'Triggers a safe service reload on PostgreSQL databases or local state nodes.', color: 'text-blue-400' },
                { action: 'restart_rtmp', label: 'Reboot RTMP Daemon', desc: 'Restarts the Nginx streaming ingress daemon listeners.', color: 'text-indigo-400' },
                { action: 'restart_api', label: 'Restart API Server Only', desc: 'Restarts the internal HTTP API routes thread without touching frontends.', color: 'text-purple-400' },
                { action: 'restart_frontend', label: 'Reload Frontend Portal', desc: 'Reloads Webpack or Vite client static assets serving threads.', color: 'text-emerald-400' },
                { action: 'clear_cache', label: 'Clear Stream Cache', desc: 'Completely purges all TS chunks and generated HLS playlist files.', color: 'text-red-400' },
              ].map((item) => (
                <div key={item.action} className="bg-zinc-950 border border-zinc-850 p-4.5 rounded-xl space-y-3 flex flex-col justify-between">
                  <div>
                    <h4 className="text-xs font-bold text-zinc-100 flex items-center gap-2">
                      <Terminal className={`w-3.5 h-3.5 ${item.color}`} />
                      {item.label}
                    </h4>
                    <p className="text-[10px] text-zinc-500 leading-normal mt-1">{item.desc}</p>
                  </div>
                  <button
                    onClick={() => handleSystemControl(item.action)}
                    disabled={actionLoading}
                    className="w-full bg-zinc-900 hover:bg-zinc-850 border border-zinc-800 text-zinc-300 hover:text-white py-1.5 rounded-lg text-[11px] font-semibold transition"
                  >
                    Execute Command
                  </button>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* TAB 6: BACKUP & RECOVERY */}
        {activeTab === 'backup' && (
          <div className="space-y-6 animate-fadeIn">
            <div>
              <h3 className="text-base font-bold text-zinc-100 flex items-center gap-2">
                <Database className="w-5 h-5 text-emerald-400" /> Backup, Disaster Recovery & Configurations
              </h3>
              <p className="text-xs text-zinc-400 mt-1">Generate complete database snapshots, download backup configuration JSONs, or recover state machines.</p>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              {/* Core DB Backup and Restoration */}
              <div className="p-5 bg-zinc-950 border border-zinc-850 rounded-xl space-y-4">
                <h4 className="text-xs font-bold text-zinc-200 uppercase tracking-wider flex items-center gap-2">
                  <Database className="w-4 h-4 text-emerald-500" /> Core Database Snapshot
                </h4>
                <p className="text-[11px] text-zinc-500 leading-normal">
                  Back up all database instances (PostgreSQL tables or JSON files). Restores are executed against the latest compiled snapshot in `/data`.
                </p>

                <div className="grid grid-cols-2 gap-3 pt-1">
                  <button
                    onClick={handleBackupDb}
                    disabled={actionLoading}
                    className="flex items-center justify-center gap-2 py-2 bg-emerald-600 hover:bg-emerald-500 text-white rounded-lg text-xs font-semibold transition"
                  >
                    Create Snapshot
                  </button>
                  <button
                    onClick={handleRestoreDb}
                    disabled={actionLoading}
                    className="flex items-center justify-center gap-2 py-2 bg-zinc-900 hover:bg-zinc-850 border border-zinc-800 text-zinc-300 rounded-lg text-xs font-semibold transition"
                  >
                    Restore Latest
                  </button>
                </div>
              </div>

              {/* Module backups */}
              <div className="p-5 bg-zinc-950 border border-zinc-850 rounded-xl space-y-4">
                <h4 className="text-xs font-bold text-zinc-200 uppercase tracking-wider">Modular Backups</h4>
                <p className="text-[11px] text-zinc-500 leading-normal">
                  Isolate backup files of distinct StreamPulse blocks. Backup JSON logs are generated in your local `/data` directory.
                </p>

                <div className="grid grid-cols-3 gap-2">
                  <button
                    onClick={() => handleCreateModuleBackup('stream-settings')}
                    disabled={actionLoading}
                    className="py-1.5 bg-zinc-900 hover:bg-zinc-850 border border-zinc-800 text-zinc-300 text-[11px] font-semibold rounded-lg transition"
                  >
                    Stream Config
                  </button>
                  <button
                    onClick={() => handleCreateModuleBackup('users')}
                    disabled={actionLoading}
                    className="py-1.5 bg-zinc-900 hover:bg-zinc-850 border border-zinc-800 text-zinc-300 text-[11px] font-semibold rounded-lg transition"
                  >
                    User Profiles
                  </button>
                  <button
                    onClick={() => handleCreateModuleBackup('channels')}
                    disabled={actionLoading}
                    className="py-1.5 bg-zinc-900 hover:bg-zinc-850 border border-zinc-800 text-zinc-300 text-[11px] font-semibold rounded-lg transition"
                  >
                    Channels/Keys
                  </button>
                </div>
              </div>

              {/* Import/Export Config */}
              <div className="p-5 bg-zinc-950 border border-zinc-850 rounded-xl space-y-4 md:col-span-2">
                <h4 className="text-xs font-bold text-zinc-200 uppercase tracking-wider flex items-center gap-2">
                  <Upload className="w-4 h-4 text-blue-400" /> Export & Import System Configuration
                </h4>
                <p className="text-[11px] text-zinc-400 leading-normal">
                  Downloads a local backup file containing your serverSettings, forcedPasswordResets, and configuration hashes. Use the Import feature to instantly restore the same platform metadata onto another StreamPulse host node.
                </p>

                <div className="flex flex-col sm:flex-row gap-4 pt-1">
                  <button
                    onClick={handleExportConfig}
                    className="flex items-center justify-center gap-2 px-5 py-2 bg-blue-600 hover:bg-blue-500 text-white rounded-lg text-xs font-semibold transition"
                  >
                    <Download className="w-3.5 h-3.5" /> Export Configuration JSON
                  </button>

                  <div className="flex-1 relative">
                    <input
                      type="file"
                      accept=".json"
                      onChange={handleImportConfig}
                      disabled={actionLoading}
                      className="hidden"
                      id="import-config-file"
                    />
                    <label
                      htmlFor="import-config-file"
                      className="flex items-center justify-center gap-2 w-full sm:w-auto px-5 py-2 bg-zinc-900 hover:bg-zinc-850 border border-zinc-800 text-zinc-300 rounded-lg text-xs font-semibold cursor-pointer transition select-none"
                    >
                      <Upload className="w-3.5 h-3.5" /> Import Configuration JSON File
                    </label>
                  </div>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* TAB 7: SOFTWARE UPDATES */}
        {activeTab === 'updates' && (
          <div className="space-y-6 animate-fadeIn">
            <div>
              <h3 className="text-base font-bold text-zinc-100 flex items-center gap-2">
                <ArrowUpCircle className="w-5 h-5 text-blue-500" /> Software Updates & Repository Version Checks
              </h3>
              <p className="text-xs text-zinc-400 mt-1">Check for recent StreamPulse repository updates, pull Docker images, or upgrade Linux hosting packages.</p>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              {/* Version Details */}
              <div className="bg-zinc-950 border border-zinc-850 rounded-xl p-5 space-y-4 font-mono text-xs">
                <div className="flex justify-between border-b border-zinc-900 pb-2">
                  <span className="text-zinc-500 font-sans">Installed Version</span>
                  <span className="text-zinc-200 font-bold">{updateDetails?.installedVersion || '1.2.4'}</span>
                </div>
                <div className="flex justify-between border-b border-zinc-900 pb-2">
                  <span className="text-zinc-500 font-sans">Latest Available Release</span>
                  <span className="text-emerald-400 font-bold">{updateDetails?.latestVersion || '1.3.0'}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-zinc-500 font-sans">Update Status</span>
                  <span className={`font-bold font-sans ${updateDetails?.updateAvailable ? 'text-amber-400' : 'text-zinc-500'}`}>
                    {updateDetails?.updateAvailable ? 'Upgrade Available' : 'Current Codebase Up-To-Date'}
                  </span>
                </div>
              </div>

              {/* Update Triggers */}
              <div className="p-4.5 bg-zinc-950 border border-zinc-850 rounded-xl space-y-3">
                <h4 className="text-xs font-bold text-zinc-200 uppercase tracking-wider">Trigger System Upgrade</h4>
                <p className="text-[10px] text-zinc-500 leading-normal">
                  Triggers production level commands across distinct target groups. Host must have connection privileges.
                </p>

                <div className="space-y-2">
                  <button
                    onClick={() => handleExecuteUpdate('streampulse')}
                    disabled={actionLoading}
                    className="w-full flex items-center justify-between px-3 py-2 bg-zinc-900 hover:bg-zinc-850 border border-zinc-800 text-zinc-200 hover:text-white rounded-lg text-xs font-semibold transition"
                  >
                    <span>Update StreamPulse Code</span>
                    <span className="text-[10px] font-mono font-bold text-blue-400">git pull</span>
                  </button>

                  <button
                    onClick={() => handleExecuteUpdate('docker')}
                    disabled={actionLoading}
                    className="w-full flex items-center justify-between px-3 py-2 bg-zinc-900 hover:bg-zinc-850 border border-zinc-800 text-zinc-200 hover:text-white rounded-lg text-xs font-semibold transition"
                  >
                    <span>Pull Docker Stack Images</span>
                    <span className="text-[10px] font-mono font-bold text-teal-400">compose pull</span>
                  </button>

                  <button
                    onClick={() => handleExecuteUpdate('system')}
                    disabled={actionLoading}
                    className="w-full flex items-center justify-between px-3 py-2 bg-zinc-900 hover:bg-zinc-850 border border-zinc-800 text-zinc-200 hover:text-white rounded-lg text-xs font-semibold transition"
                  >
                    <span>Upgrade OS Packages (ffmpeg/openssl)</span>
                    <span className="text-[10px] font-mono font-bold text-amber-500">apt-get upgrade</span>
                  </button>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* TAB 8: DIAGNOSTICS & SYSTEM INTEGRITY CHECKS */}
        {activeTab === 'diagnostics' && (
          <div className="space-y-6 animate-fadeIn">
            <div>
              <h3 className="text-base font-bold text-zinc-100 flex items-center gap-2">
                <Activity className="w-5 h-5 text-blue-500" /> Advanced Diagnostic & Integrity Verification Suite
              </h3>
              <p className="text-xs text-zinc-400 mt-1">One-click testing matrix checking Database, Docker, Nginx, FFmpeg, ports, HLS chunkers, resources, and network paths.</p>
            </div>

            <div className="space-y-4">
              <div className="flex justify-between items-center bg-zinc-950 border border-zinc-850 p-4 rounded-xl">
                <div>
                  <h4 className="text-xs font-bold text-zinc-200">Run Comprehensive Integrity Test Suite</h4>
                  <p className="text-[10px] text-zinc-500 leading-normal mt-0.5">Executes real validation checks across all 11 critical modular layers.</p>
                </div>
                <button
                  onClick={handleRunDiagnostics}
                  disabled={runningDiagnostics}
                  className="flex items-center gap-2 px-5 py-2 bg-blue-600 hover:bg-blue-500 text-white rounded-xl text-xs font-bold transition disabled:opacity-50"
                >
                  {runningDiagnostics ? <RefreshCcw className="w-3.5 h-3.5 animate-spin" /> : <Activity className="w-3.5 h-3.5" />}
                  {runningDiagnostics ? 'Evaluating Systems...' : 'Trigger Integrity Diagnostic'}
                </button>
              </div>

              {/* Diagnostic Results Grid */}
              {diagnosticResults ? (
                <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
                  {Object.keys(diagnosticResults).map((system) => {
                    const result = diagnosticResults[system];
                    return (
                      <div key={system} className="bg-zinc-950 border border-zinc-850 p-3.5 rounded-xl space-y-2">
                        <div className="flex justify-between items-start">
                          <span className="text-xs font-bold text-zinc-200">{system}</span>
                          <span className={`px-2 py-0.5 rounded text-[8px] font-mono font-bold uppercase tracking-wider ${
                            result.status === 'pass' ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20' :
                            result.status === 'warning' ? 'bg-amber-500/10 text-amber-400 border border-amber-500/20' :
                            'bg-red-500/10 text-red-400 border border-red-500/20'
                          }`}>
                            {result.status}
                          </span>
                        </div>
                        <p className="text-[10px] text-zinc-400 leading-normal font-mono">{result.message}</p>
                      </div>
                    );
                  })}
                </div>
              ) : (
                <div className="bg-zinc-950/40 border border-dashed border-zinc-850 rounded-xl p-12 text-center text-zinc-500 space-y-2">
                  <Activity className="w-8 h-8 text-zinc-600 mx-auto" />
                  <p className="text-xs">No diagnostic logs found. Run the suite to view system status.</p>
                </div>
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  );
};
