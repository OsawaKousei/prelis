import NativeTimerSound, {type Sound} from './native/NativeTimerSound';

export type {Sound} from './native/NativeTimerSound';
export type SoundLibrary = {version: 1; sounds: Sound[]; selectedId: string | null};
const idPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const isSound = (value: unknown): value is Sound => {
  if (typeof value !== 'object' || value === null) return false;
  const sound = value as Record<string, unknown>;
  return typeof sound.id === 'string' && idPattern.test(sound.id) &&
    typeof sound.name === 'string' && sound.name.length > 0 &&
    (sound.mimeType === 'audio/mpeg' || sound.mimeType === 'audio/wav');
};

export const parseSounds = (value: string): SoundLibrary => {
  const data: unknown = JSON.parse(value);
  if (typeof data !== 'object' || data === null) throw new Error('音声一覧が不正です。');
  const library = data as Record<string, unknown>;
  if (library.version !== 1 || !Array.isArray(library.sounds) || !library.sounds.every(isSound) ||
      new Set(library.sounds.map(sound => sound.id)).size !== library.sounds.length ||
      (library.selectedId !== null && !library.sounds.some(sound => sound.id === library.selectedId))) {
    throw new Error('音声一覧が不正です。');
  }
  return {version: 1, sounds: library.sounds, selectedId: library.selectedId as string | null};
};

export const loadSoundLibrary = async (): Promise<SoundLibrary> => {
  const value = await NativeTimerSound.readLibrary();
  return value === null ? {version: 1, sounds: [], selectedId: null} : parseSounds(value);
};

const saveLibrary = async (library: SoundLibrary): Promise<SoundLibrary> => {
  await NativeTimerSound.writeLibrary(JSON.stringify(library));
  return library;
};

export const selectSound = async (library: SoundLibrary, id: string | null): Promise<SoundLibrary> => {
  if (id !== null && !library.sounds.some(sound => sound.id === id)) throw new Error('音声が見つかりません。');
  await NativeTimerSound.stopSound();
  return saveLibrary({...library, selectedId: id});
};

export const addSound = async (library: SoundLibrary): Promise<SoundLibrary | null> => {
  const sound = await NativeTimerSound.pickSound();
  if (sound === null) return null;
  try {
    if (!isSound(sound) || library.sounds.some(item => item.id === sound.id)) throw new Error('音声情報が不正です。');
    await NativeTimerSound.stopSound();
    return await saveLibrary({...library, sounds: [...library.sounds, sound], selectedId: sound.id});
  } catch (error) {
    if (typeof sound.id === 'string' && idPattern.test(sound.id) && !library.sounds.some(item => item.id === sound.id)) {
      await NativeTimerSound.deleteSoundFile(sound.id).catch(() => undefined);
    }
    throw error;
  }
};

export const deleteSound = async (library: SoundLibrary, id: string): Promise<SoundLibrary> => {
  if (!library.sounds.some(sound => sound.id === id)) throw new Error('音声が見つかりません。');
  if (library.selectedId === id) await NativeTimerSound.stopSound();
  const next = await saveLibrary({
    ...library,
    sounds: library.sounds.filter(sound => sound.id !== id),
    selectedId: library.selectedId === id ? null : library.selectedId,
  });
  // Once the index is committed, a leftover file must not restore its deleted entry.
  await NativeTimerSound.deleteSoundFile(id).catch(() => undefined);
  return next;
};
