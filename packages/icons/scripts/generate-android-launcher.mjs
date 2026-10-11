import {mkdir, readFile, writeFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {Resvg} from '@resvg/resvg-js';

const packageDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const logo = (await readFile(path.join(packageDir, 'assets/brand.png'))).toString('base64');
const resourceDir = path.resolve(packageDir, '../../apps/mobile/android/app/src/main/res');
const sizes = {mdpi: 48, hdpi: 72, xhdpi: 96, xxhdpi: 144, xxxhdpi: 192};

for (const [density, size] of Object.entries(sizes)) {
  const dir = path.join(resourceDir, `mipmap-${density}`);
  await mkdir(dir, {recursive: true});
  for (const round of [false, true]) {
    const clip = round ? '<defs><clipPath id="shape"><circle cx="50" cy="50" r="50"/></clipPath></defs>' : '';
    const background = round ? '<circle cx="50" cy="50" r="50" fill="#EAF7FC"/>' : '<rect width="100" height="100" rx="22" fill="#EAF7FC"/>';
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="${size}" height="${size}">${clip}<g${round ? ' clip-path="url(#shape)"' : ''}>${background}<image href="data:image/png;base64,${logo}" x="12" y="12" width="76" height="76"/></g></svg>`;
    const png = new Resvg(svg).render().asPng();
    await writeFile(path.join(dir, round ? 'ic_launcher_round.png' : 'ic_launcher.png'), png);
  }
  console.log(`Generated ${density} launcher icons`);
}

const foregroundDir = path.join(resourceDir, 'drawable-nodpi');
await mkdir(foregroundDir, {recursive: true});
const foreground = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="432" height="432"><image href="data:image/png;base64,${logo}" x="17" y="17" width="66" height="66"/></svg>`;
await writeFile(path.join(foregroundDir, 'ic_launcher_foreground.png'), new Resvg(foreground).render().asPng());
console.log('Generated adaptive launcher foreground');
