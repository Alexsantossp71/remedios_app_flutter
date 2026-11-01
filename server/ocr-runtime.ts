/**
 * Runtime de OCR (Tesseract.js) compartilhado pelas funções serverless.
 *
 * Tudo aqui nasceu do DEBUG DE PRODUÇÃO da leitura do cartão: launcher que
 * espera assinatura Express, traineddata que não entra no bundle sozinho,
 * worker caro que vale reaproveitar, promessa perdedora que derruba o
 * processo. Extrair para um módulo mantém uma única fonte dessas lições —
 * `api/read-card.ts` (cartão do plano) e `api/read-receita.ts` (receituário)
 * só definem o próprio parser e limites.
 */

import { createWorker, type Worker } from 'tesseract.js';
import { tmpdir } from 'node:os';
import { existsSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';

export interface NodeRequestLike {
  method?: string;
  headers?: Record<string, string | string[] | undefined>;
  body?: unknown;
  /** Query string desserializada (GET) — Vercel Node functions entrega `req.query`. */
  query?: Record<string, string | string[] | undefined>;
}

export interface NodeResponseLike {
  status(code: number): NodeResponseLike;
  json(body: unknown): unknown;
}

export function sendJson(
  res: NodeResponseLike,
  status: number,
  body: unknown,
): unknown {
  return res.status(status).json(body);
}

export function clientIp(req: NodeRequestLike): string {
  const forwarded = req.headers?.['x-forwarded-for'];
  const value = Array.isArray(forwarded) ? forwarded[0] : forwarded;
  return value?.split(',')[0]?.trim() ?? 'unknown';
}

/**
 * O launcher Node já entrega `body` desserializado quando o content-type é
 * JSON, mas tratar string mantém o handler correto se o body chegar cru.
 */
export function parseBody(req: NodeRequestLike): unknown {
  const body = req.body;
  if (typeof body !== 'string') return body;
  try {
    return JSON.parse(body);
  } catch {
    return null;
  }
}

/**
 * Rate limit best-effort em memória: válido enquanto a instância estiver
 * viva. Para limites estritos, trocar por @vercel/kv. Cada função cria o
 * seu — instâncias não compartilham memória de qualquer forma.
 */
export function createRateLimiter(perDayLimit: number) {
  const hitsByIp = new Map<string, { day: string; count: number }>();

  function today(): string {
    return new Date().toISOString().slice(0, 10);
  }

  return {
    isLimited(ip: string): boolean {
      const entry = hitsByIp.get(ip);
      if (!entry || entry.day !== today()) {
        hitsByIp.set(ip, { day: today(), count: 0 });
        return false;
      }
      return entry.count >= perDayLimit;
    },
    register(ip: string): void {
      const entry = hitsByIp.get(ip);
      if (entry && entry.day === today()) entry.count += 1;
    },
  };
}

const TRAINEDDATA_FILE = 'por.traineddata';

/**
 * Onde o traineddata fica depende de como a função foi empacotada: no repo é
 * `api/langdata/`, mas o caminho do ponto de entrada pode mudar no artefato.
 * Por isso testamos candidatos em vez de assumir um só — um caminho fixo
 * passaria no teste local e cairia no CDN só em produção.
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

export function withDeadline<T>(work: Promise<T>, label: string): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const guard = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new Error(`ocr_timeout:${label}`)), OCR_TIMEOUT_MS);
  });
  // O prazo é uma barreira, não um cancelamento: sem este catch, a promessa
  // perdedora continuaria rejeitada depois do timeout e o Node derrubaria o
  // processo com unhandledRejection, derrubando requisições seguintes.
  work.catch(() => undefined);
  return Promise.race([work, guard]).finally(() => clearTimeout(timer)) as Promise<T>;
}

const OCR_TIMEOUT_MS = 25_000;

/**
 * Worker único reaproveitado entre requisições: criar um worker custa ~500ms
 * (carregar o WASM e o modelo), então paga-se uma vez por instância aquecida.
 */
let workerPromise: Promise<Worker> | null = null;

export function getOcrWorker(logLabel: string): Promise<Worker> {
  if (!workerPromise) {
    const localLangPath = resolveLocalLangPath();
    // O log de runtime é a única pista que existe quando a OCR falha em produção:
    // sem ele, um traineddata ausente e um WASM quebrado são indistinguíveis
    // do lado de fora, porque os dois viram o mesmo 502 "unreadable".
    console.log(
      `[${logLabel}] cwd=${process.cwd()} langPath=${localLangPath ?? 'AUSENTE'}`,
    );
    if (!localLangPath) {
      throw new Error(
        'por.traineddata não encontrado no bundle; ver scripts/inject-ocr-assets.mjs',
      );
    }
    // /tmp é o único diretório gravável no runtime de função da Vercel.
    const cachePath = join(tmpdir(), 'tesseract-cache');
    mkdirSync(cachePath, { recursive: true });
    const pending = createWorker('por', 1, {
      langPath: localLangPath,
      cachePath,
      // Com langPath local o arquivo é procurado como "por.traineddata.gz"
      // quando gzip=true (o padrão), e esse .gz não existe.
      gzip: false,
    });
    workerPromise = pending;
    pending.catch(() => {
      if (workerPromise === pending) workerPromise = null;
    });
  }
  return workerPromise;
}

export async function recognizeText(
  imageBase64: string,
  logLabel: string,
): Promise<string> {
  const worker = await withDeadline(getOcrWorker(logLabel), 'worker');
  const buffer = Buffer.from(imageBase64, 'base64');
  const { data } = await withDeadline(worker.recognize(buffer), 'recognize');
  return data.text ?? '';
}
