export const characterSets = {
  uppercase: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
  lowercase: 'abcdefghijklmnopqrstuvwxyz',
  numbers: '0123456789',
  symbols: '!@#$%^&*_-+=?',
} as const;

export type CharacterType = keyof typeof characterSets;
export type PasswordLength = 4 | 8 | 12 | 16;

// Each byte is rejected above the largest multiple of the pool size.
export async function generatePassword(
  length: PasswordLength,
  selectedTypes: readonly CharacterType[],
  randomBytes: (count: number) => Promise<readonly number[]>,
): Promise<string> {
  if (selectedTypes.length === 0) throw new Error('文字種を1つ以上選択してください。');
  const pool = selectedTypes.map(type => characterSets[type]).join('');
  const limit = Math.floor(256 / pool.length) * pool.length;
  let bytes: readonly number[] = [];
  let offset = 0;
  const index = async () => {
    while (true) {
      if (offset >= bytes.length) {
        bytes = await randomBytes(256);
        offset = 0;
      }
      const value = bytes[offset++];
      if (value !== undefined && value < limit) return value % pool.length;
    }
  };
  while (true) {
    let password = '';
    for (let i = 0; i < length; i++) password += pool[await index()];
    if (selectedTypes.every(type => [...password].some(character => characterSets[type].includes(character))))
      return password;
  }
}
