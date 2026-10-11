import { useEffect, useState } from 'react';
import { TimerView } from './timer-view';
import { useTimerSounds } from './use-timer-sounds';
import './timer.css';
export const TimerApp = () => {
  const sounds = useTimerSounds();
  const { playCompletion } = sounds;
  const [minutes, setMinutes] = useState('25');
  const duration = Number(minutes);
  const validDuration =
    Number.isInteger(duration) && duration >= 1 && duration <= 180;
  const [remainingMilliseconds, setRemainingMilliseconds] = useState(
    25 * 60 * 1000,
  );
  const [deadline, setDeadline] = useState<number | null>(null);
  const completed = remainingMilliseconds === 0;
  useEffect(() => {
    if (deadline === null) return;
    const id = window.setInterval(() => {
      const milliseconds = Math.max(0, deadline - Date.now());
      setRemainingMilliseconds(milliseconds);
      if (milliseconds === 0) {
        window.clearInterval(id);
        setDeadline(null);
        playCompletion();
      }
    }, 100);
    return () => window.clearInterval(id);
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
      desktop={sounds.desktop}
      onAddSound={sounds.onAdd}
      onSelectSound={sounds.onSelect}
      onDeleteSound={sounds.onDelete}
      onPreviewSound={sounds.onPreview}
      onRetrySounds={sounds.onRetry}
      onMinutes={(next) => {
        if (completed) return;
        setMinutes(next);
        const duration = Number(next);
        if (Number.isInteger(duration) && duration >= 1 && duration <= 180)
          setRemainingMilliseconds(duration * 60 * 1000);
      }}
      onToggle={() => {
        if (deadline !== null) {
          const milliseconds = Math.max(0, deadline - Date.now());
          setRemainingMilliseconds(milliseconds);
          setDeadline(null);
          if (milliseconds === 0) playCompletion();
        } else {
          if (completed || !validDuration || !sounds.ready || sounds.busy)
            return;
          const milliseconds = remainingMilliseconds || duration * 60 * 1000;
          setRemainingMilliseconds(milliseconds);
          setDeadline(Date.now() + milliseconds);
        }
      }}
      onReset={() => {
        sounds.stopCompletion();
        setDeadline(null);
        if (!validDuration) setMinutes('25');
        setRemainingMilliseconds((validDuration ? duration : 25) * 60 * 1000);
      }}
    />
  );
};
