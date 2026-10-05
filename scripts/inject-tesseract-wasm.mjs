#!/usr/bin/env node
/**
 * Copia os binários .wasm do tesseract.js-core para dentro do bundle da função.
 *
 * Por que isso é necessário e não dá para resolver com includeFiles:
 *
 * O tracer de arquivos da Vercel empacota o que o bundle IMPORTA. Do
 * tesseract.js-core ele leva os .js (o loader), porque são eles que o
 * require() enxerga. O .wasm não é importado por ninguém — ele é lido em
 * tempo de execução, por fetch, quando o worker é criado. Resultado: o
 * artefato tinha o loader de 89 KB e nenhum binário, e em produção:
 *
 *   failed to asynchronously prepare wasm: ENOENT ...
 *     /var/task/node_modules/tesseract.js-core/tesseract-core-relaxedsimd.wasm
 *   RuntimeError: Aborted(...)  ->  502 "unreadable"
 *
 * includeFiles não resolve: o padrão "node_modules/tesseract.js-core/*.wasm"
 * é aceito no vercel.json sem erro e simplesmente não casa com nada — os
 * arquivos de dependência ficam fora do alcance dele. Confirmado pelo gate,
 * que reportou "tesseract.js-core: 0 .wasm" com o glob no lugar.
 *
 * Como o deploy é --prebuilt, o artefato publicado é literalmente o que está
 * em .vercel/output/functions. Então a cópia é feita ali, depois do
 * `vercel build` e antes do gate — que valida exatamente os bytes que vão
 * subir, e falha o deploy se algum .wasm faltar.
 */

import { readdirSync, existsSync, copyFileSync, mkdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

const SOURCE_DIR = join('node_modules', 'tesseract.js-core');
const FUNCS_DIR = join('.vercel', 'output', 'functions');

let failures = 0;

if (!existsSync(SOURCE_DIR)) {
  console.error(`[inject:wasm] node_modules/tesseract.js-core ausente — rode npm ci antes.`);
  process.exit(1);
}

const wasms = readdirSync(SOURCE_DIR).filter((f) => f.endsWith('.wasm'));

if (wasms.length === 0) {
  console.error(`[inject:wasm] nenhum .wasm em ${SOURCE_DIR} — o pacote está corrompido?`);
  process.exit(1);
}

const totalBytes = wasms.reduce(
  (sum, f) => sum + statSync(join(SOURCE_DIR, f)).size,
  0,
);
console.log(
  `[inject:wasm] origem: ${wasms.length} .wasm em ${SOURCE_DIR} ` +
    `(${(totalBytes / 1e6).toFixed(1)} MB)`,
);

if (!existsSync(FUNCS_DIR)) {
  console.error(`[inject:wasm] ${FUNCS_DIR} não existe — o "vercel build" não rodou?`);
  process.exit(1);
}

// Só as funções que realmente tracem o tesseract.js-core precisam do binário.
// Descobrir pelo próprio artefato evita assumir o nome read-card.func e
// funciona se a Vercel mudar o nome do diretório.
const targets = readdirSync(FUNCS_DIR, { withFileTypes: true })
  .filter((e) => e.isDirectory() && e.name.endsWith('.func'))
  .map((e) => e.name)
  .filter((name) => existsSync(join(FUNCS_DIR, name, 'node_modules', 'tesseract.js-core')));

if (targets.length === 0) {
  failures += 1;
  console.error(`\n[inject:wasm] *** NENHUMA FUNÇÃO COM tesseract.js-core NO ARTEFATO ***`);
  console.error(`[inject:wasm] Esperado ao menos uma função com OCR. Verifique o vercel.json.`);
  process.exit(1);
}

for (const name of targets) {
  const destDir = join(FUNCS_DIR, name, 'node_modules', 'tesseract.js-core');
  mkdirSync(destDir, { recursive: true });

  const copied = [];
  for (const file of wasms) {
    copyFileSync(join(SOURCE_DIR, file), join(destDir, file));
    copied.push(file);
  }

  // Confere o resultado no disco, e não a intenção: o gate vem depois e
  // falharia com "NENHUM .wasm", mas o erro aqui é mais direto.
  const landed = readdirSync(destDir).filter((f) => f.endsWith('.wasm'));
  if (landed.length !== wasms.length) {
    failures += 1;
    console.error(`\n[inject:wasm] *** CÓPIA INCOMPLETA EM ${name} ***`);
    console.error(`[inject:wasm] esperado ${wasms.length}, no disco ${landed.length}`);
    continue;
  }

  console.log(`[inject:wasm] ${name}: ${landed.length} .wasm injetados -> ${destDir}`);
  console.log(`[inject:wasm] ${name}:   ${copied.join(', ')}`);
}

if (failures > 0) {
  console.error(`\n[inject:wasm] falha em ${failures} função(ões).`);
  process.exit(1);
}

console.log('[inject:wasm] ok');