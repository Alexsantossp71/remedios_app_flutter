// Laudos de laboratório: converte a resposta da IA em valores estruturados,
// compara cada valor com a faixa de referência (no app, nunca na IA) e
// calcula a evolução de exames repetidos. Funções puras e testáveis —
// portas fiéis do `utils/labResults.ts` do PWA.

/// Um valor medido no laudo (ex.: Glicemia 95 mg/dL, faixa 70–99).
class LabValue {
  const LabValue({
    required this.examName,
    required this.valueText,
    required this.numericValue,
    required this.unit,
    required this.referenceLow,
    required this.referenceHigh,
    required this.referenceText,
    required this.flag,
  });

  /// "Glicemia", "Hemoglobina".
  final String examName;

  /// Valor como escrito no laudo ("95", "5,4", "10.200"); '' quando ilegível.
  final String valueText;

  /// Valor numérico parseado (vírgula decimal pt-BR); null quando não numérico.
  final double? numericValue;

  /// "mg/dL", "g/dL".
  final String unit;

  /// Faixa de referência parseada; null quando não interpretável.
  final double? referenceLow;
  final double? referenceHigh;

  /// Faixa como escrita no laudo ("70 - 99"); '' quando ausente.
  final String referenceText;

  /// Comparação com a faixa, calculada no app (nunca pela IA).
  final String flag; // '' | 'low' | 'normal' | 'high'

  Map<String, dynamic> toJson() => {
    'examName': examName,
    'valueText': valueText,
    'numericValue': numericValue,
    'unit': unit,
    'referenceLow': referenceLow,
    'referenceHigh': referenceHigh,
    'referenceText': referenceText,
    'flag': flag,
  };

  static LabValue fromJson(Map<String, dynamic> json) {
    double? numOf(Object? value) => value is num ? value.toDouble() : null;

    final valueText = json['valueText'] is String
        ? json['valueText'] as String
        : '';
    final numericValue = numOf(json['numericValue']);
    final referenceText = json['referenceText'] is String
        ? json['referenceText'] as String
        : '';
    final low = numOf(json['referenceLow']);
    final high = numOf(json['referenceHigh']);

    return LabValue(
      examName: json['examName'] is String ? json['examName'] as String : '',
      valueText: valueText,
      numericValue: numericValue,
      unit: json['unit'] is String ? json['unit'] as String : '',
      referenceLow: low,
      referenceHigh: high,
      referenceText: referenceText,
      // A flag nunca é lida do banco: é sempre recalculada dos números
      // que sobreviveram (fonte única de verdade no app).
      flag: flagOf(numericValue, low, high),
    );
  }

  LabValue copyWith({
    String? examName,
    String? valueText,
    double? numericValue,
    String? unit,
    String? referenceText,
  }) {
    // Os parâmetros têm os mesmos nomes dos campos; ao mudar a faixa ou o
    // valor, os limites e a flag são sempre recalculados no app.
    final newText = valueText ?? this.valueText;
    final newReference = referenceText ?? this.referenceText;
    final newNumeric = numericValue ?? this.numericValue;
    final double? newLow;
    final double? newHigh;
    if (referenceText == null) {
      newLow = referenceLow;
      newHigh = referenceHigh;
    } else {
      final parsed = parseReferenceText(newReference);
      newLow = parsed.low;
      newHigh = parsed.high;
    }

    return LabValue(
      examName: examName ?? this.examName,
      valueText: newText,
      numericValue: newNumeric,
      unit: unit ?? this.unit,
      referenceLow: newLow,
      referenceHigh: newHigh,
      referenceText: newReference,
      flag: flagOf(newNumeric, newLow, newHigh),
    );
  }
}

/// Máximo de valores por laudo — mesma trava do PWA.
const int maxLabValuesPerResult = 40;

/// Converte texto de valor em número aceitando o padrão brasileiro:
/// vírgula como decimal ("5,4"), ponto como decimal ("5.4") e ponto de
/// milhar ("10.200" → 10200) quando o agrupamento indica milhar.
double? parseNumericValue(String text) {
  final trimmed = text.trim().replaceAll(RegExp(r'\s'), '');
  if (trimmed.isEmpty) return null;
  final hasComma = trimmed.contains(',');
  final hasDot = trimmed.contains('.');

  var normalized = trimmed;
  if (hasComma && hasDot) {
    // "10.200,45" → remove pontos de milhar, vírgula vira decimal.
    normalized = trimmed.replaceAll('.', '').replaceAll(',', '.');
  } else if (hasComma) {
    // Só vírgula: decimal ("5,4").
    normalized = trimmed.replaceFirst(',', '.');
  } else if (hasDot) {
    final groups = trimmed.split('.');
    // "10.200" → milhar quando todos os grupos após o primeiro têm 3 dígitos.
    final looksThousands =
        groups.length > 1 &&
        groups.skip(1).every((group) => RegExp(r'^\d{3}$').hasMatch(group));
    normalized = looksThousands ? trimmed.replaceAll('.', '') : trimmed;
  }

  final parsed = double.tryParse(normalized.replaceAll(RegExp(r'[^\d.-]'), ''));
  return parsed?.isFinite ?? false ? parsed : null;
}

/// Faixa de referência escrita no laudo: "70 - 99", "70 a 99",
/// "entre 70 e 99", "até 100", "< 100", "≤ 100", "≥ 4,0", "0,9-1,3".
/// Devolve os limites que conseguir extrair.
({double? low, double? high}) parseReferenceText(String text) {
  final cleaned = text.trim();
  if (cleaned.isEmpty) return (low: null, high: null);

  // Faixa completa: dois números separados por '-', 'a', 'e', 'até'.
  final rangeMatch = RegExp(
    r'(\d+(?:[.,]\d+)?)\s*(?:-|–|a|até|e)\s*(\d+(?:[.,]\d+)?)',
    caseSensitive: false,
  ).firstMatch(cleaned);
  if (rangeMatch != null) {
    final low = parseNumericValue(rangeMatch.group(1)!);
    final high = parseNumericValue(rangeMatch.group(2)!);
    if (low != null && high != null) return (low: low, high: high);
  }

  // "até X" / "< X" / "≤ X" → só limite superior.
  final upperMatch = RegExp(
    r'(?:até|<|≤|menor que|max(?:imo)?)\s*(\d+(?:[.,]\d+)?)',
    caseSensitive: false,
  ).firstMatch(cleaned);
  if (upperMatch != null) {
    final high = parseNumericValue(upperMatch.group(1)!);
    if (high != null) return (low: null, high: high);
  }

  // "≥ X" / "> X" / "a partir de X" → só limite inferior.
  final lowerMatch = RegExp(
    r'(?:>|≥|>=|maior que|a partir de|min(?:imo)?)\s*(\d+(?:[.,]\d+)?)',
    caseSensitive: false,
  ).firstMatch(cleaned);
  if (lowerMatch != null) {
    final low = parseNumericValue(lowerMatch.group(1)!);
    if (low != null) return (low: low, high: null);
  }

  return (low: null, high: null);
}

/// Compara o valor com a faixa (no app; a IA NÃO opina sobre resultado).
String flagOf(double? numericValue, double? low, double? high) {
  if (numericValue == null || (low == null && high == null)) return '';
  if (low != null && numericValue < low) return 'low';
  if (high != null && numericValue > high) return 'high';
  return 'normal';
}

/// Formata um número do laudo sem o ".0" dos doubles ("95", "5,4" vira
/// "5.4" no formato Dart — a exibição segue o que foi transcrito).
String formatLabNumber(double value) {
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return value.toInt().toString();
  }
  return value.toString();
}

bool _isValidDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
  try {
    final parsed = DateTime.parse('${value}T12:00:00');
    return parsed.year >= 1900 && parsed.year <= 2200;
  } on FormatException {
    return false;
  }
}

/// Campos reconhecidos pela IA na foto de um laudo, já sanitizados.
class LabScanResult {
  const LabScanResult({
    required this.labName,
    required this.examDate,
    required this.values,
  });

  final String labName;

  /// 'AAAA-MM-DD' ou '' quando ilegível.
  final String examDate;
  final List<LabValue> values;
}

/// Normaliza a resposta da IA para um laudo; nunca lança. Valores sem
/// nome de exame são descartados; flags são calculadas aqui, com a faixa
/// que a IA apenas transcreveu (mesma regra do `sanitizeLabScan` do PWA).
LabScanResult sanitizeLabScan(Object? value) {
  final record = value is Map<String, dynamic> ? value : <String, dynamic>{};

  final listRaw = record['resultados'] is List
      ? record['resultados'] as List
      : record['values'] is List
      ? record['values'] as List
      : const [];

  final values = <LabValue>[];
  for (final raw in listRaw.take(maxLabValuesPerResult)) {
    if (raw is! Map<String, dynamic>) continue;
    final examName = _clip(raw['examName'], 120);
    if (examName.isEmpty) continue;
    final valueText = _clip(raw['value'], 60);
    final referenceText = _clip(raw['reference'], 80);
    final numericValue = valueText.isNotEmpty
        ? parseNumericValue(valueText)
        : null;
    final parsed = parseReferenceText(referenceText);
    values.add(
      LabValue(
        examName: examName,
        valueText: valueText,
        numericValue: numericValue,
        unit: _clip(raw['unit'], 30),
        referenceLow: parsed.low,
        referenceHigh: parsed.high,
        referenceText: referenceText,
        flag: flagOf(numericValue, parsed.low, parsed.high),
      ),
    );
  }

  final examDate = _clip(record['examDate'], 10);
  return LabScanResult(
    labName: _clip(record['labName'], 120),
    examDate: _isValidDate(examDate) ? examDate : '',
    values: values,
  );
}

String _clip(Object? value, int max) {
  final text = value is String ? value.trim() : '';
  if (text.length <= max) return text;
  return text.substring(0, max);
}

/// Agrupa laudos repetidos pelo nome do exame ignorando
/// maiúsculas/acentos (equivalente do `normalizeExamName` do PWA —
/// Dart não tem NFD nativo, então acentos PT-BR viram tabela fixa).
String normalizeExamName(String name) {
  const accents = {
    'á': 'a',
    'à': 'a',
    'ã': 'a',
    'â': 'a',
    'ä': 'a',
    'é': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ï': 'i',
    'ó': 'o',
    'ô': 'o',
    'õ': 'o',
    'ö': 'o',
    'ú': 'u',
    'ü': 'u',
    'ç': 'c',
    'ñ': 'n',
  };
  final lowered = name.trim().toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lowered.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(accents[char] ?? char);
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ');
}

/// Entrada mínima para [computeTrends] (o provider passa os laudos salvos).
class LabResultLike {
  const LabResultLike({
    required this.date,
    required this.values,
    this.labName = '',
  });

  /// 'AAAA-MM-DD'.
  final String date;
  final String labName;
  final List<LabValue> values;
}

class TrendEntry {
  const TrendEntry({
    required this.date,
    required this.labName,
    required this.value,
    required this.unit,
  });

  final String date;
  final String labName;
  final double value;
  final String unit;
}

class ExamTrend {
  const ExamTrend({
    required this.examName,
    required this.entries,
    required this.first,
    required this.last,
    required this.pctChange,
    required this.direction,
  });

  /// Nome mais recente usado pelo usuário.
  final String examName;
  final List<TrendEntry> entries;
  final TrendEntry? first;
  final TrendEntry? last;

  /// Variação percentual do primeiro para o último; null sem número válido.
  final double? pctChange;

  /// 'up' | 'down' | 'stable'.
  final String direction;
}

const double _minChangePct = 2;
const int _maxTrends = 12;

/// Histórico por exame (nome normalizado), com valores numéricos
/// ordenados por data e a variação do primeiro para o último resultado —
/// porta do `computeTrends` do PWA.
List<ExamTrend> computeTrends(List<LabResultLike> results) {
  final groups = <String, ({String displayName, List<TrendEntry> entries})>{};

  for (final result in results) {
    final dateKey = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(result.date)
        ? result.date
        : '';
    if (dateKey.isEmpty) continue;
    for (final value in result.values) {
      final numeric = value.numericValue;
      if (numeric == null) continue;
      final key = normalizeExamName(value.examName);
      if (key.isEmpty) continue;
      final group = groups.putIfAbsent(
        key,
        () => (displayName: value.examName, entries: <TrendEntry>[]),
      );
      group.entries.add(
        TrendEntry(
          date: dateKey,
          labName: result.labName,
          value: numeric,
          unit: value.unit,
        ),
      );
    }
  }

  final trends = <ExamTrend>[];
  groups.forEach((_, group) {
    if (group.entries.length < 2) return;
    final entries = [...group.entries]
      ..sort((a, b) => a.date.compareTo(b.date));
    final first = entries.first;
    final last = entries.last;
    final pctChange = first.value != 0
        ? ((last.value - first.value) / first.value.abs() * 100).roundToDouble()
        : null;
    final direction = pctChange == null || pctChange.abs() < _minChangePct
        ? 'stable'
        : pctChange > 0
        ? 'up'
        : 'down';
    trends.add(
      ExamTrend(
        examName: group.displayName,
        entries: entries,
        first: first,
        last: last,
        pctChange: pctChange,
        direction: direction,
      ),
    );
  });

  trends.sort((a, b) => (b.last?.date ?? '').compareTo(a.last?.date ?? ''));
  return trends.take(_maxTrends).toList();
}
