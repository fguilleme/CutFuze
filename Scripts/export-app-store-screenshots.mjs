import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

// Export xcresulttool attachments without changing a pixel of the screenshots.
const [source, destination, device] = process.argv.slice(2);
const screenshotSizes = {
  iPhone: [1320, 2868],
  'iPhone-6.3': [1206, 2622],
  iPad: [2064, 2752],
};
if (!source || !destination || !Object.hasOwn(screenshotSizes, device)) {
  throw new Error('Usage: node Scripts/export-app-store-screenshots.mjs ATTACHMENTS OUTPUT iPhone|iPhone-6.3|iPad');
}
const dimensions = screenshotSizes[device];
const manifest = JSON.parse(fs.readFileSync(path.join(source, 'manifest.json'), 'utf8'));
const captured = [];
for (const test of manifest) {
  for (const attachment of test.attachments) {
    const match = attachment.suggestedHumanReadableName.match(/^(fr|en)-(0[1-6])-(montage|texte|effets|animation|multiformat|modeles)_/);
    if (!match) continue;
    const bytes = fs.readFileSync(path.join(source, attachment.exportedFileName));
    if (bytes.subarray(0, 8).toString('hex') !== '89504e470d0a1a0a') throw new Error('Expected PNG');
    const width = bytes.readUInt32BE(16), height = bytes.readUInt32BE(20), colorType = bytes[25];
    if (width !== dimensions[0] || height !== dimensions[1]) throw new Error(`Unexpected dimensions: ${width} × ${height}`);
    if ([4, 6].includes(colorType)) throw new Error('Screenshot contains an alpha channel');
    for (let cursor = 8; cursor < bytes.length;) {
      const length = bytes.readUInt32BE(cursor), kind = bytes.subarray(cursor + 4, cursor + 8).toString('ascii');
      if (kind === 'tRNS') throw new Error('Screenshot contains transparency');
      cursor += 12 + length;
    }
    const folder = path.join(destination, device, match[1]);
    fs.mkdirSync(folder, { recursive: true });
    const filename = `${match[2]}-${match[3]}.png`;
    fs.copyFileSync(path.join(source, attachment.exportedFileName), path.join(folder, filename));
    captured.push({ language: match[1], filename, width, height, alpha: false, sha256: crypto.createHash('sha256').update(bytes).digest('hex'), sourceTest: test.testIdentifier });
  }
}
if (captured.length !== 12) throw new Error(`Expected 12 screenshots; found ${captured.length}`);
for (const language of ['fr', 'en']) {
  if (new Set(captured.filter(item => item.language === language).map(item => item.filename)).size !== 6) throw new Error(`Incomplete ${language} set`);
}
fs.writeFileSync(path.join(destination, device, 'manifest.json'), JSON.stringify({ device, dimensions, screenshots: captured }, null, 2) + '\n');
console.log(`${device}: ${captured.length} native PNG screenshots validated (${dimensions.join(' × ')}, no alpha).`);
