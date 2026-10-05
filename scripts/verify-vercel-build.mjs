/**
 * Verifica o artefato que a Vercel empacotou, do jeito que a Lambda executa.
 *
 * Por que isto existe: `vercel build` e `vercel deploy` terminam com
 * "sucesso" mesmo quando a função está quebrada — o deploy só publica os
 * arquivos. O breakage só aparece em runtime, como 500
 * FUNCTION_INVOCATION_FAILED, cujo corpo é só "A server error has
 * occurred", sem causa. Como o token da Vercel só existe no CI, este passo
 * roda lá e imprime o erro de verdade, com stack.
 *
 * Dois detalhes que make-or-break, e que já custaram um deploy cada:
 *
 * 1. O require() roda de uma CÓPIA fora do repositório. Se rodasse de dentro
 *    dele, qualquer dependência ausente em .func/node_modules resolveria
 *    silenciosamente no node_modules do repo, um diretório acima — e o teste
 *    passaria enquanto a Lambda, que só tem o artefato, quebraria.
 *
 * 2. Não basta carregar: o handler é INVOCADO com um GET. Um módulo que
 *    carrega e explode na primeira chamada é exatamente o 500 que estamos
 *    caçando, e só a invocação mostra isso.
 */

import { readdirSync, readFileSync, existsSync, cpSync, mkdtempSync, rmSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';

const FUNCS_DIR = '.vercel/output/functions';
const sandboxes = [];

function sandboxFor(name) {
  const dir = mkdtempSync(join(tmpdir(), 'vfn-'));
  sandboxes.push(dir);
  cpSync(name, dir, { recursive: true });
  return dir;
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

function readJson(file) {
  try {
    return JSON.parse(readFileSync(file, 'utf8'));
  } catch {
    return {};
  }
}

/**
 * Lista o conteúdo do artefato. Sem isto, um 500 em produção não tem
 * explicação: o bundle carrega e o handler responde certo quando chamado
 * direto, então a diferença está no launcher que a Vercel coloca entre a
 * Lambda e o módulo. Só vendo os arquivos dá para saber qual é ele e como
 * a Lambda o executa.
 */
function describeArtifact(funcDir, indent = '    ') {
  const skip = new Set(['node_modules']);
  const rows = [];
  const walk = (dir, rel, depth) => {
    if (depth > 3) return;
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      if (skip.has(entry.name)) continue;
      const full = join(dir, entry.name);
      const r = rel ? `${rel}/${entry.name}` : entry.name;
      if (entry.isDirectory()) walk(full, r, depth + 1);
      else rows.push(`${r} (${readFileSync(full).length}b)`);
    }
  };
  walk(funcDir, '', 0);
  for (const row of rows.slice(0, 40)) console.log(`${indent}${row}`);
  if (rows.length > 40) console.log(`${indent}... +${rows.length - 40} arquivos`);

  const nm = join(funcDir, 'node_modules');
  if (existsSync(nm)) {
    const pkgs = readdirSync(nm, { withFileTypes: true })
      .filter((e) => e.isDirectory() || e.isSymbolicLink())
      .map((e) => (e.name.startsWith('@') ? readdirSync(join(nm, e.name)).map((s) => `${e.name}/${s}`) : [e.name]))
      .flat();
    console.log(`${indent}node_modules: ${pkgs.length} pacotes -> ${pkgs.slice(0, 25).join(', ')}`);
  }
}

/**
 * Tenta alcançar o handler real da Vercel. O bundle da função é um
 * esbuild "universal" que entrelaça o código da aplicação com um
 * `module.exports` sintético; o launcher que a Lambda executa é outro
 * arquivo, gerado pelo @vercel/node, e é ele que recebe a requisição.
 * Export `.default` sozinho não é o bastante para exercitar o caminho real.
 */
async function resolveHandler(requireFrom, entryDir, entryFile) {
  const candidates = [];
  const declared = readJson(join(entryDir, 'package.json')).main;
  if (declared) candidates.push(join(entryDir, declared));
  candidates.push(entryFile);

  // Descoberta em vez de chute: qualquer arquivo cujo nome sugira o
  // launcher entra na lista, em qualquer nível. A Lambda executa esse
  // arquivo, não o .default do bundle — se o teste chamar o .default
  // direto, ele mede um caminho que produção não percorre.
  const LAUNCHER = /(launcher|___vc|\.cjs$)/i;
  const scan = (dir, rel, depth) => {
    if (depth > 3) return;
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      if (entry.name === 'node_modules') continue;
      const full = join(dir, entry.name);
      const r = rel ? `${rel}/${entry.name}` : entry.name;
      if (entry.isDirectory()) scan(full, r, depth + 1);
      else if (LAUNCHER.test(entry.name)) candidates.push(full);
    }
  };
  scan(entryDir, '', 0);

  const tried = [];
  for (const candidate of candidates) {
    if (!existsSync(candidate)) {
      tried.push(`${candidate} (inexistente)`);
      continue;
    }
    try {
      const mod = requireFrom(candidate);
      const fn =
        typeof mod?.handler === 'function'
          ? mod.handler
          : typeof mod?.default === 'function'
            ? mod.default
            : null;
      if (fn) return { fn, via: candidate };
      tried.push(`${candidate} (carregou, mas sem handler)`);
    } catch (err) {
      tried.push(`${candidate} (${err.code ?? err.name}: ${err.message})`);
    }
  }
  return { fn: null, tried };
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

let failures = 0;

for (const funcDir of funcDirs) {
  const name = funcDir.split(/[\\/]/).slice(-2, -1)[0];
  const vc = readJson(join(funcDir, '.vc-config.json'));
  const handlerRel = vc.handler ?? null;
  const entryFile = handlerRel ? resolve(funcDir, handlerRel) : null;

  console.log(`\n[${name}] runtime=${vc.runtime ?? '?'} handler=${handlerRel ?? '?'}`);
  console.log(`  .vc-config.json: ${JSON.stringify(vc)}`);
  describeArtifact(funcDir);

  if (!entryFile || !existsSync(entryFile)) {
    console.error(`[${name}] ENTRADA AUSENTE — nada para carregar.`);
    failures += 1;
    continue;
  }

  // Isolamento: cópia fora do repositório, para que deps ausentes no
  // artefato não resolvam no node_modules do repo.
  const isolated = sandboxFor(funcDir);
  const isolatedEntry = join(isolated, handlerRel);
  const requireFrom = createRequire(pathToFileURL(isolatedEntry));

  let mod;
  try {
    mod = requireFrom(isolatedEntry);
    console.log(`[${name}] carregou isolado sem vazar deps do repo`);
  } catch (err) {
    failures += 1;
    console.error(`\n[${name}] *** FALHOU AO CARREGAR (isolado) ***`);
    console.error(`[${name}] ${err.name}: ${err.message}`);
    if (err.code) console.error(`[${name}] code: ${err.code}`);
    if (err.stack) {
      console.error(`[${name}] stack:\n${String(err.stack).split('\n').slice(0, 20).join('\n')}`);
    }
    continue;
  }

  console.log(`[${name}] exports: ${Object.keys(mod).join(', ') || '(nenhum)'}`);

  const { fn, tried, via } = await resolveHandler(requireFrom, isolated, isolatedEntry);
  if (!fn) {
    failures += 1;
    console.error(`[${name}] nenhum handler alcançável:`);
    for (const t of tried) console.error(`[${name}]   ${t}`);
    continue;
  }
  console.log(`[${name}] handler resolvido via ${via.replace(isolated, '<func>')}`);

  // Um GET tem de responder 405 sem encostar no Tesseract: se explode aqui,
  // o 500 é de invocação, não de OCR.
  try {
    const res = await fn(
      new Request('https://exemplo.test/api/read-card', { method: 'GET' }),
    );
    const body = await res.text();
    console.log(`[${name}] GET -> ${res.status} ${body.slice(0, 120)}`);
    if (res.status !== 405) {
      failures += 1;
      console.error(`[${name}] GET deveria dar 405, deu ${res.status}.`);
    }
  } catch (err) {
    failures += 1;
    console.error(`\n[${name}] *** GET EXPLODIU NA INVOCAÇÃO ***`);
    console.error(`[${name}] ${err.name}: ${err.message}`);
    if (err.code) console.error(`[${name}] code: ${err.code}`);
    if (err.stack) {
      console.error(`[${name}] stack:\n${String(err.stack).split('\n').slice(0, 20).join('\n')}`);
    }
  }
}

for (const dir of sandboxes) rmSync(dir, { recursive: true, force: true });

if (failures > 0) {
  console.error(`\n${failures} verificação(ões) falharam — não publicando este build.`);
  process.exit(1);
}

console.log('\nTodas as funções carregam isoladas e respondem.');