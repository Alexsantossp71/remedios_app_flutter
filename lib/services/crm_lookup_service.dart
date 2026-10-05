import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Result of a CRM lookup against a state medical council.
enum CrmLookupKind { success, notFound, unsupported, error }

class CrmLookupResult {
  const CrmLookupResult._({
    required this.kind,
    this.name = '',
    this.specialty = '',
    this.statusText = '',
    this.school = '',
    this.uf = '',
    this.message = '',
  });

  factory CrmLookupResult.success({
    required String name,
    required String specialty,
    required String statusText,
    required String school,
  }) =>
      CrmLookupResult._(
        kind: CrmLookupKind.success,
        name: name,
        specialty: specialty,
        statusText: statusText,
        school: school,
      );

  factory CrmLookupResult.notFound() =>
      const CrmLookupResult._(kind: CrmLookupKind.notFound);

  factory CrmLookupResult.unsupported(String uf) =>
      CrmLookupResult._(kind: CrmLookupKind.unsupported, uf: uf);

  factory CrmLookupResult.error(String message) =>
      CrmLookupResult._(kind: CrmLookupKind.error, message: message);

  final CrmLookupKind kind;
  final String name;
  final String specialty;
  final String statusText;
  final String school;
  final String uf;
  final String message;
}

const _nameParticles = {'da', 'de', 'do', 'das', 'dos', 'e'};

String titleCaseName(String raw) {
  final words = raw.trim().toLowerCase().split(RegExp(r'\s+'));
  return words
      .asMap()
      .entries
      .map((entry) {
        final word = entry.value;
        if (word.isEmpty) return word;
        if (entry.key > 0 && _nameParticles.contains(word)) return word;
        return word[0].toUpperCase() + word.substring(1);
      })
      .join(' ');
}

class CrmLookupService {
  CrmLookupService({http.Client? client, bool? isWebOverride})
      : _client = client ?? http.Client(),
        _isWeb = isWebOverride ?? kIsWeb;

  final http.Client _client;
  final bool _isWeb;

  static const _spBase = 'https://api.cremesp.org.br/guia-medico/medico-info';
  static const _proxyBase = 'https://api.allorigins.win/raw?url=';

  Future<CrmLookupResult> lookup(String crm, String uf) async {
    final digits = crm.replaceAll(RegExp(r'\D'), '');
    final normalizedUf = uf.trim().toUpperCase();
    if (digits.isEmpty || normalizedUf.isEmpty) {
      return CrmLookupResult.error('Informe CRM e UF');
    }
    if (normalizedUf != 'SP') {
      return CrmLookupResult.unsupported(normalizedUf);
    }

    final target = '$_spBase/$digits';
    final url = _isWeb
        ? Uri.parse('$_proxyBase${Uri.encodeComponent(target)}')
        : Uri.parse(target);

    try {
      final response =
          await _client.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 404) return CrmLookupResult.notFound();
      if (response.statusCode != 200) {
        return CrmLookupResult.error('Erro ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) {
        return CrmLookupResult.error('Resposta inesperada');
      }

      return CrmLookupResult.success(
        name: titleCaseName(
          (data['nomeLimpo'] ?? data['nome'] ?? '') as String,
        ),
        specialty: _firstSpecialty(data),
        statusText: _statusText(data),
        school: (data['escolaNome'] as String? ?? '').trim(),
      );
    } catch (e) {
      return CrmLookupResult.error('Falha na consulta: $e');
    }
  }

  static String _firstSpecialty(Map<String, dynamic> data) {
    final list = data['especialidades'];
    if (list is List && list.isNotEmpty) {
      final first = list.first;
      if (first is Map<String, dynamic>) {
        return (first['descricao'] as String? ?? '').trim();
      }
    }
    return '';
  }

  static String _statusText(Map<String, dynamic> data) {
    final situacao = (data['situacao'] as String? ?? '').toUpperCase();
    if (situacao == 'A') return 'Ativo';
    final mensagem = (data['mensagemStatus'] as String? ?? '').trim();
    if (mensagem.isNotEmpty) return 'Inativo: $mensagem';
    return situacao == 'I' ? 'Inativo' : '';
  }
}
