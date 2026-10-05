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

import { readdirSync, readFileSync, existsSync, cpSync, mkdtempSync, mkdirSync, rmSync } from 'node:fs';
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
 * O bug que a Lambda mostrou e que o require() do CI não mostra.
 *
 * O builder da Vercel emite ESM — o bundle sai com `import ... from` — mas a
 * Lambda carrega /var/task/*.js conforme o package.json do projeto. Sem
 * "type": "module", o Node trata .js como CommonJS e morre ANTES do handler
 * rodar:
 *
 *   /var/task/api/read-card.js:20
 *   import { createWorker } from 'tesseract.js';
 *   SyntaxError: Cannot use import statement outside a module
 *
 * requiring() esse mesmo arquivo no CI passava, porque o require(esm) do
 * Node 24 tolera a mistura: o gate ficava verde e a produção caía com 500.
 * Por isso a verificação é feita no texto, no formato em que a Lambda vai
 * encontrar o arquivo — e não no que o Node local aceita.
 */
function checkModuleFormat(name, entryFile) {
  const type = readJson('package.json').type ?? 'commonjs';
  const src = readFileSync(entryFile, 'utf8');
  const usesEsm = /^\s*(import[\s{]|export[\s{])/m.test(src);

  if (usesEsm && type !== 'module') {
    failures += 1;
    console.error(`\n[${name}] *** FORMATO DE MÓDULO INCOMPATÍVEL COM A LAMBDA ***`);
    console.error(`[${name}] o bundle usa sintaxe ESM, mas package.json declara "type": "${type}".`);
    console.error(`[${name}] A Lambda carrega /var/task/*.js como CommonJS e falha com:`);
    console.error(`[${name}]   SyntaxError: Cannot use import statement outside a module`);
    console.error(`[${name}] Correção: rodar \`npm run package:cjs\` (reempacota o bundle como`);
    console.error(`[${name}] CommonJS). NÃO usar "type": "module" no package.json: esse campo`);
    console.error(`[${name}] vira o tipo de módulo do diretório inteiro da função em`);
    console.error(`[${name}] /var/task e derruba o launcher da plataforma junto.`);
    return false;
  }

  console.log(
    `[${name}] formato OK (bundle ${usesEsm ? 'ESM' : 'CJS'}, package.json type="${type}")`,
  );
  return true;
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

/**
 * O binário WASM do Tesseract não é rastreado pela Vercel: o tracer do
 * bundler leva os arquivos .js (o loader de 89 KB roda normalmente) e o
 * `includeFiles` leva o traineddata, mas o `.wasm` de dentro de
 * node_modules/tesseract.js-core/ fica de fora. Em produção o resultado é:
 *
 *   failed to asynchronously prepare wasm: ENOENT ... tesseract-core-relaxedsimd.wasm
 *   RuntimeError: Aborted(...)
 *   [read-card] OCR falhou: ocr_timeout:worker
 *
 * O require() deste gate não enxerga o problema — o .wasm só é aberto quando o
 * worker é criado, isto é, no primeiro POST de verdade. Por isso esta checagem
 * não só confere se o arquivo existe: ela CRIA o worker a partir do artefato
 * isolado, que é exatamente o passo que faltava. Leva menos de 1s e é a
 * diferença entre "gate verde, produção 502" e "gate vermelho antes do deploy".
 */
async function checkOcrRuntime(name, requireFrom, funcDir) {
  const coreDir = join(funcDir, 'node_modules', 'tesseract.js-core');
  if (!existsSync(coreDir)) {
    console.log(`[${name}] tesseract.js-core ausente no artefato (função sem OCR)`);
    return true;
  }

  const wasms = readdirSync(coreDir).filter((f) => f.endsWith('.wasm'));
  console.log(
    `[${name}] tesseract.js-core: ${wasms.length} .wasm -> ${wasms.join(', ') || 'NENHUM'}`,
  );

  if (wasms.length === 0) {
    failures += 1;
    console.error(`\n[${name}] *** NENHUM .wasm DO TESSERACT NO ARTEFATO ***`);
    console.error(`[${name}] O tracer da Vercel empacota os .js e deixa o binário .wasm de`);
    console.error(`[${name}] fora. Em produção isso é ENOENT em tesseract-core-<variante>.wasm`);
    console.error(`[${name}] já no primeiro POST, surfando como 502 "unreadable".`);
    console.error(`[${name}] Correção: em vercel.json, dentro de`);
    console.error(`[${name}] functions."api/read-card.ts".includeFiles, incluir`);
    console.error(`[${name}] "node_modules/tesseract.js-core/*.wasm".`);
    return false;
  }

  const langPath = join(funcDir, 'api', 'langdata');
  if (!existsSync(join(langPath, 'por.traineddata'))) {
    failures += 1;
    console.error(`\n[${name}] *** por.traineddata AUSENTE NO ARTEFATO ***`);
    console.error(`[${name}] langPath=${langPath} não contém o modelo de português.`);
    return false;
  }

  let worker;
  let guardTimer;
  try {
    const { createWorker } = requireFrom('tesseract.js');
    const cachePath = join(tmpdir(), 'gate-tesseract-cache');
    mkdirSync(cachePath, { recursive: true });
    const guard = new Promise((_, reject) => {
      guardTimer = setTimeout(() => reject(new Error('gate: worker não subiu em 20s')), 20_000);
    });
    // Espelha as opções de api/read-card.ts (OEM 1, langPath local, gzip off).
    worker = await Promise.race([
      createWorker('por', 1, { langPath, cachePath, gzip: false }),
      guard,
    ]);
    console.log(`[${name}] worker Tesseract subiu do artefato (WASM carregado)`);
    return true;
  } catch (err) {
    failures += 1;
    console.error(`\n[${name}] *** O WORKER TESSERACT NÃO SUBIU ***`);
    console.error(`[${name}] ${err.name}: ${err.message}`);
    if (err.code) console.error(`[${name}] code: ${err.code}`);
    return false;
  } finally {
    // O worker fica vivo de propósito entre requisições, então terminá-lo e
    // limpar o timer é o que deixa o gate encerrar em vez de esperar 20s.
    if (guardTimer) clearTimeout(guardTimer);
    if (worker) await worker.terminate().catch(() => undefined);
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

  if (!checkModuleFormat(name, entryFile)) continue;

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
  //
  // A invocação espelha o launcher Node: handler(req, res). Este era o furo
  // que deixou três deploys irem a pé: o gate chamava com um `Request` de Web
  // e lia o `Response` devolvido, então validava a assinatura do runtime Edge.
  // O launcher Node passa (req, res) e espera `res.end()` — um handler
  // assinado como Web function fica com a conexão aberta até o timeout
  // (GET sem resposta nenhuma), que é o sintoma exato que a produção
  // apresentava enquanto este gate ficava verde.
  const makeRes = () => {
    const state = { ended: false, status: null, body: null };
    const res = {
      status(code) {
        state.status = code;
        return res;
      },
      json(body) {
        state.body = body;
        state.ended = true;
        return res;
      },
      end(body) {
        if (body !== undefined) state.body = body;
        state.ended = true;
        return res;
      },
      setHeader() {
        return res;
      },
      getHeader() {
        return undefined;
      },
    };
    return { res, state };
  };

  try {
    const { res, state } = makeRes();
    await fn(
      { method: 'GET', headers: {}, body: undefined, url: 'https://exemplo.test/api/x' },
      res,
    );

    const bodyText = state.body === undefined ? '' : JSON.stringify(state.body);
    console.log(`[${name}] GET -> ${state.status} ${bodyText.slice(0, 120)}`);

    if (!state.ended) {
      failures += 1;
      console.error(`\n[${name}] *** O HANDLER NÃO RESPONDEU ***`);
      console.error(`[${name}] A função foi chamada como (req, res) e nunca chamou`);
      console.error(`[${name}] res.end()/res.json(). O launcher Node fica esperando uma`);
      console.error(`[${name}] resposta que não chega: a requisição pendura até o timeout`);
      console.error(`[${name}] e a Vercel devolve erro sem corpo. Assinatura (req, res) é`);
      console.error(`[${name}] obrigatória para runtime Node; (Request) -> Response é Edge.`);
      continue;
    }

    if (state.status !== null && state.status >= 500) {
      failures += 1;
      console.error(`[${name}] GET respondeu ${state.status} — o handler está devolvendo erro.`);
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

  // Só o POST chega no Tesseract, e é aí que o .wasm ausente aparecia. O GET
  // acima ficava verde enquanto a produção devolvia 502.
  await checkOcrRuntime(name, requireFrom, isolated);
}

for (const dir of sandboxes) rmSync(dir, { recursive: true, force: true });

if (failures > 0) {
  console.error(`\n${failures} verificação(ões) falharam — não publicando este build.`);
  process.exit(1);
}

console.log('\nTodas as funções carregam isoladas e respondem.');