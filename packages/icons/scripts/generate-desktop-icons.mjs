import {copyFile, mkdir, mkdtemp, readFile, readdir, rm, writeFile} from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {Resvg} from '@resvg/resvg-js';

const packageDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repoRoot = path.resolve(packageDir, '../..');
const logo = (await readFile(path.join(packageDir, 'assets/brand.png'))).toString('base64');
const temporaryDir = await mkdtemp(path.join(os.tmpdir(), 'prelis-desktop-icon-'));

try {
  // Match the Android launcher icon's background, corner radius, and logo placement.
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="512" height="512"><rect width="100" height="100" rx="22" fill="#EAF7FC"/><image href="data:image/png;base64,${logo}" x="12" y="12" width="76" height="76"/></svg>`;
  const source = path.join(temporaryDir, 'app-icon.png');
  await writeFile(source, new Resvg(svg).render().asPng());

  const generated = path.join(temporaryDir, 'generated');
  const npm = process.platform === 'win32' ? 'npm.cmd' : 'npm';
  const result = spawnSync(npm, ['run', 'tauri', '-w', 'apps/desktop', '--', 'icon', source, '-o', generated], {
    cwd: repoRoot,
    stdio: 'inherit',
    shell: process.platform === 'win32',
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    process.exitCode = result.status ?? 1;
  } else {
    const output = path.join(repoRoot, 'apps/desktop/src-tauri/icons');
    for (const entry of await readdir(generated, {withFileTypes: true})) {
      if (entry.isFile()) {
        await copyFile(path.join(generated, entry.name), path.join(output, entry.name));
      }
    }
    const webPublic = path.join(repoRoot, 'apps/web/public');
    await mkdir(webPublic, {recursive: true});
    await copyFile(path.join(repoRoot, 'lp/frontend/app/public/brand.png'), path.join(webPublic, 'brand.png'));
  }
} finally {
  await rm(temporaryDir, {recursive: true, force: true});
}
