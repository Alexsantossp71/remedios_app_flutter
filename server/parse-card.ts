/**
 * Extrai campos de um cartão de plano de saúde a partir do texto bruto
 * devolvido pelo OCR.
 *
 * Regra de ouro: um campo só é preenchido quando existe correspondência real
 * no texto. Nada é inferido, completado ou adivinhado. Sem correspondência,
 * o campo fica vazio e a tela de conferência pede o dado ao usuário.
 *
 * Calibrado com cinco carteirinhas reais (12/11/2026) — foto na mão, scan,
 * cartão inclinado, screenshot de app e carteirinha 300px — cobrindo os
 * layouts de SIM/Unimed, Salutá, Prevent e Unimed Virtual.
 */

/** Campos no mesmo formato JSON que o cliente Dart (`CardReaderService`) espera. */
export interface CardFields {
  name: string;
  provider: string;
  cardNumber: string;
  groupNumber: string;
  beneficiaryCode: string;
  validity: string;
  coverageType: string;
  notes: string;
  rawText: string;
}

/**
 * Maiúsculas sem acento, **preservando o comprimento** para que os índices
 * casem com a linha original (necessário para recortar o valor após o rótulo).
 */
function fold(text: string): string {
  let out = '';
  for (const char of text) {
    const base = char.normalize('NFD').replace(/[\u0300-\u036f]/g, '');
    out += base.length === 1 ? base.toUpperCase() : char.toUpperCase();
  }
  return out;
}

function escapeForRegExp(text: string): string {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/** true quando [label] aparece como palavra isolada em [line]. */
function hasLabel(line: string, label: string): boolean {
  return new RegExp(`(^|[^A-Z0-9])${escapeForRegExp(label)}([^A-Z0-9]|$)`).test(line);
}

function indexAfterLabel(line: string, label: string): number {
  const match = new RegExp(`(?:^|[^A-Z0-9])${escapeForRegExp(label)}([^A-Z0-9]|$)`).exec(line);
  if (!match) return -1;
  return match.index + match[0].length;
}

function longestDigitRun(text: string, minimum = 3): string {
  const runs = text.match(/\d+/g) ?? [];
  let best = '';
  for (const run of runs) {
    if (run.length > best.length && run.length >= minimum) best = run;
  }
  return best;
}

/** Valor do rótulo: dígitos na mesma linha ou, na falta, na linha seguinte.
 * Datas são removidas antes da busca — "PRIVATIVA 30/04/2023" sob um
 * rótulo de código não pode devolver "2023". */
function valueForLabel(
  foldedLines: string[],
  labels: string[],
  minimum = 6,
): string {
  const stripDates = (line: string): string =>
    line
      .replace(/\d{1,2}\s*[/\-.]\s*\d{1,2}\s*[/\-.]\s*\d{2,4}/g, ' ')
      .replace(/\d{1,2}\s*[/\-.]\s*\d{4}/g, ' ');
  for (let i = 0; i < foldedLines.length; i += 1) {
    const line = foldedLines[i];
    for (const label of labels) {
      const cut = indexAfterLabel(line, label);
      if (cut === -1) continue;
      const sameLine = longestDigitRun(stripDates(line.slice(cut)), minimum);
      if (sameLine) return sameLine;
      const nextLine = longestDigitRun(stripDates(foldedLines[i + 1] ?? ''), minimum);
      if (nextLine) return nextLine;
    }
  }
  return '';
}

/** Operadoras conhecidas: casadas por palavra isolada, da mais específica
 * para a genérica. Lista ampliada com as operadoras das carteirinhas de
 * teste (SIM/SIM Saúde, Salutá, Prevent). */
const PROVIDERS: { pattern: string; canonical: string }[] = [
  { pattern: 'BRADESCO SAUDE', canonical: 'Bradesco Saude' },
  { pattern: 'PORTO SEGURO', canonical: 'Porto Seguro' },
  { pattern: 'SANTA CASA DE SAUDE', canonical: 'Santa Casa de Saude' },
  { pattern: 'SIM SAUDE', canonical: 'SIM Saude' },
  { pattern: 'SULAMERICA', canonical: 'Sulamerica' },
  { pattern: 'NOTREDAME', canonical: 'NotreDame' },
  { pattern: 'HAPVIDA', canonical: 'Hapvida' },
  { pattern: 'INTERMEDICA', canonical: 'Intermedica' },
  { pattern: 'CENTRAL MEDICA', canonical: 'Central Medica' },
  { pattern: 'UNIMED', canonical: 'Unimed' },
  { pattern: 'PORTISUN', canonical: 'Portisun' },
  { pattern: 'BRADESCO', canonical: 'Bradesco' },
  { pattern: 'AMIL', canonical: 'Amil' },
  { pattern: 'CASSI', canonical: 'Cassi' },
  { pattern: 'MEDIAN', canonical: 'Median' },
  { pattern: 'GEAP', canonical: 'Geap' },
  { pattern: 'UNIHOSPITAL', canonical: 'Unihospital' },
  { pattern: 'SALUTA', canonical: 'Saluta' },
  { pattern: 'PREVENT SENIOR', canonical: 'Prevent Senior' },
  { pattern: 'PREVENT', canonical: 'Prevent' },
];

const CARD_NUMBER_LABELS = [
  'CARTEIRINHA',
  'CARTEIRA',
  'CARTAO DE MEMBRO',
  'CARTAO MEMBRO',
  'CARTAO SAUDE',
  'NUMERO DO CARTAO',
  'N CARTEIRINHA',
];

const GROUP_LABELS = ['CODIGO DO GRUPO', 'GRUPO', 'GRP'];

const BENEFICIARY_LABELS = [
  'CODIGO DO BENEFICIARIO',
  'BENEFICIARIO',
  'CARTAO SUS',
  'CNS',
  // Carteirinha SIM/Unimed usa "Número da matrícula".
  'NUMERO DA MATRICULA',
  'MATRICULA',
];

const HOLDER_LABELS = [
  'NOME DO BENEFICIARIO',
  'NOME DO TITULAR',
  'BENEFICIARIO',
  'TITULAR',
  'NOME',
];

const VALIDITY_LABELS = ['VALIDADE', 'VENCIMENTO', 'VENCE', 'VAL'];

/** Rótulos que identificam datas que NÃO são validade. */
const NON_VALIDITY_DATE_LABELS = ['NASCIMENTO', 'VIGENCIA', 'ADMISSAO'];

/** Vocabulário de cobertura aceito pelo cliente. */
const COVERAGE_TERMS: { pattern: string; label: string }[] = [
  { pattern: 'AMBULATORIAL', label: 'Ambulatorial' },
  { pattern: 'HOSPITALAR', label: 'Hospitalar' },
  { pattern: 'ODONTOLOGICO', label: 'Odontologico' },
  { pattern: 'EMERGENCIA', label: 'Emergencia' },
  { pattern: 'URGENCIA', label: 'Urgencia' },
];

/** Palavras que indicam nome de PLANO (não de pessoa/operadora). */
const PLAN_KEYWORDS = [
  'PLANO',
  'ESPECIAL',
  'EMPRESARIAL',
  'FAMILIAR',
  'INDIVIDUAL',
  'COLETIVO',
  'ADESAO',
  'DENTAL',
  'PRATA',
  'OURO',
  'BRONZE',
  'CLASS',
  'TOTAL',
  'NA07',
  'NA99',
  'SAUDE',
];

const LABELS_TO_SKIP = new Set([
  ...CARD_NUMBER_LABELS,
  ...GROUP_LABELS,
  ...BENEFICIARY_LABELS,
  ...VALIDITY_LABELS,
  ...HOLDER_LABELS,
  'ABONO', 'ASSINATURA', 'CARTAO',
]);

const DATE_PATTERN = /\d{1,2}\s*[/\-.]\s*\d{4}/;

function looksLikeLabel(folded: string): boolean {
  return [...LABELS_TO_SKIP].some((label) => hasLabel(folded, label));
}

/** Proporção de vogais entre as letras: nomes/lixo de OCR têm quase nenhuma
 * vogal ("EE bb.", "mm CÁ"); nomes reais ficam acima de ~0,25. */
function vowelRatio(folded: string): number {
  const letters = folded.replace(/[^A-Z]/g, '');
  if (letters.length === 0) return 0;
  const vowels = letters.replace(/[^AEIOU]/g, '').length;
  return vowels / letters.length;
}

function isCandidateName(folded: string): boolean {
  if (folded.length < 3 || folded.length > 60) return false;
  if (DATE_PATTERN.test(folded)) return false;
  if (looksLikeLabel(folded)) return false;
  if (!/[A-Z]{2,}/.test(folded)) return false;
  // Precisa ter ao menos uma letra e não ser só número/símbolo.
  const letters = folded.replace(/[^A-Z]/g, '').length;
  if (letters < 3) return false;
  if (folded.split(/\s+/).length > 6) return false;
  if (vowelRatio(folded) < 0.25) return false;
  // Lixo de OCR costuma trazer símbolos estranhos (», ^, |…).
  if (/[^A-Z0-9 .,/&+\-'ºº:]/.test(folded)) return false;
  return true;
}

/**
 * Reconstrói candidatos a número de carteirinha de uma linha.
 *
 * Cartões formatam o número em grupos ("0000.0000.000000.00-0",
 * "0 029 100100100 100 O") e o OCR mistura O/0. Algoritmo: divide a linha
 * em tokens; token com ≥60% de dígitos após trocar O/I/L/S/B pelos dígitos
 * correspondentes entra na corrida; tokens consecutivos são concatenados e
 * sub-trechos contíguos com 10-20 dígitos viram candidatos. Datas
 * (token com '/') e palavras reais ficam de fora.
 */
function cardNumberCandidatesInLine(foldedLine: string): string[] {
  if (foldedLine.length > 120) return [];
  const tokens = foldedLine.split(/\s+/);
  const digitTokens: (string | null)[] = tokens.map((token) => {
    if (token.includes('/') || token.length > 25) return null;
    const mapped = token
      .replace(/O/g, '0')
      .replace(/[IL]/g, '1')
      .replace(/S/g, '5')
      .replace(/B/g, '8');
    const digits = mapped.replace(/\D/g, '');
    if (digits.length === 0) return null;
    if (digits.length / mapped.length < 0.6) return null;
    return digits;
  });

  const candidates = new Set<string>();
  let start = 0;
  while (start < digitTokens.length) {
    if (digitTokens[start] === null) {
      start += 1;
      continue;
    }
    let end = start;
    while (end + 1 < digitTokens.length && digitTokens[end + 1] !== null) end += 1;
    // Todos os sub-trechos contíguos [i..j] do bloco de tokens dígitos.
    for (let i = start; i <= end; i += 1) {
      let acc = '';
      for (let j = i; j <= end; j += 1) {
        acc += digitTokens[j];
        if (acc.length >= 10 && acc.length <= 20) candidates.add(acc);
        if (acc.length > 20) break;
      }
    }
    start = end + 1;
  }
  return [...candidates];
}

function parseCardNumber(foldedLines: string[], labelLines: Set<number>): string {
  // 1º passe: candidatos em linhas com rótulo de número de cartão.
  for (let i = 0; i < foldedLines.length; i += 1) {
    if (!labelLines.has(i)) continue;
    const candidates = cardNumberCandidatesInLine(foldedLines[i]);
    if (candidates.length > 0) return bestNumberCandidate(candidates);
  }
  // 2º passe: linhas sem rótulo, preferindo o candidato mais próximo do
  // comprimento típico de carteirinha (16) — nunca datas de nascimento/
  // vigência (tokens com '/' já foram barrados).
  const all: string[] = [];
  for (let i = 0; i < foldedLines.length; i += 1) {
    if (labelLines.has(i)) continue;
    all.push(...cardNumberCandidatesInLine(foldedLines[i]));
  }
  return all.length > 0 ? bestNumberCandidate(all) : '';
}

/** Empate: mais próximo de 16 dígitos (formato comum de carteirinha) ganha. */
function bestNumberCandidate(candidates: string[]): string {
  let best = candidates[0];
  let bestDistance = Math.abs(best.length - 16);
  for (const candidate of candidates) {
    const distance = Math.abs(candidate.length - 16);
    if (distance < bestDistance) {
      best = candidate;
      bestDistance = distance;
    }
  }
  return best;
}

/** Procura o nome do titular por rótulos; layouts costumam colocar o nome
 * NA LINHA DE CIMA do rótulo ("JOÃO DA SILVA SOUZA" / "Nome do beneficiário")
 * ou na de baixo ("EDUARDO OLIVEIRA" / "Nome do Beneficiário"). Nome de
 * pessoa tem ao menos duas palavras — "VIA", "CARD" e similares isolados
 * não são titulares. */
function findHolder(foldedLines: string[], rawLines: string[]): string {
  const isPersonName = (folded: string): boolean => {
    const trimmed = folded.trim();
    if (!isCandidateName(trimmed)) return false;
    if (longestDigitRun(trimmed, 1) !== '') return false;
    return trimmed.split(/\s+/).length >= 2;
  };
  for (let i = 0; i < foldedLines.length; i += 1) {
    for (const label of HOLDER_LABELS) {
      if (!hasLabel(foldedLines[i], label)) continue;
      // Valor na mesma linha, depois do rótulo (fold preserva comprimento).
      const cut = indexAfterLabel(foldedLines[i], label);
      if (isPersonName(foldedLines[i].slice(cut))) {
        return rawLines[i].slice(cut).trim();
      }
      const above = (foldedLines[i - 1] ?? '').trim();
      // Linha de cima com palavra-chave de plano ("E Salutá PLANO
      // FAMILIAR" / "Titular") é marca do cartão, não o titular — o nome
      // está abaixo do rótulo nesse layout.
      const aboveIsBrand =
        PLAN_KEYWORDS.some((keyword) => hasLabel(above, keyword));
      if (!aboveIsBrand && isPersonName(above)) {
        return (rawLines[i - 1] ?? '').trim();
      }
      const below = (foldedLines[i + 1] ?? '').trim();
      if (isPersonName(below)) {
        return (rawLines[i + 1] ?? '').trim();
      }
    }
  }
  return '';
}

export function parseCardText(rawText: string): CardFields {
  const raw = rawText.trim();
  const rawLines = raw ? raw.split(/\r?\n/) : [];
  const foldedLines = rawLines.map(fold).map((line) => line.trim());

  // Operadora: primeira linha que casa com um padrão conhecido.
  let provider = '';
  let providerLine = -1;
  for (let i = 0; i < foldedLines.length; i += 1) {
    const hit = PROVIDERS.find((candidate) => hasLabel(foldedLines[i], candidate.pattern));
    if (hit) {
      provider = hit.canonical;
      providerLine = i;
      break;
    }
  }

  // Titular: linha anotada nos notes; sai da disputa de nome do plano.
  const holder = findHolder(foldedLines, rawLines);
  const holderLines = new Set<number>();
  if (holder) {
    foldedLines.forEach((line, i) => {
      if (line.trim() && fold(holder) === line.trim()) holderLines.add(i);
    });
  }

  // Nome do plano: linha com palavra-chave de plano (incluindo a própria
  // linha da operadora — "E Salutá PLANO FAMILIAR" rende "PLANO FAMILIAR"
  // depois de limpa), depois a vizinha da operadora, depois a primeira
  // candidata. Lixo de OCR ("EE bb.", "mm CÁ") é barrado por vogais e
  // símbolos; a linha do titular sai da disputa.
  type NameCandidate = { folded: string; index: number; score: number };
  const nameCandidates: NameCandidate[] = [];
  for (let i = 0; i < foldedLines.length; i += 1) {
    if (holderLines.has(i)) continue;
    // Símbolos estranhos do OCR ("A?", "»", "^") viram separador em vez de
    // rejeitar a linha inteira — "COLABORADORES TOTAL CLASS A? EMP" ainda
    // é um nome de plano legível depois de limpo.
    const folded = foldedLines[i].replace(/[^A-Z0-9 .,/&+'\-'º:]/g, ' ');
    if (!isCandidateName(folded)) continue;
    let score = 0;
    if (i === providerLine) score += 1;
    if (i === providerLine + 1) score += 2;
    if (i === providerLine - 1 || i === providerLine + 2) score += 1;
    if (PLAN_KEYWORDS.some((keyword) => hasLabel(folded, keyword))) score += 3;
    nameCandidates.push({ folded, index: i, score });
  }
  nameCandidates.sort((a, b) => b.score - a.score || a.index - b.index);
  let name = '';
  for (const candidate of nameCandidates) {
    const providerPattern =
      candidate.index === providerLine
        ? PROVIDERS.find((p) => hasLabel(foldedLines[candidate.index], p.pattern))?.pattern ?? ''
        : '';
    const cleaned = cleanNameTokens(candidate.folded, providerPattern);
    if (cleaned.replace(/[^A-Z]/g, '').length >= 4) {
      name = cleaned;
      break;
    }
  }

  const validity = (() => {
    // Aceita "MM/YYYY" (validade impressa como mês/ano) e "DD/MM/YYYY"
    // (cartões com dia). Devolve MM/YYYY, contrato do cliente.
    const fullDate = /\d{1,2}\s*[/\-.]\s*\d{1,2}\s*[/\-.]\s*\d{2,4}/;
    const fullDateAll = new RegExp(fullDate.source, 'g');
    const monthDate = /\d{1,2}\s*[/\-.]\s*\d{4}/;
    const extract = (line: string): string | undefined => {
      const full = fullDate.exec(line);
      if (full) return full[0];
      const month = monthDate.exec(line);
      return month ? month[0] : undefined;
    };
    for (let i = 0; i < foldedLines.length; i += 1) {
      for (const label of VALIDITY_LABELS) {
        const cut = indexAfterLabel(foldedLines[i], label);
        if (cut === -1) continue;
        let source = extract(foldedLines[i].slice(cut));
        if (!source) source = extract(foldedLines[i + 1] ?? '');
        if (!source) {
          // Layout em colunas: o OCR lineariza valor antes do rótulo
          // ("PRIVATIVA 30/04/2023" / "Acomodação Validade"; "30/10/2009
          // 30/01/2020 30/01/2021" / "NASCIMENTO VIGÊNCIA VALIDADE").
          const prevLine = foldedLines[i - 1] ?? '';
          const prevDates = prevLine.match(fullDateAll) ?? [];
          // Validade fica na última coluna: última data da linha de cima.
          source = prevDates.length > 0 ? prevDates[prevDates.length - 1] : undefined;
        }
        if (!source) continue;
        const parts = source.split(/[/\-.]/).map((part) => Number(part.trim()));
        const month = parts.length >= 3 ? parts[1] : parts[0];
        const year = parts.length >= 3 ? parts[2] : parts[1];
        if (month >= 1 && month <= 12 && year >= 2000 && year <= 2099) {
          return `${String(month).padStart(2, '0')}/${year}`;
        }
      }
    }
    return '';
  })();

  const coverageType = (() => {
    const found: string[] = [];
    for (const term of COVERAGE_TERMS) {
      if (foldedLines.some((line) => hasLabel(line, term.pattern)) && !found.includes(term.label)) {
        found.push(term.label);
      }
    }
    return found.join(' + ');
  })();

  const labelLines = new Set<number>();
  foldedLines.forEach((line, i) => {
    if (CARD_NUMBER_LABELS.some((label) => hasLabel(line, label))) labelLines.add(i);
  });

  const cardNumber = parseCardNumber(foldedLines, labelLines);

  const notes = holder ? `Titular: ${holder}` : '';

  return {
    name,
    provider,
    // Sem candidato estruturado, cai para a maior sequência longa do texto.
    cardNumber: cardNumber || longestDigitRun(foldedLines.join(' '), 12),
    groupNumber: valueForLabel(foldedLines, GROUP_LABELS, 4),
    beneficiaryCode: valueForLabel(foldedLines, BENEFICIARY_LABELS, 4),
    validity,
    coverageType,
    notes,
    rawText: raw,
  };
}

/** Limpa o nome do plano: remove o padrão da operadora casado na linha,
 * caracteres fora do vocabulário de nomes ("A?" do OCR), tokens sem vogais
 * (lixo "IM", "bb") e tokens de uma letra. */
function cleanNameTokens(foldedName: string, providerPattern: string): string {
  let text = foldedName;
  if (providerPattern) {
    text = text.replace(new RegExp(escapeForRegExp(providerPattern), 'g'), ' ');
  }
  const tokens = text
    .split(/\s+/)
    .map((token) => token.replace(/[^A-Z0-9.,/&+'\-:]/g, ''))
    .filter((token) => {
      if (!token) return false;
      if (token.length === 1) return false;
      const letters = token.replace(/[^A-Z]/g, '');
      if (letters.length === 0) return false; // nome de plano é feito de letras
      return vowelRatio(token) >= 0.2;
    });
  const cleaned = tokens.join(' ').trim();
  // Vazio (não sujo): deixa o chamador tentar o próximo candidato.
  return cleaned;
}
