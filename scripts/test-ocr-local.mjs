// Testa o pipeline local de OCR (mesmo código do merge #27) sobre imagens sintéticas,
// sem empacotar o tesseract.js: card-image/parse-card são bundlados (TS puro) e o
// worker do Tesseract vem direto do node_modules com as mesmas opções do ocr-runtime.
// Uso: node /tmp/render/ocr/ocr-bundle.cjs <imagem> [mime]
import { preprocessCardImage } from '../server/card-image.ts';
import { parseCardText } from '../server/parse-card.ts';
import fs from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { mkdirSync } from 'node:fs';
import { createWorker } from 'tesseract.js';

const file = process.argv[2];
const mime = process.argv[3] || 'image/png';
const langPath = join(process.cwd(), 'api', 'langdata');
const cachePath = join(tmpdir(), 'tesseract-cache');
mkdirSync(cachePath, { recursive: true });

async function main() {
  const buffer = fs.readFileSync(file);

  console.log('===', file.split('/').pop(), mime, buffer.length, 'bytes ===');
  const processed = preprocessCardImage(buffer);
  console.log('preprocess:', processed ? `BMP ${processed.length} bytes` : 'null (usa original)');

  const worker = await createWorker('por', 1, { langPath, cachePath, gzip: false });
  try {
    // Mesma regra da API: melhor de duas passadas (original + processada).
    const passadas = processed ? [buffer, processed] : [buffer];
    let melhor = null;
    for (const src of passadas) {
      const { data } = await worker.recognize(src);
      const fields = parseCardText(data.text ?? '');
      const preenchidos = [fields.provider, fields.cardNumber, fields.name, fields.validity, fields.coverageType]
        .filter(Boolean).length;
      console.log(`--- passada (${passadas.length === 2 ? (src === processed ? 'processada' : 'original') : 'original'}) conf=${Math.round(data.confidence)} campos=${preenchidos} ---`);
      console.log(JSON.stringify({ provider: fields.provider, cardNumber: fields.cardNumber, name: fields.name, validity: fields.validity, coverageType: fields.coverageType, notes: fields.notes }));
      if (!melhor || preenchidos > melhor.preenchidos || (preenchidos === melhor.preenchidos && data.confidence > melhor.conf)) {
        melhor = { fields, preenchidos, conf: data.confidence };
      }
    }
    console.log('>>> VENCEDOR:', JSON.stringify({ provider: melhor.fields.provider, cardNumber: melhor.fields.cardNumber, name: melhor.fields.name, validity: melhor.fields.validity, coverageType: melhor.fields.coverageType }));
  } finally {
    await worker.terminate();
  }
}

main().catch((e) => { console.error('FALHA:', e.message); process.exit(1); });
