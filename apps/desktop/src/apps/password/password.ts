export const characterSets = {
  uppercase: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
  lowercase: 'abcdefghijklmnopqrstuvwxyz',
  numbers: '0123456789',
  symbols: '!@#$%^&*_-+=?',
} as const;

export type CharacterType = keyof typeof characterSets;
export type PasswordLength = 4 | 8 | 12 | 16;

const randomIndex = (size: number): number => {
  const range = 0x1_0000_0000;
  const limit = Math.floor(range / size) * size;
  while (true) {
    const value = crypto.getRandomValues(new Uint32Array(1))[0];
    if (value !== undefined && value < limit) return value % size;
  }
};

export const generatePassword = (
  length: PasswordLength,
  selectedTypes: readonly CharacterType[],
): string => {
  if (selectedTypes.length === 0) {
    throw new Error('文字種を1つ以上選択してください。');
  }

  const pool = selectedTypes.map((type) => characterSets[type]).join('');

  // 条件を満たす文字列を一様に選ぶため、全種類が現れるまで引き直す。
  while (true) {
    const password = Array.from(
      { length },
      () => pool[randomIndex(pool.length)],
    ).join('');
    if (
      selectedTypes.every((type) =>
        [...password].some((character) =>
          characterSets[type].includes(character),
        ),
      )
    ) {
      return password;
    }
  }
};
