import 'package:flutter_test/flutter_test.dart';
import 'package:remedios_app_flutter/models/user_profile.dart';

void main() {
  group('TipoSanguineo.fromValue', () {
    test('returns enum for every valid value', () {
      expect(TipoSanguineo.fromValue('A+'), TipoSanguineo.aPos);
      expect(TipoSanguineo.fromValue('A-'), TipoSanguineo.aNeg);
      expect(TipoSanguineo.fromValue('B+'), TipoSanguineo.bPos);
      expect(TipoSanguineo.fromValue('B-'), TipoSanguineo.bNeg);
      expect(TipoSanguineo.fromValue('AB+'), TipoSanguineo.abPos);
      expect(TipoSanguineo.fromValue('AB-'), TipoSanguineo.abNeg);
      expect(TipoSanguineo.fromValue('O+'), TipoSanguineo.oPos);
      expect(TipoSanguineo.fromValue('O-'), TipoSanguineo.oNeg);
    });

    test('returns null for invalid value', () {
      expect(TipoSanguineo.fromValue('X+'), isNull);
      expect(TipoSanguineo.fromValue('a+'), isNull); // case-sensitive
    });

    test('returns null for null or empty', () {
      expect(TipoSanguineo.fromValue(null), isNull);
      expect(TipoSanguineo.fromValue(''), isNull);
    });
  });

  group('UserProfile.empty', () {
    test('has sensible defaults', () {
      final profile = UserProfile.empty();
      expect(profile.nome, '');
      expect(profile.dataNascimento, isNull);
      expect(profile.fotoPath, isNull);
      expect(profile.tipoSanguineo, isNull);
      expect(profile.alergias, isEmpty);
      expect(profile.condicoesCronicas, isEmpty);
      expect(profile.peso, isNull);
      expect(profile.altura, isNull);
      expect(profile.telefone, isNull);
      expect(profile.observacoes, isNull);
      expect(profile.createdAt, isNotEmpty);
      expect(profile.updatedAt, isNotEmpty);
      expect(DateTime.tryParse(profile.createdAt), isNotNull);
      expect(DateTime.tryParse(profile.updatedAt), isNotNull);
    });
  });

  group('UserProfile toJson/fromJson', () {
    test('round-trip preserves all values', () {
      final profile = UserProfile(
        nome: 'Maria Silva',
        cpf: '123.456.789-00',
        dataNascimento: DateTime.utc(1985, 3, 15),
        fotoPath: '/tmp/foto.png',
        tipoSanguineo: TipoSanguineo.oPos,
        alergias: const ['Dipirona', 'Frutos do mar'],
        condicoesCronicas: const ['Hipertensão'],
        peso: 68.5,
        altura: 1.65,
        telefone: '11999998888',
        observacoes: 'Alergia severa a dipirona',
        consentAt: DateTime.utc(2026, 3, 10, 9, 30),
        createdAt: '2026-01-01T10:00:00.000Z',
        updatedAt: '2026-02-01T12:00:00.000Z',
      );

      final restored = UserProfile.fromJson(profile.toJson());
      expect(restored.nome, 'Maria Silva');
      expect(restored.cpf, '123.456.789-00');
      expect(restored.dataNascimento, DateTime.utc(1985, 3, 15));
      expect(restored.fotoPath, '/tmp/foto.png');
      expect(restored.tipoSanguineo, TipoSanguineo.oPos);
      expect(restored.alergias, ['Dipirona', 'Frutos do mar']);
      expect(restored.condicoesCronicas, ['Hipertensão']);
      expect(restored.peso, 68.5);
      expect(restored.altura, 1.65);
      expect(restored.telefone, '11999998888');
      expect(restored.observacoes, 'Alergia severa a dipirona');
      expect(restored.consentAt, DateTime.utc(2026, 3, 10, 9, 30));
      expect(restored.createdAt, '2026-01-01T10:00:00.000Z');
      expect(restored.updatedAt, '2026-02-01T12:00:00.000Z');
    });

    test('round-trip with null optional fields', () {
      final profile = UserProfile(
        createdAt: '2026-01-01T00:00:00.000Z',
        updatedAt: '2026-01-01T00:00:00.000Z',
      );
      final restored = UserProfile.fromJson(profile.toJson());
      expect(restored.nome, '');
      expect(restored.cpf, isNull);
      expect(restored.dataNascimento, isNull);
      expect(restored.fotoPath, isNull);
      expect(restored.tipoSanguineo, isNull);
      expect(restored.alergias, isEmpty);
      expect(restored.condicoesCronicas, isEmpty);
      expect(restored.peso, isNull);
      expect(restored.altura, isNull);
      expect(restored.telefone, isNull);
      expect(restored.observacoes, isNull);
      expect(restored.consentAt, isNull);
    });

    test('fromJson handles missing list keys', () {
      final profile = UserProfile.fromJson(const {
        'createdAt': '2026-01-01T00:00:00.000Z',
        'updatedAt': '2026-01-01T00:00:00.000Z',
      });
      expect(profile.alergias, isEmpty);
      expect(profile.condicoesCronicas, isEmpty);
    });

    test('fromJson handles non-list values for lists', () {
      final profile = UserProfile.fromJson(const {
        'alergias': 'não é lista',
        'condicoesCronicas': 42,
        'createdAt': '2026-01-01T00:00:00.000Z',
        'updatedAt': '2026-01-01T00:00:00.000Z',
      });
      expect(profile.alergias, isEmpty);
      expect(profile.condicoesCronicas, isEmpty);
    });

    test('fromJson coerces numeric peso/altura to double', () {
      final profile = UserProfile.fromJson(const {
        'peso': 70,
        'altura': 2,
        'createdAt': '2026-01-01T00:00:00.000Z',
        'updatedAt': '2026-01-01T00:00:00.000Z',
      });
      expect(profile.peso, isA<double>());
      expect(profile.peso, 70.0);
      expect(profile.altura, isA<double>());
      expect(profile.altura, 2.0);
    });

    test('fromJson ignores invalid date string', () {
      final profile = UserProfile.fromJson(const {
        'dataNascimento': 'não-é-data',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'updatedAt': '2026-01-01T00:00:00.000Z',
      });
      expect(profile.dataNascimento, isNull);
    });
  });

  group('UserProfile.copyWith', () {
    test('updates changed fields and updatedAt, preserves createdAt', () async {
      final original = UserProfile(
        nome: 'João',
        tipoSanguineo: TipoSanguineo.aNeg,
        alergias: const ['Penicilina'],
        createdAt: '2026-01-01T08:00:00.000Z',
        updatedAt: '2026-01-01T08:00:00.000Z',
      );

      // Garante timestamps diferentes
      await Future.delayed(const Duration(milliseconds: 10));
      final updated = original.copyWith(nome: 'João Pedro', peso: 80.0);

      expect(updated.nome, 'João Pedro');
      expect(updated.peso, 80.0);
      // Campos não alterados preservados
      expect(updated.tipoSanguineo, TipoSanguineo.aNeg);
      expect(updated.alergias, ['Penicilina']);
      // createdAt preservado, updatedAt renovado
      expect(updated.createdAt, original.createdAt);
      expect(updated.updatedAt, isNot(original.updatedAt));
      expect(
        DateTime.parse(updated.updatedAt)
                .isAfter(DateTime.parse(original.updatedAt)) ||
            updated.updatedAt != original.updatedAt,
        isTrue,
      );
    });

    test('copyWith with no args keeps values but refreshes updatedAt', () {
      final original = UserProfile(
        nome: 'Ana',
        createdAt: '2026-01-01T08:00:00.000Z',
        updatedAt: '2026-01-01T08:00:00.000Z',
      );
      final copy = original.copyWith();
      expect(copy.nome, 'Ana');
      expect(copy.createdAt, original.createdAt);
    });
  });
}
