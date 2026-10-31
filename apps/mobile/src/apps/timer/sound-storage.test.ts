import Storage from 'expo-sqlite/kv-store';
import * as DocumentPicker from 'expo-document-picker';
import {addSound, deleteSound, loadSoundLibrary, parseSounds, selectSound, soundFile, type Sound, type SoundLibrary} from './sound-storage';

jest.mock('expo-sqlite/kv-store', () => ({
  __esModule: true, default: {getItem: jest.fn(), setItem: jest.fn()},
}));
jest.mock('expo-document-picker', () => ({getDocumentAsync: jest.fn()}));
jest.mock('expo-crypto', () => ({randomUUID: () => '12345678-1234-4234-8234-123456789abc'}));
jest.mock('expo-file-system', () => {
  const files = new Map<string, number>();
  class Directory {
    uri: string;
    constructor(...parts: (string | {uri: string})[]) {this.uri = parts.map(p => typeof p === 'string' ? p : p.uri).join('/');}
    create() {}
  }
  class File extends Directory {
    get exists() {return files.has(this.uri);}
    get size() {return files.get(this.uri) ?? 0;}
    async copy(target: File) {files.set(target.uri, this.size);}
    delete() {files.delete(this.uri);}
  }
  return {File, Directory, Paths: {document: 'file:///document'}, __files: files};
});

const files: Map<string, number> = jest.requireMock('expo-file-system').__files;
const sound: Sound = {id: '12345678-1234-4234-8234-123456789abc', name: 'sound.wav', mimeType: 'audio/wav'};
const empty: SoundLibrary = {sounds: [], selectedId: null};
const populated: SoundLibrary = {sounds: [sound], selectedId: sound.id};
const source = 'file:///cache/picked.wav';

function picked(size: number, name = 'sound.wav') {
  files.set(source, size);
  jest.mocked(DocumentPicker.getDocumentAsync).mockResolvedValue({
    canceled: false, assets: [{uri: source, name, size: 1, lastModified: 0}],
  });
}

beforeEach(() => {
  jest.resetAllMocks(); files.clear();
  jest.mocked(Storage.getItem).mockResolvedValue(null);
  jest.mocked(Storage.setItem).mockResolvedValue(undefined);
});

test('starts with an empty library and rejects damaged saved data', async () => {
  expect(await loadSoundLibrary()).toEqual(empty);
  jest.mocked(Storage.getItem).mockResolvedValue('{broken');
  await expect(loadSoundLibrary()).rejects.toThrow();
  expect(Storage.setItem).not.toHaveBeenCalled();
});

test.each([
  {sounds: [sound, sound], selectedId: sound.id},
  {sounds: [sound], selectedId: 'missing'},
  {sounds: [{...sound, id: '../outside'}], selectedId: null},
  {sounds: [{...sound, mimeType: 'text/plain'}], selectedId: null},
])('rejects an invalid library without touching storage', value => {
  expect(() => parseSounds(JSON.stringify(value))).toThrow();
});

test('canceling a picker preserves the library', async () => {
  jest.mocked(DocumentPicker.getDocumentAsync).mockResolvedValue({canceled: true, assets: null});
  expect(await addSound(populated)).toBeNull();
  expect(Storage.setItem).not.toHaveBeenCalled();
});

test('imports a valid file, persists selection and removes its cached copy', async () => {
  picked(1024, 'sound.WAV');
  const next = await addSound(empty);
  expect(next?.selectedId).toBe(sound.id);
  expect(next?.sounds[0].mimeType).toBe('audio/wav');
  expect(files.get(soundFile(sound).uri)).toBe(1024);
  expect(files.has(source)).toBe(false);
  expect(Storage.setItem).toHaveBeenCalledWith('timer:sounds', JSON.stringify(next));
});

test.each([0, 10 * 1024 * 1024 + 1])('rejects actual size %i even when provider metadata says 1 byte', async size => {
  picked(size);
  await expect(addSound(empty)).rejects.toThrow();
  expect(Storage.setItem).not.toHaveBeenCalled();
  expect(files.size).toBe(0);
});

test('accepts the 10 MiB boundary', async () => {
  picked(10 * 1024 * 1024);
  expect((await addSound(empty))?.sounds).toHaveLength(1);
});

test('rejects unsupported extensions and cleans their cache', async () => {
  picked(100, 'sound.txt');
  await expect(addSound(empty)).rejects.toThrow('MP3 または WAV');
  expect(files.size).toBe(0);
});

test('rolls back the file when persisting an import fails', async () => {
  picked(100);
  jest.mocked(Storage.setItem).mockRejectedValue(new Error('disk full'));
  await expect(addSound(empty)).rejects.toThrow('disk full');
  expect(files.size).toBe(0);
});

test('keeps the existing sound when saving its deletion fails', async () => {
  files.set(soundFile(sound).uri, 100);
  jest.mocked(Storage.setItem).mockRejectedValue(new Error('disk full'));
  await expect(deleteSound(populated, sound.id)).rejects.toThrow('disk full');
  expect(files.has(soundFile(sound).uri)).toBe(true);
});

test('deleting the selected sound persists an empty selection and removes the file', async () => {
  files.set(soundFile(sound).uri, 100);
  expect(await deleteSound(populated, sound.id)).toEqual(empty);
  expect(files.size).toBe(0);
});

test('rejects unknown selection and deletion without saving', async () => {
  await expect(selectSound(populated, 'missing')).rejects.toThrow();
  await expect(deleteSound(populated, 'missing')).rejects.toThrow();
  expect(Storage.setItem).not.toHaveBeenCalled();
});
