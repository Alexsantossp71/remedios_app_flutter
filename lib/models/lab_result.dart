import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../core/lab_values.dart';

/// Laudo de laboratório fotografado e lido pela IA (ou digitado à mão) —
/// portado do PWA "Remédio na Hora".
class LabResult {
  const LabResult({
    required this.id,
    required this.date,
    this.labName = '',
    this.photo,
    this.values = const [],
    this.notes = '',
    this.createdAt,
  });

  factory LabResult.create({
    required DateTime date,
    String labName = '',
    String? photo,
    List<LabValue> values = const [],
    String notes = '',
  }) {
    return LabResult(
      id: const Uuid().v4(),
      date: date,
      labName: labName,
      photo: photo,
      values: values,
      notes: notes,
      createdAt: DateTime.now().toUtc(),
    );
  }

  final String id;

  /// Data do laudo/coleta.
  final DateTime date;

  /// Laboratório/clínica ('' quando não informado).
  final String labName;

  /// Foto do laudo em base64 JPEG; null quando não anexada.
  final String? photo;

  /// Um [LabValue] por marcador, na ordem do laudo.
  final List<LabValue> values;
  final String notes;
  final DateTime? createdAt;

  /// Resumo curto para o cartão: "12 valores · 2 altos · 1 baixo".
  String get valuesSummary {
    if (values.isEmpty) return 'Nenhum valor registrado';
    final high = values.where((v) => v.flag == 'high').length;
    final low = values.where((v) => v.flag == 'low').length;
    final summary = '${values.length} valores';
    if (high + low == 0) return '$summary na faixa ou sem faixa';
    return '$summary · ${[
      if (high > 0) '$high ${high == 1 ? 'acima' : 'acima'}',
      if (low > 0) '$low ${low == 1 ? 'abaixo' : 'abaixo'}',
    ].join(' · ')}';
  }

  int get highCount => values.where((v) => v.flag == 'high').length;
  int get lowCount => values.where((v) => v.flag == 'low').length;

  LabResult copyWith({
    DateTime? date,
    String? labName,
    String? photo,
    bool clearPhoto = false,
    List<LabValue>? values,
    String? notes,
  }) {
    return LabResult(
      id: id,
      date: date ?? this.date,
      labName: labName ?? this.labName,
      photo: clearPhoto ? null : (photo ?? this.photo),
      values: values ?? this.values,
      notes: notes ?? this.notes,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'labName': labName,
        'photo': photo,
        'values': values.map((value) => value.toJson()).toList(),
        'notes': notes,
        'createdAt': createdAt?.toUtc().toIso8601String(),
      };

  factory LabResult.fromJson(Map<String, dynamic> json) {
    final rawValues = json['values'];
    final values = rawValues is List
        ? rawValues
            .whereType<Map<String, dynamic>>()
            .map(LabValue.fromJson)
            .toList()
        : <LabValue>[];

    return LabResult(
      id: json['id'] as String,
      date: DateTime.parse(json['date'] as String),
      labName: json['labName'] as String? ?? '',
      photo: json['photo'] as String?,
      values: values,
      notes: json['notes'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
    );
  }

  /// Serialização em linha única (coluna values_json do SQLite).
  String get valuesJson =>
      jsonEncode(values.map((value) => value.toJson()).toList());

  static List<LabValue> valuesFromJsonText(String? text) {
    if (text == null || text.isEmpty) return const [];
    try {
      final decoded = jsonDecode(text);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(LabValue.fromJson)
          .toList();
    } on FormatException {
      return const [];
    }
  }
}
