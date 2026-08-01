import React, { useState, useEffect } from 'react';
import { CheckCircle2, AlertCircle, Info, X } from 'lucide-react';
import { toast, ToastMessage } from '../utils/toast';

export const ToastContainer: React.FC = () => {
  const [toasts, setToasts] = useState<ToastMessage[]>([]);

  useEffect(() => {
    const unsubscribe = toast.subscribe((newToast) => {
      setToasts((prev) => [...prev, newToast]);
      setTimeout(() => {
        setToasts((prev) => prev.filter((t) => t.id !== newToast.id));
      }, 3000);
    });
    return unsubscribe;
  }, []);

  if (toasts.length === 0) return null;

  return (
    <div className="fixed bottom-6 right-6 z-[99999] flex flex-col gap-2 max-w-sm pointer-events-none">
      {toasts.map((t) => (
        <div
          key={t.id}
          className={`pointer-events-auto flex items-center gap-2.5 px-4 py-3 rounded-lg shadow-2xl border text-sm font-medium transition-all duration-200 animate-in fade-in slide-in-from-bottom-2 ${
            t.type === 'success'
              ? 'bg-zinc-900 border-emerald-500/40 text-emerald-400'
              : t.type === 'error'
              ? 'bg-zinc-900 border-red-500/40 text-red-400'
              : 'bg-zinc-900 border-zinc-700 text-zinc-200'
          }`}
        >
          {t.type === 'success' && <CheckCircle2 className="w-4 h-4 text-emerald-500 shrink-0" />}
          {t.type === 'error' && <AlertCircle className="w-4 h-4 text-red-500 shrink-0" />}
          {t.type === 'info' && <Info className="w-4 h-4 text-blue-500 shrink-0" />}
          <span className="flex-1">{t.message}</span>
          <button
            onClick={() => setToasts((prev) => prev.filter((item) => item.id !== t.id))}
            className="text-zinc-500 hover:text-zinc-300 ml-2 cursor-pointer"
          >
            <X className="w-3.5 h-3.5" />
          </button>
        </div>
      ))}
    </div>
  );
};
