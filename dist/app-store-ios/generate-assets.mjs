import { copyFile, mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { crc32, deflateSync } from "node:zlib";
import { Resvg } from "@resvg/resvg-js";

const root = path.dirname(fileURLToPath(import.meta.url));
const rawScreenshots =
  process.argv[2] === "--screenshots" && process.argv.length === 4
    ? path.resolve(process.argv[3])
    : null;
if (process.argv.length > 2 && !rawScreenshots)
  throw new Error(
    "Usage: generate-assets.mjs [--screenshots <capture directory>]"
  );
const icons = path.resolve(root, "../../packages/icons/assets");
const uri = async (name) =>
  `data:image/png;base64,${(
    await readFile(path.join(icons, `${name}.png`))
  ).toString("base64")}`;
const logo = await uri("brand");
const features = await Promise.all(
  [
    ["diary", "日記", 230],
    ["timer", "タイマー", 300],
    ["password", "パスワード生成", 430],
  ].map(async ([name, label, width]) => ({
    image: await uri(name),
    label,
    width,
  }))
);

function chunk(type, data) {
  const body = Buffer.concat([Buffer.from(type), data]);
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const checksum = Buffer.alloc(4);
  checksum.writeUInt32BE(crc32(body));
  return Buffer.concat([length, body, checksum]);
}
// App Store creative assets must be opaque RGB PNGs, without an alpha channel.
function rgbPng(rendered) {
  const { width, height, pixels } = rendered;
  const stride = width * 3 + 1;
  const rows = Buffer.alloc(stride * height);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const source = (y * width + x) * 4;
      if (pixels[source + 3] !== 255)
        throw new Error("Opaque artwork required");
      pixels.copy(rows, y * stride + 1 + x * 3, source, source + 3);
    }
  }
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = 2;
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk("IHDR", header),
    chunk("IDAT", deflateSync(rows)),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

if (!rawScreenshots) {
  await mkdir(path.join(root, "creative"), { recursive: true });
  await copyFile(
    path.resolve(
      root,
      "../../apps/mobile/ios/PrelisMobile/Images.xcassets/AppIcon.appiconset/AppIcon.png"
    ),
    path.join(root, "icon.png")
  );
  for (const [name, width, height] of [
    ["header-wide", 3840, 1646],
    ["header-universal", 5244, 2950],
    ["search-results", 3840, 2560],
  ]) {
    const logicalHeight = (height / width) * 1600;
    let x = 0;
    const featureArt = features
      .map((feature) => {
        const art = `<g transform="translate(${x} 0)"><rect width="${feature.width}" height="84" rx="16" fill="#FFFFFF" stroke="#D5E6EC"/><image href="${feature.image}" x="26" y="22" width="40" height="40" filter="url(#accent)"/><text x="84" y="54" font-size="29" font-weight="500">${feature.label}</text></g>`;
        x += feature.width + 24;
        return art;
      })
      .join("");
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 1600 ${logicalHeight}">
<defs><filter id="accent" color-interpolation-filters="sRGB"><feColorMatrix type="matrix" values="0 0 0 0 0.0431 0 0 0 0 0.4706 0 0 0 0 0.6039 0 0 0 1 0"/></filter></defs>
<rect width="1600" height="${logicalHeight}" fill="#F8FCFE"/>
<circle cx="1430" cy="${logicalHeight / 2}" r="350" fill="#E4F7FC"/>
<circle cx="1460" cy="${
      logicalHeight / 2 - 20
    }" r="224" fill="none" stroke="#D5E6EC" stroke-width="2"/>
<g transform="translate(285 ${
      logicalHeight / 2 - 190
    })" fill="#183446" font-family="Noto Sans CJK JP, sans-serif">
<image href="${logo}" x="0" y="0" width="78" height="78"/>
<text x="102" y="62" font-size="66" font-weight="700" letter-spacing="-2">prelis<tspan fill="#0B789A">.</tspan></text>
<text x="0" y="220" font-size="79" font-weight="700" letter-spacing="-2">毎日を、軽やかに。</text>
<g transform="translate(0 294)">${featureArt}</g>
</g></svg>\n`;
    await writeFile(path.join(root, "creative", `${name}.svg`), svg);
    const rendered = new Resvg(svg, {
      font: { loadSystemFonts: true },
    }).render();
    await writeFile(
      path.join(root, "creative", `${name}.png`),
      rgbPng(rendered)
    );
    console.log(`${name}: ${width}x${height}, RGB`);
  }
} else {
  for (const [device, width, height] of [
    ["iphone", 1206, 2622],
    ["ipad", 2064, 2752],
  ]) {
    await mkdir(path.join(root, "screenshots", device), { recursive: true });
    for (const name of ["01-diary", "02-timer", "03-password", "04-home"]) {
      const raw = await readFile(
        path.join(rawScreenshots, device, `${name}.png`)
      );
      if (raw.readUInt32BE(16) !== width || raw.readUInt32BE(20) !== height)
        throw new Error(`Unexpected screenshot size: ${device}/${name}`);
      const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}"><rect width="100%" height="100%" fill="#FFFFFF"/><image href="data:image/png;base64,${raw.toString(
        "base64"
      )}" width="${width}" height="${height}"/></svg>`;
      await writeFile(
        path.join(root, "screenshots", device, `${name}.png`),
        rgbPng(new Resvg(svg).render())
      );
      console.log(`${device}/${name}: ${width}x${height}, RGB`);
    }
  }
  await copyFile(
    path.join(rawScreenshots, "capture-report.json"),
    path.join(root, "capture-report.json")
  );
}
