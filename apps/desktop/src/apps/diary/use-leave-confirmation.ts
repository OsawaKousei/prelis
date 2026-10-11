import { useEffect, useRef, useState } from 'react';
import { getCurrentWindow } from '@tauri-apps/api/window';
import { BEFORE_APP_NAVIGATE } from '../../shell/navigation';
import { isDesktop } from './storage';
export const useLeaveConfirmation = (dirty: boolean, saving: boolean) => {
  const [pending, setPending] = useState<{
    readonly action: () => void;
  } | null>(null);
  const [closeError, setCloseError] = useState(false);
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
    let disposed = false;
    let unlisten: (() => void) | undefined;
    if (isDesktop) {
      void getCurrentWindow()
        .onCloseRequested((event) => {
          const { dirty, saving } = current.current;
          if (disposed || (!dirty && !saving)) return;
          event.preventDefault();
          if (!saving)
            setPending({
              action: () => {
                void getCurrentWindow()
                  .destroy()
                  .catch(() => setCloseError(true));
              },
            });
        })
        .then((remove) => {
          if (disposed) remove();
          else unlisten = remove;
        })
        .catch(() => {
          if (!disposed) setCloseError(true);
        });
    }
    return () => {
      disposed = true;
      unlisten?.();
      window.removeEventListener(BEFORE_APP_NAVIGATE, beforeNavigate);
      window.removeEventListener('beforeunload', beforeUnload);
    };
  }, []);
  return {
    pending,
    closeError,
    requestLeave,
    cancel: () => setPending(null),
    discard: () => {
      const action = pending?.action;
      setPending(null);
      action?.();
    },
  };
};
