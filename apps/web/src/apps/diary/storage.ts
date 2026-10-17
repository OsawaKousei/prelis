import { diaryFilename } from './diary';
import { openDatabase, requestValue, transactionDone } from '../../storage/database';

export const readDiary = async (date: string): Promise<string> => {
  diaryFilename(date);
  const database = await openDatabase();
  const transaction = database.transaction('diaries', 'readonly');
  const content = await requestValue(transaction.objectStore('diaries').get(date));
  if (content === undefined) return '';
  if (typeof content !== 'string') throw new Error('日記データが不正です。');
  return content;
};

export const saveDiary = async (date: string, content: string): Promise<void> => {
  diaryFilename(date);
  const database = await openDatabase();
  const transaction = database.transaction('diaries', 'readwrite');
  const done = transactionDone(transaction);
  transaction.objectStore('diaries').put(content, date);
  await done;
};
