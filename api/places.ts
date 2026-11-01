/**
 * Busca de endereços para autocomplete no cadastro de médico.
 *
 * O app chama GET /api/places?q=<texto> e recebe sugestões simplificadas do
 * OpenStreetMap (Nominatim). O proxy existe porque o Nominatim exige User-
 * Agent identificável e bloqueia CORS de browser — a nossa função roda no
 * servidor, sem chave, sem terceiros além do OSM.
 *
 * Contrato:
 *   GET /api/places?q=Rua+Ada+Pereira,+Campinas
 *   200  { "results": [{ label, street, number, neighborhood, city, uf,
 *                        postalCode }], "attribution": "..." }
 *   200  { "results": [] }                       — q curto demais (nada a buscar)
 *   405  { "error": "method_not_allowed" }
 *   429  { "error": "rate_limited" }
 *   502  { "error": "unavailable" }              — OSM fora do ar / timeout
 */

import {
  clientIp,
  createRateLimiter,
  sendJson,
  withDeadline,
  type NodeRequestLike,
  type NodeResponseLike,
} from '../server/ocr-runtime.ts';
import { buildNominatimUrl, mapNominatimResults } from '../server/places.ts';

export const config = { runtime: 'nodejs' };

// Autocomplete é barato (uma requisição ao OSM por toque); 200/dia por IP
// cobre o uso real de um cadastro e protege o Nominatim de abuso.
const DAILY_LIMIT_PER_IP = 200;
const MIN_QUERY_LENGTH = 3;
const USER_AGENT =
  'RemedioNaHora/1.0 (https://remedios-app-flutter.vercel.app; contato via GitHub)';

const rateLimiter = createRateLimiter(DAILY_LIMIT_PER_IP);

export default async function handler(
  req: NodeRequestLike,
  res: NodeResponseLike,
): Promise<void> {
  if (req.method !== 'GET') {
    sendJson(res, 405, { error: 'method_not_allowed' });
    return;
  }

  const ip = clientIp(req);
  if (rateLimiter.isLimited(ip)) {
    sendJson(res, 429, { error: 'rate_limited' });
    return;
  }

  const rawQuery = req.query?.['q'];
  const query = (Array.isArray(rawQuery) ? rawQuery[0] : rawQuery ?? '')
    .toString()
    .trim();
  if (query.length < MIN_QUERY_LENGTH) {
    sendJson(res, 200, { results: [] });
    return;
  }

  rateLimiter.register(ip);

  let response: Response;
  try {
    response = await withDeadline(
      fetch(buildNominatimUrl(query), {
        headers: {
          'User-Agent': USER_AGENT,
          'Accept-Language': 'pt-BR',
        },
      }),
      'places',
    );
  } catch (err) {
    console.error(
      '[places] OSM indisponível:',
      err instanceof Error ? err.message : String(err),
    );
    sendJson(res, 502, { error: 'unavailable' });
    return;
  }

  if (!response.ok) {
    console.error(`[places] OSM respondeu ${response.status}`);
    sendJson(res, 502, { error: 'unavailable' });
    return;
  }

  let payload: unknown;
  try {
    payload = await response.json();
  } catch {
    sendJson(res, 502, { error: 'unavailable' });
    return;
  }

  sendJson(res, 200, {
    results: mapNominatimResults(payload),
    attribution: '© OpenStreetMap contributors',
  });
}
