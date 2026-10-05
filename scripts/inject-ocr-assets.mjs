#!/usr/bin/env node
/**
 * Copia para dentro do bundle da função os arquivos que o Tesseract só lê em
 * tempo de execução: os binários .wasm e o modelo de português.
 *
 * Por que nenhum dos dois vem no bundle sozinho:
 *
 * O tracer da Vercel empacota o que o bundle IMPORTA. Do tesseract.js-core ele
 * leva os .js (o loader de 89 KB), porque são eles que o require() enxerga.
 * O .wasm não é importado por ninguém — é buscado por fetch no momento em que
 * o worker é criado. E o .traineddata também não é importado: é só lido do
 * disco pelo langPath. Nenhum dos dois é rastreado, e nenhum dos dois quebra
 * o build — eles só faltam em produção:
 *
 *   failed to asynchronously prepare wasm: ENOENT ...
 *     /var/task/node_modules/tesseract.js-core/tesseract-core-relaxedsimd.wasm
 *   RuntimeError: Aborted(...)  ->  502 "unreadable"
 *
 * includeFiles não resolve nenhum dos dois. O padrão
 * "node_modules/tesseract.js-core/*.wasm" é aceito no vercel.json sem erro e
 * não casa com nada — o gate chegou a reportar "tesseract.js-core: 0 .wasm"
 * com o glob no lugar. O mesmo vale para "api/langdata/*.traineddata": o
 * vercel.json é aceito, o build passa, e o arquivo não está no artefato. Os
 * dois juntos, com expansão de chaves, também nada. Então a chave foi removida
 * do vercel.json em vez de continuar sugerindo que ela funciona.
 *
 * Como o deploy é --prebuilt, o artefato publicado é literalmente o que está em
 * .vercel/output/functions. A cópia é feita ali, depois do `vercel build` e
 * antes do gate — que valida exatamente os bytes que vão subir e barra o
 * deploy se faltar qualquer um.
 */

import { readdirSync, existsSync, copyFileSync, mkdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

const WASM_SOURCE = join('node_modules', 'tesseract.js-core');
const LANG_SOURCE = join('api', 'langdata');
const FUNCS_DIR = join('.vercel', 'output', 'functions');

let failures = 0;

function fail(message) {
  failures += 1;
  console.error(`[inject:ocr-assets] ${message}`);
}

function listFiles(dir, ext) {
  return readdirSync(dir).filter((f) => f.endsWith(ext));
}

function copyInto(destDir, files, sourceDir, ext) {
  mkdirSync(destDir, { recursive: true });
  for (const file of files) copyFileSync(join(sourceDir, file), join(destDir, file));
  // Confere o resultado no disco, e não a intenção: o gate vem depois e falharia
  // com uma mensagem genérica, mas o erro aqui aponta o arquivo exato.
  const landed = listFiles(destDir, ext);
  if (landed.length !== files.length) {
    fail(`cópia incompleta em ${destDir}: esperado ${files.length}, no disco ${landed.length}`);
    return false;
  }
  return true;
}

function findFuncDirs(dir) {
  const found = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const full = join(dir, entry.name);
    if (entry.name.endsWith('.func')) found.push(full);
    else found.push(...findFuncDirs(full));
  }
  return found;
}

const wasms = existsSync(WASM_SOURCE) ? listFiles(WASM_SOURCE, '.wasm') : [];
const models = existsSync(LANG_SOURCE) ? listFiles(LANG_SOURCE, '.traineddata') : [];

if (wasms.length === 0) fail(`nenhum .wasm em ${WASM_SOURCE} — rode npm ci antes.`);
if (models.length === 0) fail(`nenhum .traineddata em ${LANG_SOURCE}.`);
if (failures > 0) process.exit(1);

const wasmBytes = wasms.reduce((n, f) => n + statSync(join(WASM_SOURCE, f)).size, 0);
console.log(
  `[inject:ocr-assets] origem: ${wasms.length} .wasm (${(wasmBytes / 1e6).toFixed(1)} MB) ` +
    `+ ${models.length} .traineddata`,
);

if (!existsSync(FUNCS_DIR)) {
  console.error(`[inject:ocr-assets] ${FUNCS_DIR} não existe — o "vercel build" não rodou?`);
  process.exit(1);
}

// Só as funções que realmente tracem o tesseract.js-core precisam dos assets.
// Descobrir pelo próprio artefato evita assumir o nome read-card.func. A busca
// é recursiva porque a Vercel emite as funções aninhadas
// (functions/api/read-card.func) — é o mesmo motivo de
// package-cjs-functions.mjs recursar.
const targets = findFuncDirs(FUNCS_DIR).filter((dir) =>
  existsSync(join(dir, 'node_modules', 'tesseract.js-core')),
);

if (targets.length === 0) {
  console.error(`\n[inject:ocr-assets] *** NENHUMA FUNÇÃO COM tesseract.js-core NO ARTEFATO ***`);
  console.error(`[inject:ocr-assets] Esperado ao menos uma função com OCR.`);
  process.exit(1);
}

for (const funcDir of targets) {
  const name = funcDir.split(/[\\/]/).pop();

  const wasmOk = copyInto(
    join(funcDir, 'node_modules', 'tesseract.js-core'),
    wasms,
    WASM_SOURCE,
    '.wasm',
  );
  const modelOk = copyInto(join(funcDir, LANG_SOURCE), models, LANG_SOURCE, '.traineddata');

  if (wasmOk && modelOk) {
    console.log(
      `[inject:ocr-assets] ${name}: ${wasms.length} .wasm + ${models.length} .traineddata injetados`,
    );
  }
}

if (failures > 0) {
  console.error(`\n[inject:ocr-assets] ${failures} falha(s).`);
  process.exit(1);
}

console.log('[inject:ocr-assets] ok');