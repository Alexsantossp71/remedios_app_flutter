class Medicine {
  final String name;
  final String dosage;
  final String presentation;
  final String activeIngredient;
  final String registrationNumber;
  final List<String> aliases;
  final List<String> eans;
  final bool requiresManualDetails;
  final String _normalizedName;
  final String _normalizedIngredient;
  final String _normalizedSearch;
  final List<String> _normalizedAliases;

  Medicine({
    required this.name,
    required this.dosage,
    required this.presentation,
    this.activeIngredient = '',
    this.registrationNumber = '',
    this.aliases = const [],
    this.eans = const [],
    this.requiresManualDetails = false,
  })  : _normalizedName = normalizeMedicineText(name),
        _normalizedIngredient = normalizeMedicineText(activeIngredient),
        _normalizedAliases = aliases.map(normalizeMedicineText).toList(
              growable: false,
            ),
        _normalizedSearch = normalizeMedicineText(
          '$name $activeIngredient $presentation $registrationNumber ${aliases.join(' ')} ${eans.join(' ')}',
        );

  factory Medicine.fromJson(Map<String, dynamic> json) {
    final rawAliases = json['aliases'] as List<dynamic>? ?? const [];
    final rawEans = json['eans'] as List<dynamic>? ?? const [];
    return Medicine(
      name: json['name'] as String,
      dosage: json['dosage'] as String? ?? '',
      presentation: json['presentation'] as String,
      activeIngredient: json['activeIngredient'] as String? ?? '',
      registrationNumber: json['registrationNumber'] as String? ?? '',
      aliases:
          rawAliases.map((alias) => alias as String).toList(growable: false),
      eans: rawEans.map((ean) => ean as String).toList(growable: false),
      requiresManualDetails: json['requiresManualDetails'] as bool? ?? false,
    );
  }

  String get listedDosage {
    final match = RegExp(
      r'^\s*\(?\s*[\d.,]+(?:\s*(?:MCG|UG|MG|KG|G|UI|IU|U|ML|L)\b)?(?:\s*\+\s*[\d.,]+(?:\s*(?:MCG|UG|MG|KG|G|UI|IU|U|ML|L)\b)?)*\s*\)?\s*(?:MCG|UG|MG|KG|G|UI|IU|U|ML|L)\b(?:\s*/\s*(?:[\d.,]+\s*)?(?:MCG|UG|MG|G|ML|L)\b)?',
      caseSensitive: false,
    ).firstMatch(presentation);
    return match?.group(0)?.trim().replaceAll(RegExp(r'[()]'), '').trim() ?? '';
  }

  int matchRank(String normalizedQuery) {
    if (_normalizedName == normalizedQuery) return 0;
    if (_normalizedAliases.contains(normalizedQuery)) return 1;
    if (_normalizedName.startsWith(normalizedQuery)) return 2;
    if (_normalizedAliases.any((alias) => alias.startsWith(normalizedQuery))) {
      return 3;
    }
    if (_normalizedIngredient.startsWith(normalizedQuery)) return 4;
    if (_normalizedSearch.contains(normalizedQuery)) return 5;
    return -1;
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'dosage': dosage,
      'presentation': presentation,
      'activeIngredient': activeIngredient,
      'registrationNumber': registrationNumber,
      'aliases': aliases,
      'eans': eans,
      'requiresManualDetails': requiresManualDetails,
    };
  }
}

String normalizeMedicineText(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp('[áàâãä]'), 'a')
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[íìîï]'), 'i')
      .replaceAll(RegExp('[óòôõö]'), 'o')
      .replaceAll(RegExp('[úùûü]'), 'u')
      .replaceAll('ç', 'c')
      .replaceAllMapped(
        RegExp(r'([a-z])([0-9])'),
        (match) => '${match[1]} ${match[2]}',
      )
      .replaceAllMapped(
        RegExp(r'([0-9])([a-z])'),
        (match) => '${match[1]} ${match[2]}',
      )
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
}
