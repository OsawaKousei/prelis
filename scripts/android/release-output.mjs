import fs from 'node:fs';
import { dirname, join } from 'node:path';

export function readReleaseInfo(repoRoot) {
  const { version } = JSON.parse(fs.readFileSync(join(repoRoot, 'apps/mobile/package.json'), 'utf8'));
  if (typeof version !== 'string' || !/^\d+(?:\.\d+){1,3}(?:[-+][A-Za-z0-9.-]+)?$/.test(version)) {
    throw new Error('モバイルの package.json から頒布バージョンを読み取れません。');
  }
  const { expo } = JSON.parse(fs.readFileSync(join(repoRoot, 'apps/mobile/app.json'), 'utf8'));
  const gradle = fs.readFileSync(join(repoRoot, 'apps/mobile/android/app/build.gradle'), 'utf8');
  const storeVersion = gradle.match(/^\s*versionName\s+["']([^"']+)["']/m)?.[1];
  const versionCode = Number(gradle.match(/^\s*versionCode\s+(\d+)\s*$/m)?.[1]);
  if (!storeVersion || !Number.isSafeInteger(versionCode) || versionCode < 1 ||
      expo.version !== storeVersion || expo.android?.versionCode !== versionCode) {
    throw new Error('app.json と Gradle の公開バージョン・versionCode を揃えてください。');
  }
  return {
    version,
    storeVersion,
    versionCode,
    filenames: {
      play: `PrelisMobile_${version}_play.aab`,
      github: `PrelisMobile_${version}_github.apk`,
    },
  };
}

// Refuse unrelated files before replacing a release directory.
export function validateDestination(destination, filenames) {
  let stat;
  try {
    stat = fs.lstatSync(destination);
  } catch (error) {
    if (error.code === 'ENOENT') return;
    throw error;
  }
  if (!stat.isDirectory() || stat.isSymbolicLink()) {
    throw new Error(`出力先は通常のディレクトリである必要があります: ${destination}`);
  }
  const allowed = new Set([...Object.values(filenames), 'SHA256SUMS']);
  for (const entry of fs.readdirSync(destination, { withFileTypes: true })) {
    if (!entry.isFile() || !allowed.has(entry.name)) {
      throw new Error(`出力先に管理対象外のファイルがあります: ${join(destination, entry.name)}`);
    }
  }
}

// The caller keeps the transaction directory if restoring "previous" fails.
export function publishRelease(staged, destination) {
  const previous = join(dirname(staged), 'previous');
  if (fs.existsSync(destination)) fs.renameSync(destination, previous);
  try {
    fs.renameSync(staged, destination);
  } catch (error) {
    if (fs.existsSync(previous)) {
      try {
        fs.renameSync(previous, destination);
      } catch (restoreError) {
        throw new Error(`配置と復元に失敗しました。旧成果物は ${previous} に保持しています。`, {
          cause: new AggregateError([error, restoreError]),
        });
      }
    }
    throw error;
  }
}
