#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { createHash, X509Certificate } from 'node:crypto';
import { accessSync, constants, existsSync, mkdtempSync, mkdirSync, copyFileSync, realpathSync, rmSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { basename, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { publishRelease, readReleaseInfo, validateDestination } from './release-output.mjs';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const androidDir = join(repoRoot, 'apps/mobile/android');
const envFile = fileURLToPath(new URL('./.env', import.meta.url));
const mode = process.argv[2];
if (!['play', 'github', 'all', 'check'].includes(mode) || process.argv.length !== 3) {
  console.error('使い方: node scripts/android/build-release.mjs play|github|all|check');
  process.exit(2);
}
const jdkTool = name => process.env.JAVA_HOME ? join(process.env.JAVA_HOME, 'bin', name) : name;
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
  },
  github: {
    keystore: process.env.PRELIS_APP_KEYSTORE || join(homedir(), 'keys/app-signing.jks'),
    alias: process.env.PRELIS_APP_KEY_ALIAS || 'app-signing',
    storePassword: process.env.PRELIS_APP_STORE_PASSWORD,
    keyPassword: process.env.PRELIS_APP_KEY_PASSWORD,
    task: ':app:assembleRelease',
    source: 'app/build/outputs/apk/release/app-release.apk',
  },
};

function run(command, args, { cwd = androidDir, env = process.env, inherit = false, timeout = 60_000 } = {}) {
  const result = spawnSync(command, args, {
    cwd,
    env: { ...env, LC_ALL: 'C' },
    encoding: 'utf8',
    stdio: inherit ? 'inherit' : 'pipe',
    timeout,
    maxBuffer: 4 * 1024 * 1024,
  });
  if (result.error) fail(`${basename(command)} を起動できません: ${result.error.message}`);
  if (result.status !== 0) {
    if (!inherit) process.stderr.write((result.stdout || '') + (result.stderr || ''));
    fail(`${basename(command)} が失敗しました (${result.signal || `終了コード ${result.status}`})。`);
  }
  return result.stdout;
}

function fingerprint(value) {
  return value.replaceAll(':', '').toUpperCase();
}

function keystoreFingerprint(config) {
  const pem = run(jdkTool('keytool'), [
    '-exportcert', '-rfc', '-keystore', config.keystore, '-alias', config.alias,
    '-storepass:env', 'ANDROID_SIGNING_STORE_PASSWORD',
  ], { env: signingEnv(config) });
  try {
    return fingerprint(new X509Certificate(pem).fingerprint256);
  } catch {
    fail('キーストアの証明書を読み取れませんでした。');
  }
}

function apksignerPath() {
  const sdkRoot = process.env.ANDROID_HOME || process.env.ANDROID_SDK_ROOT;
  if (!sdkRoot) fail('ANDROID_HOME または ANDROID_SDK_ROOT を設定してください。');
  const apksigner = join(sdkRoot, 'build-tools/37.0.0/apksigner');
  if (!existsSync(apksigner)) fail(`apksigner が見つかりません: ${apksigner}`);
  return apksigner;
}

function verifyJar(config, artifact, expected) {
  // Trust the configured certificate explicitly, so Android self-signed keys
  // pass strict verification without suppressing unsigned-entry/signer errors.
  run(jdkTool('jarsigner'), [
    '-verify', '-strict', '-keystore', config.keystore,
    '-storepass:env', 'ANDROID_SIGNING_STORE_PASSWORD', artifact, config.alias,
  ], { env: signingEnv(config) });
  run(jdkTool('java'), [join(repoRoot, 'scripts/android/verify-jar.java'), artifact, expected]);
}

function verifyArtifact(name, config, artifact, expected) {
  if (name === 'play') {
    verifyJar(config, artifact, expected);
    return;
  }
  const verified = run(apksignerPath(), ['verify', '--verbose', '--print-certs', artifact]);
  const matches = [...verified.matchAll(/Signer(?: #\d+)?: certificate SHA-256 digest: ([0-9a-fA-F]{64})/g)];
  const certificates = new Set(matches.map(match => fingerprint(match[1])));
  if (!/^Number of signers: 1\s*$/m.test(verified) || certificates.size !== 1) {
    fail('APK の署名証明書を一意に確認できませんでした。');
  }
  if ([...certificates][0] !== expected) fail('APK の署名証明書が指定した鍵と一致しません。');
}

function signingEnv(config) {
  return {
    ...process.env,
    ANDROID_SIGNING_STORE_FILE: config.keystore,
    ANDROID_SIGNING_STORE_PASSWORD: config.storePassword,
    ANDROID_SIGNING_KEY_ALIAS: config.alias,
    ANDROID_SIGNING_KEY_PASSWORD: config.keyPassword,
  };
}

function checkTools(names) {
  run(jdkTool('java'), ['-version']);
  run(jdkTool('jar'), ['--version']);
  run(jdkTool('keytool'), ['-help']);
  run(jdkTool('jarsigner'), ['-help']);
  accessSync(join(androidDir, 'gradlew'), constants.X_OK);
  if (names.includes('github')) run(apksignerPath(), ['--version']);
}

function validateConfig(config, modeName, temporary) {
  config.keystore = resolve(config.keystore);
  if (!existsSync(config.keystore) || !statSync(config.keystore).isFile()) {
    fail(`キーストアが見つかりません: ${config.keystore}`);
  }
  accessSync(config.keystore, constants.R_OK);
  if (!config.storePassword || !config.keyPassword) {
    const prefix = modeName === 'play' ? 'PRELIS_PLAY' : 'PRELIS_APP';
    fail(`${prefix}_STORE_PASSWORD と ${prefix}_KEY_PASSWORD を scripts/android/.env または環境変数に設定してください。`);
  }
  const expected = keystoreFingerprint(config);
  const probe = join(temporary, `probe-${modeName}`);
  mkdirSync(probe);
  writeFileSync(join(probe, 'probe.txt'), 'Prelis Android signing preflight\n');
  const archive = join(probe, 'probe.jar');
  run(jdkTool('jar'), ['--create', '--file', archive, '-C', probe, 'probe.txt']);
  run(jdkTool('jarsigner'), [
    '-keystore', config.keystore,
    '-storepass:env', 'ANDROID_SIGNING_STORE_PASSWORD',
    '-keypass:env', 'ANDROID_SIGNING_KEY_PASSWORD', archive, config.alias,
  ], { env: signingEnv(config) });
  verifyJar(config, archive, expected);
  return expected;
}

let temporary;
try {
  const release = readReleaseInfo(repoRoot);
  const names = mode === 'all' || mode === 'check' ? ['play', 'github'] : [mode];
  const outputRoot = resolve(process.env.PRELIS_ANDROID_OUTPUT_DIR || join(repoRoot, 'dist/android'));
  const destination = join(outputRoot, `v${release.version}`);
  validateDestination(destination, release.filenames);
  checkTools(names);
  mkdirSync(outputRoot, { recursive: true });
  const outputRelativeToAndroid = relative(realpathSync(androidDir), realpathSync(outputRoot));
  if (!isAbsolute(outputRelativeToAndroid) && outputRelativeToAndroid !== '..' &&
      !outputRelativeToAndroid.startsWith(`..${sep}`)) {
    fail('Gradle clean による削除を避けるため、Android プロジェクトの外に出力先を指定してください。');
  }
  // Creating and writing the stage also checks output permissions before Gradle.
  temporary = mkdtempSync(join(outputRoot, `.v${release.version}-stage-`));
  const staged = join(temporary, 'new');
  mkdirSync(staged);
  const expected = new Map(names.map(name => [name, validateConfig(options[name], name, temporary)]));
  if (mode === 'check') {
    console.log(`署名試行・検証ツール・出力先を確認しました: ${destination}`);
  } else {
    for (const name of names) {
      const config = options[name];
      // Drop app CMake state first: Gradle clean can otherwise ask Ninja to
      // reconfigure against dependency Codegen sources already removed by clean.
      rmSync(join(androidDir, 'app', '.cxx'), { recursive: true, force: true });
      rmSync(join(androidDir, 'app', 'build', 'intermediates', 'cxx'), { recursive: true, force: true });
      run('./gradlew', ['clean', config.task, '--no-daemon'], { env: signingEnv(config), inherit: true, timeout: 0 });
      const source = join(androidDir, config.source);
      if (!existsSync(source)) fail(`ビルド成果物が見つかりません: ${source}`);
      const artifact = join(staged, release.filenames[name]);
      copyFileSync(source, artifact);
      verifyArtifact(name, config, artifact, expected.get(name));
      console.log(`${release.filenames[name]} の署名を確認しました (証明書 SHA-256: ${expected.get(name)})`);
    }
    const checksums = names.map(name => {
      const filename = release.filenames[name];
      const digest = createHash('sha256').update(readFileSync(join(staged, filename))).digest('hex');
      return `${digest}  ${filename}\n`;
    }).join('');
    writeFileSync(join(staged, 'SHA256SUMS'), checksums);
    validateDestination(destination, release.filenames);
    publishRelease(staged, destination);
    console.log(`成果物: ${destination}`);
  }
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
} finally {
  if (temporary) {
    if (existsSync(join(temporary, 'previous')) && existsSync(join(temporary, 'new'))) {
      console.error(`復元用の旧成果物を保持しています: ${join(temporary, 'previous')}`);
    } else {
      try {
        rmSync(temporary, { recursive: true, force: true });
      } catch (error) {
        console.error(`一時ディレクトリを削除できません: ${temporary}: ${error.message}`);
      }
    }
  }
}
