import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/treatment.dart';
import '../models/treatment_draft.dart';

/// Um medicamento extraído da foto do receituário.
///
/// Todos os campos são opcionais porque o OCR pode falhar em parte dos
/// dados; a tela de conferência permite completar o que faltar antes de
/// salvar qualquer coisa.
class PrescriptionMedication {
  const PrescriptionMedication({
    this.nome = '',
    this.dosagem = '',
    this.apresentacao = '',
    this.intervaloHoras,
    this.vezesAoDia,
    this.horarios = const [],
    this.duracaoDias,
    this.usoContinuo = false,
    this.diasAlternados = false,
    this.observacao = '',
  });

  final String nome;
  final String dosagem;
  final String apresentacao;
  final int? intervaloHoras;
  final int? vezesAoDia;
  /// Horários sugeridos "HH:MM" derivados da posologia pelo parser.
  final List<String> horarios;
  final int? duracaoDias;
  final bool usoContinuo;
  /// A receita diz "dia sim, dia não" ou "em dias alternados": vira frequência
  /// no rascunho (o formulário abre com ela, o usuário confere).
  final bool diasAlternados;
  final String observacao;

  bool get hasName => nome.trim().isNotEmpty;

  factory PrescriptionMedication.fromJson(Map<String, dynamic> json) {
    String text(String key) {
      final value = json[key];
      return value == null ? '' : value.toString().trim();
    }

    int? intOrNull(String key) {
      final value = json[key];
      if (value is num) return value.round();
      if (value is String) return int.tryParse(value.trim());
      return null;
    }

    return PrescriptionMedication(
      nome: text('nome'),
      dosagem: text('dosagem'),
      apresentacao: text('apresentacao'),
      intervaloHoras: intOrNull('intervaloHoras'),
      vezesAoDia: intOrNull('vezesAoDia'),
      horarios: (json['horarios'] as List<dynamic>? ?? const [])
          .map((time) => time.toString().trim())
          .where(_isValidTime)
          .toList(growable: false),
      duracaoDias: intOrNull('duracaoDias'),
      usoContinuo: json['usoContinuo'] == true,
      diasAlternados: json['diasAlternados'] == true,
      observacao: text('observacao'),
    );
  }

  /// Converte os horários sugeridos em [DoseTime] válidos e sem duplicata.
  List<DoseTime> get suggestedDoseTimes {
    final times = <int, DoseTime>{};
    for (final time in horarios) {
      final match = _timePattern.firstMatch(time);
      if (match == null) continue;
      final hour = int.parse(match.group(1)!);
      final minute = int.parse(match.group(2)!);
      if (hour > 23 || minute > 59) continue;
      times[hour * 60 + minute] = DoseTime(hour: hour, minute: minute);
    }
    final values = times.values.toList(growable: false)
      ..sort((first, second) =>
          first.minutesSinceMidnight.compareTo(second.minutesSinceMidnight));
    return values;
  }

  /// Rascunho pronto para o formulário de tratamento conferir e salvar.
  ///
  /// O texto de posologia cru vai para as observações (o usuário edita); uso
  /// contínuo e duração viram data de término quando existe; "dia sim, dia
  /// não" vira frequência — tudo conferível, nada salvo sem o usuário.
  TreatmentDraft toTreatmentDraft({required DateTime today}) {
    final schedule = suggestedDoseTimes.isEmpty
        ? const [DoseTime(hour: 8, minute: 0)]
        : suggestedDoseTimes;
    final notes = <String>[
      if (usoContinuo) 'Uso contínuo',
      if (observacao.trim().isNotEmpty) observacao.trim(),
    ];
    return TreatmentDraft(
      name: nome.trim(),
      dosage: dosagem.trim(),
      presentation: apresentacao.trim(),
      instructions: notes.join('\n'),
      doseTimes: schedule,
      endDate: duracaoDias == null
          ? null
          : today.add(Duration(days: duracaoDias!)),
      frequency:
          diasAlternados ? TreatmentFrequency.everyOtherDay : null,
    );
  }

  static final RegExp _timePattern = RegExp(r'^(\d{1,2}):(\d{2})$');

  /// Formato E faixa: "25:00" passa no formato, mas não é horário — lixo
  /// de OCR não pode virar dose impossível. Rejeita também "7h60" e "8:5".
  static bool _isValidTime(String time) {
    final match = _timePattern.firstMatch(time);
    if (match == null) return false;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    return hour <= 23 && minute <= 59;
  }
}

/// Resultado da leitura da receita: medicamentos + texto bruto para conferência.
class PrescriptionReadResult {
  const PrescriptionReadResult({
    required this.medicamentos,
    required this.rawText,
  });

  final List<PrescriptionMedication> medicamentos;
  final String rawText;
}

/// Erro de leitura da receita com mensagem pronta para o usuário.
class PrescriptionReaderException implements Exception {
  const PrescriptionReaderException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Lê a foto do receituário chamando o proxy serverless
/// (`api/read-receita.ts`), que faz o OCR no próprio servidor. Não há chave
/// de API nem envio a terceiros: a imagem não sai da nossa infraestrutura.
///
/// A URL do proxy pode ser sobrescrita em tempo de compilação:
/// `flutter run --dart-define=RECEITA_PROXY_URL=http://localhost:3000/api/read-receita`.
class PrescriptionReaderService {
  PrescriptionReaderService({http.Client? client, String? proxyUrl})
      : _client = client ?? http.Client(),
        proxyUrl = (proxyUrl ?? defaultProxyUrl).trim();

  /// URL padrão do proxy (sobreponível por `--dart-define=RECEITA_PROXY_URL=`).
  static const defaultProxyUrl = String.fromEnvironment(
    'RECEITA_PROXY_URL',
    defaultValue:
        'https://remedios-app-flutter.vercel.app/api/read-receita',
  );

  final http.Client _client;

  /// URL do proxy serverless responsável pela leitura.
  final String proxyUrl;

  /// Extrai os medicamentos a partir dos bytes da imagem.
  ///
  /// [mimeType] deve ser `image/jpeg`, `image/png` ou `image/webp`. Lança
  /// [PrescriptionReaderException] quando o proxy falha, o limite diário é
  /// atingido ou a leitura não traz medicamentos utilizáveis.
  Future<PrescriptionReadResult> readPrescription({
    required Uint8List imageBytes,
    String mimeType = 'image/jpeg',
  }) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(proxyUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'image': base64Encode(imageBytes),
              'mimeType': mimeType,
            }),
          )
          .timeout(const Duration(seconds: 60));
    } catch (_) {
      throw const PrescriptionReaderException(
        'Sem conexão com o serviço de leitura. Verifique sua internet ou '
        'cadastre manualmente.',
      );
    }

    if (response.statusCode != 200) {
      throw PrescriptionReaderException(_errorMessage(response));
    }

    final body = jsonDecode(response.body);
    final content = body is Map<String, dynamic> ? body['content'] : null;
    if (content is! String || content.trim().isEmpty) {
      throw const PrescriptionReaderException(
        'A leitura da receita não retornou dados. Tente outra foto ou '
        'cadastre manualmente.',
      );
    }

    return parseContent(content);
  }

  /// Converte o JSON retornado pelo servidor em [PrescriptionReadResult].
  ///
  /// Tolera cercas de código (```json), texto antes/depois do objeto e
  /// campos ausentes.
  static PrescriptionReadResult parseContent(String content) {
    final jsonText = _extractJsonObject(content);
    if (jsonText.isEmpty) {
      throw const PrescriptionReaderException(
        'Não foi possível entender a foto da receita. Tente uma foto mais '
        'nítida ou cadastre manualmente.',
      );
    }

    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      json = decoded;
    } on FormatException {
      throw const PrescriptionReaderException(
        'Não foi possível entender a foto da receita. Tente uma foto mais '
        'nítida ou cadastre manualmente.',
      );
    }

    final medicamentos = (json['medicamentos'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PrescriptionMedication.fromJson)
        .where((med) => med.hasName)
        .toList(growable: false);

    if (medicamentos.isEmpty) {
      throw const PrescriptionReaderException(
        'Não encontrei medicamentos legíveis nessa receita. Tente uma foto '
        'mais próxima do texto ou cadastre manualmente.',
      );
    }

    final rawText = json['rawText'];
    return PrescriptionReadResult(
      medicamentos: medicamentos,
      rawText: rawText is String ? rawText : '',
    );
  }

  /// Recorta o primeiro objeto JSON presente no texto.
  static String _extractJsonObject(String content) {
    var text = content.trim();
    text = text.replaceAll(RegExp(r'```(?:json)?', caseSensitive: false), '');
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end <= start) return '';
    return text.substring(start, end + 1);
  }

  String _errorMessage(http.Response response) {
    switch (response.statusCode) {
      case 400:
        return 'A imagem enviada não foi aceita pelo serviço de leitura. '
            'Tente outra foto ou cadastre manualmente.';
      case 413:
        return 'Imagem muito grande. Tente uma foto menor.';
      case 429:
        return 'Limite diário de leituras atingido. Tente novamente mais '
            'tarde ou cadastre manualmente.';
      default:
        return 'Leitura automática indisponível agora. Tente novamente ou '
            'cadastre manualmente.';
    }
  }
}
