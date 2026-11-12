// Mostra o texto cru do Tesseract para diagnóstico.
// Uso: node node_modules/.cache/ocr-test-bundle.cjs <imagem> [mime]
import fs from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { mkdirSync } from 'node:fs';
import { createWorker } from 'tesseract.js';
import { preprocessCardImage } from '../server/card-image.ts';

const file = process.argv[2];
const langPath = join(process.cwd(), 'api', 'langdata');
const cachePath = join(tmpdir(), 'tesseract-cache');
mkdirSync(cachePath, { recursive: true });

async function main() {
  const buffer = fs.readFileSync(file);
  const processed = preprocessCardImage(buffer);
  const worker = await createWorker('por', 1, { langPath, cachePath, gzip: false });
  try {
    const { data } = await worker.recognize(processed ?? buffer);
    console.log('=== RAW ===');
    console.log(data.text);
  } finally {
    await worker.terminate();
  }
}

main().catch((e) => { console.error('FALHA:', e.message); process.exit(1); });
