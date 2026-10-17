import { useEffect, useRef, useState } from 'react';
import { TimerView } from './timer-view';
import { useTimerSounds } from './use-timer-sounds';
import { completionMode } from './completion-policy';
import './timer.css';

export const TimerApp = () => {
  const sounds = useTimerSounds();
  const { playCompletion } = sounds;
  const [minutes, setMinutes] = useState('25');
  const duration = Number(minutes);
  const validDuration = Number.isInteger(duration) && duration >= 1 && duration <= 180;
  const [remainingMilliseconds, setRemainingMilliseconds] = useState(25 * 60 * 1000);
  const [deadline, setDeadline] = useState<number | null>(null);
  const [completionNotice, setCompletionNotice] = useState<string | null>(null);
  const wasHidden = useRef(false);
  const completed = remainingMilliseconds === 0;

  useEffect(() => {
    if (deadline === null) return;
    const update = () => {
      const now = Date.now();
      const mode = completionMode(deadline, now, document.visibilityState === 'visible', wasHidden.current);
      setRemainingMilliseconds(Math.max(0, deadline - now));
      if (mode === 'running') {
        if (document.visibilityState === 'visible') wasHidden.current = false;
        return;
      }
      setDeadline(null);
      if (mode === 'audible') playCompletion();
      else setCompletionNotice('背景で時間になりました。終了音は再生していません。');
    };
    const onVisibilityChange = () => {
      if (document.visibilityState === 'hidden') wasHidden.current = true;
      else update();
    };
    const id = window.setInterval(update, 100);
    document.addEventListener('visibilitychange', onVisibilityChange);
    update();
    return () => {
      window.clearInterval(id);
      document.removeEventListener('visibilitychange', onVisibilityChange);
    };
  }, [deadline, playCompletion]);

  return (
    <TimerView
      minutes={minutes}
      validDuration={validDuration}
      remaining={Math.ceil(remainingMilliseconds / 1000)}
      remainingMilliseconds={remainingMilliseconds}
      running={deadline !== null}
      completed={completed}
      soundLibrary={sounds.library}
      soundBusy={sounds.busy}
      soundReady={sounds.ready}
      soundError={sounds.error}
      completionNotice={completionNotice}
      onAddSound={sounds.onAdd}
      onSelectSound={sounds.onSelect}
      onDeleteSound={sounds.onDelete}
      onPreviewSound={sounds.onPreview}
      onRetrySounds={sounds.onRetry}
      onMinutes={(next) => {
        if (completed) return;
        setMinutes(next);
        const value = Number(next);
        if (Number.isInteger(value) && value >= 1 && value <= 180)
          setRemainingMilliseconds(value * 60 * 1000);
      }}
      onToggle={() => {
        if (deadline !== null) {
          const now = Date.now();
          const mode = completionMode(deadline, now, document.visibilityState === 'visible', wasHidden.current);
          setRemainingMilliseconds(Math.max(0, deadline - now));
          setDeadline(null);
          if (mode === 'audible') playCompletion();
          if (mode === 'silent') setCompletionNotice('背景で時間になりました。終了音は再生していません。');
        } else {
          if (completed || !validDuration || !sounds.ready || sounds.busy) return;
          const milliseconds = remainingMilliseconds || duration * 60 * 1000;
          setRemainingMilliseconds(milliseconds);
          setDeadline(Date.now() + milliseconds);
        }
      }}
      onReset={() => {
        sounds.stopCompletion();
        setCompletionNotice(null);
        wasHidden.current = false;
        setDeadline(null);
        if (!validDuration) setMinutes('25');
        setRemainingMilliseconds((validDuration ? duration : 25) * 60 * 1000);
      }}
    />
  );
};
