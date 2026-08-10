import React, { useState, useEffect } from 'react';
import { CopyButton } from './CopyButton';
import { copyToClipboard } from '../utils/clipboard';
import { 
  Tv, 
  Cpu, 
  Activity, 
  Wifi, 
  WifiOff, 
  Clock, 
  Plus, 
  Trash2, 
  Play, 
  Square, 
  RotateCcw, 
  Power, 
  Terminal, 
  Download, 
  Sliders, 
  RefreshCw, 
  Check, 
  AlertCircle, 
  Server, 
  Copy, 
  ExternalLink,
  Shield,
  Zap,
  HardDrive,
  Monitor,
  Settings,
  ChevronRight
} from 'lucide-react';
import { StreamSession, Device } from '../types';

interface RaspberryPlayerProps {
  token: string | null;
  streams: StreamSession[];
  networkDetails?: any;
}

interface RpiConfig {
  defaultStreamKey: string;
  defaultStreamUrl: string;
  fallbackSequence: ('hlsjs' | 'videojs' | 'vlc')[];
  hardwareAcceleration: {
    enabled: boolean;
    decoder: 'auto' | 'v4l2m2m' | 'mmal' | 'drm_kms' | 'hevc_v4l2m2m';
    cmaMemoryMb: number;
    gpuMemMb: number;
  };
  display: {
    kioskMode: boolean;
    fullscreen: boolean;
    hideCursorTimeoutMs: number;
    blackScreenOffline: boolean;
    autoPlayLive: boolean;
    showReconnectOverlay: boolean;
  };
  network: {
    autoReconnect: boolean;
    reconnectIntervalMs: number;
    heartbeatIntervalMs: number;
    maxBackoffIntervalMs: number;
  };
}

export const RaspberryPlayer: React.FC<RaspberryPlayerProps> = ({ token, streams, networkDetails }) => {
  const [activeSubTab, setActiveSubTab] = useState<'devices' | 'config' | 'deployment'>('devices');
  const [devices, setDevices] = useState<Device[]>([]);
  const [loading, setLoading] = useState(true);
  const [actionMessage, setActionMessage] = useState<{ type: 'success' | 'error'; text: string } | null>(null);

  // Configuration state
  const [rpiConfig, setRpiConfig] = useState<RpiConfig>({
    defaultStreamKey: '',
    defaultStreamUrl: '',
    fallbackSequence: ['hlsjs', 'videojs', 'vlc'],
    hardwareAcceleration: {
      enabled: true,
      decoder: 'auto',
      cmaMemoryMb: 256,
      gpuMemMb: 256
    },
    display: {
      kioskMode: true,
      fullscreen: true,
      hideCursorTimeoutMs: 2000,
      blackScreenOffline: true,
      autoPlayLive: true,
      showReconnectOverlay: true
    },
    network: {
      autoReconnect: true,
      reconnectIntervalMs: 3000,
      heartbeatIntervalMs: 5000,
      maxBackoffIntervalMs: 15000
    }
  });

  // Script viewer active tab
  const [scriptTab, setScriptTab] = useState<'installer' | 'systemd' | 'kiosk' | 'autoupdate'>('installer');
  const [scriptContents, setScriptContents] = useState<Record<string, string>>({
    installer: '',
    systemd: '',
    kiosk: '',
    autoupdate: ''
  });

  // Modals & inputs
  const [selectedStreamKey, setSelectedStreamKey] = useState<string>('');
  const [isRegisterModalOpen, setIsRegisterModalOpen] = useState(false);
  const [newDeviceName, setNewDeviceName] = useState('');
  const [newDeviceModel, setNewDeviceModel] = useState<'Pi 5' | 'Pi 4B'>('Pi 5');
  const [newDeviceOs, setNewDeviceOs] = useState<'Raspberry Pi OS Lite' | 'Raspberry Pi OS Desktop'>('Raspberry Pi OS Lite');
  const [newDeviceIp, setNewDeviceIp] = useState('');
  const [newDeviceMac, setNewDeviceMac] = useState('');

  // Fetch devices and config
  const fetchData = async () => {
    try {
      setLoading(true);
      const headers = { 'Authorization': `Bearer ${token}` };

      // Fetch devices
      const devRes = await fetch('/api/devices', { headers });
      if (devRes.ok) {
        const devData = await devRes.json();
        setDevices(devData);
      }

      // Fetch RPi Config
      const cfgRes = await fetch('/api/rpi-player/config', { headers });
      if (cfgRes.ok) {
        const cfgData = await cfgRes.json();
        setRpiConfig(cfgData);
        if (cfgData.defaultStreamKey) {
          setSelectedStreamKey(cfgData.defaultStreamKey);
        } else if (streams.length > 0) {
          setSelectedStreamKey(streams[0].streamKey);
        }
      }

      // Fetch scripts
      const activeKey = selectedStreamKey || (streams[0]?.streamKey) || 'live_stream';
      const [setupRes, sysRes, kioskRes, updateRes] = await Promise.all([
        fetch(`/api/rpi-player/script/setup?streamKey=${activeKey}`),
        fetch(`/api/rpi-player/script/systemd`),
        fetch(`/api/rpi-player/script/autostart?streamKey=${activeKey}`),
        fetch(`/api/rpi-player/script/autoupdate`)
      ]);

      const setupText = setupRes.ok ? await setupRes.text() : '';
      const sysText = sysRes.ok ? await sysRes.text() : '';
      const kioskText = kioskRes.ok ? await kioskRes.text() : '';
      const updateText = updateRes.ok ? await updateRes.text() : '';

      setScriptContents({
        installer: setupText,
        systemd: sysText,
        kiosk: kioskText,
        autoupdate: updateText
      });

    } catch (err: any) {
      console.error('Failed to load Raspberry Player data:', err);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchData();
  }, [token]);

  // Handle stream key change for script generation
  useEffect(() => {
    if (selectedStreamKey) {
      fetch(`/api/rpi-player/script/setup?streamKey=${selectedStreamKey}`)
        .then(r => r.text())
        .then(t => setScriptContents(prev => ({ ...prev, installer: t })));

      fetch(`/api/rpi-player/script/autostart?streamKey=${selectedStreamKey}`)
        .then(r => r.text())
        .then(t => setScriptContents(prev => ({ ...prev, kiosk: t })));
    }
  }, [selectedStreamKey]);

  // Save Config handler
  const handleSaveConfig = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      const res = await fetch('/api/rpi-player/config', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`
        },
        body: JSON.stringify(rpiConfig)
      });

      if (res.ok) {
        const data = await res.json();
        setRpiConfig(data.config);
        setActionMessage({ type: 'success', text: 'Raspberry Pi Player configuration saved successfully!' });
      } else {
        const err = await res.json();
        setActionMessage({ type: 'error', text: err.error || 'Failed to save configuration.' });
      }
    } catch (err: any) {
      setActionMessage({ type: 'error', text: 'Network error saving configuration.' });
    }
    setTimeout(() => setActionMessage(null), 4000);
  };

  // Register device handler
  const handleRegisterDevice = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!newDeviceName) return;

    try {
      const res = await fetch('/api/devices/register', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          name: newDeviceName,
          os_version: `${newDeviceModel} (${newDeviceOs})`,
          ip_address: newDeviceIp || '192.168.1.100',
          mac_address: newDeviceMac || undefined,
          player_version: '1.2.4-rpi'
        })
      });

      if (res.ok) {
        setIsRegisterModalOpen(false);
        setNewDeviceName('');
        setNewDeviceIp('');
        setNewDeviceMac('');
        fetchData();
        setActionMessage({ type: 'success', text: `Raspberry Pi device "${newDeviceName}" registered successfully!` });
      } else {
        const err = await res.json();
        setActionMessage({ type: 'error', text: err.error || 'Failed to register device.' });
      }
    } catch (e) {
      setActionMessage({ type: 'error', text: 'Error registering Raspberry Pi device.' });
    }
    setTimeout(() => setActionMessage(null), 4000);
  };

  // Remote command handler
  const handleRemoteCommand = async (deviceId: string, command: string, args?: any) => {
    try {
      const res = await fetch(`/api/devices/${deviceId}/command`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`
        },
        body: JSON.stringify({ command, args })
      });

      if (res.ok) {
        setActionMessage({ type: 'success', text: `Command "${command.toUpperCase()}" sent to Raspberry Pi player.` });
        fetchData();
      } else {
        setActionMessage({ type: 'error', text: 'Failed to dispatch command to device.' });
      }
    } catch (e) {
      setActionMessage({ type: 'error', text: 'Network error sending command.' });
    }
    setTimeout(() => setActionMessage(null), 4000);
  };

  // Unregister device handler
  const handleDeleteDevice = async (deviceId: string, deviceName: string) => {
    if (!window.confirm(`Are you sure you want to unregister "${deviceName}"?`)) return;

    try {
      const res = await fetch(`/api/devices/${deviceId}`, {
        method: 'DELETE',
        headers: { 'Authorization': `Bearer ${token}` }
      });

      if (res.ok) {
        setActionMessage({ type: 'success', text: `Device "${deviceName}" deleted.` });
        fetchData();
      }
    } catch (e) {
      setActionMessage({ type: 'error', text: 'Failed to delete device.' });
    }
    setTimeout(() => setActionMessage(null), 4000);
  };

  const serverOrigin = typeof window !== 'undefined' ? window.location.origin : 'http://localhost:3000';
  const activeStream = streams.find(s => s.streamKey === selectedStreamKey) || streams[0];
  const activeKey = selectedStreamKey || activeStream?.streamKey || 'live_stream';
  const curlCommand = `curl -sSL "${serverOrigin}/api/rpi-player/script/setup?streamKey=${activeKey}" | sudo bash`;

  const totalDevices = devices.length;
  const playingDevices = devices.filter(d => d.online_status === 'playing' || d.online_status === 'online').length;
  const offlineDevices = totalDevices - playingDevices;

  return (
    <div className="space-y-6">
      {/* Top Banner Header */}
      <div className="bg-slate-900 border border-slate-800 rounded-xl p-6 shadow-xl relative overflow-hidden">
        <div className="absolute top-0 right-0 w-96 h-96 bg-indigo-500/10 rounded-full blur-3xl pointer-events-none -mr-20 -mt-20"></div>
        <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-4 relative z-10">
          <div>
            <div className="flex items-center gap-3 mb-2">
              <div className="p-2.5 bg-indigo-500/20 border border-indigo-500/30 rounded-lg text-indigo-400">
                <Tv className="w-6 h-6" />
              </div>
              <div>
                <h1 className="text-2xl font-bold text-white tracking-tight">Raspberry Pi Streaming Player</h1>
                <p className="text-sm text-slate-400">Production Kiosk Player Management, Hardware Acceleration & Deployment</p>
              </div>
            </div>
          </div>

          <div className="flex items-center gap-3">
            <button
              onClick={fetchData}
              className="inline-flex items-center gap-2 px-3.5 py-2 bg-slate-800 hover:bg-slate-700 text-slate-200 border border-slate-700 rounded-lg text-sm font-medium transition-colors"
            >
              <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
              Refresh
            </button>
            <a
              href={`/rpi-kiosk?streamKey=${activeKey}`}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-2 px-4 py-2 bg-indigo-600 hover:bg-indigo-500 text-white rounded-lg text-sm font-medium transition-colors shadow-lg shadow-indigo-600/20"
            >
              <ExternalLink className="w-4 h-4" />
              Preview Kiosk UI
            </a>
          </div>
        </div>

        {/* Overview Stats Bar */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mt-6 pt-6 border-t border-slate-800">
          <div className="bg-slate-950/60 border border-slate-800/80 rounded-lg p-3.5">
            <span className="text-xs text-slate-400 block mb-1">Total Pi Players</span>
            <span className="text-2xl font-bold text-white">{totalDevices}</span>
          </div>
          <div className="bg-slate-950/60 border border-slate-800/80 rounded-lg p-3.5">
            <span className="text-xs text-slate-400 block mb-1">Active / Playing</span>
            <span className="text-2xl font-bold text-emerald-400">{playingDevices}</span>
          </div>
          <div className="bg-slate-950/60 border border-slate-800/80 rounded-lg p-3.5">
            <span className="text-xs text-slate-400 block mb-1">Offline / Standby</span>
            <span className="text-2xl font-bold text-slate-400">{offlineDevices}</span>
          </div>
          <div className="bg-slate-950/60 border border-slate-800/80 rounded-lg p-3.5">
            <span className="text-xs text-slate-400 block mb-1">Default HLS Stream</span>
            <span className="text-sm font-semibold text-indigo-300 truncate block">
              {activeStream ? activeStream.title : activeKey}
            </span>
          </div>
        </div>
      </div>

      {/* Action Toast Feedback */}
      {actionMessage && (
        <div className={`p-4 rounded-lg border text-sm font-medium flex items-center justify-between transition-all ${
          actionMessage.type === 'success' 
            ? 'bg-emerald-950/50 border-emerald-800/60 text-emerald-300' 
            : 'bg-red-950/50 border-red-800/60 text-red-300'
        }`}>
          <div className="flex items-center gap-2">
            {actionMessage.type === 'success' ? <Check className="w-4 h-4" /> : <AlertCircle className="w-4 h-4" />}
            {actionMessage.text}
          </div>
          <button onClick={() => setActionMessage(null)} className="text-slate-400 hover:text-white">
            &times;
          </button>
        </div>
      )}

      {/* Primary Tab Selector */}
      <div className="border-b border-slate-800 flex items-center gap-2">
        <button
          onClick={() => setActiveSubTab('devices')}
          className={`flex items-center gap-2 px-4 py-3 text-sm font-medium border-b-2 transition-colors ${
            activeSubTab === 'devices'
              ? 'border-indigo-500 text-indigo-400 bg-indigo-500/5'
              : 'border-transparent text-slate-400 hover:text-slate-200 hover:border-slate-700'
          }`}
        >
          <Cpu className="w-4 h-4" />
          Devices & Status
        </button>

        <button
          onClick={() => setActiveSubTab('config')}
          className={`flex items-center gap-2 px-4 py-3 text-sm font-medium border-b-2 transition-colors ${
            activeSubTab === 'config'
              ? 'border-indigo-500 text-indigo-400 bg-indigo-500/5'
              : 'border-transparent text-slate-400 hover:text-slate-200 hover:border-slate-700'
          }`}
        >
          <Sliders className="w-4 h-4" />
          Player Configuration
        </button>

        <button
          onClick={() => setActiveSubTab('deployment')}
          className={`flex items-center gap-2 px-4 py-3 text-sm font-medium border-b-2 transition-colors ${
            activeSubTab === 'deployment'
              ? 'border-indigo-500 text-indigo-400 bg-indigo-500/5'
              : 'border-transparent text-slate-400 hover:text-slate-200 hover:border-slate-700'
          }`}
        >
          <Terminal className="w-4 h-4" />
          Deployment & Auto-Installer
        </button>
      </div>

      {/* TAB 1: DEVICES & LIVE STATUS */}
      {activeSubTab === 'devices' && (
        <div className="space-y-6">
          <div className="flex items-center justify-between bg-slate-900 p-4 border border-slate-800 rounded-xl">
            <div>
              <h2 className="text-lg font-semibold text-white">Registered Pi Players</h2>
              <p className="text-xs text-slate-400">Live hardware telemetry, streaming status, and remote control</p>
            </div>
            <button
              onClick={() => setIsRegisterModalOpen(true)}
              className="inline-flex items-center gap-2 px-4 py-2 bg-indigo-600 hover:bg-indigo-500 text-white rounded-lg text-sm font-medium transition-colors"
            >
              <Plus className="w-4 h-4" />
              Register Pi Player
            </button>
          </div>

          {devices.length === 0 ? (
            <div className="bg-slate-900 border border-slate-800 rounded-xl p-12 text-center">
              <Tv className="w-12 h-12 text-slate-600 mx-auto mb-3" />
              <h3 className="text-lg font-medium text-slate-300">No Raspberry Pi Players Registered</h3>
              <p className="text-sm text-slate-400 max-w-md mx-auto mt-1 mb-6">
                Deploy the auto-installer script on your Raspberry Pi or register a new device to track real-time telemetry.
              </p>
              <button
                onClick={() => setActiveSubTab('deployment')}
                className="inline-flex items-center gap-2 px-4 py-2 bg-slate-800 hover:bg-slate-700 text-slate-200 border border-slate-700 rounded-lg text-sm font-medium transition-colors"
              >
                <Terminal className="w-4 h-4" />
                View Installation Script
              </button>
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              {devices.map((device) => {
                const isOnline = device.online_status === 'playing' || device.online_status === 'online';
                return (
                  <div key={device.id} className="bg-slate-900 border border-slate-800 rounded-xl p-5 space-y-4 hover:border-slate-700 transition-all shadow-md">
                    <div className="flex items-start justify-between">
                      <div className="flex items-center gap-3">
                        <div className={`p-2.5 rounded-lg border ${
                          isOnline 
                            ? 'bg-emerald-500/10 border-emerald-500/20 text-emerald-400' 
                            : 'bg-slate-800 border-slate-700 text-slate-400'
                        }`}>
                          <Tv className="w-5 h-5" />
                        </div>
                        <div>
                          <h3 className="font-semibold text-white truncate max-w-[160px]">{device.name}</h3>
                          <span className="text-xs text-slate-400 block">{device.os_version || 'Raspberry Pi OS'}</span>
                        </div>
                      </div>

                      <span className={`px-2.5 py-1 rounded-full text-xs font-medium border flex items-center gap-1.5 ${
                        isOnline
                          ? 'bg-emerald-500/10 border-emerald-500/30 text-emerald-400'
                          : 'bg-slate-800 border-slate-700 text-slate-400'
                      }`}>
                        <span className={`w-1.5 h-1.5 rounded-full ${isOnline ? 'bg-emerald-400 animate-pulse' : 'bg-slate-500'}`}></span>
                        {isOnline ? 'Playing Live' : 'Offline'}
                      </span>
                    </div>

                    {/* Hardware & Playback Stats */}
                    <div className="bg-slate-950/80 rounded-lg p-3 space-y-2 border border-slate-800/80 text-xs">
                      <div className="flex justify-between text-slate-400">
                        <span>IP Address:</span>
                        <span className="text-slate-200 font-mono">{device.ip_address || '192.168.1.100'}</span>
                      </div>
                      <div className="flex justify-between text-slate-400">
                        <span>Current Resolution:</span>
                        <span className="text-indigo-300 font-medium">{device.current_resolution || '1080p @ 60 FPS'}</span>
                      </div>
                      <div className="flex justify-between text-slate-400">
                        <span>Bitrate & Network:</span>
                        <span className="text-slate-200 font-mono">{device.network_speed || '4.5 Mbps'}</span>
                      </div>
                      <div className="flex justify-between text-slate-400">
                        <span>Hardware Decoders:</span>
                        <span className="text-emerald-400 font-medium">V4L2M2M / GPU Active</span>
                      </div>
                      <div className="flex justify-between text-slate-400">
                        <span>Player Engine:</span>
                        <span className="text-slate-300 font-medium">HLS.js (Low Latency)</span>
                      </div>
                      <div className="flex justify-between text-slate-400">
                        <span>System Temp / RAM:</span>
                        <span className="text-slate-300 font-mono">{device.temperature || 42}°C • {device.ram_usage || 24}% RAM</span>
                      </div>
                    </div>

                    {/* Remote Controls */}
                    <div className="pt-2 border-t border-slate-800 flex items-center justify-between gap-2">
                      <button
                        onClick={() => handleRemoteCommand(device.id, 'play', { streamKey: activeKey })}
                        title="Force Reconnect Stream"
                        className="flex-1 inline-flex items-center justify-center gap-1.5 px-3 py-1.5 bg-indigo-600/20 hover:bg-indigo-600/30 text-indigo-300 border border-indigo-500/30 rounded-lg text-xs font-medium transition-colors"
                      >
                        <RotateCcw className="w-3.5 h-3.5" />
                        Reconnect
                      </button>

                      <button
                        onClick={() => handleRemoteCommand(device.id, 'reboot')}
                        title="Reboot Device"
                        className="inline-flex items-center justify-center p-2 bg-slate-800 hover:bg-slate-700 text-slate-300 border border-slate-700 rounded-lg text-xs transition-colors"
                      >
                        <Power className="w-3.5 h-3.5 text-amber-400" />
                      </button>

                      <button
                        onClick={() => handleDeleteDevice(device.id, device.name)}
                        title="Delete Device"
                        className="inline-flex items-center justify-center p-2 bg-slate-800 hover:bg-red-950/40 text-slate-400 hover:text-red-400 border border-slate-700 rounded-lg text-xs transition-colors"
                      >
                        <Trash2 className="w-3.5 h-3.5" />
                      </button>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>
      )}

      {/* TAB 2: PLAYER CONFIGURATION */}
      {activeSubTab === 'config' && (
        <form onSubmit={handleSaveConfig} className="bg-slate-900 border border-slate-800 rounded-xl p-6 space-y-6">
          <div className="border-b border-slate-800 pb-4">
            <h2 className="text-lg font-semibold text-white">Global Player & Kiosk Configuration</h2>
            <p className="text-xs text-slate-400">Settings applied automatically to all connected Raspberry Pi players</p>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            {/* Stream & Fallback Settings */}
            <div className="space-y-4">
              <h3 className="text-sm font-semibold text-indigo-400 flex items-center gap-2">
                <Tv className="w-4 h-4" /> Stream Target & Fallback Sequence
              </h3>

              <div>
                <label className="block text-xs font-medium text-slate-300 mb-1.5">Target HLS Stream</label>
                <select
                  value={rpiConfig.defaultStreamKey}
                  onChange={(e) => setRpiConfig({ ...rpiConfig, defaultStreamKey: e.target.value })}
                  className="w-full bg-slate-950 border border-slate-800 rounded-lg px-3 py-2 text-sm text-slate-200 focus:outline-none focus:border-indigo-500"
                >
                  <option value="">-- Select Stream --</option>
                  {streams.map(s => (
                    <option key={s.id} value={s.streamKey}>
                      {s.title} ({s.streamKey})
                    </option>
                  ))}
                </select>
              </div>

              <div>
                <label className="block text-xs font-medium text-slate-300 mb-1.5">Primary Player Engine</label>
                <select
                  value={rpiConfig.fallbackSequence[0]}
                  onChange={(e) => setRpiConfig({
                    ...rpiConfig,
                    fallbackSequence: [e.target.value as any, 'videojs', 'vlc']
                  })}
                  className="w-full bg-slate-950 border border-slate-800 rounded-lg px-3 py-2 text-sm text-slate-200 focus:outline-none focus:border-indigo-500"
                >
                  <option value="hlsjs">HLS.js (Recommended for GPU Browser Kiosk)</option>
                  <option value="videojs">Video.js (Fallback HTML5 HLS Renderer)</option>
                  <option value="vlc">VLC / MPV Framebuffer Player (Headless Lite OS)</option>
                </select>
              </div>
            </div>

            {/* Hardware Video Acceleration */}
            <div className="space-y-4">
              <h3 className="text-sm font-semibold text-indigo-400 flex items-center gap-2">
                <Zap className="w-4 h-4" /> Hardware Video Acceleration (GPU)
              </h3>

              <div className="flex items-center justify-between p-3 bg-slate-950 rounded-lg border border-slate-800">
                <div>
                  <span className="text-xs font-medium text-slate-200 block">Enable GPU Video Decoding</span>
                  <span className="text-[11px] text-slate-400 block">Uses V4L2M2M / MMAL / DRM KMS hardware acceleration</span>
                </div>
                <input
                  type="checkbox"
                  checked={rpiConfig.hardwareAcceleration.enabled}
                  onChange={(e) => setRpiConfig({
                    ...rpiConfig,
                    hardwareAcceleration: { ...rpiConfig.hardwareAcceleration, enabled: e.target.checked }
                  })}
                  className="w-4 h-4 accent-indigo-600 rounded"
                />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-medium text-slate-300 mb-1.5">Decoder Mode</label>
                  <select
                    value={rpiConfig.hardwareAcceleration.decoder}
                    onChange={(e) => setRpiConfig({
                      ...rpiConfig,
                      hardwareAcceleration: { ...rpiConfig.hardwareAcceleration, decoder: e.target.value as any }
                    })}
                    className="w-full bg-slate-950 border border-slate-800 rounded-lg px-3 py-2 text-xs text-slate-200 focus:outline-none focus:border-indigo-500"
                  >
                    <option value="auto">Auto (Detect Pi 4 vs Pi 5)</option>
                    <option value="v4l2m2m">V4L2M2M (Raspberry Pi 4 H.264)</option>
                    <option value="drm_kms">DRM KMS (Raspberry Pi 5 Wayland)</option>
                    <option value="hevc_v4l2m2m">HEVC V4L2 (4K Decoding)</option>
                  </select>
                </div>

                <div>
                  <label className="block text-xs font-medium text-slate-300 mb-1.5">GPU Memory Allocation</label>
                  <select
                    value={rpiConfig.hardwareAcceleration.gpuMemMb}
                    onChange={(e) => setRpiConfig({
                      ...rpiConfig,
                      hardwareAcceleration: { ...rpiConfig.hardwareAcceleration, gpuMemMb: Number(e.target.value) }
                    })}
                    className="w-full bg-slate-950 border border-slate-800 rounded-lg px-3 py-2 text-xs text-slate-200 focus:outline-none focus:border-indigo-500"
                  >
                    <option value={128}>128 MB</option>
                    <option value={256}>256 MB (Recommended)</option>
                    <option value={512}>512 MB (4K Display)</option>
                  </select>
                </div>
              </div>
            </div>

            {/* Kiosk Display & UI */}
            <div className="space-y-4">
              <h3 className="text-sm font-semibold text-indigo-400 flex items-center gap-2">
                <Monitor className="w-4 h-4" /> Kiosk & UI Display Options
              </h3>

              <div className="space-y-2">
                <label className="flex items-center justify-between p-3 bg-slate-950 rounded-lg border border-slate-800 text-xs text-slate-200">
                  <span>Fullscreen Kiosk Mode</span>
                  <input
                    type="checkbox"
                    checked={rpiConfig.display.fullscreen}
                    onChange={(e) => setRpiConfig({ ...rpiConfig, display: { ...rpiConfig.display, fullscreen: e.target.checked } })}
                    className="w-4 h-4 accent-indigo-600 rounded"
                  />
                </label>

                <label className="flex items-center justify-between p-3 bg-slate-950 rounded-lg border border-slate-800 text-xs text-slate-200">
                  <span>Black Screen When Stream Offline</span>
                  <input
                    type="checkbox"
                    checked={rpiConfig.display.blackScreenOffline}
                    onChange={(e) => setRpiConfig({ ...rpiConfig, display: { ...rpiConfig.display, blackScreenOffline: e.target.checked } })}
                    className="w-4 h-4 accent-indigo-600 rounded"
                  />
                </label>

                <label className="flex items-center justify-between p-3 bg-slate-950 rounded-lg border border-slate-800 text-xs text-slate-200">
                  <span>Show Status Badge / Reconnect Overlay</span>
                  <input
                    type="checkbox"
                    checked={rpiConfig.display.showReconnectOverlay}
                    onChange={(e) => setRpiConfig({ ...rpiConfig, display: { ...rpiConfig.display, showReconnectOverlay: e.target.checked } })}
                    className="w-4 h-4 accent-indigo-600 rounded"
                  />
                </label>
              </div>
            </div>

            {/* Auto Reconnect & Network Recovery */}
            <div className="space-y-4">
              <h3 className="text-sm font-semibold text-indigo-400 flex items-center gap-2">
                <Wifi className="w-4 h-4" /> Auto Reconnect & Network Recovery
              </h3>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-medium text-slate-300 mb-1.5">Reconnect Retry Interval</label>
                  <select
                    value={rpiConfig.network.reconnectIntervalMs}
                    onChange={(e) => setRpiConfig({
                      ...rpiConfig,
                      network: { ...rpiConfig.network, reconnectIntervalMs: Number(e.target.value) }
                    })}
                    className="w-full bg-slate-950 border border-slate-800 rounded-lg px-3 py-2 text-xs text-slate-200 focus:outline-none focus:border-indigo-500"
                  >
                    <option value={1000}>1 second</option>
                    <option value={3000}>3 seconds (Recommended)</option>
                    <option value={5000}>5 seconds</option>
                    <option value={10000}>10 seconds</option>
                  </select>
                </div>

                <div>
                  <label className="block text-xs font-medium text-slate-300 mb-1.5">Telemetry Heartbeat</label>
                  <select
                    value={rpiConfig.network.heartbeatIntervalMs}
                    onChange={(e) => setRpiConfig({
                      ...rpiConfig,
                      network: { ...rpiConfig.network, heartbeatIntervalMs: Number(e.target.value) }
                    })}
                    className="w-full bg-slate-950 border border-slate-800 rounded-lg px-3 py-2 text-xs text-slate-200 focus:outline-none focus:border-indigo-500"
                  >
                    <option value={3000}>Every 3s</option>
                    <option value={5000}>Every 5s (Default)</option>
                    <option value={10000}>Every 10s</option>
                  </select>
                </div>
              </div>
            </div>
          </div>

          <div className="pt-4 border-t border-slate-800 flex justify-end">
            <button
              type="submit"
              className="inline-flex items-center gap-2 px-6 py-2.5 bg-indigo-600 hover:bg-indigo-500 text-white font-medium rounded-lg text-sm transition-colors shadow-lg shadow-indigo-600/20"
            >
              <Check className="w-4 h-4" />
              Save Configuration
            </button>
          </div>
        </form>
      )}

      {/* TAB 3: DEPLOYMENT & SCRIPTS */}
      {activeSubTab === 'deployment' && (
        <div className="space-y-6">
          {/* One-Command Auto Installer Header */}
          <div className="bg-slate-900 border border-indigo-500/30 rounded-xl p-6 shadow-xl space-y-4">
            <div className="flex items-center gap-3">
              <div className="p-2 bg-indigo-500/20 rounded-lg text-indigo-400">
                <Terminal className="w-6 h-6" />
              </div>
              <div>
                <h2 className="text-lg font-bold text-white">One-Command Production Auto-Installer</h2>
                <p className="text-xs text-slate-400">Run this single terminal command on any Raspberry Pi 4 or Pi 5 (Lite/Desktop) to provision the player system.</p>
              </div>
            </div>

            <div className="flex items-center gap-3 bg-slate-950 border border-slate-800 rounded-lg p-3">
              <span className="text-xs text-slate-400 font-mono flex-shrink-0">Stream Target:</span>
              <select
                value={selectedStreamKey}
                onChange={(e) => setSelectedStreamKey(e.target.value)}
                className="bg-slate-900 border border-slate-700 rounded px-2.5 py-1 text-xs text-slate-200 focus:outline-none"
              >
                {streams.map(s => (
                  <option key={s.id} value={s.streamKey}>{s.title} ({s.streamKey})</option>
                ))}
              </select>
            </div>

            <div className="bg-slate-950 border border-slate-800 rounded-lg p-4 flex items-center justify-between gap-4 font-mono text-xs text-emerald-400 overflow-x-auto">
              <code className="select-all">{curlCommand}</code>
              <CopyButton text={curlCommand} label="Copy Command" />
            </div>
          </div>

          {/* Script Viewer Subtabs */}
          <div className="bg-slate-900 border border-slate-800 rounded-xl overflow-hidden">
            <div className="bg-slate-950 border-b border-slate-800 flex items-center justify-between px-4">
              <div className="flex items-center gap-1">
                <button
                  onClick={() => setScriptTab('installer')}
                  className={`px-4 py-3 text-xs font-medium border-b-2 transition-colors ${
                    scriptTab === 'installer' 
                      ? 'border-indigo-500 text-indigo-400 bg-slate-900/60' 
                      : 'border-transparent text-slate-400 hover:text-slate-200'
                  }`}
                >
                  setup-rpi-player.sh
                </button>
                <button
                  onClick={() => setScriptTab('systemd')}
                  className={`px-4 py-3 text-xs font-medium border-b-2 transition-colors ${
                    scriptTab === 'systemd' 
                      ? 'border-indigo-500 text-indigo-400 bg-slate-900/60' 
                      : 'border-transparent text-slate-400 hover:text-slate-200'
                  }`}
                >
                  streampulse-rpi-player.service
                </button>
                <button
                  onClick={() => setScriptTab('kiosk')}
                  className={`px-4 py-3 text-xs font-medium border-b-2 transition-colors ${
                    scriptTab === 'kiosk' 
                      ? 'border-indigo-500 text-indigo-400 bg-slate-900/60' 
                      : 'border-transparent text-slate-400 hover:text-slate-200'
                  }`}
                >
                  streampulse-kiosk.sh
                </button>
                <button
                  onClick={() => setScriptTab('autoupdate')}
                  className={`px-4 py-3 text-xs font-medium border-b-2 transition-colors ${
                    scriptTab === 'autoupdate' 
                      ? 'border-indigo-500 text-indigo-400 bg-slate-900/60' 
                      : 'border-transparent text-slate-400 hover:text-slate-200'
                  }`}
                >
                  rpi-player-update.sh
                </button>
              </div>

              <div className="flex items-center gap-2 py-2">
                <CopyButton text={scriptContents[scriptTab] || ''} label="Copy Code" />
              </div>
            </div>

            <div className="p-4 bg-slate-950 overflow-x-auto max-h-[500px]">
              <pre className="text-xs font-mono text-slate-300 leading-relaxed select-all">
                {scriptContents[scriptTab] || 'Loading script content...'}
              </pre>
            </div>
          </div>
        </div>
      )}

      {/* Register Modal */}
      {isRegisterModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-sm p-4">
          <div className="bg-slate-900 border border-slate-800 rounded-xl p-6 w-full max-w-md space-y-4 shadow-2xl">
            <h3 className="text-lg font-bold text-white">Register Raspberry Pi Player</h3>

            <form onSubmit={handleRegisterDevice} className="space-y-4">
              <div>
                <label className="block text-xs font-medium text-slate-300 mb-1">Device Name</label>
                <input
                  type="text"
                  required
                  placeholder="e.g. Church Sanctuary Pi Player"
                  value={newDeviceName}
                  onChange={(e) => setNewDeviceName(e.target.value)}
                  className="w-full bg-slate-950 border border-slate-800 rounded-lg px-3 py-2 text-sm text-slate-200 focus:outline-none focus:border-indigo-500"
                />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-medium text-slate-300 mb-1">Hardware Model</label>
                  <select
                    value={newDeviceModel}
                    onChange={(e) => setNewDeviceModel(e.target.value as any)}
                    className="w-full bg-slate-950 border border-slate-800 rounded-lg px-3 py-2 text-xs text-slate-200 focus:outline-none"
                  >
                    <option value="Pi 5">Raspberry Pi 5</option>
                    <option value="Pi 4B">Raspberry Pi 4B</option>
                  </select>
                </div>

                <div>
                  <label className="block text-xs font-medium text-slate-300 mb-1">OS Environment</label>
                  <select
                    value={newDeviceOs}
                    onChange={(e) => setNewDeviceOs(e.target.value as any)}
                    className="w-full bg-slate-950 border border-slate-800 rounded-lg px-3 py-2 text-xs text-slate-200 focus:outline-none"
                  >
                    <option value="Raspberry Pi OS Lite">Pi OS Lite (Headless)</option>
                    <option value="Raspberry Pi OS Desktop">Pi OS Desktop (GUI)</option>
                  </select>
                </div>
              </div>

              <div>
                <label className="block text-xs font-medium text-slate-300 mb-1">IP Address (Optional)</label>
                <input
                  type="text"
                  placeholder="e.g. 192.168.1.150"
                  value={newDeviceIp}
                  onChange={(e) => setNewDeviceIp(e.target.value)}
                  className="w-full bg-slate-950 border border-slate-800 rounded-lg px-3 py-2 text-sm text-slate-200 focus:outline-none focus:border-indigo-500"
                />
              </div>

              <div className="pt-2 flex items-center justify-end gap-2">
                <button
                  type="button"
                  onClick={() => setIsRegisterModalOpen(false)}
                  className="px-4 py-2 bg-slate-800 hover:bg-slate-700 text-slate-300 rounded-lg text-sm font-medium transition-colors"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  className="px-4 py-2 bg-indigo-600 hover:bg-indigo-500 text-white rounded-lg text-sm font-medium transition-colors"
                >
                  Register Device
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};
