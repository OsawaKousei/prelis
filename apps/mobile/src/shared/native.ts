import {NativeModules} from 'react-native';

export type Sound = {id: string; name: string; mimeType: string};
export type SoundLibrary = {version: number; sounds: Sound[]; selectedId: string | null};

type PrelisNative = {
  readDiary(date: string): Promise<string>;
  saveDiary(date: string, content: string): Promise<boolean>;
  copyText(value: string): Promise<boolean>;
  randomBytes(count: number): Promise<number[]>;
  loadSounds(): Promise<string>;
  selectSound(id: string | null): Promise<string>;
  deleteSound(id: string): Promise<string>;
  pickSound(): Promise<string | null>;
  playSound(id: string, loop: boolean): Promise<boolean>;
  stopSound(): Promise<boolean>;
};

export const native = NativeModules.PrelisNative as PrelisNative;
export const parseSounds = (value: string): SoundLibrary => {
  const data: SoundLibrary = JSON.parse(value);
  if (data.version !== 1 || !Array.isArray(data.sounds)) throw new Error('音声一覧が不正です。');
  return data;
};
