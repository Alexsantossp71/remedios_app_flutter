/**
 * Leitura de cartão de plano de saúde por OCR local (Tesseract.js).
 *
 * Não existe mais chamada a API de visão nem chave de API: a imagem é
 * processada dentro da função e o texto extraído é interpretado por regex
 * determinísticas (`parse-card.ts`). Isso remove a dependência de terceiros,
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
 */

import { createWorker, type Worker } from 'tesseract.js';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';
import { mkdirSync } from 'node:fs';

import { parseCardText } from './parse-card.ts';

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

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

/**
 * Worker único reaproveitado entre requisições: criar um worker custa ~500ms
 * (carregar o WASM e o modelo), então paga-se uma vez por instância aquecida.
 */
let workerPromise: Promise<Worker> | null = null;

function getWorker(): Promise<Worker> {
  if (!workerPromise) {
    // O traineddata vem no repositório (2,3 MB). Se o pacote não tiver sido
    // incluído no bundle, cai no CDN oficial do projeto Tesseract.
    const localLangPath = fileURLToPath(new URL('./langdata/', import.meta.url));
    const cachePath = `${tmpdir()}/tesseract-cache`;
    mkdirSync(cachePath, { recursive: true });
    const attempt = (langPath?: string) =>
      createWorker('por', 1, {
        langPath,
        cachePath,
        // Com langPath local o arquivo é procurado como "por.traineddata.gz"
        // quando gzip=true (o padrão), e esse .gz não existe. No CDN ele existe.
        gzip: langPath ? false : true,
      });
    workerPromise = attempt(localLangPath).catch(() => attempt(undefined));
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

export default async function handler(request: Request): Promise<Response> {
  if (request.method !== 'POST') {
    return jsonResponse(405, { error: 'method_not_allowed' });
  }

  const ip =
    request.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ??
    'unknown';
  if (isRateLimited(ip)) return jsonResponse(429, { error: 'rate_limited' });

  let payload: { image?: unknown; mimeType?: unknown };
  try {
    payload = await request.json();
  } catch {
    return jsonResponse(400, { error: 'invalid_request' });
  }

  const image = payload.image;
  const mimeType = payload.mimeType;
  if (
    typeof image !== 'string' ||
    image.length === 0 ||
    typeof mimeType !== 'string' ||
    !ALLOWED_MIME.has(mimeType)
  ) {
    return jsonResponse(400, { error: 'invalid_request' });
  }
  if (image.length > MAX_BASE64_LENGTH) {
    return jsonResponse(413, { error: 'image_too_large' });
  }

  registerHit(ip);

  let rawText: string;
  try {
    rawText = await recognizeText(image);
  } catch {
    return jsonResponse(502, { error: 'unreadable' });
  }

  // Texto vazio (foto sem nada legível) não é erro: os campos vão vazios e o
  // cliente Dart já mostra "não encontrei dados, tente outra foto".
  const card = parseCardText(rawText);
  return jsonResponse(200, {
    content: JSON.stringify(card),
    model: 'tesseract-ocr',
  });
}