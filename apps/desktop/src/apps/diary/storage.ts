import { isTauri } from '@tauri-apps/api/core';
import {
  BaseDirectory,
  exists,
  mkdir,
  readTextFile,
  writeTextFile,
} from '@tauri-apps/plugin-fs';
import { diaryFilename } from './diary';
export const isDesktop = isTauri();
const options = { baseDir: BaseDirectory.AppData } as const;
export const readDiary = async (date: string): Promise<string> => {
  const path = diaryFilename(date);
  if (!isDesktop) return localStorage.getItem(`prelis:preview:${path}`) ?? '';
  if (!(await exists(path, options))) return '';
  return readTextFile(path, options);
};
export const saveDiary = async (
  date: string,
  content: string,
): Promise<void> => {
  const path = diaryFilename(date);
  if (!isDesktop) {
    localStorage.setItem(`prelis:preview:${path}`, content);
    return;
  }
  await mkdir('diary', { ...options, recursive: true });
  await writeTextFile(path, content, options);
};
