import { toast } from './toast';

/**
 * Universal cross-browser copy to clipboard utility.
 * Supports Chrome Desktop, Chrome Android, Firefox, Edge, Safari, Samsung Internet.
 * Includes automatic fallback for non-secure contexts or browsers without Clipboard API.
 */
export async function copyToClipboard(text: string): Promise<boolean> {
  if (!text || text.trim() === '') {
    toast.error('Copy failed');
    return false;
  }

  let success = false;

  // 1. Primary: Modern Clipboard API (supported in HTTPS/secure contexts)
  if (typeof navigator !== 'undefined' && navigator.clipboard && typeof navigator.clipboard.writeText === 'function') {
    try {
      await navigator.clipboard.writeText(text);
      success = true;
    } catch (err) {
      console.warn('[Clipboard Utility] navigator.clipboard failed, attempting fallback:', err);
    }
  }

  // 2. Fallback: Hidden Textarea with document.execCommand('copy')
  if (!success && typeof document !== 'undefined') {
    try {
      const textArea = document.createElement('textarea');
      textArea.value = text;
      
      // Prevent screen scrolling or zooming on mobile devices
      textArea.style.position = 'fixed';
      textArea.style.top = '0';
      textArea.style.left = '0';
      textArea.style.width = '2em';
      textArea.style.height = '2em';
      textArea.style.padding = '0';
      textArea.style.border = 'none';
      textArea.style.outline = 'none';
      textArea.style.boxShadow = 'none';
      textArea.style.background = 'transparent';
      textArea.style.opacity = '0';

      document.body.appendChild(textArea);
      textArea.focus();
      textArea.select();

      // iOS Safari specific selection range
      if (navigator.userAgent.match(/ipad|ipod|iphone/i)) {
        const range = document.createRange();
        range.selectNodeContents(textArea);
        const selection = window.getSelection();
        if (selection) {
          selection.removeAllRanges();
          selection.addRange(range);
        }
        textArea.setSelectionRange(0, 999999);
      }

      success = document.execCommand('copy');
      document.body.removeChild(textArea);
    } catch (err) {
      console.error('[Clipboard Utility] execCommand fallback failed:', err);
      success = false;
    }
  }

  if (success) {
    toast.success('Copied successfully');
  } else {
    toast.error('Copy failed');
  }

  return success;
}
