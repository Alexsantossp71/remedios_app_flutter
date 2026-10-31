/**
 * Extrai medicamentos de um receituário a partir do texto bruto do OCR.
 *
 * Mesma regra de ouro do `parse-card.ts`: um campo só é preenchido quando
 * existe correspondência real no texto. Nada é inferido por IA — OCR não
 * inventa pixels, e o parser não inventa medicamentos.
 *
 * O formato livre do receituário brasileiro é tratado em blocos: uma linha
 * que parece medicamento (nome + dosagem) abre um bloco; as linhas de
 * posologia seguintes ("Tomar 1 comprimido de 8/8 horas por 7 dias")
 * pertencem ao bloco aberto. Linhas de rodapé (CRM, paciente, data) são
 * ruído e nunca viram medicamento.
 *
 * Limitações conscientes (documentadas, não escondidas):
 * - "Tomar Dipirona 8/8h" na primeira linha da receita perde o nome (a linha
 *   começa com verbo de posologia). A conferência no app cobre o caso.
 * - Prescrições totalmente manuscritas fora do padrão podem não casar nada —
 *   e a resposta é uma lista vazia, não um palpite.
 */

export interface ReceitaMed {
  nome: string;
  dosagem: string;
  apresentacao: string;
  intervaloHoras: number | null;
  vezesAoDia: number | null;
  /** Sugestões "HH:MM" derivadas da posologia — o usuário edita antes de salvar. */
  horarios: string[];
  duracaoDias: number | null;
  usoContinuo: boolean;
  /**
   * "Dia sim, dia não" / "em dias alternados" na posologia — vira frequência
   * no rascunho (TreatmentFrequency.everyOtherDay), sempre conferível.
   */
  diasAlternados: boolean;
  /** Posologia crua, para conferência humana na tela de revisão. */
  observacao: string;
}

export interface ReceitaFields {
  medicamentos: ReceitaMed[];
  rawText: string;
}

/**
 * Maiúsculas sem acento, preservando espaços — para casar padrões sem se
 * preocupar com a folha do receituário ser toda em caixa alta ou não.
 */
function fold(text: string): string {
  return text
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toUpperCase();
}

const DOSAGE_PATTERN =
  /\d[\d.,]*\s*(?:MCG|UG|MG|KG|UI|IU|ML|G)\b(?:\s*\/\s*\d[\d.,]*\s*(?:MCG|UG|MG|ML|G)\b)?(?:\s*\+\s*\d[\d.,]*\s*(?:MCG|UG|MG|KG|UI|IU|ML|G)\b)*/;

const PRESENTATION_WORDS: Array<[RegExp, string]> = [
  [/\bCOMPRIMIDOS?\b/g, 'comprimido'],
  [/\bCP\s?\b|\bCOMP\.?\b/g, 'comprimido'],
  [/\bCAPSULAS?\b|\bCAPS\.?\b/g, 'cápsula'],
  [/\bPASTILHAS?\b/g, 'pastilha'],
  [/\bGOTAS?\b/g, 'gota'],
  [/\bSACHES?\b|\bSACHETS?\b/g, 'sachê'],
  [/\bSUPOSITORIOS?\b/g, 'supositório'],
  [/\bCREME\b/g, 'creme'],
  [/\bPOMADA\b/g, 'pomada'],
  [/\bXAROPE\b/g, 'xarope'],
  [/\bSOLUCAO\b|\bSOL\b/g, 'solução'],
  [/\bINJETAVEL\b|\bINJECAO\b/g, 'injeção'],
  [/\bSPRAY\b/g, 'spray'],
  [/\bAMPOLAS?\b/g, 'ampola'],
  [/\bFRASCOS?\b/g, 'frasco'],
  [/\bENXAGUATORIO\b/g, 'enxaguatório'],
];

/** Padrões de posologia — onde houver um deles, a linha continua ali. */
const POSOLOGY_SIGNALS: RegExp[] = [
  /\b\d{1,2}\s*\/\s*\d{1,2}\s*(?:H|HS|HRS|HORAS?)?\b/,
  /\b\d{1,2}\s+(?:EM|A)\s+\d{1,2}\s*(?:H|HS|HRS|HORAS?)?\b/,
  /\bA\s+CADA\s+\d{1,2}\s*(?:H|HS|HRS|HORAS?)?\b/,
  /\b\d{1,2}\s*(?:X|VEZES?)\s+AO\s+DIA\b/,
  /\b(?:MANHA|TARDE|NOITE|JEJUM|ACORDAR|DORMIR|ALMOCO|JANTAR|JANTA|CAFE)\b/,
  /\b(?:POR|DURANTE)\s+\d{1,3}\s+(?:DIAS?|SEMANAS?|MES(?:ES)?)\b/,
  /\bDIA\s+SIM\b|\bDIAS?\s+ALTERNADOS?\b/,
  /\bUSO\s+CONT[I]?NUO\b|\bCONT[I]?NUO\b/,
  /\b(?:TOMAR|TOMA|TOME|USAR|USO|ADMINISTRAR|APLICAR|INGERIR|TOMANDO|USANDO)\b/,
  /\bHORAS?\b/,
];

const NOISE_PATTERN =
  /\b(?:CRM|CRO|COREN|DR\.?|DRA\.?|PACIENTE|RECEITUARIO|RECEITA|RECEITAS|DATA|ENDERECO|TELEFONE|CPF|RG\b|NASCIMENTO|CONSULTA|RETORNO|ASSINATURA|CARIMBO|MEDICO|MEDICAMENTOS?\s+DE\s+CONTROLE|PORTARIA|VALOR|CONVENIO|CLINICA|HOSPITAL|FARMACIA|CONSULTORIO|UBS|UNIDADE\s+DE\s+SAUDE|POSTO\s+DE\s+SAUDE|CENTRO\s+MEDICO)\b/;

const INTERVAL_PATTERNS: RegExp[] = [
  /\b(\d{1,2})\s*\/\s*\d{1,2}\s*(?:H|HS|HRS|HORAS?)?\b/,
  /\b(\d{1,2})\s+(?:EM|A)\s+\d{1,2}\s*(?:H|HS|HRS|HORAS?)?\b/,
  /\bA\s+CADA\s+(\d{1,2})\s*(?:H|HS|HRS|HORAS?)?\b/,
  /\b(?:DE\s+)?(\d{1,2})\s*(?:\/|EM|A)\s*(?:\d{1,2})\s*(?:H|HS|HRS|HORAS?)\b/,
];

const DURATION_PATTERNS: RegExp[] = [
  /\b(?:POR|DURANTE|PELO?S?)\s+(\d{1,3})\s+DIAS?\b/,
  /\b(?:POR|DURANTE)\s+(\d{1,2})\s+SEMANAS?\b/,
  /\b(?:POR|DURANTE)\s+(\d{1,2})\s+MES(?:ES)?\b/,
];

function toIntervalHours(match: RegExpMatchArray): number | null {
  const hours = Number.parseInt(match[1], 10);
  if (!Number.isFinite(hours) || hours < 1 || hours > 23) return null;
  return hours;
}

/** "08:00" a partir de hora e minuto com dois dígitos. */
function hhmm(hour: number): string {
  return `${hour.toString().padStart(2, '0')}:00`;
}

/**
 * Convenção da boca do caixa — a mesma de "A cada Xh" no formulário: o dia
 * começa às 08:00 e as seguintes caem a cada intervalo (8h → 08/16/00).
 * Âncora, não verdade: o usuário ajusta na conferência.
 */
function timesFromInterval(intervalHours: number): string[] {
  const count = 24 % intervalHours === 0 ? 24 / intervalHours : 0;
  if (count === 0) return [];
  const times: string[] = [];
  for (let i = 0; i < count; i += 1) {
    times.push(hhmm((8 + i * intervalHours) % 24));
  }
  return times.sort();
}

function timesFromCount(count: number): string[] {
  if (count < 1 || count > 6) return [];
  if (count === 1) return [hhmm(8)];
  const spacing = 24 / count;
  const times: string[] = [];
  for (let i = 0; i < count; i += 1) {
    times.push(hhmm(Math.round((8 + i * spacing) % 24)));
  }
  return [...new Set(times)].sort();
}

const MEAL_TIMES: Array<[RegExp, string]> = [
  [/\b(?:MANHA|CAF[E]?E|JEJUM|ACORDAR)\b/, '08:00'],
  [/\bALMOCO\b/, '12:00'],
  [/\bTARDE\b/, '16:00'],
  [/\b(?:JANTAR|JANTA)\b/, '19:00'],
  [/\b(?:NOITE|DORMIR)\b/, '22:00'],
];

function timesFromMeals(folded: string): string[] {
  const times = MEAL_TIMES.filter(([pattern]) => pattern.test(folded)).map(
    ([, time]) => time,
  );
  return [...new Set(times)].sort();
}

interface Block {
  headerLine: string;
  headerFolded: string;
  posologyLines: string[];
}

/**
 * Decide se a linha abre medicamento: corta a linha no primeiro sinal de
 * posologia e avalia o pedaço de cima. "DIPIRONA 500MG 8/8H" rende cabeçalho
 * "DIPIRONA 500MG" e posologia "8/8H" na mesma linha; "Tomar 1 comprimido"
 * rende só posologia.
 */
function splitHeader(line: string, folded: string): {
  header: string;
  posology: string;
} | null {
  let cut = folded.length;
  for (const signal of POSOLOGY_SIGNALS) {
    const match = signal.exec(folded);
    if (match && match.index !== undefined && match.index < cut) {
      cut = match.index;
    }
  }
  const header = line.slice(0, cut).trim();
  const posology = line.slice(cut).trim();
  const headerFolded = fold(header);
  // Cabeçalho precisa de ao menos 2 letras — senão é só posologia ("8/8h") ou ruído.
  if ((headerFolded.match(/[A-ZÀ-Ú]/g) ?? []).length < 2) return null;
  if (NOISE_PATTERN.test(headerFolded)) return null;
  // Se a linha foi cortada num sinal de posologia, o pedaço de cima só é
  // medicamento se carregar uma dosagem: "1 comprimido pela manhã" vira
  // posologia do bloco aberto, não um remédio fantasma.
  if (cut < folded.length && !DOSAGE_PATTERN.test(headerFolded)) return null;
  return { header, posology };
}

function cleanName(header: string): { nome: string; apresentacao: string } {
  let nome = header;
  // Numeração de lista: "1.", "1)", "#", "-".
  nome = nome.replace(/^\s*(?:\d{1,2}\s*[).:-]|[#*-])\s*/, '');
  for (const match of nome.match(new RegExp(DOSAGE_PATTERN.source, 'gi')) ?? []) {
    nome = nome.replace(match, ' ');
  }
  let apresentacao = '';
  const folded = fold(nome);
  for (const [pattern, canonical] of PRESENTATION_WORDS) {
    pattern.lastIndex = 0;
    if (pattern.test(folded)) {
      apresentacao = apresentacao || canonical;
      nome = nome.replace(new RegExp(pattern.source, 'i'), ' ');
    }
  }
  nome = nome
    .replace(/[\s.,;:–—-]+$/g, '')
    .replace(/^\s*[.,;:–—-]+\s*/g, '')
    .replace(/\s{2,}/g, ' ')
    .trim();
  return { nome, apresentacao };
}

function extractInterval(folded: string): number | null {
  for (const pattern of INTERVAL_PATTERNS) {
    const match = pattern.exec(folded);
    if (match) {
      const hours = toIntervalHours(match);
      if (hours !== null) return hours;
    }
  }
  return null;
}

function extractCount(folded: string): number | null {
  const match =
    /\b(\d{1,2})\s*(?:X|VEZES?)\s+AO\s+DIA\b/.exec(folded) ??
    /\b(\d{1,2})\s*(?:X|VEZES?)\s+DIA\b/.exec(folded);
  if (!match) return null;
  const count = Number.parseInt(match[1], 10);
  return Number.isFinite(count) && count >= 1 && count <= 6 ? count : null;
}

/** "1 comprimido ao dia", "2 cápsulas ao dia" — só quando não há intervalo. */
function extractUnitCount(folded: string): number | null {
  const match = /\b(\d{1,2})\s+[A-ZÀ-Ú]+\s+AO\s+DIA\b/.exec(folded);
  if (!match) return null;
  const count = Number.parseInt(match[1], 10);
  return Number.isFinite(count) && count >= 1 && count <= 6 ? count : null;
}

/**
 * "DIA SIM, DIA NÃO" e "EM DIAS ALTERNADOS" — a receita define a frequência,
 * não só os horários. fold() remove acentos, então "não" chega como "NAO".
 * Só há frequência especial quando o texto diz: "todo dia" não casa aqui.
 */
const ALTERNATE_DAY_PATTERNS: RegExp[] = [
  /\bDIAS?\s+ALTERNADOS?\b/,
  /\bDIA\s+SIM\b[^\n]{0,12}\bDIA\s+NAO\b/,
];

function extractAlternateDays(folded: string): boolean {
  return ALTERNATE_DAY_PATTERNS.some((pattern) => pattern.test(folded));
}

function extractDuration(folded: string): number | null {
  for (const [index, pattern] of DURATION_PATTERNS.entries()) {
    const match = pattern.exec(folded);
    if (match) {
      const value = Number.parseInt(match[1], 10);
      if (!Number.isFinite(value) || value <= 0) continue;
      if (index === 1) return value * 7; // semanas
      if (index === 2) return value * 30; // meses
      return value;
    }
  }
  return null;
}

function firstDosage(folded: string): string {
  const match = DOSAGE_PATTERN.exec(folded);
  return match ? match[0].trim() : '';
}

export function parseReceitaText(rawText: string): ReceitaFields {
  const lines = rawText
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0);

  const blocks: Block[] = [];
  for (const line of lines) {
    const folded = fold(line);
    const headerSplit = splitHeader(line, folded);
    if (headerSplit) {
      blocks.push({
        headerLine: headerSplit.header,
        headerFolded: fold(headerSplit.header),
        posologyLines: headerSplit.posology ? [headerSplit.posology] : [],
      });
      continue;
    }
    const isNoise = NOISE_PATTERN.test(folded) && !POSOLOGY_SIGNALS.some((s) => s.test(folded));
    if (isNoise) continue;
    // Linha de posologia ou um detalhe a mais do medicamento aberto.
    if (blocks.length > 0) {
      blocks[blocks.length - 1].posologyLines.push(line);
    }
    // Posologia sem medicamento aberto (instruções gerais da receita): descartada.
  }

  const medicamentos: ReceitaMed[] = [];
  for (const block of blocks) {
    const { nome, apresentacao: headerPresentation } = cleanName(block.headerLine);
    if ((nome.match(/[A-Za-zÀ-ú]/g) ?? []).length < 2) continue;

    const posologyFolded = fold(block.posologyLines.join(' · '));
    const dosagem =
      firstDosage(block.headerFolded) || firstDosage(posologyFolded);

    let apresentacao = headerPresentation;
    if (!apresentacao) {
      for (const [pattern, canonical] of PRESENTATION_WORDS) {
        pattern.lastIndex = 0;
        if (pattern.test(posologyFolded)) {
          apresentacao = canonical;
          break;
        }
      }
    }

    const intervaloHoras = extractInterval(posologyFolded);
    let vezesAoDia = extractCount(posologyFolded);
    if (vezesAoDia === null && intervaloHoras !== null && 24 % intervaloHoras === 0) {
      vezesAoDia = 24 / intervaloHoras;
    }
    if (vezesAoDia === null && intervaloHoras === null) {
      vezesAoDia = extractUnitCount(posologyFolded);
    }

    const meals = timesFromMeals(posologyFolded);
    let horarios: string[] = [];
    if (meals.length > 0) {
      horarios = meals;
    } else if (intervaloHoras !== null) {
      horarios = timesFromInterval(intervaloHoras);
    } else if (vezesAoDia !== null) {
      horarios = timesFromCount(vezesAoDia);
    }

    const usoContinuo = /\bUSO\s+CONT[I]?NUO\b|\bCONT[I]?NUO\b/.test(posologyFolded);
    const duracaoDias = usoContinuo ? null : extractDuration(posologyFolded);
    const diasAlternados = extractAlternateDays(posologyFolded);

    medicamentos.push({
      nome,
      dosagem,
      apresentacao,
      intervaloHoras,
      vezesAoDia,
      horarios,
      duracaoDias,
      usoContinuo,
      diasAlternados,
      observacao: block.posologyLines.join('\n').slice(0, 300),
    });
  }

  return { medicamentos, rawText };
}
