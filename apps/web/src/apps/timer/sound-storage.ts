import { openDatabase, requestValue, transactionDone } from '../../storage/database';

export type TimerSound = {
  readonly id: string;
  readonly name: string;
  readonly mimeType: string;
};

export type SoundLibrary = {
  readonly sounds: readonly TimerSound[];
  readonly selectedId: string | null;
};

type SoundRecord = TimerSound & { readonly blob: Blob };

const maxSoundSize = 10 * 1024 * 1024;
const soundIdPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const soundRecord = (value: unknown): SoundRecord => {
  if (typeof value !== 'object' || value === null) throw new Error('音声データが不正です。');
  const record = value as Record<string, unknown>;
  if (
    typeof record.id !== 'string' || !soundIdPattern.test(record.id) ||
    typeof record.name !== 'string' || !record.name ||
    (record.mimeType !== 'audio/mpeg' && record.mimeType !== 'audio/wav') ||
    !(record.blob instanceof Blob)
  ) throw new Error('音声データが不正です。');
  return record as SoundRecord;
};

export const loadSoundLibrary = async (): Promise<SoundLibrary> => {
  const database = await openDatabase();
  const transaction = database.transaction(['sounds', 'settings'], 'readonly');
  const [records, selectedValue] = await Promise.all([
    requestValue(transaction.objectStore('sounds').getAll()),
    requestValue(transaction.objectStore('settings').get('selectedSoundId')),
  ]);
  const sounds = records.map((record) => {
    const { id, name, mimeType } = soundRecord(record);
    return { id, name, mimeType };
  });
  if (selectedValue !== undefined && selectedValue !== null && typeof selectedValue !== 'string')
    throw new Error('終了音の設定が不正です。');
  const selectedId = selectedValue ?? null;
  if (selectedId !== null && !sounds.some((sound) => sound.id === selectedId))
    throw new Error('選択中の音声が見つかりません。');
  return { sounds, selectedId };
};

export const addSound = async (library: SoundLibrary, file: File): Promise<SoundLibrary> => {
  const extension = file.name.toLowerCase().match(/\.(mp3|wav)$/)?.[1];
  if (!extension) throw new Error('MP3 または WAV ファイルを選択してください。');
  if (file.size === 0 || file.size > maxSoundSize)
    throw new Error('音声ファイルは 10 MB 以下にしてください。');
  const sound: TimerSound = {
    id: crypto.randomUUID(),
    name: file.name,
    mimeType: extension === 'mp3' ? 'audio/mpeg' : 'audio/wav',
  };
  const database = await openDatabase();
  const transaction = database.transaction(['sounds', 'settings'], 'readwrite');
  const done = transactionDone(transaction);
  transaction.objectStore('sounds').put({ ...sound, blob: file });
  transaction.objectStore('settings').put(sound.id, 'selectedSoundId');
  await done;
  return { sounds: [...library.sounds, sound], selectedId: sound.id };
};

export const selectSound = async (library: SoundLibrary, selectedId: string | null): Promise<SoundLibrary> => {
  if (selectedId !== null && !library.sounds.some((sound) => sound.id === selectedId))
    throw new Error('音声が見つかりません。');
  const database = await openDatabase();
  const transaction = database.transaction('settings', 'readwrite');
  const done = transactionDone(transaction);
  transaction.objectStore('settings').put(selectedId, 'selectedSoundId');
  await done;
  return { ...library, selectedId };
};

export const deleteSound = async (library: SoundLibrary, id: string): Promise<SoundLibrary> => {
  if (!library.sounds.some((sound) => sound.id === id)) throw new Error('音声が見つかりません。');
  const selectedId = library.selectedId === id ? null : library.selectedId;
  const database = await openDatabase();
  const transaction = database.transaction(['sounds', 'settings'], 'readwrite');
  const done = transactionDone(transaction);
  transaction.objectStore('sounds').delete(id);
  transaction.objectStore('settings').put(selectedId, 'selectedSoundId');
  await done;
  return { sounds: library.sounds.filter((sound) => sound.id !== id), selectedId };
};

export const readSound = async (id: string): Promise<Uint8Array> => {
  if (!soundIdPattern.test(id)) throw new Error('音声IDが不正です。');
  const database = await openDatabase();
  const transaction = database.transaction('sounds', 'readonly');
  const record = await requestValue(transaction.objectStore('sounds').get(id));
  if (record === undefined) throw new Error('音声が見つかりません。');
  return new Uint8Array(await soundRecord(record).blob.arrayBuffer());
};
