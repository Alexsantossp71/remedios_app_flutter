import 'package:uuid/uuid.dart';

/// Represents a health plan or medical insurance/coverage.
class HealthPlan {
  final String id;
  final String name;
  final String provider;
  final String? cardNumber;
  final String? groupNumber;
  final String? beneficiaryCode;
  final String? validity;
  final String? coverageType;
  final List<String> specialties;
  final String? notes;
  final String createdAt;
  final String updatedAt;

  const HealthPlan({
    required this.id,
    required this.name,
    required this.provider,
    this.cardNumber,
    this.groupNumber,
    this.beneficiaryCode,
    this.validity,
    this.coverageType,
    this.specialties = const [],
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Creates a new HealthPlan with auto-generated ID and timestamps.
  factory HealthPlan.create({
    required String name,
    required String provider,
    String? cardNumber,
    String? groupNumber,
    String? beneficiaryCode,
    String? validity,
    String? coverageType,
    List<String> specialties = const [],
    String? notes,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    return HealthPlan(
      id: const Uuid().v4(),
      name: name,
      provider: provider,
      cardNumber: cardNumber,
      groupNumber: groupNumber,
      beneficiaryCode: beneficiaryCode,
      validity: validity,
      coverageType: coverageType,
      specialties: specialties,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );
  }

  factory HealthPlan.fromJson(Map<String, dynamic> json) {
    final rawSpecialties = json['specialties'] as List<dynamic>? ?? const [];
    return HealthPlan(
      id: json['id'] as String,
      name: json['name'] as String,
      provider: json['provider'] as String,
      cardNumber: json['cardNumber'] as String?,
      groupNumber: json['groupNumber'] as String?,
      beneficiaryCode: json['beneficiaryCode'] as String?,
      validity: json['validity'] as String?,
      coverageType: json['coverageType'] as String?,
      specialties: rawSpecialties.map((s) => s as String).toList(),
      notes: json['notes'] as String?,
      createdAt: json['createdAt'] as String,
      updatedAt: json['updatedAt'] as String,
    );
  }

  HealthPlan copyWith({
    String? name,
    String? provider,
    String? cardNumber,
    String? groupNumber,
    String? beneficiaryCode,
    String? validity,
    String? coverageType,
    List<String>? specialties,
    String? notes,
  }) {
    return HealthPlan(
      id: id,
      name: name ?? this.name,
      provider: provider ?? this.provider,
      cardNumber: cardNumber ?? this.cardNumber,
      groupNumber: groupNumber ?? this.groupNumber,
      beneficiaryCode: beneficiaryCode ?? this.beneficiaryCode,
      validity: validity ?? this.validity,
      coverageType: coverageType ?? this.coverageType,
      specialties: specialties ?? this.specialties,
      notes: notes ?? this.notes,
      createdAt: createdAt,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'provider': provider,
      'cardNumber': cardNumber,
      'groupNumber': groupNumber,
      'beneficiaryCode': beneficiaryCode,
      'validity': validity,
      'coverageType': coverageType,
      'specialties': specialties,
      'notes': notes,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  /// Returns a display string for the card (name + truncated card number).
  String get displayName => name;

  /// Returns masked card number for display (show last 4 digits).
  String? get maskedCardNumber {
    if (cardNumber == null || cardNumber!.length < 4) return cardNumber;
    return '•••• ${cardNumber!.substring(cardNumber!.length - 4)}';
  }
}

/// Common health plan providers for quick selection.
const kCommonProviders = [
  'Unimed',
  'Bradesco Saúde',
  'SulAmérica',
  'Amil',
  'NotreDame Intermédica',
  'Golden Cross',
  'Cassi',
  'Saúde Caixa',
  'Porto Seguro',
  'Omint',
  'Care Plus',
  'Medial',
  'Green Line',
  'São Francisco',
  'Hapvida',
  'Prevent Senior',
  'Outros',
];

/// Common coverage types.
const kCoverageTypes = [
  'Ambulatorial',
  'Hospitalar',
  'Odontológico',
  'Ambulatorial + Hospitalar',
  'Ambulatorial + Odontológico',
  'Completo (médico + odontológico)',
  'Emergência',
  'Urgência',
];

/// Common medical specialties for coverage selection.
const kMedicalSpecialties = [
  'Clínico Geral',
  'Cardiologia',
  'Dermatologia',
  'Endocrinologia',
  'Gastroenterologia',
  'Ginecologia',
  'Neurologia',
  'Oftalmologia',
  'Ortopedia',
  'Pediatria',
  'Psiquiatria',
  'Urologia',
];
