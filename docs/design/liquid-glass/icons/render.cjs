const fs = require('node:fs');
const path = require('node:path');
const sharp = require('sharp');

async function render() {
  const svg = fs.readFileSync(path.join(__dirname, 'combo-app-icon.svg'));
  const catalog = path.resolve(__dirname, '../../../../Combo/App/Media.xcassets/AppIcon.appiconset');
  const { images } = JSON.parse(fs.readFileSync(path.join(catalog, 'Contents.json'), 'utf8'));
  for (const { filename, size, scale } of images) {
    const pixels = parseInt(size, 10) * parseInt(scale, 10);
    await sharp(svg).resize(pixels, pixels).png().toFile(path.join(catalog, filename));
  }
  fs.copyFileSync(path.join(catalog, 'icon_512x512@2x.png'), path.join(__dirname, 'combo-app-icon.png'));
  const icon = 'data:image/svg+xml;base64,' + svg.toString('base64');
  const image = (x, y, size) => `<image x="${x}" y="${y}" width="${size}" height="${size}" href="${icon}"/>`;
  const preview = `<svg xmlns="http://www.w3.org/2000/svg" width="1440" height="950" viewBox="0 0 1440 950">
    <rect width="1440" height="950" fill="#edf1f7"/>
    <text x="72" y="82" font-family="Helvetica Neue,sans-serif" font-size="34" font-weight="600" fill="#20252d">Combo</text>
    <text x="72" y="119" font-family="PingFang SC,sans-serif" font-size="18" fill="#414b59">Wi-Fi、电池、声音，聚合为一。</text>
    <rect x="48" y="158" width="660" height="500" rx="28" fill="#f7f9fc"/>
    <rect x="732" y="158" width="660" height="500" rx="28" fill="#282e38"/>
    ${image(174, 194, 408)}${image(858, 194, 408)}
    <text x="378" y="622" text-anchor="middle" font-family="PingFang SC,sans-serif" font-size="16" fill="#414b59">浅色背景</text>
    <text x="1062" y="622" text-anchor="middle" font-family="PingFang SC,sans-serif" font-size="16" fill="#d2d9e5">深色背景</text>
    ${[16, 32, 64, 128, 256].map((size, i) => {
      const center = [120, 295, 500, 755, 1120][i];
      return image(center - size / 2, 795 - size / 2, size) + `<text x="${center}" y="916" text-anchor="middle" font-family="Helvetica Neue,sans-serif" font-size="15" fill="#414b59">${size} px</text>`;
    }).join('')}
  </svg>`;
  await sharp(Buffer.from(preview)).png().toFile(path.join(__dirname, 'preview.png'));
  const metadata = await sharp(path.join(__dirname, 'combo-app-icon.png')).metadata();
  if (metadata.width !== 1024 || metadata.height !== 1024 || !metadata.hasAlpha) throw new Error('Invalid icon dimensions or transparency');
  const { data, info } = await sharp(path.join(__dirname, 'combo-app-icon.png')).raw().toBuffer({ resolveWithObject: true });
  for (const [x, y] of [[512, 227], [512, 422], [355, 680]]) {
    const offset = (y * info.width + x) * info.channels;
    if (Math.min(...data.subarray(offset, offset + 3)) < 200 || data[offset + 3] !== 255) throw new Error('Power arc, Wi-Fi or music columns are missing');
  }
}
render().catch(error => { console.error(error); process.exitCode = 1; });
