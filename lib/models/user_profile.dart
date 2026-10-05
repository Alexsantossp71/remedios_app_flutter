/// Tipo sanguíneo com fator Rh (ex.: 'A+', 'O-').
enum TipoSanguineo {
  aPos('A+'),
  aNeg('A-'),
  bPos('B+'),
  bNeg('B-'),
  abPos('AB+'),
  abNeg('AB-'),
  oPos('O+'),
  oNeg('O-');

  const TipoSanguineo(this.value);

  /// Representação textual (ex.: 'A+').
  final String value;

  /// Converte a representação textual em enum, ou null se não reconhecido.
  static TipoSanguineo? fromValue(String? value) {
    if (value == null || value.isEmpty) return null;
    for (final tipo in TipoSanguineo.values) {
      if (tipo.value == value) return tipo;
    }
    return null;
  }
}

/// Representa o perfil do usuário (dados pessoais e de saúde).
class UserProfile {
  final String nome;
  final String? cpf;
  final DateTime? dataNascimento;
  final String? fotoPath;
  final TipoSanguineo? tipoSanguineo;
  final List<String> alergias;
  final List<String> condicoesCronicas;
  final double? peso;
  final double? altura;
  final String? telefone;
  final String? observacoes;
  final DateTime? consentAt;
  final String createdAt;
  final String updatedAt;

  const UserProfile({
    this.nome = '',
    this.cpf,
    this.dataNascimento,
    this.fotoPath,
    this.tipoSanguineo,
    this.alergias = const [],
    this.condicoesCronicas = const [],
    this.peso,
    this.altura,
    this.telefone,
    this.observacoes,
    this.consentAt,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Cria um perfil vazio com timestamps.
  factory UserProfile.empty() {
    final now = DateTime.now().toUtc().toIso8601String();
    return UserProfile(createdAt: now, updatedAt: now);
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    List<String> parseList(dynamic raw) {
      if (raw is List) return raw.map((e) => e.toString()).toList();
      return const [];
    }

    return UserProfile(
      nome: json['nome'] as String? ?? '',
      cpf: json['cpf'] as String?,
      dataNascimento: json['dataNascimento'] != null
          ? DateTime.tryParse(json['dataNascimento'] as String)
          : null,
      fotoPath: json['fotoPath'] as String?,
      tipoSanguineo: TipoSanguineo.fromValue(json['tipoSanguineo'] as String?),
      alergias: parseList(json['alergias']),
      condicoesCronicas: parseList(json['condicoesCronicas']),
      peso: (json['peso'] as num?)?.toDouble(),
      altura: (json['altura'] as num?)?.toDouble(),
      telefone: json['telefone'] as String?,
      observacoes: json['observacoes'] as String?,
      consentAt: json['consentAt'] != null
          ? DateTime.tryParse(json['consentAt'] as String)
          : null,
      createdAt: json['createdAt'] as String,
      updatedAt: json['updatedAt'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'nome': nome,
      'cpf': cpf,
      'dataNascimento': dataNascimento?.toUtc().toIso8601String(),
      'fotoPath': fotoPath,
      'tipoSanguineo': tipoSanguineo?.value,
      'alergias': alergias,
      'condicoesCronicas': condicoesCronicas,
      'peso': peso,
      'altura': altura,
      'telefone': telefone,
      'observacoes': observacoes,
      'consentAt': consentAt?.toUtc().toIso8601String(),
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  UserProfile copyWith({
    String? nome,
    String? cpf,
    DateTime? dataNascimento,
    String? fotoPath,
    TipoSanguineo? tipoSanguineo,
    List<String>? alergias,
    List<String>? condicoesCronicas,
    double? peso,
    double? altura,
    String? telefone,
    String? observacoes,
    DateTime? consentAt,
  }) {
    return UserProfile(
      nome: nome ?? this.nome,
      cpf: cpf ?? this.cpf,
      dataNascimento: dataNascimento ?? this.dataNascimento,
      fotoPath: fotoPath ?? this.fotoPath,
      tipoSanguineo: tipoSanguineo ?? this.tipoSanguineo,
      alergias: alergias ?? this.alergias,
      condicoesCronicas: condicoesCronicas ?? this.condicoesCronicas,
      peso: peso ?? this.peso,
      altura: altura ?? this.altura,
      telefone: telefone ?? this.telefone,
      observacoes: observacoes ?? this.observacoes,
      consentAt: consentAt ?? this.consentAt,
      createdAt: createdAt,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }
}
