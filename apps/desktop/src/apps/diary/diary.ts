export const localDate = (date = new Date()): string =>
  `${String(date.getFullYear()).padStart(4, '0')}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
export const isDiaryDate = (date: string): boolean => {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || date < '0001-01-01') return false;
  const parsed = new Date(`${date}T12:00:00`);
  return !Number.isNaN(parsed.getTime()) && localDate(parsed) === date;
};
export const shiftDate = (date: string, days: number): string => {
  const next = new Date(`${date}T12:00:00`);
  next.setDate(next.getDate() + days);
  return localDate(next);
};
export const diaryFilename = (date: string): string => {
  if (!isDiaryDate(date)) throw new Error('日付が正しくありません。');
  return `diary/${date}.txt`;
};
export const dateHeading = (date: string) =>
  new Intl.DateTimeFormat('ja-JP', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  }).format(new Date(`${date}T12:00:00`));
export const weekday = (date: string) =>
  new Intl.DateTimeFormat('ja-JP', { weekday: 'long' }).format(
    new Date(`${date}T12:00:00`),
  );
