const kBrazilianStates = <String>[
  'AC',
  'AL',
  'AP',
  'AM',
  'BA',
  'CE',
  'DF',
  'ES',
  'GO',
  'MA',
  'MT',
  'MS',
  'MG',
  'PA',
  'PB',
  'PR',
  'PE',
  'PI',
  'RJ',
  'RN',
  'RS',
  'RO',
  'RR',
  'SC',
  'SP',
  'SE',
  'TO',
];

const kMedicalSpecialties = <String>[
  'Acupuntura',
  'Alergia e Imunologia',
  'Anestesiologia',
  'Angiologia',
  'Cardiologia',
  'Cirurgia Cardiovascular',
  'Cirurgia da Mão',
  'Cirurgia de Cabeça e Pescoço',
  'Cirurgia do Aparelho Digestivo',
  'Cirurgia Geral',
  'Cirurgia Pediátrica',
  'Cirurgia Plástica',
  'Cirurgia Torácica',
  'Cirurgia Vascular',
  'Clínica Médica',
  'Coloproctologia',
  'Dermatologia',
  'Endocrinologia',
  'Endoscopia',
  'Gastroenterologia',
  'Genética Médica',
  'Geriatria',
  'Ginecologia e Obstetrícia',
  'Hematologia',
  'Homeopatia',
  'Infectologia',
  'Mastologia',
  'Medicina de Emergência',
  'Medicina de Família e Comunidade',
  'Medicina do Trabalho',
  'Medicina Esportiva',
  'Medicina Física e Reabilitação',
  'Medicina Intensiva',
  'Medicina Legal',
  'Medicina Nuclear',
  'Nefrologia',
  'Neurocirurgia',
  'Neurologia',
  'Nutrologia',
  'Oftalmologia',
  'Oncologia',
  'Ortopedia e Traumatologia',
  'Otorrinolaringologia',
  'Patologia',
  'Pediatria',
  'Pneumologia',
  'Psiquiatria',
  'Radiologia e Diagnóstico por Imagem',
  'Radioterapia',
  'Reumatologia',
  'Urologia',
];

const kCommonHealthPlans = <String>[
  'Particular',
  'Unimed',
  'Bradesco Saúde',
  'Amil',
  'SulAmérica',
  'NotreDame Intermédica',
  'Hapvida',
  'Porto Seguro',
  'Prevent Senior',
  'Cassi',
];

bool isValidBrazilianUf(String value) {
  return kBrazilianStates.contains(value.trim().toUpperCase());
}

bool isValidCrmNumber(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  return digits.length >= 4 && digits.length <= 7;
}

List<String> suggestSpecialties(String query, {Iterable<String> extra = const []}) {
  final seen = <String>{};
  final pool = <String>[
    ...extra.where((item) => item.trim().isNotEmpty),
    ...kMedicalSpecialties,
  ];
  final normalized = query.trim().toLowerCase();
  final matches = <String>[];
  for (final specialty in pool) {
    final key = specialty.toLowerCase();
    if (!seen.add(key)) continue;
    if (normalized.isEmpty || key.contains(normalized)) {
      matches.add(specialty);
    }
  }
  matches.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return matches;
}
