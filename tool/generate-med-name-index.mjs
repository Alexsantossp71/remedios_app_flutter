#!/usr/bin/env node
/**
 * Gera server/med-name-index.ts a partir de assets/data/medicine_catalog.json.
 *
 * O índice alimenta o parser de receituário (server/parse-receita.ts): uma
 * linha só abre medicamento quando carrega evidência real (dosagem,
 * apresentação, posologia) OU quando o nome casa com uma entrada da ANVISA.
 * Serve também para extrair o nome limpo — "ORAL TRAMAL COM REVL 1COMP"
 * reduz a "TRAMAL".
 *
 * Fonte única de verdade: o mesmo catálogo embarcado no app. Rode de novo
 * sempre que atualizar o catálogo:
 *
 *   node tool/generate-med-name-index.mjs
 */

import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
const catalogPath = join(repoRoot, 'assets/data/medicine_catalog.json');
const outPath = join(repoRoot, 'server/med-name-index.ts');

/** Maiúsculas sem acento, tokens alfanuméricos unidos por espaço simples. */
function foldKey(value) {
  const folded = value
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toUpperCase();
  const tokens = folded.match(/[A-Z0-9]+/g) ?? [];
  return tokens.join(' ');
}

/** Sais/veículos que prefixam princípios ativos ("cloridrato de metformina"). */
const SALT_WORDS = new Set([
  'ACETATO', 'ASCORBATO', 'BENZOATO', 'BESILATO', 'BICARBONATO', 'BISSULFATO',
  'BITARTRATO', 'BROMIDRATO', 'CAPRILATO', 'CARBONATO', 'CITRATO',
  'CLORIDRATO', 'ESTEARATO', 'ESTOLATO', 'FUMARATO', 'FOSFATO', 'GLUTAMATO',
  'HEMISSUCCINATO', 'HIDROBROMETO', 'HIDROCLORETO', 'HIDROTARTARATO',
  'IODIDRATO', 'IODETO', 'LACTATO', 'LACTOBIONATO', 'LAURILSULFATO',
  'MALEATO', 'MESILATO', 'NITRATO', 'OLEATO', 'OXALATO', 'PALMITATO',
  'PANTOTENATO', 'PIVALATO', 'PROPIONATO', 'SUCCINATO', 'SULFATO', 'TARTRATO',
  'TIOSULFATO', 'TOLFENAMATO', 'TROMETAMOL', 'VALERATO', 'DICLORIDRATO', 'DIFOSFATO', 'DE',
]);

/** Qualificadores que sufixam princípios ativos ("diclofenaco sodico"). */
const QUALIFIER_WORDS = new Set([
  'SODICA', 'SODICO', 'DISSODICA', 'DISSODICO', 'MONOSSODICA', 'MONOSSODICO',
  'POTASSICA', 'POTASSICO', 'CALCICA', 'CALCICO', 'MONOIDRATADA',
  'MONOIDRATADO', 'DIIDRATADA', 'DIIDRATADO', 'HIDRATADA', 'HIDRATADO',
  'ANIDRA', 'ANIDRO', 'BASE', 'DE',
  'CLORIDRATO', 'BESILATO', 'MALEATO', 'MESILATO', 'TARTRATO', 'FUMARATO',
  'SUCCINATO', 'HEMISSUCCINATO', 'OXALATO', 'BISSULFATO', 'DICLORIDRATO', 'DIFOSFATO',
]);

/** Corta sais do início e qualificadores do fim; devolve null se não mudou. */
function stripSaltVariants(tokens) {
  let start = 0;
  let end = tokens.length;
  while (start < end && SALT_WORDS.has(tokens[start])) start += 1;
  while (end > start && QUALIFIER_WORDS.has(tokens[end - 1])) end -= 1;
  if (start >= end) return null;
  const stripped = tokens.slice(start, end);
  if (stripped.length === tokens.length) return null;
  return stripped;
}

const catalog = JSON.parse(readFileSync(catalogPath, 'utf8'));
const items = catalog.items ?? [];

const keys = new Set();
let maxTokens = 1;

function addKey(text) {
  const key = foldKey(text);
  if (!key) return;
  const tokens = key.split(' ');
  keys.add(key);
  if (tokens.length > maxTokens) maxTokens = tokens.length;
  const stripped = stripSaltVariants(tokens);
  if (stripped && stripped.length) {
    const strippedKey = stripped.join(' ');
    keys.add(strippedKey);
    if (stripped.length > maxTokens) maxTokens = stripped.length;
  }
}

for (const item of items) {
  if (typeof item.name === 'string' && item.name.trim()) {
    addKey(item.name.trim());
  }
  const pa = typeof item.activeIngredient === 'string' ? item.activeIngredient : '';
  if (!pa.trim()) continue;
  // Associações vêm separadas por vírgula ou "+": cada componente é um nome
  // que pode aparecer sozinho na receita.
  for (const part of pa.split(/[,+;]/)) {
    const component = part.trim();
    if (component) addKey(component);
  }
}

const sorted = [...keys].sort((a, b) => a.localeCompare(b));
const body = sorted.map((key) => `  '${key}',`).join('\n');
const generatedAt = new Date().toISOString().slice(0, 10);

const source = `// GERADO por tool/generate-med-name-index.mjs a partir de
// assets/data/medicine_catalog.json (${items.length} registros da ANVISA).
// Não editar à mão — rode "node tool/generate-med-name-index.mjs".
// ${sorted.length} chaves fold (maiúsculas sem acento) · gerado em ${generatedAt}
export const MED_NAME_MAX_TOKENS = ${maxTokens};
export const MED_NAMES: ReadonlySet<string> = new Set([
${body}
]);
`;

writeFileSync(outPath, source);
console.log(`Registros lidos: ${items.length}`);
console.log(`Chaves no índice: ${sorted.length}`);
console.log(`Máximo de tokens por nome: ${maxTokens}`);
console.log(`Tamanho do arquivo: ${(source.length / 1024).toFixed(0)} KB`);
console.log(`Escrito: ${outPath}`);
