import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Dados extraídos da imagem do cartão de plano de saúde.
///
/// Todos os campos são opcionais porque a leitura por IA pode falhar em
/// parte dos dados; a tela de conferência permite completar o que faltar.
class CardReadResult {
  const CardReadResult({
    this.name = '',
    this.provider = '',
    this.cardNumber,
    this.groupNumber,
    this.beneficiaryCode,
    this.validity,
    this.coverageType,
    this.notes,
    this.rawText = '',
  });

  final String name;
  final String provider;
  final String? cardNumber;
  final String? groupNumber;
  final String? beneficiaryCode;
  final String? validity;
  final String? coverageType;
  final String? notes;

  /// Texto bruto lido no cartão (mostrado para conferência do usuário).
  final String rawText;

  /// Quantidade de campos preenchidos pela leitura.
  int get filledFields => [
        name,
        provider,
        cardNumber ?? '',
        groupNumber ?? '',
        beneficiaryCode ?? '',
        validity ?? '',
        coverageType ?? '',
      ].where((value) => value.isNotEmpty).length;
}

/// Erro de leitura do cartão com mensagem pronta para o usuário.
class CardReaderException implements Exception {
  const CardReaderException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Lê a imagem do cartão de plano de saúde chamando o proxy serverless
/// (`api/read-card.ts`), que faz o reconhecimento de texto (OCR) no próprio
/// servidor. Não há chave de API nem envio a terceiros: a imagem não sai da
/// nossa infraestrutura.
///
/// A URL do proxy pode ser sobrescrita em tempo de compilação para
/// desenvolvimento local:
/// `flutter run --dart-define=CARD_PROXY_URL=http://localhost:3000/api/read-card`.
class CardReaderService {
  CardReaderService({http.Client? client, String? proxyUrl})
      : _client = client ?? http.Client(),
        proxyUrl =
            (proxyUrl ?? defaultProxyUrl).trim();

  /// URL padrão do proxy (sobreponível por `--dart-define=CARD_PROXY_URL=`).
  static const defaultProxyUrl = String.fromEnvironment(
    'CARD_PROXY_URL',
    defaultValue:
        'https://remedios-app-flutter.vercel.app/api/read-card',
  );

  final http.Client _client;

  /// URL do proxy serverless responsável pela leitura.
  final String proxyUrl;

  /// Extrai os dados do cartão a partir dos bytes da imagem.
  ///
  /// [mimeType] deve ser `image/jpeg`, `image/png` ou `image/webp`. Lança
  /// [CardReaderException] quando o proxy falha, o limite diário é atingido
  /// ou a resposta não traz dados utilizáveis.
  Future<CardReadResult> readCard({
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
      throw const CardReaderException(
        'Sem conexão com o serviço de leitura. Verifique sua internet ou '
        'cadastre manualmente.',
      );
    }

    if (response.statusCode != 200) {
      throw CardReaderException(_errorMessage(response));
    }

    final body = jsonDecode(response.body);
    final content =
        body is Map<String, dynamic> ? body['content'] : null;
    if (content is! String || content.trim().isEmpty) {
      throw const CardReaderException(
        'A leitura do cartão não retornou dados. Tente outra foto ou '
        'cadastre manualmente.',
      );
    }

    return parseContent(content);
  }

  /// Converte o texto retornado pelo modelo em [CardReadResult].
  ///
  /// Tolera cercas de código (```json), texto antes/depois do objeto e
  /// chaves ausentes.
  static CardReadResult parseContent(String content) {
    final jsonText = _extractJsonObject(content);
    if (jsonText.isEmpty) {
      throw const CardReaderException(
        'Não foi possível entender a imagem do cartão. Tente uma foto mais '
        'nítida ou cadastre manualmente.',
      );
    }

    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      json = decoded;
    } on FormatException {
      throw const CardReaderException(
        'Não foi possível entender a imagem do cartão. Tente uma foto mais '
        'nítida ou cadastre manualmente.',
      );
    }

    String text(String key) {
      final value = json[key];
      if (value == null) return '';
      return value.toString().trim();
    }

    final name = text('name');
    final provider = text('provider');

    if (name.isEmpty && provider.isEmpty) {
      throw const CardReaderException(
        'Não encontrei dados de plano de saúde nessa imagem. Tente outra '
        'foto ou cadastre manualmente.',
      );
    }

    return CardReadResult(
      name: name,
      provider: provider,
      cardNumber: _digitsOrNull(text('cardNumber')),
      groupNumber: _digitsOrNull(text('groupNumber')),
      beneficiaryCode: _digitsOrNull(text('beneficiaryCode')),
      validity: _nullIfEmpty(text('validity')),
      coverageType: _nullIfEmpty(text('coverageType')),
      notes: _nullIfEmpty(text('notes')),
      rawText: _nullIfEmpty(text('rawText')) ?? '',
    );
  }

  static String? _digitsOrNull(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    return digits.isEmpty ? null : digits;
  }

  static String? _nullIfEmpty(String value) =>
      value.isEmpty ? null : value;

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
