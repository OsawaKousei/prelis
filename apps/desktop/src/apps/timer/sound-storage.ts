import { isTauri } from '@tauri-apps/api/core';
import {
  BaseDirectory,
  exists,
  mkdir,
  readFile,
  readTextFile,
  remove,
  writeFile,
  writeTextFile,
} from '@tauri-apps/plugin-fs';

export type TimerSound = {
  readonly id: string;
  readonly name: string;
  readonly mimeType: string;
};

export type SoundLibrary = {
  readonly sounds: readonly TimerSound[];
  readonly selectedId: string | null;
};

export const isDesktop = isTauri();
const options = { baseDir: BaseDirectory.AppData } as const;
const directory = 'timer/sounds';
const indexPath = 'timer/sounds.json';
const maxSoundSize = 10 * 1024 * 1024;
const soundIdPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const emptyLibrary: SoundLibrary = { sounds: [], selectedId: null };

const soundPath = (id: string): string => {
  if (!soundIdPattern.test(id)) throw new Error('音声IDが不正です。');
  return `${directory}/${id}`;
};

const parseLibrary = (text: string): SoundLibrary => {
  const value: unknown = JSON.parse(text);
  if (typeof value !== 'object' || value === null)
    throw new Error('音声一覧が不正です。');
  const data = value as Record<string, unknown>;
  if (data.version !== 1 || !Array.isArray(data.sounds))
    throw new Error('音声一覧が不正です。');
  const sounds: TimerSound[] = data.sounds.map((sound: unknown) => {
    if (typeof sound !== 'object' || sound === null)
      throw new Error('音声一覧が不正です。');
    const item = sound as Record<string, unknown>;
    if (
      typeof item.id !== 'string' ||
      !soundIdPattern.test(item.id) ||
      typeof item.name !== 'string' ||
      !item.name ||
      (item.mimeType !== 'audio/mpeg' && item.mimeType !== 'audio/wav')
    )
      throw new Error('音声一覧が不正です。');
    return { id: item.id, name: item.name, mimeType: item.mimeType };
  });
  if (
    (data.selectedId !== null && typeof data.selectedId !== 'string') ||
    (data.selectedId !== null &&
      !sounds.some((sound) => sound.id === data.selectedId))
  )
    throw new Error('音声一覧が不正です。');
  return { sounds, selectedId: data.selectedId };
};

const writeLibrary = async (library: SoundLibrary): Promise<void> => {
  await mkdir('timer', { ...options, recursive: true });
  await writeTextFile(
    indexPath,
    JSON.stringify({ version: 1, ...library }),
    options,
  );
};

export const loadSoundLibrary = async (): Promise<SoundLibrary> => {
  if (!isDesktop) return emptyLibrary;
  if (!(await exists(indexPath, options))) return emptyLibrary;
  return parseLibrary(await readTextFile(indexPath, options));
};

export const addSound = async (
  library: SoundLibrary,
  file: File,
): Promise<SoundLibrary> => {
  if (!isDesktop) throw new Error('音声の保存はデスクトップ版で利用できます。');
  const extension = file.name.toLowerCase().match(/\.(mp3|wav)$/)?.[1];
  if (!extension)
    throw new Error('MP3 または WAV ファイルを選択してください。');
  if (file.size === 0 || file.size > maxSoundSize)
    throw new Error('音声ファイルは 10 MB 以下にしてください。');
  const id = crypto.randomUUID();
  const sound: TimerSound = {
    id,
    name: file.name,
    mimeType: extension === 'mp3' ? 'audio/mpeg' : 'audio/wav',
  };
  await mkdir(directory, { ...options, recursive: true });
  await writeFile(
    soundPath(id),
    new Uint8Array(await file.arrayBuffer()),
    options,
  );
  const next = { sounds: [...library.sounds, sound], selectedId: id };
  try {
    await writeLibrary(next);
  } catch (error) {
    await remove(soundPath(id), options).catch(() => undefined);
    throw error;
  }
  return next;
};

export const selectSound = async (
  library: SoundLibrary,
  selectedId: string | null,
): Promise<SoundLibrary> => {
  if (!isDesktop) throw new Error('音声の選択はデスクトップ版で利用できます。');
  if (
    selectedId !== null &&
    !library.sounds.some((sound) => sound.id === selectedId)
  )
    throw new Error('音声が見つかりません。');
  const next = { ...library, selectedId };
  await writeLibrary(next);
  return next;
};

export const deleteSound = async (
  library: SoundLibrary,
  id: string,
): Promise<SoundLibrary> => {
  if (!isDesktop) throw new Error('音声の削除はデスクトップ版で利用できます。');
  if (!library.sounds.some((sound) => sound.id === id))
    throw new Error('音声が見つかりません。');
  const next = {
    sounds: library.sounds.filter((sound) => sound.id !== id),
    selectedId: library.selectedId === id ? null : library.selectedId,
  };
  await writeLibrary(next);
  await remove(soundPath(id), options).catch(() => undefined);
  return next;
};

export const readSound = async (id: string): Promise<Uint8Array> => {
  if (!isDesktop)
    throw new Error('音声の読み込みはデスクトップ版で利用できます。');
  return readFile(soundPath(id), options);
};
