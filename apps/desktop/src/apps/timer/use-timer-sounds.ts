import { useCallback, useEffect, useRef, useState } from 'react';
import {
  addSound,
  deleteSound,
  isDesktop,
  loadSoundLibrary,
  readSound,
  selectSound,
  type SoundLibrary,
} from './sound-storage';

export const useTimerSounds = () => {
  const [library, setLibrary] = useState<SoundLibrary | null>(null);
  const [loadedId, setLoadedId] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [retryCount, setRetryCount] = useState(0);
  const audioRef = useRef<HTMLAudioElement | null>(null);

  useEffect(() => {
    let cancelled = false;
    loadSoundLibrary()
      .then((saved) => {
        if (!cancelled) {
          setLibrary(saved);
          setError(null);
        }
      })
      .catch(() => {
        if (!cancelled) setError('保存済みの音声を読み込めませんでした。');
      });
    return () => {
      cancelled = true;
    };
  }, [retryCount]);

  const selectedId = library?.selectedId ?? null;
  const selectedSound = library?.sounds.find(
    (sound) => sound.id === selectedId,
  );
  useEffect(() => {
    if (!selectedId || !selectedSound) {
      return;
    }
    let cancelled = false;
    readSound(selectedId)
      .then((bytes) => {
        if (cancelled) return;
        const buffer = new ArrayBuffer(bytes.byteLength);
        new Uint8Array(buffer).set(bytes);
        const url = URL.createObjectURL(
          new Blob([buffer], { type: selectedSound.mimeType }),
        );
        try {
          const audio = new Audio(url);
          audio.preload = 'auto';
          audio.onerror = () => {
            if (!cancelled) {
              setLoadedId(null);
              setError(
                '選択中の音声を再生できません。別のファイルを選択してください。',
              );
            }
          };
          audio.load();
          audioRef.current = audio;
          setLoadedId(selectedId);
        } catch (error) {
          URL.revokeObjectURL(url);
          throw error;
        }
      })
      .catch(() => {
        if (!cancelled) setError('選択中の音声を読み込めませんでした。');
      });
    return () => {
      cancelled = true;
      const audio = audioRef.current;
      if (audio) {
        audio.pause();
        URL.revokeObjectURL(audio.src);
        audioRef.current = null;
      }
    };
  }, [selectedId, selectedSound]);

  const playCompletion = useCallback(() => {
    const audio = audioRef.current;
    if (!audio) return;
    audio.loop = true;
    audio.currentTime = 0;
    void audio.play().catch(() => {
      setError('音声を再生できませんでした。試聴で確認してください。');
    });
  }, []);

  const stopCompletion = useCallback(() => {
    const audio = audioRef.current;
    if (!audio) return;
    audio.pause();
    audio.loop = false;
    audio.currentTime = 0;
  }, []);

  const runChange = async (
    change: (current: SoundLibrary) => Promise<SoundLibrary>,
  ) => {
    if (!library || busy) return;
    setBusy(true);
    setError(null);
    try {
      const next = await change(library);
      setLoadedId(null);
      setLibrary(next);
    } catch (reason) {
      setError(
        reason instanceof Error
          ? reason.message
          : '音声を保存できませんでした。',
      );
    } finally {
      setBusy(false);
    }
  };

  return {
    library,
    busy,
    error,
    desktop: isDesktop,
    ready: library !== null && (selectedId === null || selectedId === loadedId),
    onAdd: (file: File) => runChange((current) => addSound(current, file)),
    onSelect: (id: string | null) =>
      runChange((current) => selectSound(current, id)),
    onDelete: (id: string) => runChange((current) => deleteSound(current, id)),
    onPreview: () => {
      const audio = audioRef.current;
      if (!audio) return;
      audio.loop = false;
      audio.currentTime = 0;
      void audio.play().catch(() => setError('音声を再生できませんでした。'));
    },
    onRetry: () => setRetryCount((count) => count + 1),
    playCompletion,
    stopCompletion,
  };
};
