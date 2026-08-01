import React, { useState } from 'react';
import { Copy, Check } from 'lucide-react';
import { copyToClipboard } from '../utils/clipboard';

interface CopyButtonProps {
  text: string;
  className?: string;
  iconClassName?: string;
  label?: React.ReactNode;
  copiedLabel?: React.ReactNode;
  showIconOnly?: boolean;
  disabled?: boolean;
  onCopySuccess?: () => void;
  onCopyError?: () => void;
  title?: string;
}

export const CopyButton: React.FC<CopyButtonProps> = ({
  text,
  className = 'p-1.5 hover:bg-zinc-800 text-zinc-400 hover:text-white rounded transition-colors',
  iconClassName = 'w-3.5 h-3.5',
  label,
  copiedLabel,
  showIconOnly = false,
  disabled = false,
  onCopySuccess,
  onCopyError,
  title = 'Copy to clipboard'
}) => {
  const [isCopied, setIsCopied] = useState(false);
  const [isCopying, setIsCopying] = useState(false);

  const isEmpty = !text || text.trim() === '';
  const isDisabled = disabled || isEmpty || isCopying;

  const handleClick = async (e: React.MouseEvent) => {
    e.stopPropagation();
    e.preventDefault();

    if (isDisabled) return;

    setIsCopying(true);
    const success = await copyToClipboard(text);
    setIsCopying(false);

    if (success) {
      setIsCopied(true);
      if (onCopySuccess) onCopySuccess();
      setTimeout(() => {
        setIsCopied(false);
      }, 2000);
    } else {
      if (onCopyError) onCopyError();
    }
  };

  return (
    <button
      type="button"
      onClick={handleClick}
      disabled={isDisabled}
      title={isEmpty ? 'Nothing to copy' : title}
      className={`${className} ${isDisabled && isEmpty ? 'opacity-40 cursor-not-allowed' : 'cursor-pointer'}`}
    >
      {isCopied ? (
        <Check className={`${iconClassName} text-emerald-500`} />
      ) : (
        <Copy className={iconClassName} />
      )}
      {!showIconOnly && label && (
        <span className="ml-1 flex items-center gap-1">
          {isCopied ? (copiedLabel || 'Copied!') : label}
        </span>
      )}
    </button>
  );
};
