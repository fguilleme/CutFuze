import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve('CutFuze');
const files = fs.readdirSync(root, { recursive: true }).filter(p => p.endsWith('.swift'));
const literal = '"((?:\\\\.|[^"\\\\])*)"';
const catalog = new Set();
for (const name of ['UI/DesignSystem.swift', 'UI/LocalizationExtra.swift', 'UI/LocalizationEnglish.swift']) {
  if (!fs.existsSync(path.join(root, name))) continue;
  for (const m of fs.readFileSync(path.join(root, name), 'utf8').matchAll(new RegExp(literal + '\\s*:', 'g'))) catalog.add(m[1]);
}
let missing = 0;
const seen = new Set();
const candidates = new Set();
for (const file of files) {
  if (file.includes('Localization') || file === 'UI/DesignSystem.swift') continue;
  const source = fs.readFileSync(path.join(root, file), 'utf8');
  if (process.argv.includes('--errors')) {
    for (const m of source.matchAll(new RegExp('\\b(?:DocumentError|MediaFailure)\\.\\w+\\(' + literal, 'g'))) {
      if (!m[1].includes('\\(') && !catalog.has(m[1]) && !seen.has(m[1])) { seen.add(m[1]); missing++; console.log(`ERROR ${file}: ${m[1]}`); }
    }
  }
  const inline = new Set([...source.matchAll(new RegExp('\\bSL\\(' + literal + '\\s*,', 'g'))].map(m => m[1]));
  if (process.argv.includes('--candidates')) {
    for (const m of source.matchAll(new RegExp(literal, 'g'))) {
      if (/[À-ÖØ-öø-ÿ]|\b(?:les|des|une|pour|sans|avec|sur|du|dans|Ajouter|Modifier|Supprimer|Police|Fond|Texte|Son|Scène|Piste|Projet|Exporter)\b/.test(m[1]) && !catalog.has(m[1]) && !inline.has(m[1]) && !candidates.has(m[1])) {
        candidates.add(m[1]); console.log(`CANDIDATE ${file}: ${m[1]}`);
      }
    }
  }
  for (const m of source.matchAll(new RegExp('\\bL\\(' + literal + '\\)', 'g'))) {
    if (!catalog.has(m[1]) && !seen.has(m[1])) { seen.add(m[1]); missing++; console.log(`MISSING ${file}: ${m[1]}`); }
  }
  if (process.argv.includes('--raw')) {
    for (const m of source.matchAll(new RegExp('\\b(?:Text|Label|Button|TextField|Toggle|Picker|Section|navigationTitle|accessibilityLabel)\\(' + literal, 'g'))) {
      if (/[À-ÿ]|\b(?:les|des|une|pour|sans|avec|sur|du|dans|Ajouter|Modifier|Supprimer|Police|Fond|Texte|Son|Scène|Format|Piste|Projet|Exporter)\b/.test(m[1])) console.log(`RAW ${file}: ${m[1]}`);
    }
  }
}
console.log(`Static L keys missing English: ${missing}`);
if (missing && process.argv.includes('--check')) process.exitCode = 1;
