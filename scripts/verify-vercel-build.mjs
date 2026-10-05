/**
 * Carrega o artefato da função exatamente como a Vercel o empacotou e falha
 * se ele não carregar.
 *
 * Por que isto existe: `vercel build` e `vercel deploy` terminam com
 * "sucesso" mesmo quando a função está quebrada — o deploy só publica os
 * arquivos. O breakage só aparece em runtime, como 500
 * FUNCTION_INVOCATION_FAILED sem nenhuma mensagem útil no corpo da
 * resposta. Como o token da Vercel só existe no CI, este passo roda lá:
 * tenta require() no launcher gerado e imprime o erro de verdade, com
 * stack, no log do run.
 *
 * Sem ele, cada hipótese sobre a causa do 500 custa um deploy completo.
 */

import { readdirSync, readFileSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';

const FUNCS_DIR = '.vercel/output/functions';

function findFuncDirs(dir) {
  const found = [];
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch (err) {
    console.error(`ERRO: não consegui ler ${dir}: ${err.message}`);
    process.exit(1);
  }
  for (const entry of entries) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name.endsWith('.func')) {
        found.push(full);
      } else {
        found.push(...findFuncDirs(full));
      }
    }
  }
  return found;
}

/** Procura o launcher em qualquer subpasta (o .func preserva api/, lib/...). */
function findIndexJs(dir, depth = 0) {
  if (depth > 3) return null;
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (!entry.isFile()) continue;
    if (entry.name === 'index.js' || entry.name === 'index.cjs') {
      return join(dir, entry.name);
    }
  }
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.isDirectory() && entry.name !== 'node_modules') {
      const hit = findIndexJs(join(dir, entry.name), depth + 1);
      if (hit) return hit;
    }
  }
  return null;
}

function runtimeOf(funcDir) {
  const p = join(funcDir, '.vc-config.json');
  if (!existsSync(p)) return '(desconhecido)';
  try {
    return JSON.parse(readFileSync(p, 'utf8')).runtime ?? '(sem runtime)';
  } catch {
    return '(ilegível)';
  }
}

if (!existsSync(FUNCS_DIR)) {
  console.error(`ERRO: ${FUNCS_DIR} não existe — o vercel build não gerou funções.`);
  process.exit(1);
}

const funcDirs = findFuncDirs(FUNCS_DIR);

if (funcDirs.length === 0) {
  console.error(`ERRO: nenhuma pasta *.func em ${FUNCS_DIR}.`);
  process.exit(1);
}

console.log(`Funções empacotadas: ${funcDirs.length}`);
for (const dir of funcDirs) console.log(`  ${dir}`);

let failures = 0;

for (const funcDir of funcDirs) {
  const name = funcDir.split(/[\\/]/).slice(-2).join('/');
  const pkgPath = join(funcDir, 'package.json');

  let pkg = {};
  if (existsSync(pkgPath)) {
    try {
      pkg = JSON.parse(readFileSync(pkgPath, 'utf8'));
    } catch (err) {
      console.error(`\n[${name}] package.json ilegível: ${err.message}`);
      failures += 1;
      continue;
    }
  }

  // O launcher não fica na raiz da pasta .func: o .vc-config.json diz onde
  // está. Confiar em package.json.main erra, porque ele aponta para
  // "index.js" enquanto o arquivo real vive em api/index.js.
  const vcConfigPath = join(funcDir, '.vc-config.json');
  let handler = null;
  if (existsSync(vcConfigPath)) {
    try {
      handler = JSON.parse(readFileSync(vcConfigPath, 'utf8')).handler ?? null;
    } catch {
      /* segue com a busca recursiva */
    }
  }
  const entryPath = handler
    ? resolve(funcDir, handler)
    : findIndexJs(funcDir);

  console.log(`\n[${name}] type=${pkg.type ?? '(cjs)'} runtime=${runtimeOf(funcDir)} handler=${handler ?? '(desconhecido)'}`);

  if (!entryPath || !existsSync(entryPath)) {
    console.error(`[${name}] ENTRADA AUSENTE (handler=${handler ?? '?'})`);
    failures += 1;
    continue;
  }

  try {
    const require = createRequire(import.meta.url);
    if (pkg.type === 'module') {
      const mod = await import(pathToFileURL(entryPath).href);
      console.log(`[${name}] OK (ESM) — exports: ${Object.keys(mod).join(', ') || '(nenhum)'}`);
    } else {
      const mod = require(entryPath);
      const keys = Object.keys(mod);
      const hasHandler =
        typeof mod.default === 'function' ||
        typeof mod.handler === 'function' ||
        keys.length > 0;
      console.log(`[${name}] OK (CJS) — exports: ${keys.join(', ') || '(nenhum)'}`);
      if (!hasHandler) {
        console.error(`[${name}] carregou sem nenhum handler exportado.`);
        failures += 1;
      }
    }
  } catch (err) {
    failures += 1;
    console.error(`\n[${name}] *** FALHOU AO CARREGAR ***`);
    console.error(`[${name}] ${err && err.name}: ${err && err.message}`);
    if (err && err.code) console.error(`[${name}] code: ${err.code}`);
    if (err && err.stack) {
      console.error(`[${name}] stack:\n${String(err.stack).split('\n').slice(0, 18).join('\n')}`);
    }
  }
}

if (failures > 0) {
  console.error(`\n${failures} função(ões) não carregam — não publicando esse build.`);
  process.exit(1);
}

console.log('\nTodas as funções carregam.');