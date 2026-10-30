import {generatePassword as generateSharedPassword} from '@prelis/core';
export {characterSets} from '@prelis/core';
export type {CharacterType, PasswordLength} from '@prelis/core';
import type {CharacterType, PasswordLength} from '@prelis/core';

export const generatePassword = (
  length: PasswordLength,
  selectedTypes: readonly CharacterType[],
  excludeAmbiguous = false,
) =>
  generateSharedPassword(
    length,
    selectedTypes,
    async count => [...crypto.getRandomValues(new Uint8Array(count))],
    {excludeAmbiguous},
  );
