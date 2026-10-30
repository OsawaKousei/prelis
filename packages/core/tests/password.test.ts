import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import test from 'node:test';
import {generatePassword} from '../src/password.ts';
import type {CharacterType, PasswordLength} from '../src/password.ts';

const types: readonly CharacterType[] = ['uppercase', 'lowercase', 'numbers', 'symbols'];
const lengths: readonly PasswordLength[] = [4, 8, 12, 16];
const originalSets = {
  uppercase: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
  lowercase: 'abcdefghijklmnopqrstuvwxyz',
  numbers: '0123456789',
  symbols: '!@#$%^&*_-+=?',
};
const filteredSets = {
  uppercase: 'ABCDEFGHJKLMNPQRSTUVWXYZ',
  lowercase: 'abcdefghijkmnopqrstuvwxyz',
  numbers: '23456789',
  symbols: '!@#$%^&*_-+=?',
};
const secureBytes = async (count: number) => [...randomBytes(count)];

test('all character selections and lengths satisfy the generation conditions with either option', async () => {
  for (const excludeAmbiguous of [false, true]) {
    const sets = excludeAmbiguous ? filteredSets : originalSets;
    for (let selection = 1; selection < 16; selection++) {
      const selected = types.filter((_, index) => selection & (1 << index));
      const allowed = selected.map(type => sets[type]).join('');
      for (const length of lengths) {
        for (let attempt = 0; attempt < 10; attempt++) {
          const password = await generatePassword(length, selected, secureBytes, {excludeAmbiguous});
          assert.equal(password.length, length);
          assert.ok([...password].every(character => allowed.includes(character)));
          for (const type of selected) {
            assert.ok([...password].some(character => sets[type].includes(character)));
          }
          if (excludeAmbiguous) assert.doesNotMatch(password, /[IOl01]/);
        }
      }
    }
  }
});

test('default, disabled and enabled options use the exact specified character sets', async () => {
  for (const options of [undefined, {excludeAmbiguous: false}, {excludeAmbiguous: true}]) {
    const sets = options?.excludeAmbiguous ? filteredSets : originalSets;
    for (const type of types) {
      for (const [index, character] of [...sets[type]].entries()) {
        const password = await generatePassword(
          4,
          [type],
          async count => Array<number>(count).fill(index),
          options,
        );
        assert.equal(password, character.repeat(4));
      }
    }
  }
});

test('rejects a selection with no character types with either option', async () => {
  for (const excludeAmbiguous of [false, true]) {
    await assert.rejects(
      generatePassword(16, [], secureBytes, {excludeAmbiguous}),
      /文字種を1つ以上選択してください。/,
    );
  }
});

test('propagates random source errors with either option', async () => {
  for (const excludeAmbiguous of [false, true]) {
    const error = new Error('Random source unavailable');
    await assert.rejects(
      generatePassword(16, types, async () => {throw error;}, {excludeAmbiguous}),
      error,
    );
  }
});
