#!/usr/bin/env node
// Compatibility entry point shared with the iOS scripts.
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const options = {
  '--installer': 'PRELIS_APPSTORE_INSTALLER_P12_PASSWORD',
  '--api-key-id': 'PRELIS_APPSTORE_API_KEY_ID',
  '--api-issuer-id': 'PRELIS_APPSTORE_API_ISSUER_ID',
  '--github-p12': 'PRELIS_GITHUB_P12_PASSWORD',
};
const key = process.argv[2] ? options[process.argv[2]] : 'PRELIS_APPSTORE_P12_PASSWORD';
if (!key || process.argv.length > 3) {
  console.error('read-appstore-env.mjs の引数が不正です。');
  process.exit(2);
}
const result = spawnSync('python3', [fileURLToPath(new URL('./read-config.py', import.meta.url)), '--get', key], { stdio: 'inherit' });
if (result.error) console.error(result.error.message);
process.exit(result.status ?? 1);
