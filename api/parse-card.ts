/**
 * Extrai campos de um cartão de plano de saúde a partir do texto bruto
 * devolvido pelo OCR.
 *
 * Regra de ouro: um campo só é preenchido quando existe correspondência real
 * no texto. Nada é inferido, completado ou adivinhado. Sem correspondência,
 * o campo fica vazio e a tela de conferência pede o dado ao usuário.
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

/** Valor do rótulo: dígitos na mesma linha ou, na falta, na linha seguinte. */
function valueForLabel(
  foldedLines: string[],
  labels: string[],
  minimum = 6,
): string {
  for (let i = 0; i < foldedLines.length; i += 1) {
    const line = foldedLines[i];
    for (const label of labels) {
      const cut = indexAfterLabel(line, label);
      if (cut === -1) continue;
      const sameLine = longestDigitRun(line.slice(cut), minimum);
      if (sameLine) return sameLine;
      const nextLine = longestDigitRun(foldedLines[i + 1] ?? '', minimum);
      if (nextLine) return nextLine;
    }
  }
  return '';
}

/** Operadoras conviene: casadas por palavra isolada, da mais específica para a genérica. */
const PROVIDERS: { pattern: string; canonical: string }[] = [
  { pattern: 'BRADESCO SAUDE', canonical: 'Bradesco Saude' },
  { pattern: 'SANTA CASA DE SAUDE', canonical: 'Santa Casa de Saude' },
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
];

const VALIDITY_LABELS = ['VALIDADE', 'VENCIMENTO', 'VENCE', 'VAL'];

/** Vocabulário de cobertura aceito pelo cliente. */
const COVERAGE_TERMS: { pattern: string; label: string }[] = [
  { pattern: 'AMBULATORIAL', label: 'Ambulatorial' },
  { pattern: 'HOSPITALAR', label: 'Hospitalar' },
  { pattern: 'ODONTOLOGICO', label: 'Odontologico' },
  { pattern: 'EMERGENCIA', label: 'Emergencia' },
  { pattern: 'URGENCIA', label: 'Urgencia' },
];

const LABELS_TO_SKIP = new Set([
  ...CARD_NUMBER_LABELS,
  ...GROUP_LABELS,
  ...BENEFICIARY_LABELS,
  ...VALIDITY_LABELS,
  'ABONO', 'ASSINATURA', 'CARTAO',
]);

const DATE_PATTERN = /\d{1,2}\s*[/\-.]\s*\d{4}/;

function looksLikeLabel(folded: string): boolean {
  return [...LABELS_TO_SKIP].some((label) => hasLabel(folded, label));
}

function isCandidateName(folded: string): boolean {
  if (folded.length < 3 || folded.length > 60) return false;
  if (DATE_PATTERN.test(folded)) return false;
  if (looksLikeLabel(folded)) return false;
  if (!/[A-Z]{2,}/.test(folded)) return false;
  // Precisa ter ao menos uma letra e não ser só número/símbolo.
  const letters = folded.replace(/[^A-Z]/g, '').length;
  return letters >= 3 && folded.split(/\s+/).length <= 6;
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

  // Nome do plano: melhor a linha seguinte à operadora; senão, primeira
  // linha que não seja rótulo, data ou número.
  let name = '';
  const order: number[] = [];
  if (providerLine >= 0 && providerLine + 1 < foldedLines.length) order.push(providerLine + 1);
  for (let i = 0; i < foldedLines.length; i += 1) order.push(i);
  for (const i of order) {
    if (i === providerLine) continue;
    if (isCandidateName(foldedLines[i])) {
      name = rawLines[i].trim();
      break;
    }
  }

  const validity = (() => {
    for (let i = 0; i < foldedLines.length; i += 1) {
      for (const label of VALIDITY_LABELS) {
        const cut = indexAfterLabel(foldedLines[i], label);
        if (cut === -1) continue;
        const hit = new RegExp(/\d{1,2}\s*[/\-.]\s*\d{4}/).exec(foldedLines[i].slice(cut));
        const source = hit ? hit[0] : /(\d{1,2}\s*[/\-.]\s*\d{4})/.exec(foldedLines[i + 1] ?? '')?.[1];
        if (!source) continue;
        const [month, year] = source.split(/[/\-.]/).map((part) => Number(part.trim()));
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

  const cardNumber = valueForLabel(foldedLines, CARD_NUMBER_LABELS, 6);

  return {
    name,
    provider,
    // Sem cartão identified por rótulo, tenta a maior sequência longa do texto.
    cardNumber: cardNumber || longestDigitRun(raw, 12),
    groupNumber: valueForLabel(foldedLines, GROUP_LABELS, 4),
    beneficiaryCode: valueForLabel(foldedLines, BENEFICIARY_LABELS, 4),
    validity,
    coverageType,
    notes: '',
    rawText: raw,
  };
}