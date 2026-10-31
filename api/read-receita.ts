/**
 * Leitura de receituário médico por OCR local (Tesseract.js).
 *
 * Mesma arquitetura da leitura do cartão de plano (`api/read-card.ts`): a
 * imagem é processada dentro da função e o texto vira medicamentos através
 * de regex determinísticas (`server/parse-receita.ts`) — sem chave de API,
 * sem terceiros, sem alucinação.
 *
 * Runtime de OCR compartilhado: `server/ocr-runtime.ts`. Contrato e
 * limitações de formato (assinatura Express, body desserializado) também
 * valem aqui — ver o cabeçalho de read-card.ts.
 *
 * Contrato:
 *   POST { "image": "<base64>", "mimeType": "image/jpeg|png|webp" }
 *   200  { "content": "<JSON com medicamentos + rawText>", "model": "tesseract-ocr" }
 *   400  { "error": "invalid_request" }
 *   405  { "error": "method_not_allowed" }
 *   413  { "error": "image_too_large" }
 *   429  { "error": "rate_limited" }
 *   502  { "error": "unreadable" }
 */

import { parseReceitaText } from '../server/parse-receita.ts';
import {
  clientIp,
  createRateLimiter,
  parseBody,
  recognizeText,
  sendJson,
  type NodeRequestLike,
  type NodeResponseLike,
} from '../server/ocr-runtime.ts';

// Tesseract precisa de Node (usa fs e WASM), não roda no runtime Edge.
export const config = { runtime: 'nodejs' };

// ~4 MB de imagem => ~5,6 MiB em base64 + teto de segurança.
const MAX_BASE64_LENGTH = 6 * 1024 * 1024;
const ALLOWED_MIME = new Set(['image/jpeg', 'image/png', 'image/webp']);
const DAILY_LIMIT_PER_IP = 10;

const rateLimiter = createRateLimiter(DAILY_LIMIT_PER_IP);

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
  if (rateLimiter.isLimited(ip)) {
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

  rateLimiter.register(ip);

  let rawText: string;
  try {
    rawText = await recognizeText(image, 'read-receita');
  } catch (err) {
    console.error(
      '[read-receita] OCR falhou:',
      err instanceof Error ? err.message : String(err),
    );
    sendJson(res, 502, { error: 'unreadable' });
    return;
  }

  // Texto vazio (foto sem nada legível) não é erro: a lista vai vazia e o
  // cliente Dart já mostra "não encontrei medicamentos, tente outra foto".
  const receita = parseReceitaText(rawText);
  sendJson(res, 200, {
    content: JSON.stringify(receita),
    model: 'tesseract-ocr',
  });
}
