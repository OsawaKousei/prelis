#!/usr/bin/env node
import { existsSync, readFileSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const envFile = fileURLToPath(new URL('./.env', import.meta.url));
const key = 'PRELIS_APPSTORE_P12_PASSWORD';
let password = process.env[key];

function fail(message) {
  console.error(message);
  process.exit(1);
}

if (existsSync(envFile)) {
  if (statSync(envFile).mode & 0o077) {
    fail('scripts/macos/.env の権限を 0600 にしてください。');
  }
  const lines = readFileSync(envFile, 'utf8').split(/\r?\n/);
  for (const [index, line] of lines.entries()) {
    if (!line.trim() || line.trimStart().startsWith('#')) continue;
    const match = line.match(/^\s*(?:export\s+)?([A-Z][A-Z0-9_]*)\s*=(.*)$/);
    if (!match || match[1] !== key) {
      fail(`scripts/macos/.env の ${index + 1} 行目が不正です。${key} だけを記述してください。`);
    }
    let value = match[2].trim();
    if (value.startsWith('"') || value.startsWith("'")) {
      const quote = value[0];
      if (value.length < 2 || !value.endsWith(quote)) {
        fail(`scripts/macos/.env の ${index + 1} 行目の引用符が閉じられていません。`);
      }
      value = value.slice(1, -1);
    }
    if (password === undefined) password = value;
  }
}

if (!password || /[\r\n\0]/.test(password)) {
  fail(`${key} を scripts/macos/.env または環境変数に設定してください。`);
}
process.stdout.write(`${password}\n`);
