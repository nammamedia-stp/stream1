import React, { useState } from 'react';
import { 
  Shield, 
  Lock, 
  CheckCircle2, 
  AlertTriangle, 
  ChevronRight, 
  ChevronLeft, 
  RefreshCcw,
  Check,
  Globe,
  Clock
} from 'lucide-react';

interface SetupWizardProps {
  onSetupComplete: () => void;
}

const COMMON_TIMEZONES = [
  'UTC',
  'America/New_York',
  'America/Chicago',
  'America/Denver',
  'America/Los_Angeles',
  'Europe/London',
  'Europe/Paris',
  'Asia/Tokyo',
  'Asia/Kolkata',
  'Asia/Singapore',
  'Australia/Sydney'
];

export const SetupWizard: React.FC<SetupWizardProps> = ({ onSetupComplete }) => {
  const [step, setStep] = useState(1);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Form States
  const [username, setUsername] = useState('admin');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  
  // Auto-detect browser timezone or default to UTC
  const [timezone, setTimezone] = useState(() => {
    try {
      const detected = Intl.DateTimeFormat().resolvedOptions().timeZone;
      return COMMON_TIMEZONES.includes(detected) || detected ? detected : 'UTC';
    } catch (e) {
      return 'UTC';
    }
  });

  // "Optional: Install SSL later? (Yes/No)"
  // Default is 'yes' (meaning skip Let's Encrypt for now / install later)
  const [installSslLater, setInstallSslLater] = useState<boolean>(true);

  const validateStep = () => {
    setError(null);
    if (step === 1) {
      if (!username || username.trim().length < 3) {
        setError('Username must be at least 3 characters long.');
        return false;
      }
      if (!password || password.length < 6) {
        setError('Password must be at least 6 characters long.');
        return false;
      }
      if (password !== confirmPassword) {
        setError('Passwords do not match.');
        return false;
      }
    }
    return true;
  };

  const handleNext = () => {
    if (!validateStep()) return;
    setStep(prev => prev + 1);
  };

  const handleBack = () => {
    setError(null);
    setStep(prev => prev - 1);
  };

  const handleFinish = async () => {
    setLoading(true);
    setError(null);
    try {
      const response = await fetch('/api/setup/complete', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          username,
          password,
          timezone,
          sslOption: installSslLater ? 'skip' : 'letsencrypt'
        })
      });
      
      const data = await response.json();
      if (!response.ok) {
        throw new Error(data.error || 'Failed to complete configuration setup.');
      }
      
      onSetupComplete();
    } catch (err: any) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-zinc-950 flex items-center justify-center p-4">
      <div className="w-full max-w-xl bg-zinc-900 border border-zinc-800 rounded-2xl shadow-2xl overflow-hidden flex flex-col relative font-sans">
        <div className="absolute top-0 left-0 w-full h-1 bg-gradient-to-r from-blue-500 via-teal-500 to-purple-500"></div>
        
        {/* Header */}
        <div className="p-6 border-b border-zinc-800 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="p-2.5 bg-blue-600/10 rounded-xl border border-blue-500/20">
              <Shield className="w-5 h-5 text-blue-500" />
            </div>
            <div>
              <h1 className="text-lg font-bold tracking-tight text-zinc-100">StreamPulse Setup</h1>
              <p className="text-[10px] text-zinc-500 uppercase font-mono tracking-wider mt-0.5">StreamPulse Installation Wizard</p>
            </div>
          </div>
          <div className="text-xs font-mono font-semibold text-zinc-400 bg-zinc-950 border border-zinc-850 px-2.5 py-1 rounded-lg">
            Step {step} of 3
          </div>
        </div>

        {/* Content Box */}
        <div className="p-6 sm:p-8 flex-grow space-y-6 min-h-[280px]">
          {error && (
            <div className="p-3.5 bg-red-500/10 border border-red-500/20 text-red-400 rounded-xl text-xs font-semibold flex items-center gap-2.5 animate-pulse">
              <AlertTriangle className="w-4 h-4 shrink-0" />
              <span>{error}</span>
            </div>
          )}

          {/* STEP 1: Create Administrator Account & Timezone */}
          {step === 1 && (
            <div className="space-y-4 animate-fadeIn">
              <div className="space-y-1">
                <h2 className="text-base font-bold text-zinc-100 font-sans">Create Administrator Account</h2>
                <p className="text-xs text-zinc-400 font-medium">Establish your supervisor security credentials and configure system timezone.</p>
              </div>

              <div className="space-y-3 pt-2">
                <div className="space-y-1.5">
                  <label className="text-[10px] font-bold text-zinc-500 uppercase tracking-wider">Admin Username</label>
                  <input 
                    type="text" 
                    value={username}
                    onChange={(e) => setUsername(e.target.value)}
                    placeholder="e.g. admin"
                    className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-3 py-2 text-xs focus:ring-1 focus:ring-blue-500 outline-none text-zinc-100 font-medium"
                  />
                </div>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                  <div className="space-y-1.5">
                    <label className="text-[10px] font-bold text-zinc-500 uppercase tracking-wider">Password</label>
                    <input 
                      type="password" 
                      value={password}
                      onChange={(e) => setPassword(e.target.value)}
                      placeholder="••••••••"
                      className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-3 py-2 text-xs focus:ring-1 focus:ring-blue-500 outline-none text-zinc-100"
                    />
                  </div>
                  <div className="space-y-1.5">
                    <label className="text-[10px] font-bold text-zinc-500 uppercase tracking-wider">Confirm Password</label>
                    <input 
                      type="password" 
                      value={confirmPassword}
                      onChange={(e) => setConfirmPassword(e.target.value)}
                      placeholder="••••••••"
                      className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-3 py-2 text-xs focus:ring-1 focus:ring-blue-500 outline-none text-zinc-100"
                    />
                  </div>
                </div>

                <div className="space-y-1.5 pt-1">
                  <label className="text-[10px] font-bold text-zinc-500 uppercase tracking-wider flex items-center gap-1.5">
                    <Clock className="w-3 h-3 text-zinc-500" /> System Timezone
                  </label>
                  <select
                    value={timezone}
                    onChange={(e) => setTimezone(e.target.value)}
                    className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-3 py-2 text-xs focus:ring-1 focus:ring-blue-500 outline-none text-zinc-100"
                  >
                    {!COMMON_TIMEZONES.includes(timezone) && (
                      <option value={timezone}>{timezone} (Detected)</option>
                    )}
                    {COMMON_TIMEZONES.map((tz) => (
                      <option key={tz} value={tz}>{tz}</option>
                    ))}
                  </select>
                </div>
              </div>
            </div>
          )}

          {/* STEP 2: SSL Settings */}
          {step === 2 && (
            <div className="space-y-4 animate-fadeIn">
              <div className="space-y-1">
                <h2 className="text-base font-bold text-zinc-100">Configure SSL Management</h2>
                <p className="text-xs text-zinc-400">StreamPulse runs securely via SSL. Decide if you would like to set up SSL now or install it later.</p>
              </div>

              <div className="space-y-3 pt-2">
                <label className="text-[10px] font-bold text-zinc-500 uppercase tracking-wider block mb-1">Install SSL later?</label>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                  <button
                    onClick={() => setInstallSslLater(true)}
                    className={`flex flex-col text-left p-4 rounded-xl border transition ${installSslLater ? 'bg-amber-600/10 border-amber-500 text-amber-400 font-sans' : 'bg-zinc-950 border-zinc-850 hover:border-zinc-700 text-zinc-300'}`}
                  >
                    <span className="text-xs font-bold flex items-center gap-2">
                      <Check className="w-3.5 h-3.5 text-amber-500" /> Yes, Install SSL Later
                    </span>
                    <span className="text-[10px] text-zinc-500 mt-1 leading-normal">Bypasses Let's Encrypt for now. The platform will operate over standard HTTP.</span>
                  </button>

                  <button
                    onClick={() => setInstallSslLater(false)}
                    className={`flex flex-col text-left p-4 rounded-xl border transition ${!installSslLater ? 'bg-emerald-600/10 border-emerald-500 text-emerald-400 font-sans' : 'bg-zinc-950 border-zinc-850 hover:border-zinc-700 text-zinc-300'}`}
                  >
                    <span className="text-xs font-bold flex items-center gap-2">
                      <Globe className="w-3.5 h-3.5 text-emerald-500" /> No, Configure SSL Now
                    </span>
                    <span className="text-[10px] text-zinc-500 mt-1 leading-normal">Automatically requests, registers, and provisions standard Let's Encrypt certificates now.</span>
                  </button>
                </div>
              </div>
            </div>
          )}

          {/* STEP 3: Final Review */}
          {step === 3 && (
            <div className="space-y-4 animate-fadeIn">
              <div className="space-y-1">
                <h2 className="text-base font-bold text-zinc-100">Finish System Setup</h2>
                <p className="text-xs text-zinc-400">Review your installation parameters. Click finish to launch StreamPulse instantly.</p>
              </div>

              <div className="bg-zinc-950 border border-zinc-850 rounded-xl p-4.5 space-y-3 font-mono text-xs">
                <div className="flex justify-between border-b border-zinc-900 pb-2">
                  <span className="text-zinc-500">Admin Account</span>
                  <span className="text-zinc-300 font-bold">{username}</span>
                </div>
                <div className="flex justify-between border-b border-zinc-900 pb-2">
                  <span className="text-zinc-500">System Timezone</span>
                  <span className="text-blue-400 font-bold">{timezone}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-zinc-500">SSL Installation</span>
                  <span className={`font-bold ${!installSslLater ? 'text-emerald-500' : 'text-amber-500'}`}>
                    {!installSslLater ? "Configure SSL Now" : 'Install SSL Later'}
                  </span>
                </div>
              </div>
            </div>
          )}
        </div>

        {/* Footer Navigation */}
        <div className="p-6 border-t border-zinc-800 bg-zinc-900/50 flex justify-between gap-4">
          {step > 1 ? (
            <button
              onClick={handleBack}
              disabled={loading}
              className="flex items-center gap-1.5 px-4 py-2 bg-zinc-850 hover:bg-zinc-800 border border-zinc-750 text-zinc-300 rounded-xl text-xs font-semibold transition disabled:opacity-50 font-sans"
            >
              <ChevronLeft className="w-4 h-4" /> Back
            </button>
          ) : (
            <div></div>
          )}

          {step < 3 ? (
            <button
              onClick={handleNext}
              className="flex items-center gap-1.5 px-5 py-2 bg-blue-600 hover:bg-blue-500 text-white rounded-xl text-xs font-semibold transition shadow-lg shadow-blue-950/20 font-sans"
            >
              Continue <ChevronRight className="w-4 h-4" />
            </button>
          ) : (
            <button
              onClick={handleFinish}
              disabled={loading}
              className="flex items-center gap-1.5 px-6 py-2 bg-emerald-600 hover:bg-emerald-500 text-white rounded-xl text-xs font-bold transition shadow-lg shadow-emerald-950/20 disabled:opacity-50 font-sans"
            >
              {loading ? (
                <>
                  <RefreshCcw className="w-3.5 h-3.5 animate-spin" /> Finalizing...
                </>
              ) : (
                <>
                  <CheckCircle2 className="w-3.5 h-3.5" /> Launch StreamPulse
                </>
              )}
            </button>
          )}
        </div>
      </div>
    </div>
  );
};
