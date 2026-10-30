import { copyFile, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Resvg } from '@resvg/resvg-js';

const directory = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(directory, '../../..');
const icons = path.join(root, 'packages/icons/assets');
const imageUri = async (name) =>
  `data:image/png;base64,${(await readFile(path.join(icons, `${name}.png`))).toString('base64')}`;

// Reuse the existing store icon without changing the brand artwork.
await copyFile(
  path.join(root, 'dist/play-store/icon.png'),
  path.join(directory, 'icon.png'),
);

const logo = await imageUri('brand');
const features = await Promise.all(
  [
    ['diary', '日記', 224],
    ['timer', 'タイマー', 282],
    ['password', 'パスワード生成', 410],
  ].map(async ([name, label, width]) => ({
    label,
    width,
    image: await imageUri(name),
  })),
);
let offset = 0;
const featureArt = features.map(({ label, width, image }) => {
  const art = `<g transform="translate(${offset} 0)">
    <rect width="${width}" height="80" rx="18" fill="#FFFFFF" stroke="#D5E6EC" stroke-width="2"/>
    <image href="${image}" x="26" y="20" width="40" height="40" filter="url(#accent)"/>
    <text x="86" y="52" font-size="28" font-weight="500">${label}</text>
  </g>`;
  offset += width + 24;
  return art;
}).join('\n');

// Match the editable App Store creative layout in a Snap-specific 3:1 canvas.
const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="640" viewBox="0 0 1920 640">
  <defs>
    <filter id="accent" color-interpolation-filters="sRGB">
      <feColorMatrix type="matrix" values="0 0 0 0 0.0431 0 0 0 0 0.4706 0 0 0 0 0.6039 0 0 0 1 0"/>
    </filter>
  </defs>
  <rect width="1920" height="640" fill="#F8FCFE"/>
  <circle cx="1730" cy="320" r="410" fill="#E4F7FC"/>
  <circle cx="1770" cy="305" r="280" fill="none" stroke="#D5E6EC" stroke-width="2"/>
  <g font-family="Noto Sans CJK JP, sans-serif" fill="#183446">
    <image href="${logo}" x="236" y="105" width="72" height="72"/>
    <text x="330" y="160" font-size="62" font-weight="700" letter-spacing="-2">prelis<tspan fill="#0B789A">.</tspan></text>
    <text x="236" y="298" font-size="78" font-weight="700" letter-spacing="-2">毎日を、軽やかに。</text>
    <g transform="translate(236 366)">${featureArt}</g>
    <text x="238" y="510" font-size="23" fill="#527183">Prelis Desktop · KUPAC LLC</text>
  </g>
</svg>
`;

await writeFile(path.join(directory, 'featured-banner.svg'), svg);
const rendered = new Resvg(svg, { font: { loadSystemFonts: true } }).render();
await writeFile(path.join(directory, 'featured-banner.png'), rendered.asPng());
console.log('icon.png: 512x512; featured-banner.png: 1920x640');
