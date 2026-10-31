import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash, X509Certificate } from 'node:crypto';
import fs from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { after, before, test } from 'node:test';
import { publishRelease, readReleaseInfo } from './release-output.mjs';

const source = dirname(fileURLToPath(import.meta.url));
const version = '1.0.1';
const filenames = { play: `PrelisMobile_${version}_play.aab`, github: `PrelisMobile_${version}_github.apk` };
let temporary;
let key;
let archives;
let appFingerprint;

function command(program, args, options = {}) {
  const result = spawnSync(program, args, { encoding: 'utf8', timeout: 90_000, ...options });
  assert.equal(result.status, 0, `${program}: ${result.error || ''}\n${result.stdout}\n${result.stderr}`);
  return result.stdout;
}

const tool = name => process.env.JAVA_HOME ? join(process.env.JAVA_HOME, 'bin', name) : name;
const keyEnv = () => ({ ...process.env, PRELIS_TEST_STORE: 'fixture-store', PRELIS_TEST_KEY: 'fixture-key' });

before(() => {
  temporary = fs.mkdtempSync(join(tmpdir(), 'prelis-android-test-'));
  key = join(temporary, 'fixture.jks');
  for (const alias of ['play', 'app']) {
    command(tool('keytool'), [
      '-genkeypair', '-alias', alias, '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650',
      '-dname', `CN=Prelis Temporary ${alias}`, '-storetype', 'JKS', '-keystore', key,
      '-storepass:env', 'PRELIS_TEST_STORE', '-keypass:env', 'PRELIS_TEST_KEY', '-noprompt',
    ], { env: keyEnv() });
  }
  const publicCertificate = join(temporary, 'fixture.pem');
  command(tool('keytool'), ['-exportcert', '-rfc', '-alias', 'app', '-keystore', key,
    '-storepass:env', 'PRELIS_TEST_STORE', '-file', publicCertificate], { env: keyEnv() });
  appFingerprint = new X509Certificate(fs.readFileSync(publicCertificate)).fingerprint256.replaceAll(':', '');
  command(tool('keytool'), ['-importcert', '-alias', 'cert-only', '-file', publicCertificate, '-keystore', key,
    '-storepass:env', 'PRELIS_TEST_STORE', '-noprompt'], { env: keyEnv() });

  const payload = join(temporary, 'payload');
  fs.mkdirSync(join(payload, 'base/assets'), { recursive: true });
  fs.writeFileSync(join(payload, 'base/assets/index.android.bundle'), 'test bundle');
  const unsigned = join(temporary, 'unsigned.aab');
  command(tool('jar'), ['--create', '--file', unsigned, '-C', payload, '.']);
  const sign = (archive, alias) => command(tool('jarsigner'), [
    '-keystore', key, '-storepass:env', 'PRELIS_TEST_STORE', '-keypass:env', 'PRELIS_TEST_KEY', archive, alias,
  ], { env: keyEnv() });
  archives = {};
  for (const name of ['valid', 'unsigned-entry', 'corrupt', 'multiple-signers', 'wrong-signer']) {
    archives[name] = join(temporary, `${name}.aab`);
    fs.copyFileSync(unsigned, archives[name]);
    sign(archives[name], name === 'wrong-signer' ? 'app' : 'play');
  }
  fs.writeFileSync(join(payload, 'extra.txt'), 'unsigned addition');
  command(tool('jar'), ['--update', '--file', archives['unsigned-entry'], '--no-manifest', '-C', payload, 'extra.txt']);
  fs.writeFileSync(join(payload, 'base/assets/index.android.bundle'), 'changed after signing');
  command(tool('jar'), ['--update', '--file', archives.corrupt, '--no-manifest', '-C', payload, 'base/assets/index.android.bundle']);
  sign(archives['multiple-signers'], 'app');
});

after(() => {
  if (temporary) fs.rmSync(temporary, { recursive: true, force: true });
});

function fixture() {
  const root = fs.mkdtempSync(join(temporary, 'repo-'));
  const scripts = join(root, 'scripts/android');
  const android = join(root, 'apps/mobile/android');
  fs.mkdirSync(scripts, { recursive: true });
  fs.mkdirSync(join(android, 'app'), { recursive: true });
  for (const name of ['build-release.mjs', 'build-all.sh', 'release-output.mjs', 'verify-jar.java']) {
    fs.copyFileSync(join(source, name), join(scripts, name));
  }
  fs.writeFileSync(join(root, 'apps/mobile/app.json'), JSON.stringify({ expo: { version, android: { versionCode: 2 } } }));
  fs.writeFileSync(join(android, 'app/build.gradle'), `versionName "${version}"\nversionCode 2\n`);
  fs.writeFileSync(join(android, 'gradlew'), `#!${process.execPath}
const fs = require('node:fs');
const path = require('node:path');
const name = process.argv.includes(':app:bundleRelease') ? 'play' : 'github';
fs.appendFileSync(process.env.PRELIS_TEST_LOG, name + '\\n');
if (process.env.PRELIS_TEST_FAIL === name) process.exit(1);
fs.rmSync('app/build', {recursive:true, force:true});
const out = name === 'play' ? 'app/build/outputs/bundle/release/app-release.aab' : 'app/build/outputs/apk/release/app-release.apk';
fs.mkdirSync(path.dirname(out), {recursive:true});
if (name === 'play') fs.copyFileSync(process.env.PRELIS_TEST_AAB, out);
else fs.writeFileSync(out, 'apk:' + (process.env.PRELIS_TEST_BAD_APK ? '0'.repeat(64) : process.env.PRELIS_TEST_APP_FINGERPRINT));
`, { mode: 0o755 });
  const sdk = join(root, 'sdk');
  fs.mkdirSync(join(sdk, 'build-tools/37.0.0'), { recursive: true });
  fs.writeFileSync(join(sdk, 'build-tools/37.0.0/apksigner'), `#!${process.execPath}
const fs = require('node:fs');
if (process.argv.includes('--version')) { console.log('37.0.0'); process.exit(0); }
const contents = fs.readFileSync(process.argv.at(-1), 'utf8');
if (!/^apk:[0-9A-Fa-f]{64}$/.test(contents)) process.exit(1);
console.log('Number of signers: 1\\nSigner #1: certificate SHA-256 digest: ' + contents.slice(4));
`, { mode: 0o755 });
  const env = Object.fromEntries(Object.entries(process.env).filter(([name]) => !name.startsWith('PRELIS_') && !name.startsWith('ANDROID_SIGNING_')));
  for (const [prefix, alias] of [['PRELIS_PLAY', 'play'], ['PRELIS_APP', 'app']]) {
    Object.assign(env, { [prefix + '_KEYSTORE']: key, [prefix + '_KEY_ALIAS']: alias,
      [prefix + '_STORE_PASSWORD']: 'fixture-store', [prefix + '_KEY_PASSWORD']: 'fixture-key' });
  }
  Object.assign(env, { ANDROID_HOME: sdk, PRELIS_TEST_LOG: join(root, 'gradle.log'),
    PRELIS_TEST_AAB: archives.valid, PRELIS_TEST_APP_FINGERPRINT: appFingerprint });
  return { root, scripts, android, env, output: join(root, `dist/android/v${version}`) };
}

function run(value, mode, extraEnv = {}) {
  // All paths, keys and Gradle/APK tools belong to this isolated fixture.
  return spawnSync(process.execPath, [join(value.scripts, 'build-release.mjs'), mode], {
    cwd: tmpdir(), env: { ...value.env, ...extraEnv }, encoding: 'utf8', timeout: 90_000,
  });
}

function succeeded(result) {
  assert.equal(result.status, 0, `${result.error || ''}\n${result.stdout}\n${result.stderr}`);
}

function failedBeforeGradle(value, result) {
  assert.notEqual(result.status, 0, result.stdout);
  assert.equal(fs.existsSync(value.env.PRELIS_TEST_LOG), false, 'Gradle must not run after a preflight failure');
}

function seedPrevious(value) {
  fs.mkdirSync(value.output, { recursive: true });
  fs.writeFileSync(join(value.output, filenames.play), 'old AAB');
  fs.writeFileSync(join(value.output, filenames.github), 'old APK');
  fs.writeFileSync(join(value.output, 'SHA256SUMS'), 'old sums');
}

function previousIntact(value) {
  assert.equal(fs.readFileSync(join(value.output, filenames.play), 'utf8'), 'old AAB');
  assert.equal(fs.readFileSync(join(value.output, filenames.github), 'utf8'), 'old APK');
  assert.equal(fs.readFileSync(join(value.output, 'SHA256SUMS'), 'utf8'), 'old sums');
}

test('uses the public version and rejects Expo/Gradle mismatches before building', () => {
  const value = fixture();
  assert.equal(readReleaseInfo(value.root).version, version);
  fs.writeFileSync(join(value.android, 'app/build.gradle'), 'versionName "0.1.3"\nversionCode 2\n');
  const result = run(value, 'all');
  failedBeforeGradle(value, result);
  assert.match(result.stderr, /公開バージョン・versionCode/);
});

test('preflight signs with both private keys and accepts their self-signed certificates', () => {
  const value = fixture();
  seedPrevious(value);
  const result = run(value, 'check');
  succeeded(result);
  assert.equal(fs.existsSync(value.env.PRELIS_TEST_LOG), false);
  previousIntact(value);
});

test('an incorrect second key password fails before either Gradle build', () => {
  const value = fixture();
  seedPrevious(value);
  const result = run(value, 'all', { PRELIS_APP_KEY_PASSWORD: 'wrong-key-password' });
  failedBeforeGradle(value, result);
  previousIntact(value);
  assert.doesNotMatch(result.stdout + result.stderr, /wrong-key-password|fixture-key|fixture-store/);
});

test('a certificate-only alias cannot pass the signing preflight', () => {
  const value = fixture();
  failedBeforeGradle(value, run(value, 'check', { PRELIS_PLAY_KEY_ALIAS: 'cert-only' }));
});

test('missing APK verification tools fail before Gradle', () => {
  const value = fixture();
  failedBeforeGradle(value, run(value, 'all', { ANDROID_HOME: join(value.root, 'missing-sdk') }));
});

test('an unwritable output path fails before Gradle', () => {
  const value = fixture();
  const file = join(value.root, 'not-a-directory');
  fs.writeFileSync(file, 'keep');
  failedBeforeGradle(value, run(value, 'all', { PRELIS_ANDROID_OUTPUT_DIR: file }));
  assert.equal(fs.readFileSync(file, 'utf8'), 'keep');
});

test('unmanaged output files prevent a replacement before Gradle', () => {
  const value = fixture();
  seedPrevious(value);
  fs.writeFileSync(join(value.output, 'notes.txt'), 'keep');
  failedBeforeGradle(value, run(value, 'all'));
  previousIntact(value);
});

test('a dangling symlink cannot be used as the versioned output directory', () => {
  const value = fixture();
  fs.mkdirSync(dirname(value.output), { recursive: true });
  fs.symlinkSync(join(value.root, 'missing'), value.output);
  failedBeforeGradle(value, run(value, 'all'));
  assert.equal(fs.lstatSync(value.output).isSymbolicLink(), true);
});

test('an output root inside Gradle clean targets is rejected, including through a symlink', () => {
  const value = fixture();
  const target = join(value.android, 'app/build/artifacts');
  fs.mkdirSync(target, { recursive: true });
  const link = join(value.root, 'output-link');
  fs.symlinkSync(target, link);
  failedBeforeGradle(value, run(value, 'all', { PRELIS_ANDROID_OUTPUT_DIR: link }));
});

test('build-all publishes the verified versioned artifact set and its checksums', () => {
  const value = fixture();
  seedPrevious(value);
  const oldVersion = join(value.root, 'dist/android/v0.9.0');
  fs.mkdirSync(oldVersion);
  fs.writeFileSync(join(oldVersion, 'keep.txt'), 'keep');
  const result = spawnSync('bash', [join(value.scripts, 'build-all.sh')], {
    env: value.env, encoding: 'utf8', timeout: 90_000,
  });
  succeeded(result);
  assert.deepEqual(fs.readdirSync(value.output).sort(), [...Object.values(filenames), 'SHA256SUMS'].sort());
  for (const line of fs.readFileSync(join(value.output, 'SHA256SUMS'), 'utf8').trim().split('\n')) {
    const [digest, filename] = line.split('  ');
    assert.equal(createHash('sha256').update(fs.readFileSync(join(value.output, filename))).digest('hex'), digest);
  }
  assert.equal(fs.readFileSync(join(oldVersion, 'keep.txt'), 'utf8'), 'keep');
  assert.deepEqual(fs.readdirSync(dirname(value.output)).sort(), ['v0.9.0', `v${version}`]);
});

test('a second build failure leaves both previous artifacts and checksums intact', () => {
  const value = fixture();
  seedPrevious(value);
  assert.notEqual(run(value, 'all', { PRELIS_TEST_FAIL: 'github' }).status, 0);
  previousIntact(value);
});

for (const variant of ['unsigned-entry', 'corrupt', 'multiple-signers', 'wrong-signer']) {
  test(`rejects ${variant} AAB payload without replacing the previous set`, () => {
    const value = fixture();
    seedPrevious(value);
    const result = run(value, 'play', { PRELIS_TEST_AAB: archives[variant] });
    assert.notEqual(result.status, 0, result.stdout);
    previousIntact(value);
  });
}

test('an APK signer mismatch leaves the previous set intact', () => {
  const value = fixture();
  seedPrevious(value);
  assert.notEqual(run(value, 'all', { PRELIS_TEST_BAD_APK: '1' }).status, 0);
  previousIntact(value);
});

test('a single-format build replaces the set without retaining a stale counterpart', () => {
  const value = fixture();
  seedPrevious(value);
  succeeded(run(value, 'play'));
  assert.deepEqual(fs.readdirSync(value.output).sort(), [filenames.play, 'SHA256SUMS'].sort());
});

test('a custom output root also contains a public-version directory', () => {
  const value = fixture();
  const custom = join(value.root, 'custom-output');
  succeeded(run(value, 'github', { PRELIS_ANDROID_OUTPUT_DIR: custom }));
  assert.equal(fs.existsSync(join(custom, `v${version}`, filenames.github)), true);
  assert.equal(fs.existsSync(value.output), false);
});

test('a directory commit failure restores the whole previous set', t => {
  const root = fs.mkdtempSync(join(temporary, 'publish-'));
  const staged = join(root, 'transaction/new');
  const destination = join(root, 'v1.0.1');
  fs.mkdirSync(staged, { recursive: true });
  fs.mkdirSync(destination);
  fs.writeFileSync(join(staged, 'artifact'), 'new');
  fs.writeFileSync(join(destination, 'artifact'), 'old');
  const rename = fs.renameSync;
  t.mock.method(fs, 'renameSync', (from, to) => {
    if (from === staged) throw new Error('simulated commit failure');
    return rename(from, to);
  });
  assert.throws(() => publishRelease(staged, destination), /simulated commit failure/);
  assert.equal(fs.readFileSync(join(destination, 'artifact'), 'utf8'), 'old');
  assert.equal(fs.readFileSync(join(staged, 'artifact'), 'utf8'), 'new');
});

test('a failed rollback keeps the previous set at the reported backup path', t => {
  const root = fs.mkdtempSync(join(temporary, 'publish-'));
  const staged = join(root, 'transaction/new');
  const previous = join(root, 'transaction/previous');
  const destination = join(root, 'v1.0.1');
  fs.mkdirSync(staged, { recursive: true });
  fs.mkdirSync(destination);
  fs.writeFileSync(join(destination, 'artifact'), 'old');
  const rename = fs.renameSync;
  t.mock.method(fs, 'renameSync', (from, to) => {
    if (to === destination) throw new Error('simulated move failure');
    return rename(from, to);
  });
  assert.throws(() => publishRelease(staged, destination), error => error.message.includes(previous));
  assert.equal(fs.readFileSync(join(previous, 'artifact'), 'utf8'), 'old');
});
