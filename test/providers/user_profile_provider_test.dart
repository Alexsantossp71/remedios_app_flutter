import 'package:flutter_test/flutter_test.dart';
import 'package:remedios_app_flutter/models/emergency_contact.dart';
import 'package:remedios_app_flutter/models/user_profile.dart';
import 'package:remedios_app_flutter/providers/user_profile_provider.dart';
import 'package:remedios_app_flutter/services/database_service.dart';

import '../database_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UserProfileProvider', () {
    setUp(() async {
      await setupTestDatabase();
    });

    tearDown(() async {
      await DatabaseService.instance.close();
    });

    UserProfile buildProfile() {
      final now = DateTime.now().toUtc().toIso8601String();
      return UserProfile(
        nome: 'Maria Silva',
        cpf: '123.456.789-00',
        dataNascimento: DateTime.utc(1985, 3, 15),
        tipoSanguineo: TipoSanguineo.aPos,
        alergias: const ['Dipirona'],
        condicoesCronicas: const ['Hipertensão'],
        peso: 70,
        altura: 1.70,
        telefone: '11999998888',
        observacoes: 'Obs',
        createdAt: now,
        updatedAt: now,
      );
    }

    test('starts with null profile and empty contacts', () async {
      final provider = UserProfileProvider();
      await provider.initialize();

      expect(provider.profile, isNull);
      expect(provider.emergencyContacts, isEmpty);
      expect(provider.isLoading, isFalse);
    });

    test('saveProfile persiste e recarrega em nova instância', () async {
      final provider = UserProfileProvider();
      await provider.initialize();
      await provider.saveProfile(buildProfile());

      expect(provider.profile?.nome, 'Maria Silva');
      expect(provider.profile?.cpf, '123.456.789-00');

      final reloaded = UserProfileProvider();
      await reloaded.initialize();

      expect(reloaded.profile, isNotNull);
      expect(reloaded.profile?.nome, 'Maria Silva');
      expect(reloaded.profile?.cpf, '123.456.789-00');
      expect(reloaded.profile?.tipoSanguineo, TipoSanguineo.aPos);
      expect(reloaded.profile?.alergias, ['Dipirona']);
      expect(reloaded.profile?.condicoesCronicas, ['Hipertensão']);
      expect(reloaded.profile?.peso, 70.0);
      expect(reloaded.profile?.altura, 1.70);
      expect(reloaded.profile?.telefone, '11999998888');
      expect(reloaded.profile?.observacoes, 'Obs');
    });

    test('consentAt persiste no banco e recarrega (LGPD)', () async {
      final provider = UserProfileProvider();
      await provider.initialize();

      expect(provider.profile?.consentAt, isNull);

      final consentAt = DateTime.utc(2026, 3, 10, 9, 30);
      await provider.saveProfile(
          buildProfile().copyWith(consentAt: consentAt));

      expect(provider.profile?.consentAt, consentAt);

      final reloaded = UserProfileProvider();
      await reloaded.initialize();
      expect(reloaded.profile?.consentAt, consentAt);

      // deleteAllData (revogação) remove o consentimento junto com o
      // perfil — nova instância volta a ter consentAt null.
      await reloaded.deleteAllData();
      final fresh = UserProfileProvider();
      await fresh.initialize();
      expect(fresh.profile, isNull);
    });

    test('saveProfile substitui a linha única e preserva createdAt',
        () async {
      final provider = UserProfileProvider();
      await provider.initialize();
      await provider.saveProfile(buildProfile());
      final createdAt = provider.profile!.createdAt;

      await provider.saveProfile(buildProfile().copyWith(nome: 'Maria Souza'));

      expect(provider.profile?.nome, 'Maria Souza');
      expect(provider.profile?.createdAt, createdAt);

      final reloaded = UserProfileProvider();
      await reloaded.initialize();
      expect(reloaded.profile?.nome, 'Maria Souza');
    });

    test('contatos de emergência: add, update, remove persistem', () async {
      final provider = UserProfileProvider();
      await provider.initialize();

      final ana = EmergencyContact.create(
          nome: 'Ana', parentesco: 'Irmã', telefone: '1111');
      final bruno = EmergencyContact.create(
          nome: 'Bruno', parentesco: 'Pai', telefone: '2222');
      await provider.addEmergencyContact(bruno);
      await provider.addEmergencyContact(ana);

      // ordenados por nome (case-insensitive)
      expect(provider.emergencyContacts.map((c) => c.nome).toList(),
          ['Ana', 'Bruno']);

      await provider.updateEmergencyContact(
          ana.copyWith(telefone: '3333'));
      expect(provider.emergencyContacts.first.telefone, '3333');

      final reloaded = UserProfileProvider();
      await reloaded.initialize();
      expect(reloaded.emergencyContacts.length, 2);
      expect(reloaded.emergencyContacts.first.nome, 'Ana');
      expect(reloaded.emergencyContacts.first.telefone, '3333');

      await reloaded.removeEmergencyContact(ana.id);
      expect(reloaded.emergencyContacts.length, 1);
      expect(reloaded.emergencyContacts.first.nome, 'Bruno');
    });

    test('deleteAllData limpa perfil e contatos (LGPD)', () async {
      final provider = UserProfileProvider();
      await provider.initialize();
      await provider.saveProfile(buildProfile());
      await provider.addEmergencyContact(
          EmergencyContact.create(nome: 'Ana', telefone: '1111'));

      await provider.deleteAllData();

      expect(provider.profile, isNull);
      expect(provider.emergencyContacts, isEmpty);

      final reloaded = UserProfileProvider();
      await reloaded.initialize();
      expect(reloaded.profile, isNull);
      expect(reloaded.emergencyContacts, isEmpty);
    });
  });
}
