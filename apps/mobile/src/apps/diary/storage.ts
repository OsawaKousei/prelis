import {isDiaryDate} from '@prelis/core';
import NativeDiary from './native/NativeDiary';

const validateDate = (date: string) => {
  if (!isDiaryDate(date)) throw new Error('日付が正しくありません。');
};

export const readDiary = async (date: string): Promise<string> => {
  validateDate(date);
  return NativeDiary.readDiary(date);
};

export const saveDiary = async (date: string, content: string): Promise<void> => {
  validateDate(date);
  await NativeDiary.saveDiary(date, content);
};
