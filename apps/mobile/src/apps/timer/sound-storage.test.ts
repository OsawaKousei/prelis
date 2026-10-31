import NativeTimerSound from './native/NativeTimerSound';
import {addSound, deleteSound, loadSoundLibrary, parseSounds, selectSound, type SoundLibrary} from './sound-storage';

jest.mock('./native/NativeTimerSound', () => ({
  __esModule: true,
  default: {
    readLibrary: jest.fn(), writeLibrary: jest.fn(), pickSound: jest.fn(),
    deleteSoundFile: jest.fn(), stopSound: jest.fn(),
  },
}));

const native = jest.mocked(NativeTimerSound);
const sound = {id: '12345678-1234-4234-8234-123456789abc', name: 'alarm.wav', mimeType: 'audio/wav'};
const other = {...sound, id: '12345678-1234-4234-8234-123456789abd', name: 'other.wav'};
const empty = (): SoundLibrary => ({version: 1, sounds: [], selectedId: null});
const selected = (): SoundLibrary => ({version: 1, sounds: [sound], selectedId: sound.id});

beforeEach(() => {
  jest.resetAllMocks();
  native.writeLibrary.mockResolvedValue(true);
  native.deleteSoundFile.mockResolvedValue(true);
  native.stopSound.mockResolvedValue(true);
});

test('loads the existing version 1 format and initializes only a missing index', async () => {
  native.readLibrary.mockResolvedValueOnce(JSON.stringify(selected())).mockResolvedValueOnce(null);
  expect(await loadSoundLibrary()).toEqual(selected());
  expect(await loadSoundLibrary()).toEqual(empty());
  expect(native.writeLibrary).not.toHaveBeenCalled();
});

test.each([
  'null', '{}', '{"version":2,"sounds":[],"selectedId":null}',
  JSON.stringify({...selected(), selectedId: other.id}),
  JSON.stringify({...selected(), sounds: [sound, sound]}),
  JSON.stringify({...selected(), sounds: [{...sound, id: '../outside'}]}),
  JSON.stringify({...selected(), sounds: [{...sound, mimeType: 'text/plain'}]}),
])('rejects an invalid index without overwriting it: %s', async value => {
  expect(() => parseSounds(value)).toThrow();
  native.readLibrary.mockResolvedValue(value);
  await expect(loadSoundLibrary()).rejects.toThrow();
  expect(native.writeLibrary).not.toHaveBeenCalled();
});

test('selecting no sound stops playback and persists the selection', async () => {
  const current = selected();
  expect(await selectSound(current, null)).toEqual({...current, selectedId: null});
  expect(current.selectedId).toBe(sound.id);
  expect(native.stopSound.mock.invocationCallOrder[0]).toBeLessThan(native.writeLibrary.mock.invocationCallOrder[0]);
  expect(JSON.parse(native.writeLibrary.mock.calls[0][0])).toEqual({...current, selectedId: null});
});

test('cancelling the picker leaves the index and playback unchanged', async () => {
  native.pickSound.mockResolvedValue(null);
  expect(await addSound(selected())).toBeNull();
  expect(native.writeLibrary).not.toHaveBeenCalled();
  expect(native.stopSound).not.toHaveBeenCalled();
  expect(native.deleteSoundFile).not.toHaveBeenCalled();
});

test('an imported sound becomes selected only after its index is saved', async () => {
  native.pickSound.mockResolvedValue(other);
  const current = selected();
  const next = await addSound(current);
  expect(next).toEqual({version: 1, sounds: [sound, other], selectedId: other.id});
  expect(current).toEqual(selected());
  expect(JSON.parse(native.writeLibrary.mock.calls[0][0])).toEqual(next);
  expect(native.deleteSoundFile).not.toHaveBeenCalled();
});

test('a failed index write removes the newly imported file and retains the previous library', async () => {
  native.pickSound.mockResolvedValue(other);
  native.writeLibrary.mockRejectedValue(new Error('disk full'));
  const current = selected();
  await expect(addSound(current)).rejects.toThrow('disk full');
  expect(current).toEqual(selected());
  expect(native.deleteSoundFile).toHaveBeenCalledWith(other.id);
});

test('duplicate imported metadata never deletes an existing sound', async () => {
  native.pickSound.mockResolvedValue(sound);
  await expect(addSound(selected())).rejects.toThrow('音声情報が不正です。');
  expect(native.writeLibrary).not.toHaveBeenCalled();
  expect(native.deleteSoundFile).not.toHaveBeenCalled();
});

test('a failed removal write preserves the sound file and previous selection', async () => {
  native.writeLibrary.mockRejectedValue(new Error('disk full'));
  const current = selected();
  await expect(deleteSound(current, sound.id)).rejects.toThrow('disk full');
  expect(current).toEqual(selected());
  expect(native.deleteSoundFile).not.toHaveBeenCalled();
});

test('removing the selected sound stops playback and commits the index before deleting its file', async () => {
  expect(await deleteSound(selected(), sound.id)).toEqual(empty());
  expect(native.stopSound.mock.invocationCallOrder[0]).toBeLessThan(native.writeLibrary.mock.invocationCallOrder[0]);
  expect(native.writeLibrary.mock.invocationCallOrder[0]).toBeLessThan(native.deleteSoundFile.mock.invocationCallOrder[0]);
});

test('removing another sound keeps the selected sound playing', async () => {
  expect(await deleteSound({version: 1, sounds: [sound, other], selectedId: sound.id}, other.id)).toEqual(selected());
  expect(native.stopSound).not.toHaveBeenCalled();
});

test('an unknown sound cannot change the index or remove any file', async () => {
  await expect(selectSound(empty(), sound.id)).rejects.toThrow('音声が見つかりません。');
  await expect(deleteSound(empty(), sound.id)).rejects.toThrow('音声が見つかりません。');
  expect(native.writeLibrary).not.toHaveBeenCalled();
  expect(native.deleteSoundFile).not.toHaveBeenCalled();
});
