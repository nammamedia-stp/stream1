import React, { useState, useEffect, useCallback } from 'react';
import { 
  Shield, 
  FileText, 
  Search, 
  Filter, 
  RefreshCcw, 
  Download, 
  Trash2, 
  Settings, 
  Clock, 
  User, 
  AlertTriangle, 
  CheckCircle2, 
  XCircle, 
  ChevronLeft, 
  ChevronRight, 
  SlidersHorizontal,
  Calendar,
  Activity,
  Key,
  Server,
  Tv,
  Users,
  Eye,
  Info,
  X,
  Database
} from 'lucide-react';

export interface AuditLogItem {
  id: string;
  timestamp: string;
  username: string;
  user_role: string;
  action: string;
  module: string;
  ip_address: string;
  user_agent: string;
  result: 'success' | 'failed';
  details: string;
}

interface AuditLogsProps {
  currentUser: any;
  fetchWithNetworkHeaders: (url: string, init?: RequestInit) => Promise<Response>;
}

export const AuditLogs: React.FC<AuditLogsProps> = ({
  currentUser,
  fetchWithNetworkHeaders,
}) => {
  const [logs, setLogs] = useState<AuditLogItem[]>([]);
  const [totalCount, setTotalCount] = useState<number>(0);
  const [page, setPage] = useState<number>(1);
  const [limit, setLimit] = useState<number>(20);
  const [totalPages, setTotalPages] = useState<number>(1);
  const [retentionDays, setRetentionDays] = useState<number>(30);
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);

  // Filter states
  const [search, setSearch] = useState<string>('');
  const [moduleFilter, setModuleFilter] = useState<string>('all');
  const [resultFilter, setResultFilter] = useState<string>('all');
  const [actionFilter, setActionFilter] = useState<string>('all');
  const [usernameFilter, setUsernameFilter] = useState<string>('');
  const [startDate, setStartDate] = useState<string>('');
  const [endDate, setEndDate] = useState<string>('');

  // UI Modals
  const [selectedLog, setSelectedLog] = useState<AuditLogItem | null>(null);
  const [showRetentionModal, setShowRetentionModal] = useState<boolean>(false);
  const [newRetentionDays, setNewRetentionDays] = useState<number>(30);
  const [retentionSaving, setRetentionSaving] = useState<boolean>(false);
  const [retentionMessage, setRetentionMessage] = useState<{ type: 'success' | 'error'; text: string } | null>(null);
  const [cleanupLoading, setCleanupLoading] = useState<boolean>(false);

  // Check if admin
  const isAdmin = currentUser?.role === 'admin';

  // Fetch Audit Logs
  const fetchAuditLogs = useCallback(async () => {
    if (!isAdmin) return;
    setIsLoading(true);
    setError(null);

    try {
      const queryParams = new URLSearchParams();
      queryParams.append('page', page.toString());
      queryParams.append('limit', limit.toString());

      if (search.trim()) queryParams.append('search', search.trim());
      if (moduleFilter !== 'all') queryParams.append('module', moduleFilter);
      if (resultFilter !== 'all') queryParams.append('result', resultFilter);
      if (actionFilter !== 'all') queryParams.append('action', actionFilter);
      if (usernameFilter.trim()) queryParams.append('username', usernameFilter.trim());
      if (startDate) queryParams.append('startDate', startDate);
      if (endDate) queryParams.append('endDate', endDate);

      const res = await fetchWithNetworkHeaders(`/api/admin/audit-logs?${queryParams.toString()}`);
      if (!res.ok) {
        if (res.status === 403) {
          throw new Error('Access denied: Administrator privileges required');
        }
        const errData = await res.json().catch(() => ({}));
        throw new Error(errData.error || 'Failed to retrieve system audit logs');
      }

      const data = await res.json();
      setLogs(data.logs || []);
      setTotalCount(data.totalCount || 0);
      setTotalPages(data.totalPages || 1);
      if (data.retentionDays !== undefined) {
        setRetentionDays(data.retentionDays);
        setNewRetentionDays(data.retentionDays);
      }
    } catch (err: any) {
      console.error('Error loading audit logs:', err);
      setError(err.message || 'An unexpected error occurred while fetching audit logs');
    } finally {
      setIsLoading(false);
    }
  }, [isAdmin, page, limit, search, moduleFilter, resultFilter, actionFilter, usernameFilter, startDate, endDate, fetchWithNetworkHeaders]);

  useEffect(() => {
    fetchAuditLogs();
  }, [fetchAuditLogs]);

  // Reset pagination when filter changes
  const handleFilterChange = (setter: (val: any) => void, val: any) => {
    setter(val);
    setPage(1);
  };

  const handleClearFilters = () => {
    setSearch('');
    setModuleFilter('all');
    setResultFilter('all');
    setActionFilter('all');
    setUsernameFilter('');
    setStartDate('');
    setEndDate('');
    setPage(1);
  };

  // Export handlers
  const handleExport = async (format: 'csv' | 'json') => {
    try {
      const queryParams = new URLSearchParams();
      queryParams.append('format', format);
      if (search.trim()) queryParams.append('search', search.trim());
      if (moduleFilter !== 'all') queryParams.append('module', moduleFilter);
      if (resultFilter !== 'all') queryParams.append('result', resultFilter);
      if (actionFilter !== 'all') queryParams.append('action', actionFilter);
      if (usernameFilter.trim()) queryParams.append('username', usernameFilter.trim());
      if (startDate) queryParams.append('startDate', startDate);
      if (endDate) queryParams.append('endDate', endDate);

      const res = await fetchWithNetworkHeaders(`/api/admin/audit-logs/export?${queryParams.toString()}`);
      if (!res.ok) {
        throw new Error('Export failed');
      }

      const blob = await res.blob();
      const url = window.URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `streampulse_audit_logs_${new Date().toISOString().slice(0, 10)}.${format}`;
      document.body.appendChild(a);
      a.click();
      window.URL.revokeObjectURL(url);
      document.body.removeChild(a);
    } catch (err: any) {
      alert('Failed to export audit logs: ' + err.message);
    }
  };

  // Save retention policy
  const handleSaveRetention = async () => {
    setRetentionSaving(true);
    setRetentionMessage(null);
    try {
      const res = await fetchWithNetworkHeaders('/api/admin/audit-logs/retention', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ retentionDays: newRetentionDays })
      });

      const data = await res.json();
      if (!res.ok) {
        throw new Error(data.error || 'Failed to update retention policy');
      }

      setRetentionDays(newRetentionDays);
      setRetentionMessage({ type: 'success', text: `Audit log retention period successfully set to ${newRetentionDays} days` });
      setTimeout(() => setRetentionMessage(null), 4000);
    } catch (err: any) {
      setRetentionMessage({ type: 'error', text: err.message || 'Failed to save retention policy' });
    } finally {
      setRetentionSaving(false);
    }
  };

  // Manual cleanup trigger
  const handleRunCleanup = async () => {
    if (!window.confirm(`Are you sure you want to run retention cleanup now? This will permanently delete audit logs older than ${retentionDays} days.`)) {
      return;
    }

    setCleanupLoading(true);
    try {
      const res = await fetchWithNetworkHeaders('/api/admin/audit-logs/cleanup', {
        method: 'POST'
      });
      const data = await res.json();
      if (!res.ok) {
        throw new Error(data.error || 'Cleanup failed');
      }

      alert(data.message || `Successfully purged ${data.count || 0} expired log entries.`);
      fetchAuditLogs();
    } catch (err: any) {
      alert('Failed to run audit cleanup: ' + err.message);
    } finally {
      setCleanupLoading(false);
    }
  };

  // Module Badge Styling Helper
  const getModuleBadge = (moduleName: string) => {
    switch (moduleName) {
      case 'Authentication':
        return 'bg-blue-500/10 text-blue-400 border-blue-500/30';
      case 'User Management':
        return 'bg-purple-500/10 text-purple-400 border-purple-500/30';
      case 'Streaming':
        return 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30';
      case 'Settings':
        return 'bg-amber-500/10 text-amber-400 border-amber-500/30';
      case 'System':
        return 'bg-rose-500/10 text-rose-400 border-rose-500/30';
      default:
        return 'bg-slate-500/10 text-slate-400 border-slate-500/30';
    }
  };

  // Action Icon Helper
  const getActionIcon = (action: string) => {
    if (action.includes('Login') || action.includes('Logout')) return <Key className="w-3.5 h-3.5 mr-1" />;
    if (action.includes('Password') || action.includes('Role') || action.includes('User')) return <User className="w-3.5 h-3.5 mr-1" />;
    if (action.includes('Stream') || action.includes('Playback') || action.includes('Resolution')) return <Tv className="w-3.5 h-3.5 mr-1" />;
    if (action.includes('SSL') || action.includes('Domain') || action.includes('Settings')) return <Settings className="w-3.5 h-3.5 mr-1" />;
    if (action.includes('Restart') || action.includes('Backup') || action.includes('Restore') || action.includes('Docker')) return <Server className="w-3.5 h-3.5 mr-1" />;
    return <Activity className="w-3.5 h-3.5 mr-1" />;
  };

  if (!isAdmin) {
    return (
      <div className="p-8 text-center max-w-2xl mx-auto my-12 bg-slate-900 border border-slate-800 rounded-xl shadow-2xl">
        <Shield className="w-16 h-16 text-rose-500 mx-auto mb-4 animate-bounce" />
        <h2 className="text-2xl font-bold text-slate-100 mb-2">Access Denied</h2>
        <p className="text-slate-400 mb-6">
          System Audit Logs are strictly confidential and restricted to Super Administrators only.
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* HEADER SECTION */}
      <div className="flex flex-col lg:flex-row lg:items-center justify-between gap-4 bg-slate-900/80 p-6 rounded-2xl border border-slate-800 backdrop-blur-md">
        <div>
          <div className="flex items-center space-x-3 mb-1">
            <div className="p-2.5 bg-gradient-to-br from-indigo-500/20 to-purple-500/20 border border-indigo-500/30 rounded-xl">
              <Shield className="w-6 h-6 text-indigo-400" />
            </div>
            <div>
              <div className="flex items-center space-x-2">
                <span className="text-xs font-semibold uppercase tracking-wider text-indigo-400 bg-indigo-500/10 px-2 py-0.5 rounded border border-indigo-500/20">
                  System → Audit Logs
                </span>
                <span className="text-xs text-slate-500">•</span>
                <span className="text-xs text-emerald-400 flex items-center font-medium">
                  <CheckCircle2 className="w-3 h-3 mr-1" /> Read-Only Immutable Trail
                </span>
              </div>
              <h1 className="text-2xl font-bold text-slate-100 tracking-tight">System Audit Log Trail</h1>
            </div>
          </div>
          <p className="text-sm text-slate-400 mt-1">
            Real-time security auditing tracking authentication, user management, stream operations, settings changes, and system events.
          </p>
        </div>

        {/* Action Controls */}
        <div className="flex flex-wrap items-center gap-2">
          <button
            onClick={() => handleExport('csv')}
            className="flex items-center px-3.5 py-2 bg-slate-800 hover:bg-slate-700 text-slate-200 text-sm font-medium rounded-lg border border-slate-700 transition-colors shadow-sm"
            title="Export filtered logs as CSV"
          >
            <Download className="w-4 h-4 mr-2 text-indigo-400" />
            Export CSV
          </button>
          <button
            onClick={() => handleExport('json')}
            className="flex items-center px-3.5 py-2 bg-slate-800 hover:bg-slate-700 text-slate-200 text-sm font-medium rounded-lg border border-slate-700 transition-colors shadow-sm"
            title="Export filtered logs as JSON"
          >
            <Download className="w-4 h-4 mr-2 text-purple-400" />
            Export JSON
          </button>
          <button
            onClick={() => setShowRetentionModal(true)}
            className="flex items-center px-3.5 py-2 bg-slate-800 hover:bg-slate-700 text-slate-200 text-sm font-medium rounded-lg border border-slate-700 transition-colors shadow-sm"
          >
            <Settings className="w-4 h-4 mr-2 text-amber-400" />
            Retention ({retentionDays}d)
          </button>
          <button
            onClick={fetchAuditLogs}
            disabled={isLoading}
            className="flex items-center px-3.5 py-2 bg-indigo-600 hover:bg-indigo-500 text-white text-sm font-medium rounded-lg transition-colors shadow-sm disabled:opacity-50"
          >
            <RefreshCcw className={`w-4 h-4 mr-2 ${isLoading ? 'animate-spin' : ''}`} />
            Refresh
          </button>
        </div>
      </div>

      {/* METRIC OVERVIEW CARDS */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <div className="bg-slate-900/60 p-4 rounded-xl border border-slate-800/80">
          <div className="flex items-center justify-between">
            <span className="text-xs font-medium text-slate-400">Total Audit Events</span>
            <Activity className="w-4 h-4 text-indigo-400" />
          </div>
          <p className="text-2xl font-bold text-slate-100 mt-2">{totalCount.toLocaleString()}</p>
          <span className="text-xs text-slate-500 mt-1 block">Indexed records in history</span>
        </div>

        <div className="bg-slate-900/60 p-4 rounded-xl border border-slate-800/80">
          <div className="flex items-center justify-between">
            <span className="text-xs font-medium text-slate-400">Retention Policy</span>
            <Clock className="w-4 h-4 text-amber-400" />
          </div>
          <p className="text-2xl font-bold text-slate-100 mt-2">{retentionDays} Days</p>
          <span className="text-xs text-slate-500 mt-1 block">Auto-purge after retention limit</span>
        </div>

        <div className="bg-slate-900/60 p-4 rounded-xl border border-slate-800/80">
          <div className="flex items-center justify-between">
            <span className="text-xs font-medium text-slate-400">Current View Range</span>
            <Filter className="w-4 h-4 text-purple-400" />
          </div>
          <p className="text-2xl font-bold text-slate-100 mt-2">{logs.length} Records</p>
          <span className="text-xs text-slate-500 mt-1 block">Page {page} of {totalPages}</span>
        </div>

        <div className="bg-slate-900/60 p-4 rounded-xl border border-slate-800/80">
          <div className="flex items-center justify-between">
            <span className="text-xs font-medium text-slate-400">Access Security</span>
            <Shield className="w-4 h-4 text-emerald-400" />
          </div>
          <p className="text-2xl font-bold text-emerald-400 mt-2">Active</p>
          <span className="text-xs text-slate-500 mt-1 block">Strict Admin Authentication</span>
        </div>
      </div>

      {/* FILTER & SEARCH BAR */}
      <div className="bg-slate-900/70 p-5 rounded-xl border border-slate-800 space-y-4">
        <div className="flex items-center justify-between border-b border-slate-800 pb-3">
          <div className="flex items-center space-x-2 text-slate-200 font-medium text-sm">
            <SlidersHorizontal className="w-4 h-4 text-indigo-400" />
            <span>Filter Audit Trail</span>
          </div>
          {(search || moduleFilter !== 'all' || resultFilter !== 'all' || actionFilter !== 'all' || usernameFilter || startDate || endDate) && (
            <button
              onClick={handleClearFilters}
              className="text-xs text-indigo-400 hover:text-indigo-300 font-medium flex items-center"
            >
              <X className="w-3.5 h-3.5 mr-1" />
              Reset All Filters
            </button>
          )}
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 lg:grid-cols-6 gap-3">
          {/* Search Box */}
          <div className="md:col-span-2">
            <label className="block text-xs font-medium text-slate-400 mb-1">Search Keywords</label>
            <div className="relative">
              <Search className="w-4 h-4 text-slate-500 absolute left-3 top-1/2 -translate-y-1/2" />
              <input
                type="text"
                value={search}
                onChange={(e) => handleFilterChange(setSearch, e.target.value)}
                placeholder="Search action, IP, username, details..."
                className="w-full pl-9 pr-3 py-2 bg-slate-950 border border-slate-800 rounded-lg text-sm text-slate-200 placeholder-slate-500 focus:outline-none focus:border-indigo-500"
              />
            </div>
          </div>

          {/* Module Filter */}
          <div>
            <label className="block text-xs font-medium text-slate-400 mb-1">Module</label>
            <select
              value={moduleFilter}
              onChange={(e) => handleFilterChange(setModuleFilter, e.target.value)}
              className="w-full px-3 py-2 bg-slate-950 border border-slate-800 rounded-lg text-sm text-slate-200 focus:outline-none focus:border-indigo-500"
            >
              <option value="all">All Modules</option>
              <option value="Authentication">Authentication</option>
              <option value="User Management">User Management</option>
              <option value="Streaming">Streaming</option>
              <option value="Settings">Settings</option>
              <option value="System">System</option>
            </select>
          </div>

          {/* Result Filter */}
          <div>
            <label className="block text-xs font-medium text-slate-400 mb-1">Result Status</label>
            <select
              value={resultFilter}
              onChange={(e) => handleFilterChange(setResultFilter, e.target.value)}
              className="w-full px-3 py-2 bg-slate-950 border border-slate-800 rounded-lg text-sm text-slate-200 focus:outline-none focus:border-indigo-500"
            >
              <option value="all">All Results</option>
              <option value="success">Success</option>
              <option value="failed">Failed</option>
            </select>
          </div>

          {/* Start Date */}
          <div>
            <label className="block text-xs font-medium text-slate-400 mb-1">From Date</label>
            <input
              type="date"
              value={startDate}
              onChange={(e) => handleFilterChange(setStartDate, e.target.value)}
              className="w-full px-3 py-2 bg-slate-950 border border-slate-800 rounded-lg text-sm text-slate-200 focus:outline-none focus:border-indigo-500"
            />
          </div>

          {/* End Date */}
          <div>
            <label className="block text-xs font-medium text-slate-400 mb-1">To Date</label>
            <input
              type="date"
              value={endDate}
              onChange={(e) => handleFilterChange(setEndDate, e.target.value)}
              className="w-full px-3 py-2 bg-slate-950 border border-slate-800 rounded-lg text-sm text-slate-200 focus:outline-none focus:border-indigo-500"
            />
          </div>
        </div>
      </div>

      {/* ERROR BANNER */}
      {error && (
        <div className="p-4 bg-rose-500/10 border border-rose-500/30 rounded-xl flex items-center justify-between text-rose-300 text-sm">
          <div className="flex items-center space-x-2">
            <AlertTriangle className="w-5 h-5 text-rose-400 shrink-0" />
            <span>{error}</span>
          </div>
          <button onClick={fetchAuditLogs} className="underline text-xs hover:text-rose-200">
            Retry
          </button>
        </div>
      )}

      {/* AUDIT LOG TABLE */}
      <div className="bg-slate-900/80 rounded-2xl border border-slate-800 overflow-hidden shadow-xl">
        <div className="overflow-x-auto">
          <table className="w-full text-left border-collapse">
            <thead>
              <tr className="bg-slate-950/80 border-b border-slate-800 text-xs font-semibold text-slate-400 uppercase tracking-wider">
                <th className="py-3.5 px-4">Timestamp</th>
                <th className="py-3.5 px-4">User</th>
                <th className="py-3.5 px-4">Action</th>
                <th className="py-3.5 px-4">Module</th>
                <th className="py-3.5 px-4">IP Address</th>
                <th className="py-3.5 px-4">Result</th>
                <th className="py-3.5 px-4 text-right">Details</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800/60 text-sm text-slate-200">
              {isLoading ? (
                Array.from({ length: 5 }).map((_, i) => (
                  <tr key={i} className="animate-pulse">
                    <td className="py-4 px-4"><div className="h-4 bg-slate-800 rounded w-28"></div></td>
                    <td className="py-4 px-4"><div className="h-4 bg-slate-800 rounded w-20"></div></td>
                    <td className="py-4 px-4"><div className="h-4 bg-slate-800 rounded w-24"></div></td>
                    <td className="py-4 px-4"><div className="h-4 bg-slate-800 rounded w-20"></div></td>
                    <td className="py-4 px-4"><div className="h-4 bg-slate-800 rounded w-24"></div></td>
                    <td className="py-4 px-4"><div className="h-4 bg-slate-800 rounded w-16"></div></td>
                    <td className="py-4 px-4"><div className="h-4 bg-slate-800 rounded w-12 ml-auto"></div></td>
                  </tr>
                ))
              ) : logs.length === 0 ? (
                <tr>
                  <td colSpan={7} className="py-12 text-center text-slate-500">
                    <FileText className="w-12 h-12 mx-auto mb-3 opacity-30" />
                    <p className="text-base font-medium text-slate-400">No audit log records found</p>
                    <p className="text-xs text-slate-600 mt-1">Try clearing your search query or selecting a broader date filter</p>
                  </td>
                </tr>
              ) : (
                logs.map((log) => (
                  <tr
                    key={log.id}
                    onClick={() => setSelectedLog(log)}
                    className="hover:bg-slate-800/50 cursor-pointer transition-colors group"
                  >
                    {/* Timestamp */}
                    <td className="py-3.5 px-4 whitespace-nowrap text-xs text-slate-300 font-mono">
                      {new Date(log.timestamp).toLocaleString(undefined, {
                        year: 'numeric',
                        month: '2-digit',
                        day: '2-digit',
                        hour: '2-digit',
                        minute: '2-digit',
                        second: '2-digit'
                      })}
                    </td>

                    {/* User */}
                    <td className="py-3.5 px-4 whitespace-nowrap">
                      <div className="flex items-center space-x-2">
                        <span className="font-semibold text-slate-200">{log.username}</span>
                        <span className={`text-[10px] px-1.5 py-0.5 rounded font-medium border ${
                          log.user_role === 'admin'
                            ? 'bg-rose-500/10 text-rose-400 border-rose-500/30'
                            : 'bg-slate-800 text-slate-400 border-slate-700'
                        }`}>
                          {log.user_role}
                        </span>
                      </div>
                    </td>

                    {/* Action */}
                    <td className="py-3.5 px-4 whitespace-nowrap font-medium text-slate-100">
                      <div className="flex items-center text-xs">
                        {getActionIcon(log.action)}
                        <span>{log.action}</span>
                      </div>
                    </td>

                    {/* Module */}
                    <td className="py-3.5 px-4 whitespace-nowrap">
                      <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium border ${getModuleBadge(log.module)}`}>
                        {log.module}
                      </span>
                    </td>

                    {/* IP Address */}
                    <td className="py-3.5 px-4 whitespace-nowrap font-mono text-xs text-slate-400">
                      {log.ip_address}
                    </td>

                    {/* Result */}
                    <td className="py-3.5 px-4 whitespace-nowrap">
                      {log.result === 'success' ? (
                        <span className="inline-flex items-center px-2 py-0.5 rounded text-xs font-semibold bg-emerald-500/10 text-emerald-400 border border-emerald-500/30">
                          <CheckCircle2 className="w-3 h-3 mr-1" />
                          Success
                        </span>
                      ) : (
                        <span className="inline-flex items-center px-2 py-0.5 rounded text-xs font-semibold bg-rose-500/10 text-rose-400 border border-rose-500/30">
                          <XCircle className="w-3 h-3 mr-1" />
                          Failed
                        </span>
                      )}
                    </td>

                    {/* Details Preview / Inspector */}
                    <td className="py-3.5 px-4 text-right whitespace-nowrap text-xs text-indigo-400 group-hover:text-indigo-300 font-medium">
                      <div className="flex items-center justify-end space-x-1">
                        <span className="hidden sm:inline">Inspect</span>
                        <Eye className="w-4 h-4" />
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>

        {/* PAGINATION FOOTER */}
        <div className="bg-slate-950/90 px-6 py-4 border-t border-slate-800 flex flex-col sm:flex-row items-center justify-between gap-4">
          <div className="text-xs text-slate-400 flex items-center space-x-4">
            <span>
              Showing <strong className="text-slate-200">{logs.length > 0 ? (page - 1) * limit + 1 : 0}</strong> to <strong className="text-slate-200">{Math.min(page * limit, totalCount)}</strong> of <strong className="text-slate-200">{totalCount.toLocaleString()}</strong> records
            </span>

            {/* Per page selector */}
            <div className="flex items-center space-x-2">
              <span>Per page:</span>
              <select
                value={limit}
                onChange={(e) => {
                  setLimit(Number(e.target.value));
                  setPage(1);
                }}
                className="bg-slate-900 border border-slate-800 rounded px-2 py-1 text-xs text-slate-300 focus:outline-none"
              >
                <option value={10}>10</option>
                <option value={20}>20</option>
                <option value={50}>50</option>
                <option value={100}>100</option>
              </select>
            </div>
          </div>

          <div className="flex items-center space-x-2">
            <button
              onClick={() => setPage(1)}
              disabled={page === 1 || isLoading}
              className="px-2.5 py-1.5 bg-slate-800 hover:bg-slate-700 disabled:opacity-40 text-slate-300 text-xs font-medium rounded border border-slate-700 transition-colors"
            >
              First
            </button>
            <button
              onClick={() => setPage(p => Math.max(1, p - 1))}
              disabled={page === 1 || isLoading}
              className="p-1.5 bg-slate-800 hover:bg-slate-700 disabled:opacity-40 text-slate-300 text-xs font-medium rounded border border-slate-700 transition-colors"
            >
              <ChevronLeft className="w-4 h-4" />
            </button>

            <span className="text-xs text-slate-400 px-2 font-medium">
              Page {page} of {totalPages || 1}
            </span>

            <button
              onClick={() => setPage(p => Math.min(totalPages, p + 1))}
              disabled={page >= totalPages || isLoading}
              className="p-1.5 bg-slate-800 hover:bg-slate-700 disabled:opacity-40 text-slate-300 text-xs font-medium rounded border border-slate-700 transition-colors"
            >
              <ChevronRight className="w-4 h-4" />
            </button>
            <button
              onClick={() => setPage(totalPages)}
              disabled={page >= totalPages || isLoading}
              className="px-2.5 py-1.5 bg-slate-800 hover:bg-slate-700 disabled:opacity-40 text-slate-300 text-xs font-medium rounded border border-slate-700 transition-colors"
            >
              Last
            </button>
          </div>
        </div>
      </div>

      {/* INSPECT LOG DETAILS MODAL */}
      {selectedLog && (
        <div className="fixed inset-0 z-50 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="bg-slate-900 border border-slate-800 rounded-2xl max-w-2xl w-full p-6 space-y-6 shadow-2xl relative">
            <div className="flex items-center justify-between border-b border-slate-800 pb-4">
              <div className="flex items-center space-x-3">
                <div className="p-2 bg-indigo-500/10 border border-indigo-500/20 rounded-lg">
                  <Shield className="w-5 h-5 text-indigo-400" />
                </div>
                <div>
                  <h3 className="text-lg font-bold text-slate-100">Audit Log Details</h3>
                  <p className="text-xs text-slate-400">ID: {selectedLog.id}</p>
                </div>
              </div>
              <button
                onClick={() => setSelectedLog(null)}
                className="p-1.5 text-slate-400 hover:text-slate-200 hover:bg-slate-800 rounded-lg transition-colors"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            <div className="grid grid-cols-2 gap-4 text-xs">
              <div className="bg-slate-950 p-3 rounded-lg border border-slate-800">
                <span className="text-slate-500 block mb-1">Timestamp</span>
                <span className="text-slate-200 font-mono">{new Date(selectedLog.timestamp).toISOString()}</span>
              </div>

              <div className="bg-slate-950 p-3 rounded-lg border border-slate-800">
                <span className="text-slate-500 block mb-1">User & Role</span>
                <span className="text-slate-200 font-semibold">{selectedLog.username} ({selectedLog.user_role})</span>
              </div>

              <div className="bg-slate-950 p-3 rounded-lg border border-slate-800">
                <span className="text-slate-500 block mb-1">Action</span>
                <span className="text-slate-200 font-medium">{selectedLog.action}</span>
              </div>

              <div className="bg-slate-950 p-3 rounded-lg border border-slate-800">
                <span className="text-slate-500 block mb-1">Module</span>
                <span className="text-slate-200 font-medium">{selectedLog.module}</span>
              </div>

              <div className="bg-slate-950 p-3 rounded-lg border border-slate-800">
                <span className="text-slate-500 block mb-1">IP Address</span>
                <span className="text-slate-200 font-mono">{selectedLog.ip_address}</span>
              </div>

              <div className="bg-slate-950 p-3 rounded-lg border border-slate-800">
                <span className="text-slate-500 block mb-1">Result Status</span>
                <span className={selectedLog.result === 'success' ? 'text-emerald-400 font-bold' : 'text-rose-400 font-bold'}>
                  {selectedLog.result.toUpperCase()}
                </span>
              </div>
            </div>

            {/* Details box */}
            <div className="space-y-2">
              <label className="text-xs font-semibold text-slate-300">Action Details & Message</label>
              <div className="bg-slate-950 p-3.5 rounded-lg border border-slate-800 text-xs font-mono text-slate-300 whitespace-pre-wrap break-all max-h-36 overflow-y-auto">
                {selectedLog.details || 'No additional details logged'}
              </div>
            </div>

            {/* User Agent */}
            <div className="space-y-1">
              <label className="text-xs font-semibold text-slate-400">User Agent</label>
              <p className="bg-slate-950 p-2.5 rounded border border-slate-800 text-[11px] font-mono text-slate-500 break-all">
                {selectedLog.user_agent}
              </p>
            </div>

            <div className="flex justify-end pt-2 border-t border-slate-800">
              <button
                onClick={() => setSelectedLog(null)}
                className="px-4 py-2 bg-slate-800 hover:bg-slate-700 text-slate-200 text-xs font-medium rounded-lg transition-colors"
              >
                Close Inspector
              </button>
            </div>
          </div>
        </div>
      )}

      {/* RETENTION SETTINGS MODAL */}
      {showRetentionModal && (
        <div className="fixed inset-0 z-50 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4">
          <div className="bg-slate-900 border border-slate-800 rounded-2xl max-w-md w-full p-6 space-y-6 shadow-2xl relative">
            <div className="flex items-center justify-between border-b border-slate-800 pb-4">
              <div className="flex items-center space-x-3">
                <div className="p-2 bg-amber-500/10 border border-amber-500/20 rounded-lg">
                  <Clock className="w-5 h-5 text-amber-400" />
                </div>
                <div>
                  <h3 className="text-lg font-bold text-slate-100">Audit Log Retention Policy</h3>
                  <p className="text-xs text-slate-400">Configure historical log retention and purging</p>
                </div>
              </div>
              <button
                onClick={() => {
                  setShowRetentionModal(false);
                  setRetentionMessage(null);
                }}
                className="p-1.5 text-slate-400 hover:text-slate-200 hover:bg-slate-800 rounded-lg transition-colors"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            {retentionMessage && (
              <div className={`p-3.5 rounded-lg text-xs flex items-center space-x-2 ${
                retentionMessage.type === 'success' ? 'bg-emerald-500/10 border border-emerald-500/30 text-emerald-300' : 'bg-rose-500/10 border border-rose-500/30 text-rose-300'
              }`}>
                {retentionMessage.type === 'success' ? <CheckCircle2 className="w-4 h-4 text-emerald-400 shrink-0" /> : <AlertTriangle className="w-4 h-4 text-rose-400 shrink-0" />}
                <span>{retentionMessage.text}</span>
              </div>
            )}

            <div className="space-y-4">
              <div>
                <label className="block text-xs font-medium text-slate-300 mb-2">
                  Retention Duration (Days)
                </label>
                <input
                  type="number"
                  min={1}
                  max={3650}
                  value={newRetentionDays}
                  onChange={(e) => setNewRetentionDays(Math.max(1, parseInt(e.target.value, 10) || 1))}
                  className="w-full px-3.5 py-2.5 bg-slate-950 border border-slate-800 rounded-lg text-sm text-slate-100 focus:outline-none focus:border-amber-500"
                />
                <p className="text-[11px] text-slate-500 mt-1.5">
                  Audit logs older than {newRetentionDays} days will be automatically purged by the daily automated background cleanup engine.
                </p>
              </div>

              <div className="p-3 bg-slate-950 border border-slate-800 rounded-lg flex items-center justify-between">
                <div>
                  <span className="text-xs font-medium text-slate-200 block">Manual Immediate Purge</span>
                  <span className="text-[11px] text-slate-500">Purge records older than {retentionDays} days right now</span>
                </div>
                <button
                  onClick={handleRunCleanup}
                  disabled={cleanupLoading}
                  className="px-3 py-1.5 bg-rose-600/20 hover:bg-rose-600/30 border border-rose-500/30 text-rose-300 text-xs font-medium rounded-lg transition-colors flex items-center disabled:opacity-50"
                >
                  <Trash2 className="w-3.5 h-3.5 mr-1" />
                  {cleanupLoading ? 'Purging...' : 'Purge Now'}
                </button>
              </div>
            </div>

            <div className="flex items-center justify-end space-x-3 pt-3 border-t border-slate-800">
              <button
                onClick={() => {
                  setShowRetentionModal(false);
                  setRetentionMessage(null);
                }}
                className="px-4 py-2 bg-slate-800 hover:bg-slate-700 text-slate-300 text-xs font-medium rounded-lg transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={handleSaveRetention}
                disabled={retentionSaving}
                className="px-4 py-2 bg-amber-600 hover:bg-amber-500 text-white text-xs font-semibold rounded-lg transition-colors flex items-center disabled:opacity-50"
              >
                {retentionSaving ? 'Saving...' : 'Save Retention Policy'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
