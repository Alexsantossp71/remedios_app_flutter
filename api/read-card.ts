/**
 * Leitura de cartão de plano de saúde por OCR local (Tesseract.js).
 *
 * Não existe mais chamada a API de visão nem chave de API: a imagem é
 * processada dentro da função e o texto extraído é interpretado por regex
 * determinísticas (`server/parse-card.ts`). Isso remove a dependência de
 * terceiros, elimina a alucinação de dados (OCR não inventa texto que não
 * está nos pixels) e derruba o custo por leitura para zero.
 *
 * O runtime de OCR (worker, traineddata, prazo, rate limit) vive em
 * `server/ocr-runtime.ts`, compartilhado com `api/read-receita.ts`.
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

import { parseCardText, type CardFields } from '../server/parse-card.ts';
import {
  clientIp,
  createRateLimiter,
  parseBody,
  preprocessCardImage,
  recognizeBuffer,
  sendJson,
  withDeadline,
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

  // Duas passadas de OCR: a imagem original e a imagem preprocessada
  // (alpha nivelado, ampliada, inclinação corrigida, contraste esticado).
  // Carteirinhas reais mostram que cada passada ganha em cenários diferentes
  // — scans limpos leem melhor sem intervenção; fotos tortas/pequenas só
  // leem com preprocessamento. A melhor leitura vence por:
  //   campos preenchidos (peso 1000 cada) > confiança do Tesseract (×10)
  //   > volume de texto bruto. Nada é misturado entre passadas.
  const originalBuffer = Buffer.from(image, 'base64');
  const preparedBuffer = preprocessCardImage(originalBuffer, mimeType);

  const [originalPass, preparedPass] = await Promise.all([
    (async () => {
      try {
        return await withDeadline(recognizeBuffer(originalBuffer), 'recognize');
      } catch (err) {
        console.error(
          '[read-card] OCR original falhou:',
          err instanceof Error ? err.message : String(err),
        );
        return null;
      }
    })(),
    (async () => {
      if (preparedBuffer === originalBuffer) return null; // nada a preprocessar
      try {
        return await withDeadline(recognizeBuffer(preparedBuffer), 'recognize');
      } catch (err) {
        console.error(
          '[read-card] OCR preprocessado falhou:',
          err instanceof Error ? err.message : String(err),
        );
        return null;
      }
    })(),
  ]);

  if (!originalPass && !preparedPass) {
    // Sem este log, "traineddata ausente", "WASM quebrado" e "timeout"
    // chegam ao cliente como o mesmo 502 unreadable — indistinguíveis de
    // fora, e cada hipótese custa um deploy inteiro.
    sendJson(res, 502, { error: 'unreadable' });
    return;
  }

  const candidates = [
    { pass: originalPass, card: originalPass ? parseCardText(originalPass.text) : null },
    { pass: preparedPass, card: preparedPass ? parseCardText(preparedPass.text) : null },
  ].filter((entry) => entry.card !== null) as {
    pass: { text: string; confidence: number };
    card: CardFields;
  }[];

  let best = candidates[0];
  let bestScore = -1;
  for (const entry of candidates) {
    const score = scoreCardRead(entry.card, entry.pass.confidence);
    if (score > bestScore) {
      bestScore = score;
      best = entry;
    }
  }

  sendJson(res, 200, {
    content: JSON.stringify(best.card),
    model: 'tesseract-ocr',
  });
}

/** Pontua uma leitura: mais campos preenchidos ganha; empate pela confiança
 * do OCR e, por fim, pelo volume de texto (carteirinha lida > página em
 * branco). Sempre >= 0 porque a confiança pode ser 0. */
function scoreCardRead(card: CardFields, confidence: number): number {
  const filled = [
    card.name,
    card.provider,
    card.cardNumber,
    card.groupNumber,
    card.beneficiaryCode,
    card.validity,
    card.coverageType,
  ].filter((value) => value && value.trim().length > 0).length;
  return filled * 1000 + confidence * 10 + Math.min(card.rawText.length, 400);
}
