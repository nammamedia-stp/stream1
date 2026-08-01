import React, { useState, useEffect } from 'react';
import { 
  User, 
  Shield, 
  Key, 
  Eye, 
  EyeOff, 
  Check, 
  X, 
  Lock, 
  AlertCircle, 
  CheckCircle2, 
  RefreshCcw, 
  Save, 
  AlertTriangle,
  FileText
} from 'lucide-react';

interface AdminProfileProps {
  currentUser: any;
  fetchWithNetworkHeaders: (url: string, init?: RequestInit) => Promise<Response>;
  onUpdateCurrentUser: (updatedUser: any, newToken: string) => void;
}

export const AdminProfile: React.FC<AdminProfileProps> = ({
  currentUser,
  fetchWithNetworkHeaders,
  onUpdateCurrentUser,
}) => {
  const [username, setUsername] = useState(currentUser?.username || '');
  const [displayName, setDisplayName] = useState(currentUser?.display_name || '');
  
  const [currentPassword, setCurrentPassword] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');

  const [showCurrentPassword, setShowCurrentPassword] = useState(false);
  const [showNewPassword, setShowNewPassword] = useState(false);
  const [showConfirmPassword, setShowConfirmPassword] = useState(false);

  const [isSubmitting, setIsSubmitting] = useState(false);
  const [successMessage, setSuccessMessage] = useState<string | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  // Sync state if currentUser changes
  useEffect(() => {
    if (currentUser) {
      setUsername(currentUser.username || '');
      setDisplayName(currentUser.display_name || '');
    }
  }, [currentUser]);

  // Password criteria verification
  const reqMinLength = newPassword.length >= 12;
  const reqUpper = /[A-Z]/.test(newPassword);
  const reqLower = /[a-z]/.test(newPassword);
  const reqNumber = /[0-9]/.test(newPassword);
  const reqSpecial = /[^A-Za-z0-9]/.test(newPassword);

  const criteriaList = [
    { label: 'Minimum 12 characters', valid: reqMinLength },
    { label: 'At least one uppercase letter (A-Z)', valid: reqUpper },
    { label: 'At least one lowercase letter (a-z)', valid: reqLower },
    { label: 'At least one numeric digit (0-9)', valid: reqNumber },
    { label: 'At least one special character (!@#$%^&*)', valid: reqSpecial },
  ];

  const passedCount = criteriaList.filter(c => c.valid).length;
  const strengthPercentage = newPassword ? (passedCount / criteriaList.length) * 100 : 0;

  const isPasswordMatching = newPassword && confirmPassword ? newPassword === confirmPassword : true;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);
    setSuccessMessage(null);

    const cleanUsername = username.trim();
    const cleanDisplayName = displayName.trim();

    if (!cleanUsername) {
      setErrorMessage('Username cannot be empty');
      return;
    }

    if (cleanUsername.length < 3) {
      setErrorMessage('Username must be at least 3 characters long');
      return;
    }

    if (!currentPassword) {
      setErrorMessage('Current password is required to verify identity and save profile changes');
      return;
    }

    if (newPassword) {
      if (passedCount < criteriaList.length) {
        setErrorMessage('New password does not meet all strong password security criteria');
        return;
      }
      if (newPassword !== confirmPassword) {
        setErrorMessage('New password and confirm password do not match');
        return;
      }
    }

    setIsSubmitting(true);

    try {
      const res = await fetchWithNetworkHeaders('/api/admin/profile', {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          currentPassword,
          newUsername: cleanUsername,
          newDisplayName: cleanDisplayName,
          newPassword: newPassword || undefined,
          confirmPassword: confirmPassword || undefined
        })
      });

      const data = await res.json();

      if (!res.ok) {
        throw new Error(data.error || 'Failed to update admin profile');
      }

      setSuccessMessage('Admin profile updated successfully!');
      setCurrentPassword('');
      setNewPassword('');
      setConfirmPassword('');

      if (data.user && data.token) {
        onUpdateCurrentUser(data.user, data.token);
      }
    } catch (err: any) {
      console.error('Error in profile update:', err);
      setErrorMessage(err.message || 'An error occurred while updating profile');
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="space-y-6 max-w-4xl mx-auto animate-in fade-in duration-200">
      {/* Header Banner */}
      <div className="bg-zinc-900 border border-zinc-800 rounded-2xl p-6 shadow-sm flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div className="flex items-center gap-4">
          <div className="p-3 bg-blue-600/15 rounded-xl border border-blue-500/20 text-blue-500 shrink-0">
            <Shield className="w-8 h-8" />
          </div>
          <div>
            <h2 className="text-2xl font-bold tracking-tight text-white flex items-center gap-2">
              Administrator Profile Management
            </h2>
            <p className="text-sm text-zinc-400 mt-0.5">
              Update your administrator identity credentials, display name, and authentication password.
            </p>
          </div>
        </div>
        <div className="px-3.5 py-1.5 bg-zinc-950 border border-zinc-800 rounded-lg text-xs font-mono text-zinc-400 flex items-center gap-2 self-start md:self-auto">
          <span className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse"></span>
          <span>Role: Super Administrator</span>
        </div>
      </div>

      {/* Alert Messages */}
      {errorMessage && (
        <div className="p-4 bg-red-500/10 border border-red-500/20 text-red-400 rounded-xl text-sm font-semibold flex items-center gap-3">
          <AlertTriangle className="w-5 h-5 shrink-0" />
          <div className="flex-1">{errorMessage}</div>
          <button onClick={() => setErrorMessage(null)} className="text-red-400 hover:text-red-200 p-1">
            <X className="w-4 h-4" />
          </button>
        </div>
      )}

      {successMessage && (
        <div className="p-4 bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 rounded-xl text-sm font-semibold flex items-center gap-3">
          <CheckCircle2 className="w-5 h-5 shrink-0" />
          <div className="flex-1">{successMessage}</div>
          <button onClick={() => setSuccessMessage(null)} className="text-emerald-400 hover:text-emerald-200 p-1">
            <X className="w-4 h-4" />
          </button>
        </div>
      )}

      <form onSubmit={handleSubmit} className="space-y-6">
        {/* Account Details Card */}
        <div className="bg-zinc-900 border border-zinc-800 rounded-2xl p-6 shadow-sm space-y-6">
          <div className="border-b border-zinc-800 pb-4 flex items-center gap-2">
            <User className="w-5 h-5 text-blue-500" />
            <h3 className="text-lg font-bold text-white">Identity Credentials</h3>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            {/* Username */}
            <div className="space-y-2">
              <label className="text-xs font-bold text-zinc-400 uppercase tracking-wider block">
                Administrator Username <span className="text-red-500">*</span>
              </label>
              <div className="relative">
                <input
                  type="text"
                  required
                  value={username}
                  onChange={(e) => setUsername(e.target.value)}
                  placeholder="admin"
                  className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-3.5 py-2.5 text-sm focus:ring-2 focus:ring-blue-500/50 outline-none text-zinc-100 font-medium font-mono"
                />
              </div>
              <p className="text-[11px] text-zinc-500">
                Must be unique across the platform. Whitespace is automatically trimmed.
              </p>
            </div>

            {/* Display Name */}
            <div className="space-y-2">
              <label className="text-xs font-bold text-zinc-400 uppercase tracking-wider block">
                Display Name / System Alias
              </label>
              <div className="relative">
                <input
                  type="text"
                  value={displayName}
                  onChange={(e) => setDisplayName(e.target.value)}
                  placeholder="e.g. Master Operations Admin"
                  className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-3.5 py-2.5 text-sm focus:ring-2 focus:ring-blue-500/50 outline-none text-zinc-100 font-medium"
                />
              </div>
              <p className="text-[11px] text-zinc-500">
                Friendly display name shown in navigation headers and logs.
              </p>
            </div>
          </div>
        </div>

        {/* Security & Password Management Card */}
        <div className="bg-zinc-900 border border-zinc-800 rounded-2xl p-6 shadow-sm space-y-6">
          <div className="border-b border-zinc-800 pb-4 flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Key className="w-5 h-5 text-amber-500" />
              <h3 className="text-lg font-bold text-white">Security & Password Management</h3>
            </div>
            <span className="text-[10px] uppercase font-bold text-zinc-500 bg-zinc-950 px-2.5 py-1 rounded border border-zinc-800">
              Bcrypt Hashing Enforced
            </span>
          </div>

          {/* Current Password Field */}
          <div className="p-4 bg-zinc-950/60 border border-zinc-800/80 rounded-xl space-y-2">
            <label className="text-xs font-bold text-amber-400 uppercase tracking-wider flex items-center gap-2">
              <Lock className="w-3.5 h-3.5" />
              Current Administrator Password <span className="text-red-500">*</span>
            </label>
            <div className="relative">
              <input
                type={showCurrentPassword ? "text" : "password"}
                required
                value={currentPassword}
                onChange={(e) => setCurrentPassword(e.target.value)}
                placeholder="Enter current password to authorize changes"
                className="w-full bg-zinc-950 border border-zinc-800 rounded-lg pl-3.5 pr-10 py-2.5 text-sm focus:ring-2 focus:ring-amber-500/50 outline-none text-zinc-100 font-mono"
              />
              <button
                type="button"
                onClick={() => setShowCurrentPassword(!showCurrentPassword)}
                className="absolute right-3 top-1/2 -translate-y-1/2 text-zinc-400 hover:text-zinc-200 p-1"
                title={showCurrentPassword ? "Hide password" : "Show password"}
              >
                {showCurrentPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
              </button>
            </div>
            <p className="text-[11px] text-zinc-400">
              Your current password is required for security verification before saving profile changes.
            </p>
          </div>

          <div className="pt-2 border-t border-zinc-800/60 space-y-6">
            <h4 className="text-xs font-bold text-zinc-300 uppercase tracking-wider">
              Change Password (Optional)
            </h4>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              {/* New Password */}
              <div className="space-y-2">
                <label className="text-xs font-bold text-zinc-400 uppercase tracking-wider block">
                  New Password
                </label>
                <div className="relative">
                  <input
                    type={showNewPassword ? "text" : "password"}
                    value={newPassword}
                    onChange={(e) => setNewPassword(e.target.value)}
                    placeholder="Leave blank to keep existing password"
                    className="w-full bg-zinc-950 border border-zinc-800 rounded-lg pl-3.5 pr-10 py-2.5 text-sm focus:ring-2 focus:ring-blue-500/50 outline-none text-zinc-100 font-mono"
                  />
                  <button
                    type="button"
                    onClick={() => setShowNewPassword(!showNewPassword)}
                    className="absolute right-3 top-1/2 -translate-y-1/2 text-zinc-400 hover:text-zinc-200 p-1"
                    title={showNewPassword ? "Hide password" : "Show password"}
                  >
                    {showNewPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                  </button>
                </div>
              </div>

              {/* Confirm New Password */}
              <div className="space-y-2">
                <label className="text-xs font-bold text-zinc-400 uppercase tracking-wider block">
                  Confirm New Password
                </label>
                <div className="relative">
                  <input
                    type={showConfirmPassword ? "text" : "password"}
                    value={confirmPassword}
                    onChange={(e) => setConfirmPassword(e.target.value)}
                    placeholder="Re-enter new password"
                    className="w-full bg-zinc-950 border border-zinc-800 rounded-lg pl-3.5 pr-10 py-2.5 text-sm focus:ring-2 focus:ring-blue-500/50 outline-none text-zinc-100 font-mono"
                  />
                  <button
                    type="button"
                    onClick={() => setShowConfirmPassword(!showConfirmPassword)}
                    className="absolute right-3 top-1/2 -translate-y-1/2 text-zinc-400 hover:text-zinc-200 p-1"
                    title={showConfirmPassword ? "Hide password" : "Show password"}
                  >
                    {showConfirmPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                  </button>
                </div>
                {newPassword && confirmPassword && (
                  <p className={`text-[11px] font-bold ${newPassword === confirmPassword ? 'text-emerald-400' : 'text-red-400'}`}>
                    {newPassword === confirmPassword ? '✓ Passwords match' : '✕ Passwords do not match'}
                  </p>
                )}
              </div>
            </div>

            {/* Password Strength Meter & Compliance Checklist */}
            {newPassword && (
              <div className="p-4 bg-zinc-950 border border-zinc-800 rounded-xl space-y-4 animate-in fade-in duration-200">
                <div className="flex items-center justify-between">
                  <span className="text-xs font-bold text-zinc-300 uppercase tracking-wider">
                    Password Security Evaluation
                  </span>
                  <span className={`text-[10px] font-bold px-2.5 py-0.5 rounded border uppercase tracking-wider ${
                    passedCount === 5 
                      ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30' 
                      : passedCount >= 3 
                      ? 'bg-amber-500/10 text-amber-400 border-amber-500/30' 
                      : 'bg-red-500/10 text-red-400 border-red-500/30'
                  }`}>
                    {passedCount === 5 ? 'Strong & Compliant' : passedCount >= 3 ? 'Moderate' : 'Weak Password'}
                  </span>
                </div>

                {/* Strength Meter Bar */}
                <div className="w-full bg-zinc-900 h-2 rounded-full overflow-hidden border border-zinc-800">
                  <div 
                    className={`h-full transition-all duration-300 ${
                      passedCount === 5 ? 'bg-emerald-500' : passedCount >= 3 ? 'bg-amber-500' : 'bg-red-500'
                    }`}
                    style={{ width: `${strengthPercentage}%` }}
                  />
                </div>

                {/* Criteria Checklist */}
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-2.5 pt-1">
                  {criteriaList.map((crit, idx) => (
                    <div key={idx} className="flex items-center gap-2 text-xs">
                      {crit.valid ? (
                        <CheckCircle2 className="w-4 h-4 text-emerald-400 shrink-0" />
                      ) : (
                        <X className="w-4 h-4 text-zinc-600 shrink-0" />
                      )}
                      <span className={crit.valid ? 'text-zinc-200 font-medium' : 'text-zinc-500'}>
                        {crit.label}
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        </div>

        {/* Action Controls */}
        <div className="flex items-center justify-end gap-4 pt-2">
          <button
            type="submit"
            disabled={isSubmitting}
            className="px-6 py-3 bg-blue-600 hover:bg-blue-500 disabled:opacity-50 disabled:cursor-not-allowed text-white font-bold text-sm rounded-xl transition-all flex items-center justify-center gap-2 shadow-lg shadow-blue-900/30"
          >
            {isSubmitting ? (
              <>
                <RefreshCcw className="w-4 h-4 animate-spin" />
                Updating Admin Profile...
              </>
            ) : (
              <>
                <Save className="w-4 h-4" />
                Save Profile Changes
              </>
            )}
          </button>
        </div>
      </form>
    </div>
  );
};
