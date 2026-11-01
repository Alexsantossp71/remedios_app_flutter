/**
 * Extrai medicamentos de um receituário a partir do texto bruto do OCR.
 *
 * Mesma regra de ouro do `parse-card.ts`: um campo só é preenchido quando
 * existe correspondência real no texto. Nada é inferido por IA — OCR não
 * inventa pixels, e o parser não inventa medicamentos.
 *
 * O formato livre do receituário brasileiro é tratado em blocos: uma linha
 * só abre um bloco de medicamento quando carrega evidência real — dosagem,
 * apresentação, posologia ou nome conhecido no índice da ANVISA
 * (`med-name-index.ts`). Rótulos do formulário ("Identificação do
 * emitente"), dados do paciente/CRM e ruído de OCR ficam de fora: resposta
 * menor e certa vale mais que lista cheia de fantasma. As linhas de
 * posologia seguintes ("Tomar 1 comprimido de 8/8 horas por 7 dias")
 * pertencem ao bloco aberto.
 *
 * O índice da ANVISA também limpa o nome: "ORAL TRAMAL COM REVL 1COMP"
 * (linha de tabela do receituário eletrônico) reduz a "TRAMAL" — o nome
 * sai do texto da própria receita, o catálogo só aponta onde ele começa e
 * termina.
 *
 * Limitações conscientes (documentadas, não escondidas):
 * - "Tomar Dipirona 8/8h" na primeira linha da receita perde o nome (a linha
 *   começa com verbo de posologia). A conferência no app cobre o caso.
 * - Medicamento fora do catálogo ANVISA precisa de dosagem, apresentação ou
 *   posologia na própria linha para abrir bloco — nome sozinho desconhecido
 *   é provavelmente rótulo, não remédio.
 * - Linha de continuação sem posologia, dosagem, apresentação ou nome
 *   conhecido (ex.: "com alimentos") não é anexada ao bloco aberto.
 * - Prescrições totalmente manuscritas fora do padrão podem não casar nada —
 *   e a resposta é uma lista vazia, não um palpite.
 */

import { MED_NAMES, MED_NAME_MAX_TOKENS } from './med-name-index.ts';

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
  /**
   * "1x por semana" e afins na posologia — vira frequência semanal no
   * rascunho (TreatmentFrequency.weekly). Nulo = a receita não falou em
   * semana; "por 8 semanas" é duração, não frequência.
   */
  vezesPorSemana: number | null;
  /**
   * Dias nomeados na posologia ("aos sábados e domingos"), 1=segunda …
   * 7=domingo. Vazio quando a receita não nomeia dia nenhum — o usuário
   * escolhe na conferência, ausência de informação não é inferência.
   */
  diasDaSemana: number[];
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

interface HeaderToken {
  /** Conteúdo fold do token (maiúsculo, sem acento). */
  text: string;
  /** Posição do token no texto ORIGINAL (para devolver o trecho lido). */
  start: number;
  end: number;
}

/**
 * Palavra isolada que nunca é medicamento por si só — via de administração e
 * rótulos de formulário que andam colados no nome na linha de tabela.
 */
const SINGLE_TOKEN_BLOCKLIST = new Set([
  'ORAL', 'USO', 'NASAL', 'TOPICO', 'TOPICA', 'OFTALMICO', 'OFTALMICA',
  'OTOLOGICO', 'OTICO', 'VAGINAL', 'RETAL', 'SUBLINGUAL', 'INALATORIO',
  'INALACAO', 'INJETAVEL', 'DERMATOLOGICO', 'COMPRIMIDO', 'CAPSULA',
  'MEDICAMENTO', 'MEDICAMENTOS', 'DOSAGEM', 'POSOLOGIA', 'FREQUENCIA',
  'DURACAO', 'PACIENTE', 'NOME', 'DATA', 'DIAS', 'DIA',
]);

function tokenize(text: string): HeaderToken[] {
  const tokens: HeaderToken[] = [];
  const pattern = /[A-Za-z0-9À-ÿ]+/g;
  let match: RegExpExecArray | null;
  while ((match = pattern.exec(text)) !== null) {
    tokens.push({
      text: fold(match[0]),
      start: match.index,
      end: match.index + match[0].length,
    });
  }
  return tokens;
}

/**
 * Acha o nome de medicamento dentro de um texto qualquer: o n-grama (do mais
 * longo para o mais curto) que casa com uma entrada do índice da ANVISA.
 * "ORAL TRAMAL COM REVL 1COMP" → "TRAMAL". Palavra isolada só conta com 5+
 * caracteres e fora da lista de rótulos — "ORAL" e "COM" não são remédio.
 * Devolve as posições no texto original, não o texto fold.
 */
function findMedSpan(
  tokens: HeaderToken[],
): { start: number; end: number } | null {
  const count = tokens.length;
  if (count === 0) return null;
  for (let n = Math.min(MED_NAME_MAX_TOKENS, count); n >= 1; n -= 1) {
    for (let i = 0; i + n <= count; i += 1) {
      const gram = tokens
        .slice(i, i + n)
        .map((token) => token.text)
        .join(' ');
      if (!MED_NAMES.has(gram)) continue;
      if (n === 1 && (gram.length < 5 || SINGLE_TOKEN_BLOCKLIST.has(gram))) {
        continue;
      }
      return { start: tokens[i].start, end: tokens[i + n - 1].end };
    }
  }
  return null;
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
  /\b\d{1,2}\s*(?:X|VEZES?)\s*(?:\/|POR|DE|NA|A\s+CADA|EM)?\s*SEMANAS?\b/,
  /\b\d{1,2}\s+[A-Z]{3,12}\s+(?:POR|DE|NA|A\s+CADA|EM)\s+SEMANAS?\b/,
  /\b(?:UMA?\s+VEZ\s+POR\s+SEMANA|SEMANAL(?:MENTE)?)\b/,
  /\b(?:MANHA|TARDE|NOITE|JEJUM|ACORDAR|DORMIR|ALMOCO|JANTAR|JANTA|CAFE)\b/,
  /\b(?:POR|DURANTE)\s+\d{1,3}\s+(?:DIAS?|SEMANAS?|MES(?:ES)?)\b/,
  /\bDIA\s+SIM\b|\bDIAS?\s+ALTERNADOS?\b/,
  /\bUSO\s+CONT[I]?NUO\b|\bCONT[I]?NUO\b/,
  /\b(?:TOMAR|TOMA|TOME|USAR|USO|ADMINISTRAR|APLICAR|INGERIR|TOMANDO|USANDO)\b/,
  /\bHORAS?\b/,
];

const NOISE_PATTERN =
  /\b(?:C\.?R\.?M\.?|C\.?R\.?O\.?|C\.?O\.?R\.?E\.?N\.?|DR\.?|DRA\.?|PACIENTE|RECEITUARIO|RECEITA|RECEITAS|PRESCRIPTION|DATA|ENDERECO|BAIRRO|CIDADE|CEP|TELEFONE|CPF|RG\b|NASCIMENTO|CONSULTA|RETORNO|ASSINATURA|ASSINAD[OA]|CARIMBO|MEDICO|MEDICAMENTOS?\s+DE\s+CONTROLE|MEDICAMENTOS?\s+PRESCRITOS|PORTARIA|CERTIFICADO|VALOR|CONVENIO|CLINICA|HOSPITAL|FARMACIA|FARMACEUTICO|CONSULTORIO|INSTITUICAO|EMITENTE|COMPRADOR|FORNECEDOR|EMISSOR|IDENTIFICACAO|IDENT\b|OBSERVACOES?|NOME\b|CIRURGIAO|POSOLOGIA|DOSAGEM|FREQUENCIA|DURACAO|UBS|UNIDADE\s+DE\s+SAUDE|POSTO\s+DE\s+SAUDE|CENTRO\s+MEDICO)\b/;

/** Hash de assinatura digital (ICP Brasil) — run hexadecimal longa. */
const SIGNATURE_HASH_PATTERN = /\b[0-9A-F]{16,}\b/;

/**
 * Linha de cabeçalho de tabela do receituário eletrônico
 * ("Uso: Medicamento: Dosagem: Posologia: Frequência: Duração:").
 */
const TABLE_HEADER_WORDS =
  /\b(?:USO|MEDICAMENTOS?|DOSAGEM|POSOLOGIA|FREQUENCIA|DURACAO)\b/g;

function isTableHeaderRow(folded: string): boolean {
  let count = 0;
  for (const _ of folded.matchAll(TABLE_HEADER_WORDS)) count += 1;
  return count >= 3;
}

/** Datas "31/10/2026" não são posologia — tiram o "8/8" do ar. */
function withoutDates(folded: string): string {
  return folded.replace(/\b\d{1,2}\s*\/\s*\d{1,2}\s*\/\s*\d{2,4}\b/g, ' ');
}

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
  // "30 DIAS" na coluna Duração do receituário eletrônico — sem "por".
  /\b(\d{1,3})\s+DIAS?\b/,
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
 * Via de administração na frente do nome (coluna "Uso" do receituário
 * eletrônico): "USO ORAL FÓRMULA MANIPULADA" → "FÓRMULA MANIPULADA".
 */
const ROUTE_PREFIX =
  /^(?:(?:USO\s+)?(?:ORAL|NASAL|TOPIC[OA]|OFTALMIC[OA]|OTOLOGIC[OA]|OTIC[OA]|VAGINAL|RETAL|SUBLINGUAL|INALATORI[OA]|INALAC[AO][OA]|INJETAVEL|DERMATOLOGIC[OA])\s+)+/i;

/**
 * Refina o nome lido: primeiro tenta achar o medicamento da ANVISA dentro do
 * texto (mantém a grafia da própria receita, só corta o que não é nome);
 * sem reconhecimento, tira a via de administração da frente e a quantidade
 * (número solto) do fim — manipulados e fórmulas não estão no catálogo e
 * seguem editáveis na conferência. Nome conhecido não passa por aqui: nomes
 * da ANVISA que terminam em número ("ALBUREX 20") são preservados pelo
 * caminho do dicionário.
 */
function refineName(nome: string): string {
  const span = findMedSpan(tokenize(nome));
  if (span) return nome.slice(span.start, span.end).trim();
  let stripped = nome.replace(ROUTE_PREFIX, '').trim();
  // Quantidade no fim: "FÓRMULA MANIPULADA 30" (de "30 cápsulas").
  while (/\s+\d{1,4}$/.test(stripped)) {
    stripped = stripped.replace(/\s+\d{1,4}$/, '').trim();
  }
  return stripped.length >= 2 ? stripped : nome;
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
  // medicamento com evidência: dosagem ou nome conhecido na ANVISA.
  // "1 comprimido pela manhã" continua posologia do bloco aberto (não tem
  // dosagem nem nome); "METOTREXATO 1x por semana" abre medicamento.
  if (
    cut < folded.length &&
    !DOSAGE_PATTERN.test(headerFolded) &&
    findMedSpan(tokenize(header)) === null
  ) {
    return null;
  }
  // Linha SEM posologia só abre bloco com evidência de medicamento: dosagem,
  // apresentação ou nome conhecido na ANVISA. "My Prescription",
  // "Identificação do emitente" e lixo de OCR não têm nenhuma das três.
  if (cut >= folded.length) {
    const hasDosage = DOSAGE_PATTERN.test(headerFolded);
    const hasPresentation = PRESENTATION_WORDS.some(([pattern]) => {
      pattern.lastIndex = 0;
      return pattern.test(headerFolded);
    });
    const knownMedication = findMedSpan(tokenize(header)) !== null;
    if (!hasDosage && !hasPresentation && !knownMedication) return null;
  }
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

/**
 * "N vezes por semana" — a frequência semanal (metotrexato 1x/sem). Semana
 * não é dia: nada disto pode virar vezesAoDia. Sem dígito ("uma vez por
 * semana", "semanal") conta como 1x.
 */
const WEEKLY_COUNT_PATTERNS: RegExp[] = [
  // "1x por semana", "2 X SEMANA", "1 vez por semana", "1x/semana", "1x na semana".
  /\b(\d{1,2})\s*(?:X|VEZES?)\s*(?:\/|POR|DE|NA|A\s+CADA|EM)?\s*SEMANAS?\b/,
  // "1 comprimido por semana", "2 cápsulas na semana" — unidade entre o
  // número e a semana. Exige o conector para não casar duração ("por 2 semanas"
  // tem o número colado em "semanas").
  /\b(\d{1,2})\s+[A-Z]{3,12}\s+(?:POR|DE|NA|A\s+CADA|EM)\s+SEMANAS?\b/,
  // "uma vez por semana" por extenso — o dígito sumiu ou veio escrito.
  /\bUMA?\s+VEZ\s+POR\s+SEMANA\b/,
  // "semanal" / "semanalmente".
  /\bSEMANAL(?:MENTE)?\b/,
];

function extractWeeklyCount(folded: string): number | null {
  for (const pattern of WEEKLY_COUNT_PATTERNS) {
    const match = pattern.exec(folded);
    if (!match) continue;
    if (match[1] === undefined) return 1;
    const count = Number.parseInt(match[1], 10);
    if (Number.isFinite(count) && count >= 1 && count <= 7) return count;
  }
  return null;
}

/**
 * Dias da semana nomeados na posologia — [padrão, dia] com a numeração de
 * DateTime.weekday (1=segunda … 7=domingo). "sexta-feira" casa em "sexta";
 * "por 2 semanas" não tem dia nenhum.
 */
const WEEKDAY_PATTERNS: Array<[RegExp, number]> = [
  [/\bSEGUNDAS?\b/, 1],
  [/\bTERCAS?\b/, 2],
  [/\bQUARTAS?\b/, 3],
  [/\bQUINTAS?\b/, 4],
  [/\bSEXTAS?\b/, 5],
  [/\bSABADOS?\b/, 6],
  [/\bDOMINGOS?\b/, 7],
];

function extractWeekdays(folded: string): number[] {
  const days = new Set<number>();
  for (const [pattern, weekday] of WEEKDAY_PATTERNS) {
    if (pattern.test(folded)) days.add(weekday);
  }
  return [...days].sort((first, second) => first - second);
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
    // Linha de rótulo de tabela do receituário eletrônico não é nada.
    if (isTableHeaderRow(folded)) continue;
    const headerSplit = splitHeader(line, folded);
    if (headerSplit) {
      blocks.push({
        headerLine: headerSplit.header,
        headerFolded: fold(headerSplit.header),
        posologyLines: headerSplit.posology ? [headerSplit.posology] : [],
      });
      continue;
    }
    const sansDates = withoutDates(folded);
    const isNoise =
      (NOISE_PATTERN.test(folded) || SIGNATURE_HASH_PATTERN.test(folded)) &&
      !POSOLOGY_SIGNALS.some((s) => s.test(sansDates));
    if (isNoise) continue;
    // Continuação precisa levar informação de verdade — posologia (sem datas),
    // dosagem, apresentação, nome conhecido ou "N dias". Borda de tabela e
    // lixo de OCR ("= . E] Otsensação: IC P") não somam nada ao bloco aberto.
    const carriesInfo =
      POSOLOGY_SIGNALS.some((s) => s.test(sansDates)) ||
      /\b\d{1,3}\s+DIAS?\b/.test(sansDates) ||
      DOSAGE_PATTERN.test(folded) ||
      PRESENTATION_WORDS.some(([pattern]) => {
        pattern.lastIndex = 0;
        return pattern.test(folded);
      }) ||
      findMedSpan(tokenize(line)) !== null;
    if (!carriesInfo) continue;
    // Linha de posologia ou um detalhe a mais do medicamento aberto.
    if (blocks.length > 0) {
      blocks[blocks.length - 1].posologyLines.push(line);
    }
    // Posologia sem medicamento aberto (instruções gerais da receita): descartada.
  }

  const medicamentos: ReceitaMed[] = [];
  for (const block of blocks) {
    const { nome: rawName, apresentacao: headerPresentation } = cleanName(
      block.headerLine,
    );
    const nome = refineName(rawName);
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
    const vezesPorSemana = extractWeeklyCount(posologyFolded);
    const diasDaSemana = extractWeekdays(posologyFolded);

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
      vezesPorSemana,
      diasDaSemana,
      observacao: block.posologyLines.join('\n').slice(0, 300),
    });
  }

  return { medicamentos, rawText };
}
