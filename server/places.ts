/**
 * Busca de endereços no OpenStreetMap (Nominatim) para o cadastro de médico.
 *
 * Módulo puro: montar a URL e mapear a resposta — o endpoint (`api/places.ts`)
 * só faz fetch, rate limit e contrato de erro. Nada é inventado: um campo
 * estruturado só existe quando o Nominatim devolve o pedaço correspondente.
 *
 * Atribuição obrigatória pela política de uso do OSM (também devolvida no
 * corpo da resposta): © OpenStreetMap contributors.
 */

export interface PlaceSuggestion {
  /** Rótulo completo do Nominatim (display_name), pronto para a lista. */
  label: string;
  street: string;
  number: string;
  neighborhood: string;
  city: string;
  /** Sigla da UF ("SP") quando reconhecida; vazio caso contrário. */
  uf: string;
  postalCode: string;
}

export function buildNominatimUrl(query: string): string {
  const params = new URLSearchParams({
    q: query,
    format: 'jsonv2',
    addressdetails: '1',
    limit: '6',
    countrycodes: 'br',
    'accept-language': 'pt-BR',
  });
  return `https://nominatim.openstreetmap.org/search?${params.toString()}`;
}

/** Nome de estado → UF. Só as 27 unidades; fora delas, uf vai vazio. */
const STATE_TO_UF: Record<string, string> = {
  'acre': 'AC', 'alagoas': 'AL', 'amapa': 'AP', 'amazonas': 'AM',
  'bahia': 'BA', 'ceara': 'CE', 'distrito federal': 'DF',
  'espirito santo': 'ES', 'goias': 'GO', 'maranhao': 'MA',
  'mato grosso': 'MT', 'mato grosso do sul': 'MS', 'minas gerais': 'MG',
  'para': 'PA', 'paraiba': 'PB', 'parana': 'PR', 'pernambuco': 'PE',
  'piaui': 'PI', 'rio de janeiro': 'RJ', 'rio grande do norte': 'RN',
  'rio grande do sul': 'RS', 'rondonia': 'RO', 'roraima': 'RR',
  'santa catarina': 'SC', 'sao paulo': 'SP', 'sergipe': 'SE',
  'tocantins': 'TO',
};

function fold(text: string): string {
  return text
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .trim();
}

function text(address: Record<string, unknown>, keys: string[]): string {
  for (const key of keys) {
    const value = address[key];
    if (typeof value === 'string' && value.trim().length > 0) {
      return value.trim();
    }
  }
  return '';
}

/** Converte a resposta do Nominatim em sugestões para o autocomplete. */
export function mapNominatimResults(raw: unknown): PlaceSuggestion[] {
  if (!Array.isArray(raw)) return [];
  const suggestions: PlaceSuggestion[] = [];
  for (const item of raw) {
    if (typeof item !== 'object' || item === null) continue;
    const record = item as Record<string, unknown>;
    const label = typeof record['display_name'] === 'string'
      ? record['display_name'].trim()
      : '';
    if (label === '') continue;
    const address =
      typeof record['address'] === 'object' && record['address'] !== null
        ? (record['address'] as Record<string, unknown>)
        : {};

    const state = text(address, ['state']);
    const uf = STATE_TO_UF[fold(state)] ?? '';

    suggestions.push({
      label,
      street: text(address, ['road', 'pedestrian', 'footway']),
      number: text(address, ['house_number']),
      neighborhood: text(address, [
        'suburb',
        'neighbourhood',
        'borough',
        'city_district',
      ]),
      city: text(address, ['city', 'town', 'village', 'municipality']),
      uf,
      postalCode: text(address, ['postcode']),
    });
  }
  return suggestions;
}
