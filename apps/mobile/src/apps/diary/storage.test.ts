import Storage from 'expo-sqlite/kv-store';
import {readDiary, saveDiary} from './storage';

jest.mock('expo-sqlite/kv-store', () => ({
  __esModule: true, default: {getItem: jest.fn(), setItem: jest.fn()},
}));

beforeEach(() => jest.resetAllMocks());

test('loads an empty day and writes UTF-8 text to its own date key', async () => {
  jest.mocked(Storage.getItem).mockResolvedValue(null);
  expect(await readDiary('2026-11-01')).toBe('');
  await saveDiary('2026-11-01', '日記\n🙂');
  expect(Storage.setItem).toHaveBeenCalledWith('diary:2026-11-01', '日記\n🙂');
});

test('rejects invalid dates before accessing storage', async () => {
  await expect(readDiary('../../outside')).rejects.toThrow();
  await expect(saveDiary('2026-02-30', 'invalid')).rejects.toThrow();
  expect(Storage.getItem).not.toHaveBeenCalled();
  expect(Storage.setItem).not.toHaveBeenCalled();
});

test('reports save errors so the editor can retain unsaved text', async () => {
  jest.mocked(Storage.setItem).mockRejectedValue(new Error('disk full'));
  await expect(saveDiary('2026-11-01', '未保存')).rejects.toThrow('disk full');
});
