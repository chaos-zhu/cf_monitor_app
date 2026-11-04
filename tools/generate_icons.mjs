// Run from any directory. Requires sharp (npm install --prefix /tmp/cf-artwork sharp).
// SHARP_MODULE may point to an existing sharp installation.
import { createRequire } from 'node:module';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const require = createRequire(import.meta.url);
const sharp = require(process.env.SHARP_MODULE || 'sharp');
const root = fileURLToPath(new URL('../', import.meta.url));
const source = await readFile(path.join(root, 'assets/branding/logo.svg'), 'utf8');
const backgroundColors = [...source.matchAll(/<stop[^>]+stop-color="([^"]+)"/g)].map(match => match[1]);
if (backgroundColors.length !== 2) throw new Error('Expected two background gradient stops.');
const save = async (name, data) => {
  const target = path.join(root, name);
  await mkdir(path.dirname(target), { recursive: true });
  await writeFile(target, data);
};
const png = (size, input = source) => sharp(Buffer.from(input), { density: 288 })
  .resize(size, size).removeAlpha().png().toBuffer();

await save('assets/branding/logo.png', await png(1024));
for (const [density, size] of Object.entries({ mdpi: 48, hdpi: 72, xhdpi: 96, xxhdpi: 144, xxxhdpi: 192 })) {
  // Legacy launchers receive a rounded tile with transparent corners.
  const rounded = source.replace('<path fill="url(#background)" d="M0 0h1024v1024H0z"/>',
    '<rect width="1024" height="1024" rx="224" fill="url(#background)"/>');
  await save(`android/app/src/main/res/mipmap-${density}/ic_launcher.png`,
    await sharp(Buffer.from(rounded), { density: 288 }).resize(size, size).png().toBuffer());
}
const iconset = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
const contents = JSON.parse(await readFile(path.join(root, iconset, 'Contents.json'), 'utf8'));
for (const item of contents.images) {
  const size = Math.round(parseFloat(item.size) * parseFloat(item.scale));
  await save(`${iconset}/${item.filename}`, await png(size));
}

// Use the same paths as the SVG for adaptive and Android 13 themed icons.
const paths = [...source.matchAll(/<path d="([^"]+)"\s+fill="none" stroke="([^"]+)" stroke-width="([^"]+)"/g)];
if (paths.length !== 2) throw new Error('Unexpected logo paths; update the vector exporter.');
const dot = source.match(/<circle cx="([^"]+)" cy="([^"]+)" r="([^"]+)" fill="([^"]+)"/);
if (!dot) throw new Error('Missing status light.');
function vector(monochrome) {
  const strokes = paths.map(([, d, color, width]) =>
    `        <path android:pathData="${d}" android:fillColor="@android:color/transparent" android:strokeColor="${monochrome ? '#ffffff' : color}" android:strokeWidth="${width}" android:strokeLineCap="round" android:strokeLineJoin="round"/>`).join('\n');
  const [, x, y, radius, color] = dot;
  const circle = `M${+x-radius},${y}a${radius},${radius} 0,1 0,${radius*2} 0a${radius},${radius} 0,1 0,-${radius*2} 0`;
  return `<?xml version="1.0" encoding="utf-8"?>\n<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="1024" android:viewportHeight="1024">\n${strokes}\n        <path android:pathData="${circle}" android:fillColor="${monochrome ? '#ffffff' : color}"/>\n</vector>\n`;
}
await save('android/app/src/main/res/drawable/ic_launcher_foreground.xml', vector(false));
await save('android/app/src/main/res/drawable/ic_launcher_monochrome.xml', vector(true));
await save('android/app/src/main/res/drawable/ic_launcher_background.xml', `<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <gradient android:angle="315" android:startColor="${backgroundColors[0]}" android:endColor="${backgroundColors[1]}"/>
</shape>
`);
for (const version of [26, 33]) {
  await save(`android/app/src/main/res/mipmap-anydpi-v${version}/ic_launcher.xml`, `<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background"/>
    <foreground android:drawable="@drawable/ic_launcher_foreground"/>
${version >= 33 ? '    <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>\n' : ''}</adaptive-icon>
`);
}
console.log('Generated brand PNG, Android legacy/adaptive/themed icons, and all iOS icon sizes.');
