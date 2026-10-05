import 'package:flutter_test/flutter_test.dart';
import 'package:remedios_app_flutter/models/emergency_contact.dart';

void main() {
  group('EmergencyContact.create', () {
    test('generates unique non-empty ids', () {
      final a = EmergencyContact.create(nome: 'Ana', telefone: '111');
      final b = EmergencyContact.create(nome: 'Ana', telefone: '111');
      expect(a.id, isNotEmpty);
      expect(b.id, isNotEmpty);
      expect(a.id, isNot(b.id));
    });

    test('applies default parentesco', () {
      final c = EmergencyContact.create(nome: 'Ana', telefone: '111');
      expect(c.parentesco, '');
    });
  });

  group('EmergencyContact toJson/fromJson', () {
    test('round-trip preserves all values', () {
      const contact = EmergencyContact(
        id: 'abc-123',
        nome: 'Carlos',
        parentesco: 'Irmão',
        telefone: '11987654321',
      );
      final restored = EmergencyContact.fromJson(contact.toJson());
      expect(restored.id, 'abc-123');
      expect(restored.nome, 'Carlos');
      expect(restored.parentesco, 'Irmão');
      expect(restored.telefone, '11987654321');
    });

    test('fromJson handles missing optional fields', () {
      final contact = EmergencyContact.fromJson(const {'id': 'x'});
      expect(contact.id, 'x');
      expect(contact.nome, '');
      expect(contact.parentesco, '');
      expect(contact.telefone, '');
    });
  });

  group('EmergencyContact.copyWith', () {
    test('updates fields and preserves id', () {
      const original = EmergencyContact(
        id: 'keep-me',
        nome: 'Ana',
        parentesco: 'Mãe',
        telefone: '111',
      );
      final updated = original.copyWith(telefone: '222');
      expect(updated.id, 'keep-me');
      expect(updated.nome, 'Ana');
      expect(updated.parentesco, 'Mãe');
      expect(updated.telefone, '222');
    });

    test('copyWith with no args returns equal values', () {
      const original = EmergencyContact(
        id: 'id-1',
        nome: 'Ana',
        parentesco: 'Mãe',
        telefone: '111',
      );
      final copy = original.copyWith();
      expect(copy.id, original.id);
      expect(copy.nome, original.nome);
      expect(copy.parentesco, original.parentesco);
      expect(copy.telefone, original.telefone);
    });
  });
}
