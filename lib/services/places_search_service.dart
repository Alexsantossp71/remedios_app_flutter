import 'dart:convert';

import 'package:http/http.dart' as http;

/// Uma sugestão de endereço do OpenStreetMap para o autocomplete.
///
/// Campos estruturados só chegam preenchidos quando o Nominatim devolve o
/// pedaço correspondente — nada é inferido no cliente.
class PlaceSuggestion {
  const PlaceSuggestion({
    required this.label,
    required this.street,
    required this.number,
    required this.neighborhood,
    required this.city,
    required this.uf,
    required this.postalCode,
  });

  /// Rótulo completo do Nominatim, pronto para a lista de sugestões.
  final String label;
  final String street;
  final String number;
  final String neighborhood;
  final String city;
  final String uf;
  final String postalCode;

  bool get hasAddressData =>
      street.isNotEmpty || neighborhood.isNotEmpty || city.isNotEmpty;

  factory PlaceSuggestion.fromJson(Map<String, dynamic> json) {
    String text(String key) =>
        (json[key] as String? ?? '').trim();

    return PlaceSuggestion(
      label: text('label'),
      street: text('street'),
      number: text('number'),
      neighborhood: text('neighborhood'),
      city: text('city'),
      uf: text('uf'),
      postalCode: text('postalCode'),
    );
  }
}

/// Busca endereços através do proxy serverless (`api/places.ts`), que
/// consulta o OpenStreetMap no servidor — sem chave, e o browser nunca
/// fala direto com o Nominatim (CORS + User-Agent exigido).
///
/// A URL pode ser sobrescrita em tempo de compilação:
/// `flutter run --dart-define=PLACES_URL=http://localhost:3000/api/places`.
class PlacesSearchService {
  PlacesSearchService({http.Client? client, String? placesUrl})
      : _client = client ?? http.Client(),
        placesUrl = (placesUrl ?? defaultPlacesUrl).trim();

  /// URL padrão do proxy (sobreponível por `--dart-define=PLACES_URL=`).
  static const defaultPlacesUrl = String.fromEnvironment(
    'PLACES_URL',
    defaultValue: 'https://remedios-app-flutter.vercel.app/api/places',
  );

  final http.Client _client;

  /// URL do proxy serverless de busca.
  final String placesUrl;

  /// Sugestões para o texto digitado. Falha de rede/limite devolve lista
  /// vazia: autocomplete é um atalho, o formulário segue manual de pé.
  Future<List<PlaceSuggestion>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 3) return const [];

    final http.Response response;
    try {
      response = await _client
          .get(
            Uri.parse(placesUrl).replace(queryParameters: {'q': trimmed}),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      return const [];
    }
    if (response.statusCode != 200) return const [];

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return const [];
    final results = decoded['results'];
    if (results is! List) return const [];

    return results
        .whereType<Map<String, dynamic>>()
        .map(PlaceSuggestion.fromJson)
        .where((suggestion) => suggestion.label.isNotEmpty)
        .toList(growable: false);
  }
}
