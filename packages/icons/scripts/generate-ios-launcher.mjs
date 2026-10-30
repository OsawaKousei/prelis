import {mkdir, readFile, writeFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {crc32, deflateSync} from 'node:zlib';
import {Resvg} from '@resvg/resvg-js';

const packageDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const logo = (await readFile(path.join(packageDir, 'assets/brand.png'))).toString('base64');
const output = path.resolve(packageDir, '../../apps/mobile/ios/PrelisMobile/Images.xcassets/AppIcon.appiconset');
// Match Android's regular launcher. iOS applies its own corner mask.
const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="1024" height="1024"><rect width="100" height="100" fill="#EAF7FC"/><image href="data:image/png;base64,${logo}" x="12" y="12" width="76" height="76"/></svg>`;
const rendered = new Resvg(svg).render();
const pixels = rendered.pixels;
const size = 1024;
const rows = Buffer.alloc(size * (1 + size * 3));
for (let y = 0; y < size; y++) {
  for (let x = 0; x < size; x++) {
    const source = (y * size + x) * 4;
    if (pixels[source + 3] !== 255) throw new Error('App Store icon must be opaque');
    pixels.copy(rows, y * (1 + size * 3) + 1 + x * 3, source, source + 3);
  }
}

// Encode RGB PNG explicitly: App Store icons must have no alpha channel.
function chunk(type, data) {
  const body = Buffer.concat([Buffer.from(type), data]);
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const checksum = Buffer.alloc(4);
  checksum.writeUInt32BE(crc32(body));
  return Buffer.concat([length, body, checksum]);
}
const header = Buffer.alloc(13);
header.writeUInt32BE(size, 0);
header.writeUInt32BE(size, 4);
header[8] = 8;
header[9] = 2; // RGB, no alpha
const png = Buffer.concat([
  Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
  chunk('IHDR', header),
  chunk('IDAT', deflateSync(rows)),
  chunk('IEND', Buffer.alloc(0)),
]);
await mkdir(output, {recursive: true});
await writeFile(path.join(output, 'AppIcon.png'), png);
await writeFile(path.join(output, 'Contents.json'), `${JSON.stringify({
  images: [{filename: 'AppIcon.png', idiom: 'universal', platform: 'ios', size: '1024x1024'}],
  info: {author: 'xcode', version: 1},
}, null, 2)}\n`);
console.log('Generated iOS launcher icon (1024×1024 RGB)');
