#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { X509Certificate } from 'node:crypto';
import { existsSync, mkdtempSync, mkdirSync, copyFileSync, renameSync, rmSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { basename, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const androidDir = join(repoRoot, 'apps/mobile/android');
const envFile = fileURLToPath(new URL('./.env', import.meta.url));
const mode = process.argv[2];
const allowedEnv = new Set([
  'PRELIS_PLAY_KEYSTORE', 'PRELIS_PLAY_KEY_ALIAS',
  'PRELIS_PLAY_STORE_PASSWORD', 'PRELIS_PLAY_KEY_PASSWORD',
  'PRELIS_APP_KEYSTORE', 'PRELIS_APP_KEY_ALIAS',
  'PRELIS_APP_STORE_PASSWORD', 'PRELIS_APP_KEY_PASSWORD',
]);

function fail(message) {
  throw new Error(message);
}

function loadEnvFile() {
  if (!existsSync(envFile)) return;
  const lines = readFileSync(envFile, 'utf8').split(/\r?\n/);
  for (const [index, line] of lines.entries()) {
    if (!line.trim() || line.trimStart().startsWith('#')) continue;
    const match = line.match(/^\s*(?:export\s+)?([A-Z][A-Z0-9_]*)\s*=(.*)$/);
    if (!match || !allowedEnv.has(match[1])) {
      fail(`.env の ${index + 1} 行目が不正です。対応する PRELIS_* 変数だけを記述してください。`);
    }
    let value = match[2].trim();
    if (value.startsWith('"') || value.startsWith("'")) {
      const quote = value[0];
      if (value.length < 2 || !value.endsWith(quote)) {
        fail(`.env の ${index + 1} 行目の引用符が閉じられていません。`);
      }
      value = value.slice(1, -1);
    }
    if (process.env[match[1]] === undefined) process.env[match[1]] = value;
  }
}

try {
  loadEnvFile();
} catch (error) {
  console.error(error.message);
  process.exit(1);
}

const options = {
  play: {
    keystore: process.env.PRELIS_PLAY_KEYSTORE || join(homedir(), 'keys/play-upload.jks'),
    alias: process.env.PRELIS_PLAY_KEY_ALIAS || 'play-upload',
    storePassword: process.env.PRELIS_PLAY_STORE_PASSWORD,
    keyPassword: process.env.PRELIS_PLAY_KEY_PASSWORD,
    task: ':app:bundleRelease',
    source: 'app/build/outputs/bundle/release/app-release.aab',
    destination: 'prelis-play.aab',
  },
  github: {
    keystore: process.env.PRELIS_APP_KEYSTORE || join(homedir(), 'keys/app-signing.jks'),
    alias: process.env.PRELIS_APP_KEY_ALIAS || 'app-signing',
    storePassword: process.env.PRELIS_APP_STORE_PASSWORD,
    keyPassword: process.env.PRELIS_APP_KEY_PASSWORD,
    task: ':app:assembleRelease',
    source: 'app/build/outputs/apk/release/app-release.apk',
    destination: 'prelis-github.apk',
  },
};

function run(command, args, { cwd = androidDir, env = process.env, input, inherit = false } = {}) {
  const result = spawnSync(command, args, {
    cwd,
    env: { ...env, LC_ALL: 'C' },
    input,
    encoding: 'utf8',
    stdio: inherit ? 'inherit' : 'pipe',
  });
  if (result.error) fail(`${basename(command)} を起動できません: ${result.error.message}`);
  if (result.status !== 0) {
    if (!inherit) process.stderr.write(result.stderr || '');
    fail(`${basename(command)} が失敗しました (終了コード ${result.status})。`);
  }
  return result.stdout;
}

function fingerprint(value) {
  return value.replaceAll(':', '').toUpperCase();
}

function keystoreFingerprint(config) {
  const pem = run('keytool', [
    '-exportcert', '-rfc', '-keystore', config.keystore, '-alias', config.alias,
  ], { input: `${config.storePassword}\n` });
  try {
    return fingerprint(new X509Certificate(pem).fingerprint256);
  } catch {
    fail('キーストアの証明書を読み取れませんでした。');
  }
}

function artifactFingerprint(config, artifact) {
  if (mode === 'play') {
    const verified = run('jarsigner', ['-verify', artifact]);
    if (!verified.includes('jar verified.')) fail('AAB の JAR 署名を確認できませんでした。');
    const details = run('keytool', ['-printcert', '-jarfile', artifact]);
    const match = details.match(/SHA256:\s*([0-9A-Fa-f:]{64,95})/);
    if (!match) fail('AAB の署名証明書を読み取れませんでした。');
    return fingerprint(match[1]);
  }

  const sdkRoot = process.env.ANDROID_HOME || process.env.ANDROID_SDK_ROOT;
  if (!sdkRoot) fail('ANDROID_HOME または ANDROID_SDK_ROOT を設定してください。');
  const apksigner = join(sdkRoot, 'build-tools/37.0.0/apksigner');
  if (!existsSync(apksigner)) fail(`apksigner が見つかりません: ${apksigner}`);
  const verified = run(apksigner, ['verify', '--verbose', '--print-certs', artifact]);
  const matches = [...verified.matchAll(/Signer(?: #\d+)?: certificate SHA-256 digest: ([0-9a-fA-F]{64})/g)];
  const certificates = new Set(matches.map(match => fingerprint(match[1])));
  if (!verified.includes('Number of signers: 1') || certificates.size !== 1) {
    fail('APK の署名証明書を一意に確認できませんでした。');
  }
  return [...certificates][0];
}

if ((!Object.hasOwn(options, mode) && mode !== 'check') || process.argv.length !== 3) {
  console.error('使い方: node scripts/android/build-release.mjs play|github|check');
  process.exit(2);
}

function validateConfig(config, modeName) {
  if (!existsSync(config.keystore)) fail(`キーストアが見つかりません: ${config.keystore}`);
  if (!config.storePassword || !config.keyPassword) {
    const prefix = modeName === 'play' ? 'PRELIS_PLAY' : 'PRELIS_APP';
    fail(`${prefix}_STORE_PASSWORD と ${prefix}_KEY_PASSWORD を scripts/android/.env または環境変数に設定してください。`);
  }
  return keystoreFingerprint(config);
}

try {
  if (mode === 'check') {
    for (const [name, config] of Object.entries(options)) validateConfig(config, name);
    console.log('Play 用と GitHub 用の署名設定を確認しました。');
    process.exit(0);
  }

  const config = options[mode];
  const expected = validateConfig(config, mode);
  const env = {
    ...process.env,
    ANDROID_SIGNING_STORE_FILE: config.keystore,
    ANDROID_SIGNING_STORE_PASSWORD: config.storePassword,
    ANDROID_SIGNING_KEY_ALIAS: config.alias,
    ANDROID_SIGNING_KEY_PASSWORD: config.keyPassword,
  };

  // Gradle may clean dependency Codegen output before Ninja cleans the app.
  // Drop the generated app CMake state first so clean cannot reconfigure it
  // against JNI sources that have just been removed.
  rmSync(join(androidDir, 'app', '.cxx'), { recursive: true, force: true });
  rmSync(join(androidDir, 'app', 'build', 'intermediates', 'cxx'), { recursive: true, force: true });
  run('./gradlew', ['clean', config.task, '--no-daemon'], { env, inherit: true });
  const source = join(androidDir, config.source);
  if (!existsSync(source)) fail(`ビルド成果物が見つかりません: ${source}`);
  const actual = artifactFingerprint(config, source);
  if (actual !== expected) fail(`${config.destination} の署名証明書が指定した鍵と一致しません。`);

  const outputDir = process.env.PRELIS_ANDROID_OUTPUT_DIR || join(repoRoot, 'dist/android');
  mkdirSync(outputDir, { recursive: true });
  const stagingDir = mkdtempSync(join(outputDir, '.stage-'));
  try {
    const staged = join(stagingDir, config.destination);
    copyFileSync(source, staged);
    renameSync(staged, join(outputDir, config.destination));
  } finally {
    rmSync(stagingDir, { recursive: true, force: true });
  }
  console.log(`署名を確認しました (SHA-256: ${actual})`);
  console.log(`成果物: ${join(outputDir, config.destination)}`);
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
