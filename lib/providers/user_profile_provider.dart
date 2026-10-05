import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/emergency_contact.dart';
import '../models/user_profile.dart';
import '../services/database_service.dart';

/// Provider para gerenciar o estado do perfil do usuário e contatos de
/// emergência. Segue o mesmo padrão do HealthPlanProvider.
class UserProfileProvider extends ChangeNotifier {
  UserProfileProvider({DatabaseService? dbService})
      : _dbService = dbService ?? DatabaseService.instance;

  final DatabaseService _dbService;

  UserProfile? _profile;
  List<EmergencyContact> _emergencyContacts = [];
  bool _isLoading = true;

  /// Perfil atual do usuário (null se ainda não foi criado).
  UserProfile? get profile => _profile;

  /// Visão imutável dos contatos de emergência.
  UnmodifiableListView<EmergencyContact> get emergencyContacts =>
      UnmodifiableListView(_emergencyContacts);

  /// Retorna true enquanto carrega do armazenamento.
  bool get isLoading => _isLoading;

  /// Inicializa o provider carregando o perfil e os contatos.
  Future<void> initialize() async {
    final db = await _dbService.database;

    final profileRows = await db.query('user_profile', limit: 1);
    _profile =
        profileRows.isEmpty ? null : _rowToUserProfile(profileRows.first);

    final contactRows =
        await db.query('emergency_contacts', orderBy: 'nome ASC');
    _emergencyContacts =
        contactRows.map((row) => _rowToEmergencyContact(row)).toList();

    _isLoading = false;
    notifyListeners();
  }

  /// Salva (cria ou atualiza) o perfil do usuário.
  Future<void> saveProfile(UserProfile profile) async {
    final db = await _dbService.database;
    final now = DateTime.now().toUtc().toIso8601String();

    final createdAt = _profile?.createdAt ?? profile.createdAt;

    await db.insert(
      'user_profile',
      {
        'id': 1,
        'nome': profile.nome,
        'cpf': profile.cpf,
        'data_nascimento':
            profile.dataNascimento?.toUtc().toIso8601String(),
        'foto_path': profile.fotoPath,
        'tipo_sanguineo': profile.tipoSanguineo?.value,
        'alergias': jsonEncode(profile.alergias),
        'condicoes_cronicas': jsonEncode(profile.condicoesCronicas),
        'peso': profile.peso,
        'altura': profile.altura,
        'telefone': profile.telefone,
        'observacoes': profile.observacoes,
        'consent_at': profile.consentAt?.toUtc().toIso8601String(),
        'created_at': createdAt,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    _profile = UserProfile(
      nome: profile.nome,
      cpf: profile.cpf,
      dataNascimento: profile.dataNascimento,
      fotoPath: profile.fotoPath,
      tipoSanguineo: profile.tipoSanguineo,
      alergias: profile.alergias,
      condicoesCronicas: profile.condicoesCronicas,
      peso: profile.peso,
      altura: profile.altura,
      telefone: profile.telefone,
      observacoes: profile.observacoes,
      consentAt: profile.consentAt,
      createdAt: createdAt,
      updatedAt: now,
    );
    notifyListeners();
  }

  /// Registra o consentimento LGPD (art. 11) preservando os demais dados
  /// do perfil. Se o perfil ainda não existe, cria um perfil mínimo.
  Future<void> grantConsent() async {
    final consentAt = DateTime.now().toUtc();
    final current = _profile;
    await saveProfile(
      current != null
          ? current.copyWith(consentAt: consentAt)
          : UserProfile.empty().copyWith(consentAt: consentAt),
    );
  }

  /// Adiciona um contato de emergência.
  Future<void> addEmergencyContact(EmergencyContact contact) async {
    final db = await _dbService.database;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.insert('emergency_contacts', {
      'id': contact.id,
      'nome': contact.nome,
      'parentesco': contact.parentesco,
      'telefone': contact.telefone,
      'created_at': now,
      'updated_at': now,
    });

    _emergencyContacts = [..._emergencyContacts, contact];
    _sortContacts();
    notifyListeners();
  }

  /// Atualiza um contato de emergência existente.
  Future<void> updateEmergencyContact(EmergencyContact contact) async {
    final db = await _dbService.database;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.update(
      'emergency_contacts',
      {
        'nome': contact.nome,
        'parentesco': contact.parentesco,
        'telefone': contact.telefone,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [contact.id],
    );

    _emergencyContacts = [
      for (final item in _emergencyContacts)
        if (item.id == contact.id) contact else item,
    ];
    _sortContacts();
    notifyListeners();
  }

  /// Remove um contato de emergência pelo ID.
  Future<void> removeEmergencyContact(String id) async {
    final db = await _dbService.database;
    await db
        .delete('emergency_contacts', where: 'id = ?', whereArgs: [id]);

    _emergencyContacts =
        _emergencyContacts.where((c) => c.id != id).toList();
    notifyListeners();
  }

  /// Apaga todos os dados do perfil e contatos (LGPD).
  Future<void> deleteAllData() async {
    final db = await _dbService.database;
    await db.transaction((txn) async {
      await txn.delete('user_profile');
      await txn.delete('emergency_contacts');
    });

    _profile = null;
    _emergencyContacts = [];
    notifyListeners();
  }

  void _sortContacts() {
    _emergencyContacts.sort((first, second) =>
        first.nome.toLowerCase().compareTo(second.nome.toLowerCase()));
  }

  UserProfile _rowToUserProfile(Map<String, dynamic> row) {
    List<String> decodeList(dynamic raw) {
      try {
        return (jsonDecode(raw as String? ?? '[]') as List)
            .map((e) => e.toString())
            .toList();
      } catch (_) {
        return const [];
      }
    }

    String? nullIfEmpty(String? value) =>
        (value == null || value.isEmpty) ? null : value;

    return UserProfile(
      nome: row['nome'] as String? ?? '',
      cpf: nullIfEmpty(row['cpf'] as String?),
      dataNascimento: row['data_nascimento'] != null
          ? DateTime.tryParse(row['data_nascimento'] as String)
          : null,
      fotoPath: nullIfEmpty(row['foto_path'] as String?),
      tipoSanguineo:
          TipoSanguineo.fromValue(row['tipo_sanguineo'] as String?),
      alergias: decodeList(row['alergias']),
      condicoesCronicas: decodeList(row['condicoes_cronicas']),
      peso: (row['peso'] as num?)?.toDouble(),
      altura: (row['altura'] as num?)?.toDouble(),
      telefone: nullIfEmpty(row['telefone'] as String?),
      observacoes: nullIfEmpty(row['observacoes'] as String?),
      consentAt: row['consent_at'] != null
          ? DateTime.tryParse(row['consent_at'] as String)
          : null,
      createdAt: row['created_at'] as String,
      updatedAt: row['updated_at'] as String,
    );
  }

  EmergencyContact _rowToEmergencyContact(Map<String, dynamic> row) {
    return EmergencyContact(
      id: row['id'] as String,
      nome: row['nome'] as String? ?? '',
      parentesco: row['parentesco'] as String? ?? '',
      telefone: row['telefone'] as String? ?? '',
    );
  }
}
