import Storage from 'expo-sqlite/kv-store';
import * as DocumentPicker from 'expo-document-picker';
import * as Crypto from 'expo-crypto';
import {Directory, File, Paths} from 'expo-file-system';

export type Sound = {id: string; name: string; mimeType: 'audio/mpeg' | 'audio/wav'};
export type SoundLibrary = {sounds: Sound[]; selectedId: string | null};
const storageKey = 'timer:sounds';
const maximumBytes = 10 * 1024 * 1024;
const idPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const directory = () => new Directory(Paths.document, 'timer', 'sounds');

const isSound = (value: unknown): value is Sound => {
  if (typeof value !== 'object' || value === null) return false;
  const sound = value as Record<string, unknown>;
  return typeof sound.id === 'string' && idPattern.test(sound.id) &&
    typeof sound.name === 'string' && sound.name.length > 0 &&
    (sound.mimeType === 'audio/mpeg' || sound.mimeType === 'audio/wav');
};

export function soundFile(sound: Sound): File {
  if (!isSound(sound)) throw new Error('音声情報が不正です。');
  return new File(directory(), `${sound.id}.${sound.mimeType === 'audio/mpeg' ? 'mp3' : 'wav'}`);
}

export function parseSounds(value: string): SoundLibrary {
  const data: unknown = JSON.parse(value);
  if (typeof data !== 'object' || data === null) throw new Error('音声一覧が不正です。');
  const library = data as Record<string, unknown>;
  if (!Array.isArray(library.sounds) || !library.sounds.every(isSound) ||
      new Set(library.sounds.map(sound => sound.id)).size !== library.sounds.length ||
      (library.selectedId !== null && !library.sounds.some(sound => sound.id === library.selectedId))) {
    throw new Error('音声一覧が不正です。');
  }
  return {sounds: library.sounds, selectedId: library.selectedId as string | null};
}

export async function loadSoundLibrary(): Promise<SoundLibrary> {
  const value = await Storage.getItem(storageKey);
  return value === null ? {sounds: [], selectedId: null} : parseSounds(value);
}

async function saveLibrary(library: SoundLibrary): Promise<SoundLibrary> {
  await Storage.setItem(storageKey, JSON.stringify(library));
  return library;
}

export async function selectSound(library: SoundLibrary, id: string | null): Promise<SoundLibrary> {
  if (id !== null && !library.sounds.some(sound => sound.id === id)) throw new Error('音声が見つかりません。');
  return saveLibrary({...library, selectedId: id});
}

export async function addSound(library: SoundLibrary): Promise<SoundLibrary | null> {
  const result = await DocumentPicker.getDocumentAsync({
    type: ['audio/mpeg', 'audio/wav', 'audio/x-wav', 'audio/wave'],
    multiple: false,
    copyToCacheDirectory: true,
  });
  if (result.canceled) return null;
  const asset = result.assets[0];
  if (!asset) throw new Error('音声を開けませんでした。');
  const source = new File(asset.uri);
  let imported: File | undefined;
  try {
    const extension = asset.name.split('.').pop()?.toLowerCase();
    if (extension !== 'mp3' && extension !== 'wav') throw new Error('MP3 または WAV ファイルを選択してください。');
    if (!source.exists) throw new Error('音声を開けませんでした。');
    // Validate the actual cached file; provider metadata is optional and may be inaccurate.
    if (source.size === 0) throw new Error('空の音声ファイルです。');
    if (source.size > maximumBytes) throw new Error('音声ファイルは 10 MB 以下にしてください。');
    const sound: Sound = {
      id: Crypto.randomUUID(), name: asset.name,
      mimeType: extension === 'mp3' ? 'audio/mpeg' : 'audio/wav',
    };
    directory().create({intermediates: true, idempotent: true});
    const target = soundFile(sound);
    imported = target;
    await source.copy(target);
    if (!target.exists || target.size !== source.size) throw new Error('音声を保存できませんでした。');
    const next = await saveLibrary({...library, sounds: [...library.sounds, sound], selectedId: sound.id});
    imported = undefined;
    return next;
  } finally {
    // A failed index save must not leave an imported file behind.
    try { if (imported?.exists) imported.delete(); } catch { /* Best-effort cleanup. */ }
    try { if (source.exists) source.delete(); } catch { /* The OS may already have cleared its cache. */ }
  }
}

export async function deleteSound(library: SoundLibrary, id: string): Promise<SoundLibrary> {
  const sound = library.sounds.find(item => item.id === id);
  if (!sound) throw new Error('音声が見つかりません。');
  const next = await saveLibrary({
    sounds: library.sounds.filter(item => item.id !== id),
    selectedId: library.selectedId === id ? null : library.selectedId,
  });
  // Commit the index first so a failed save cannot delete a registered sound.
  try { const file = soundFile(sound); if (file.exists) file.delete(); } catch { /* Unreferenced files may be cleaned later. */ }
  return next;
}
