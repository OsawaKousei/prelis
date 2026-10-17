import { useEffect, useRef, useState } from 'react';
import { BEFORE_APP_NAVIGATE } from '../../shell/navigation';
export const useLeaveConfirmation = (dirty: boolean, saving: boolean) => {
  const [pending, setPending] = useState<{
    readonly action: () => void;
  } | null>(null);
  const current = useRef({ dirty, saving });
  useEffect(() => {
    current.current = { dirty, saving };
  }, [dirty, saving]);
  const requestLeave = (action: () => void) => {
    if (saving) return;
    if (dirty) setPending({ action });
    else action();
  };
  useEffect(() => {
    const beforeNavigate = (event: Event) => {
      const { dirty, saving } = current.current;
      if (!(event instanceof CustomEvent) || typeof event.detail !== 'function')
        return;
      if (saving || dirty) {
        event.preventDefault();
        if (!saving) setPending({ action: event.detail as () => void });
      }
    };
    const beforeUnload = (event: BeforeUnloadEvent) => {
      const { dirty, saving } = current.current;
      if (dirty || saving) {
        event.preventDefault();
        event.returnValue = '';
      }
    };
    window.addEventListener(BEFORE_APP_NAVIGATE, beforeNavigate);
    window.addEventListener('beforeunload', beforeUnload);
    return () => {
      window.removeEventListener(BEFORE_APP_NAVIGATE, beforeNavigate);
      window.removeEventListener('beforeunload', beforeUnload);
    };
  }, []);
  return {
    pending,
    requestLeave,
    cancel: () => setPending(null),
    discard: () => {
      const action = pending?.action;
      setPending(null);
      action?.();
    },
  };
};
