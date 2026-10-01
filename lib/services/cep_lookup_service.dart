import 'dart:convert';

import 'package:http/http.dart' as http;

class AddressLookup {
  const AddressLookup({
    required this.street,
    required this.neighborhood,
    required this.city,
    required this.uf,
    this.complement = '',
  });

  final String street;
  final String neighborhood;
  final String city;
  final String uf;
  final String complement;
}

class CepLookupService {
  CepLookupService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<AddressLookup?> lookup(String cep) async {
    final digits = cep.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 8) return null;

    try {
      final response = await _client
          .get(Uri.https('viacep.com.br', '/ws/$digits/json/'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) return null;
      if (data['erro'] == true || data['erro'] == 'true') return null;

      return AddressLookup(
        street: (data['logradouro'] as String? ?? '').trim(),
        neighborhood: (data['bairro'] as String? ?? '').trim(),
        city: (data['localidade'] as String? ?? '').trim(),
        uf: (data['uf'] as String? ?? '').trim().toUpperCase(),
        complement: (data['complemento'] as String? ?? '').trim(),
      );
    } catch (_) {
      return null;
    }
  }
}
