/**
 * Reempacota os handlers que a Vercel gerou como CommonJS.
 *
 * O problema: `vercel build` emite o bundle da função em ESM (o arquivo sai
 * com `import ... from`), mas a Lambda carrega /var/task/*.js como CommonJS.
 * O Node morre antes do handler rodar:
 *
 *   /var/task/api/read-card.js:20
 *   import { createWorker } from 'tesseract.js';
 *   SyntaxError: Cannot use import statement outside a module
 *
 * Isso é 500 em toda requisição, com o corpo genérico e sem causa aparente.
 *
 * Por que não resolver com "type": "module" no package.json: esse campo é
 * copiado para /var/task/package.json e vira o tipo de módulo de TODO o
 * diretório da função, incluindo o launcher e os helpers que a plataforma
 * injeta. O sintoma piora — a função de sondagem, que não importa nada,
 * também deixa de responder. Formato de módulo do bundle é problema do
 * bundle, não do projeto inteiro.
 *
 * Como o deploy é --prebuilt, o artefato publicado é exatamente o que está
 * em .vercel/output/functions. Reescrever o handler ali dá controle total
 * sobre o formato sem tocar no runtime.
 *
 * `packages: 'external'` é obrigatório: o tesseract.js-core localiza o WASM
 * por caminho relativo ao próprio pacote, e embutir o pacote no bundle
 * quebraria essa resolução. As dependências continuam saindo do
 * node_modules que a Vercel já empacota.
 */

import { build } from 'esbuild';
import { existsSync, readdirSync, readFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';

const FUNCS_DIR = '.vercel/output/functions';

// Deixa o módulo exportado ser a função em si, além de `.default`/`.handler`.
// O launcher da plataforma pode procurar qualquer um dos três; servir os três
// remove uma classe inteira de falha sem precisar ver o código do launcher.
const FOOTER = `
;(function () {
  var exp = module.exports;
  var fn = exp && typeof exp.default === 'function'
    ? exp.default
    : typeof exp === 'function' ? exp : null;
  if (!fn) return;
  fn.default = fn;
  fn.handler = fn;
  if (exp && exp.config) fn.config = exp.config;
  module.exports = fn;
})();
`;

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

function readJson(file) {
  try {
    return JSON.parse(readFileSync(file, 'utf8'));
  } catch {
    return {};
  }
}

/** `api/read-card.js` no artefato vem de `api/read-card.ts` no repositório. */
function findSource(handlerRel) {
  const base = handlerRel.replace(/\.(js|mjs|cjs)$/, '');
  for (const ext of ['.ts', '.js', '.mjs']) {
    if (existsSync(base + ext)) return base + ext;
  }
  return null;
}

if (!existsSync(FUNCS_DIR)) {
  console.error(`ERRO: ${FUNCS_DIR} não existe — rode depois de \`vercel build\`.`);
  process.exit(1);
}

const funcDirs = findFuncDirs(FUNCS_DIR);
if (funcDirs.length === 0) {
  console.error(`ERRO: nenhuma pasta *.func em ${FUNCS_DIR}.`);
  process.exit(1);
}

console.log(`Reempacotando ${funcDirs.length} função(ões) como CommonJS.`);

let failures = 0;

for (const funcDir of funcDirs) {
  const name = funcDir.split(/[\\/]/).slice(-2, -1)[0];
  const vc = readJson(join(funcDir, '.vc-config.json'));
  const handlerRel = vc.handler;

  if (!handlerRel) {
    console.error(`[${name}] sem "handler" em .vc-config.json — pulando.`);
    failures += 1;
    continue;
  }

  const source = findSource(handlerRel);
  if (!source) {
    console.error(`[${name}] não achei o fonte para ${handlerRel} — pulando.`);
    failures += 1;
    continue;
  }

  const outfile = join(funcDir, handlerRel);
  const before = existsSync(outfile) ? readFileSync(outfile).length : 0;

  try {
    await build({
      entryPoints: [source],
      outfile,
      bundle: true,
      platform: 'node',
      target: 'node20',
      format: 'cjs',
      packages: 'external',
      sourcemap: false,
      footer: { js: FOOTER },
      logLevel: 'silent',
    });
  } catch (err) {
    failures += 1;
    console.error(`[${name}] esbuild falhou: ${err.message}`);
    continue;
  }

  // Sourcemap do bundle antigo descreve um arquivo que não existe mais, e o
  // runtime tenta usá-lo quando shouldAddSourcemapSupport está ligado.
  const staleMap = `${outfile}.map`;
  if (existsSync(staleMap)) rmSync(staleMap, { force: true });

  const emitted = readFileSync(outfile, 'utf8');
  const stillEsm = /^\s*(import[\s{]|export[\s{])/m.test(emitted);

  console.log(
    `[${name}] ${source} -> ${handlerRel}  ${before}b -> ${emitted.length}b  ` +
      `sintaxe ESM restante: ${stillEsm ? 'SIM (ERRO)' : 'não'}`,
  );
  if (stillEsm) failures += 1;
}

if (failures > 0) {
  console.error(`\n${failures} função(ões) não foram reempacotadas.`);
  process.exit(1);
}

console.log('\nHandlers reempacotados em CommonJS.');