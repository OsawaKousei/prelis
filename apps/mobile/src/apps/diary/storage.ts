import Storage from 'expo-sqlite/kv-store';
import {isDiaryDate} from '@prelis/core';

const key = (date: string) => {
  if (!isDiaryDate(date)) throw new Error('日付が正しくありません。');
  return `diary:${date}`;
};

export async function readDiary(date: string): Promise<string> {
  return await Storage.getItem(key(date)) ?? '';
}

export async function saveDiary(date: string, content: string): Promise<void> {
  await Storage.setItem(key(date), content);
}
