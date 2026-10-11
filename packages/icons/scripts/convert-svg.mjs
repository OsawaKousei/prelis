import {readdir, readFile, mkdir, writeFile, stat} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {Resvg} from '@resvg/resvg-js';

const inputDir = process.argv[2];
const overwrite = process.argv.includes('--force');
const sizeFlag = process.argv.indexOf('--size');
const size = sizeFlag >= 0 ? Number(process.argv[sizeFlag + 1]) : 128;
if (!inputDir) {
  console.error('Usage: npm run convert -w packages/icons -- <svg-directory> [--size 128] [--force]');
  process.exit(1);
}
if (!Number.isInteger(size) || size < 16 || size > 1024) throw new Error('Size must be an integer from 16 to 1024');

const outputDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../assets');
const files = (await readdir(inputDir)).filter(file => /^[a-z][a-z0-9-]*\.svg$/.test(file)).sort();
if (files.length === 0) throw new Error(`No SVG files found in ${inputDir}`);
await mkdir(outputDir, {recursive: true});

for (const file of files) {
  const output = path.join(outputDir, file.replace(/\.svg$/, '.png'));
  if (!overwrite) {
    try {
      await stat(output);
      throw new Error(`${output} already exists; pass --force to replace a canonical icon`);
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
  }
  const svg = await readFile(path.join(inputDir, file));
  const png = new Resvg(svg, {fitTo: {mode: 'width', value: size}}).render().asPng();
  await writeFile(output, png);
  console.log(`${file} → ${output}`);
}
