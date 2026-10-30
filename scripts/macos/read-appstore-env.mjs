#!/usr/bin/env node
import { existsSync, readFileSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const envFile = fileURLToPath(new URL('./.env', import.meta.url));
const keys = [
  'PRELIS_APPSTORE_P12_PASSWORD',
  'PRELIS_APPSTORE_INSTALLER_P12_PASSWORD',
  'PRELIS_APPSTORE_API_KEY_ID',
  'PRELIS_APPSTORE_API_ISSUER_ID',
  'PRELIS_GITHUB_P12_PASSWORD',
];
const options = {
  '--installer': keys[1],
  '--api-key-id': keys[2],
  '--api-issuer-id': keys[3],
  '--github-p12': keys[4],
};
const requestedKey = process.argv[2] ? options[process.argv[2]] : keys[0];
if (process.argv.length > 3 || !requestedKey) {
  console.error('使い方: read-appstore-env.mjs [--installer|--api-key-id|--api-issuer-id|--github-p12]');
  process.exit(2);
}
const values = Object.fromEntries(keys.map((key) => [key, process.env[key]]));

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
    if (!match || !keys.includes(match[1])) {
      fail(`scripts/macos/.env の ${index + 1} 行目が不正です。許可された変数だけを記述してください。`);
    }
    let value = match[2].trim();
    if (value.startsWith('"') || value.startsWith("'")) {
      const quote = value[0];
      if (value.length < 2 || !value.endsWith(quote)) {
        fail(`scripts/macos/.env の ${index + 1} 行目の引用符が閉じられていません。`);
      }
      value = value.slice(1, -1);
    }
    if (values[match[1]] === undefined) values[match[1]] = value;
  }
}

const requestedValue = values[requestedKey] || (requestedKey === keys[1] ? values[keys[0]] : undefined);
if (!requestedValue || /[\r\n\0]/.test(requestedValue)) {
  fail(`${requestedKey} を scripts/macos/.env または環境変数に設定してください。`);
}
if (requestedKey === keys[2] && !/^[A-Z0-9]{10}$/.test(requestedValue)) {
  fail(`${requestedKey} の形式が不正です。`);
}
if (requestedKey === keys[3] && !/^[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$/.test(requestedValue)) {
  fail(`${requestedKey} の形式が不正です。`);
}
process.stdout.write(`${requestedValue}\n`);
