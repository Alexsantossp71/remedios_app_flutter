/**
 * Leitura de cartão de plano de saúde por OCR local (Tesseract.js).
 *
 * Não existe mais chamada a API de visão nem chave de API: a imagem é
 * processada dentro da função e o texto extraído é interpretado por regex
 * determinísticas (`server/parse-card.ts`). Isso remove a dependência de
 * terceiros,
 * elimina a alucinação de dados (OCR não inventa texto que não está nos
 * pixels) e derruba o custo por leitura para zero.
 *
 * Contrato:
 *   POST { "image": "<base64>", "mimeType": "image/jpeg|png|webp" }
 *   200  { "content": "<JSON com os campos>", "model": "tesseract-ocr" }
 *   400  { "error": "invalid_request" }
 *   405  { "error": "method_not_allowed" }
 *   413  { "error": "image_too_large" }
 *   429  { "error": "rate_limited" }
 *   502  { "error": "unreadable" }  (a imagem não pôde ser processada)
 *
 * Assinatura (req, res) e NÃO (Request) -> Response: o launcher Node da Vercel
 * chama a função como Express e espera `res.end()`. Uma função que devolve um
 * `Response` sem tocar em `res` deixa a requisição pendurar até o timeout — foi
 * exatamente o sintoma de GET sem resposta. `req.headers` também é um objeto
 * comum aqui, sem `.get()`.
 */

import { createWorker, type Worker } from 'tesseract.js';
import { tmpdir } from 'node:os';
import { existsSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';

import { parseCardText } from '../server/parse-card.ts';

// Tesseract precisa de Node (usa fs e WASM), não roda no runtime Edge.
export const config = { runtime: 'nodejs' };

// ~4 MB de imagem => ~5,6 MiB em base64 + teto de segurança.
const MAX_BASE64_LENGTH = 6 * 1024 * 1024;
const ALLOWED_MIME = new Set(['image/jpeg', 'image/png', 'image/webp']);
const DAILY_LIMIT_PER_IP = 10;
const OCR_TIMEOUT_MS = 25_000;

// Rate limit best-effort em memória: válido enquanto a instância estiver viva.
// Para limites estritos, trocar por @vercel/kv.
const hitsByIp = new Map<string, { day: string; count: number }>();

function today(): string {
  return new Date().toISOString().slice(0, 10);
}

function isRateLimited(ip: string): boolean {
  const entry = hitsByIp.get(ip);
  if (!entry || entry.day !== today()) {
    hitsByIp.set(ip, { day: today(), count: 0 });
    return false;
  }
  return entry.count >= DAILY_LIMIT_PER_IP;
}

function registerHit(ip: string): void {
  const entry = hitsByIp.get(ip);
  if (entry && entry.day === today()) entry.count += 1;
}

interface NodeRequestLike {
  method?: string;
  headers?: Record<string, string | string[] | undefined>;
  body?: unknown;
}

interface NodeResponseLike {
  status(code: number): NodeResponseLike;
  json(body: unknown): unknown;
}

function sendJson(
  res: NodeResponseLike,
  status: number,
  body: unknown,
): unknown {
  return res.status(status).json(body);
}

function clientIp(req: NodeRequestLike): string {
  const forwarded = req.headers?.['x-forwarded-for'];
  const value = Array.isArray(forwarded) ? forwarded[0] : forwarded;
  return value?.split(',')[0]?.trim() ?? 'unknown';
}

/**
 * O launcher Node já entrega `body` desserializado quando o content-type é
 * JSON, mas tratar string mantém o handler correto se o body chegar cru.
 */
function parseBody(req: NodeRequestLike): unknown {
  const body = req.body;
  if (typeof body !== 'string') return body;
  try {
    return JSON.parse(body);
  } catch {
    return null;
  }
}

/**
 * Worker único reaproveitado entre requisições: criar um worker custa ~500ms
 * (carregar o WASM e o modelo), então paga-se uma vez por instância aquecida.
 */
let workerPromise: Promise<Worker> | null = null;

const TRAINEDDATA_FILE = 'por.traineddata';

/**
 * Onde o traineddata fica depende de como a função foi empacotada: no repo é
 * `api/langdata/`, mas o `includeFiles` da Vercel copia preservando o caminho
 * relativo enquanto o ponto de entrada pode mudar de lugar. Por isso testamos
 * candidatos em vez de assumir um só — um caminho fixo passaria no teste local
 * e cairia no CDN só em produção.
 *
 * Só `process.cwd()`: `import.meta.url` é erro de sintaxe quando o builder
 * emite CommonJS, e derrubaria o módulo inteiro no load.
 */
function resolveLocalLangPath(): string | undefined {
  const candidates = [
    join(process.cwd(), 'api', 'langdata'),
    join(process.cwd(), 'langdata'),
    join(process.cwd(), '..', 'api', 'langdata'),
  ];
  for (const dir of candidates) {
    if (existsSync(join(dir, TRAINEDDATA_FILE))) return dir;
  }
  return undefined;
}

function getWorker(): Promise<Worker> {
  if (!workerPromise) {
    // O traineddata vem no repositório (2,3 MB). Se não estiver no bundle,
    // cai no CDN oficial do projeto Tesseract.
    const localLangPath = resolveLocalLangPath();
    // /tmp é o único diretório gravável no runtime de função da Vercel.
    const cachePath = join(tmpdir(), 'tesseract-cache');
    mkdirSync(cachePath, { recursive: true });
    const attempt = (langPath?: string) =>
      createWorker('por', 1, {
        langPath,
        cachePath,
        // Com langPath local o arquivo é procurado como "por.traineddata.gz"
        // quando gzip=true (o padrão), e esse .gz não existe. No CDN ele existe.
        gzip: langPath ? false : true,
      });
    const pending = localLangPath
      ? attempt(localLangPath).catch(() => attempt(undefined))
      : attempt(undefined);
    workerPromise = pending;
    // Sem este reset uma falha transitória deixaria a promise rejeitada presa
    // em workerPromise, e a instância aquecida nunca mais tentaria de novo.
    pending.catch(() => {
      if (workerPromise === pending) workerPromise = null;
    });
  }
  return workerPromise;
}

async function recognizeText(imageBase64: string): Promise<string> {
  const worker = await getWorker();
  const buffer = Buffer.from(imageBase64, 'base64');
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    const { data } = await Promise.race([
      worker.recognize(buffer),
      new Promise<never>((_, reject) => {
        timer = setTimeout(() => reject(new Error('ocr_timeout')), OCR_TIMEOUT_MS);
      }),
    ]);
    return data.text ?? '';
  } finally {
    clearTimeout(timer);
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

export default async function handler(
  req: NodeRequestLike,
  res: NodeResponseLike,
): Promise<void> {
  if (req.method !== 'POST') {
    sendJson(res, 405, { error: 'method_not_allowed' });
    return;
  }

  const ip = clientIp(req);
  if (isRateLimited(ip)) {
    sendJson(res, 429, { error: 'rate_limited' });
    return;
  }

  const payload = parseBody(req);
  if (!isRecord(payload)) {
    sendJson(res, 400, { error: 'invalid_request' });
    return;
  }

  const image = payload.image;
  const mimeType = payload.mimeType;
  if (
    typeof image !== 'string' ||
    image.length === 0 ||
    typeof mimeType !== 'string' ||
    !ALLOWED_MIME.has(mimeType)
  ) {
    sendJson(res, 400, { error: 'invalid_request' });
    return;
  }
  if (image.length > MAX_BASE64_LENGTH) {
    sendJson(res, 413, { error: 'image_too_large' });
    return;
  }

  registerHit(ip);

  let rawText: string;
  try {
    rawText = await recognizeText(image);
  } catch {
    sendJson(res, 502, { error: 'unreadable' });
    return;
  }

  // Texto vazio (foto sem nada legível) não é erro: os campos vão vazios e o
  // cliente Dart já mostra "não encontrei dados, tente outra foto".
  const card = parseCardText(rawText);
  sendJson(res, 200, {
    content: JSON.stringify(card),
    model: 'tesseract-ocr',
  });
}