import React, {createContext, useCallback, useContext, useEffect, useRef, useState} from 'react';
import {AppState} from 'react-native';
import {setAudioModeAsync, setIsAudioActiveAsync, useAudioPlayer, useAudioPlayerStatus} from 'expo-audio';
import {addSound, deleteSound, loadSoundLibrary, selectSound, soundFile, type SoundLibrary} from './sound-storage';

function useTimerState() {
  const [minutes, setMinutes] = useState('25');
  const duration = Number(minutes);
  const valid = /^\d+$/.test(minutes) && Number.isInteger(duration) && duration >= 1 && duration <= 180;
  const [remaining, setRemaining] = useState(25 * 60 * 1000);
  const [deadline, setDeadline] = useState<number | null>(null);
  const [library, setLibrary] = useState<SoundLibrary | null>(null);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const busyRef = useRef(false);
  const audioQueue = useRef(Promise.resolve());
  const audioRequest = useRef(0);
  const [retry, setRetry] = useState(0);
  const completed = remaining === 0;
  const player = useAudioPlayer(null, {keepAudioSessionActive: false});
  const status = useAudioPlayerStatus(player);

  useEffect(() => {
    let active = true;
    loadSoundLibrary().then(value => {if (active) {setLibrary(value); setError('');}})
      .catch(() => {if (active) setError('保存済みの音声を読み込めませんでした。');});
    return () => {active = false;};
  }, [retry]);

  const enqueueAudio = useCallback((operation: () => Promise<void>) => {
    const next = audioQueue.current.then(operation, operation);
    audioQueue.current = next.catch(() => {});
    return next;
  }, []);

  const stopSound = useCallback(() => {
    audioRequest.current += 1;
    return enqueueAudio(async () => {
      player.pause();
      player.replace(null);
      await setIsAudioActiveAsync(false);
    });
  }, [enqueueAudio, player]);

  const playSound = useCallback(async (id: string, loop: boolean) => {
    const sound = library?.sounds.find(item => item.id === id);
    if (!sound) throw new Error('音声が見つかりません。');
    const file = soundFile(sound);
    if (!file.exists) throw new Error('音声が見つかりません。');
    const request = ++audioRequest.current;
    await enqueueAudio(async () => {
      if (request !== audioRequest.current) return;
      player.pause();
      await setAudioModeAsync({playsInSilentMode: true, shouldPlayInBackground: false, interruptionMode: 'mixWithOthers'});
      if (request !== audioRequest.current) return;
      await setIsAudioActiveAsync(true);
      if (request !== audioRequest.current) return;
      player.replace({uri: file.uri});
      // Expo's AudioPlayer is a mutable native object; loop is its documented setter.
      player.loop = loop;
      player.play();
    });
  }, [enqueueAudio, library, player]);

  const playCompletion = useCallback(() => {
    if (library?.selectedId) playSound(library.selectedId, true)
      .catch(() => setError('終了音を再生できませんでした。'));
  }, [library, playSound]);

  useEffect(() => {
    if (deadline === null) return;
    let finished = false;
    const tick = () => {
      if (finished) return;
      const next = Math.max(0, deadline - Date.now());
      setRemaining(next);
      if (next === 0) {finished = true; setDeadline(null); playCompletion();}
    };
    const id = setInterval(tick, 100);
    const listener = AppState.addEventListener('change', state => {if (state === 'active') tick();});
    return () => {clearInterval(id); listener.remove();};
  }, [deadline, playCompletion]);

  const changeSounds = async (action: (current: SoundLibrary) => Promise<SoundLibrary | null>) => {
    if (busyRef.current || !library || deadline !== null || completed) return;
    busyRef.current = true;
    setBusy(true); setError('');
    try {
      await stopSound();
      const value = await action(library);
      if (value) setLibrary(value);
    } catch (reason) {setError(reason instanceof Error ? reason.message : '音声を変更できませんでした。');}
    finally {busyRef.current = false; setBusy(false);}
  };

  return {
    minutes, valid, remaining, running: deadline !== null, library,
    error: error || (status.error ? '音声を再生できませんでした。' : ''), busy,
    onMinutes: (value: string) => {
      setMinutes(value);
      const next = Number(value);
      if (/^\d+$/.test(value) && Number.isInteger(next) && next >= 1 && next <= 180) setRemaining(next * 60 * 1000);
    },
    onToggle: () => {
      if (deadline !== null) {
        const next = Math.max(0, deadline - Date.now());
        setRemaining(next); setDeadline(null);
        if (next === 0) playCompletion();
      } else {
        stopSound().catch(() => setError('音声を停止できませんでした。'));
        setDeadline(Date.now() + remaining);
      }
    },
    onReset: () => {
      stopSound().catch(() => setError('終了音を停止できませんでした。'));
      setDeadline(null);
      if (!valid) setMinutes('25');
      setRemaining((valid ? duration : 25) * 60 * 1000);
    },
    onRetry: () => setRetry(value => value + 1),
    onSelectSound: (id: string | null) => changeSounds(current => selectSound(current, id)),
    onAddSound: () => changeSounds(addSound),
    onPreviewSound: (id: string) => {
      setError('');
      playSound(id, false).catch(() => setError('音声を再生できませんでした。'));
    },
    onDeleteSound: (id: string) => changeSounds(current => deleteSound(current, id)),
  };
}

const TimerContext = createContext<ReturnType<typeof useTimerState> | null>(null);

export function TimerProvider({children}: {children: React.ReactNode}) {
  const timer = useTimerState();
  return <TimerContext.Provider value={timer}>{children}</TimerContext.Provider>;
}

export function useTimer() {
  const timer = useContext(TimerContext);
  if (!timer) throw new Error('TimerProvider is missing.');
  return timer;
}
