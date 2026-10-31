import React, {useCallback, useEffect, useState} from 'react';
import {native, parseSounds, type SoundLibrary} from '../../shared/native';
import {TimerView} from './timer-view';

export function TimerApp() {
  const [minutes, setMinutes] = useState('25');
  const duration = Number(minutes);
  const valid = /^\d+$/.test(minutes) && Number.isInteger(duration) && duration >= 1 && duration <= 180;
  const [remaining, setRemaining] = useState(25 * 60 * 1000);
  const [deadline, setDeadline] = useState<number | null>(null);
  const [library, setLibrary] = useState<SoundLibrary | null>(null);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [retry, setRetry] = useState(0);
  const completed = remaining === 0;
  useEffect(() => {
    let active = true;
    native.loadSounds().then(value => {if (active) {setLibrary(parseSounds(value)); setError('');}})
      .catch(() => {if (active) setError('保存済みの音声を読み込めませんでした。');});
    return () => {active = false;};
  }, [retry]);
  const playCompletion = useCallback(() => {
    if (library?.selectedId) native.playSound(library.selectedId, true).catch(() => setError('終了音を再生できませんでした。'));
  }, [library]);
  useEffect(() => {
    if (deadline === null) return;
    const id = setInterval(() => {
      const next = Math.max(0, deadline - Date.now());
      setRemaining(next);
      if (next === 0) {
        clearInterval(id);
        setDeadline(null);
        playCompletion();
      }
    }, 100);
    return () => clearInterval(id);
  }, [deadline, playCompletion]);
  const changeSounds = async (action: () => Promise<string | null>) => {
    if (busy || !library || deadline !== null || completed) return;
    setBusy(true); setError('');
    try {const value = await action(); if (value) setLibrary(parseSounds(value));}
    catch (reason) {setError(reason instanceof Error ? reason.message : '音声を変更できませんでした。');}
    finally {setBusy(false);}
  };
  return <TimerView
    minutes={minutes} valid={valid} remaining={remaining} running={deadline !== null}
    library={library} error={error} busy={busy}
    onMinutes={value => {
      setMinutes(value);
      const next = Number(value);
      if (/^\d+$/.test(value) && Number.isInteger(next) && next >= 1 && next <= 180) setRemaining(next * 60 * 1000);
    }}
    onToggle={() => {
      if (deadline !== null) {
        const next = Math.max(0, deadline - Date.now());
        setRemaining(next); setDeadline(null);
        if (next === 0) playCompletion();
      } else setDeadline(Date.now() + remaining);
    }}
    onReset={() => {
      native.stopSound().catch(() => setError('終了音を停止できませんでした。'));
      setDeadline(null);
      if (!valid) setMinutes('25');
      setRemaining((valid ? duration : 25) * 60 * 1000);
    }}
    onRetry={() => setRetry(value => value + 1)}
    onSelectSound={id => changeSounds(() => native.selectSound(id))}
    onAddSound={() => changeSounds(native.pickSound)}
    onPreviewSound={id => {
      native.playSound(id, false).catch(() => setError('音声を再生できませんでした。'));
    }}
    onDeleteSound={id => changeSounds(() => native.deleteSound(id))}
  />;
}
