import 'package:uuid/uuid.dart';

/// Representa um contato de emergência do usuário.
class EmergencyContact {
  final String id;
  final String nome;
  final String parentesco;
  final String telefone;

  const EmergencyContact({
    required this.id,
    required this.nome,
    this.parentesco = '',
    required this.telefone,
  });

  /// Cria um novo contato com ID gerado automaticamente.
  factory EmergencyContact.create({
    required String nome,
    String parentesco = '',
    required String telefone,
  }) {
    return EmergencyContact(
      id: const Uuid().v4(),
      nome: nome,
      parentesco: parentesco,
      telefone: telefone,
    );
  }

  factory EmergencyContact.fromJson(Map<String, dynamic> json) {
    return EmergencyContact(
      id: json['id'] as String,
      nome: json['nome'] as String? ?? '',
      parentesco: json['parentesco'] as String? ?? '',
      telefone: json['telefone'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nome': nome,
      'parentesco': parentesco,
      'telefone': telefone,
    };
  }

  EmergencyContact copyWith({
    String? nome,
    String? parentesco,
    String? telefone,
  }) {
    return EmergencyContact(
      id: id,
      nome: nome ?? this.nome,
      parentesco: parentesco ?? this.parentesco,
      telefone: telefone ?? this.telefone,
    );
  }
}
