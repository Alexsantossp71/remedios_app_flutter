import 'package:flutter_test/flutter_test.dart';

import 'package:remedios_app_flutter/models/doctor.dart';
import 'package:remedios_app_flutter/services/doctor_matching.dart';

/// Regra única de casamento de médico com o catálogo — usada por "quem
/// receitou" (tratamento), pedido de exame e foto da receita para cadastro.
Doctor doctorOf(String name, {String crm = '', String crmState = ''}) =>
    Doctor(id: 'id-$name-$crm-$crmState', name: name, crm: crm, crmState: crmState);

void main() {
  group('findDoctorInCatalog', () {
    test('casa pelo nome ignorando caixa e espaços extras', () {
      final catalog = [
        doctorOf('  joão   silva ', crm: '123456', crmState: 'SP'),
      ];
      final match = findDoctorInCatalog(catalog, name: 'João Silva');
      expect(match, isNotNull);
      expect(match!.crm, '123456');
    });

    test('casa por CRM+UF mesmo com nome ruidoso do OCR', () {
      final catalog = [doctorOf('Dr. João Silva', crm: '123456', crmState: 'SP')];
      final match = findDoctorInCatalog(
        catalog,
        name: 'Dr, Joao S1lva',
        crm: '123456',
        crmState: 'sp',
      );
      expect(match, isNotNull);
      expect(match!.name, 'Dr. João Silva');
    });

    test('mesmo nome com CRM divergente não casa (nova conferência)', () {
      final catalog = [doctorOf('Dr. João Silva', crm: '111111', crmState: 'SP')];
      expect(
        findDoctorInCatalog(catalog, name: 'Dr. João Silva', crm: '222222'),
        isNull,
      );
    });

    test('rascunho sem CRM casa médico do catálogo que tem CRM', () {
      final catalog = [doctorOf('Dr. João Silva', crm: '123456', crmState: 'SP')];
      expect(findDoctorInCatalog(catalog, name: 'dr. joão silva'), isNotNull);
    });

    test('médico sem CRM no catálogo casa por nome mesmo com CRM no rascunho', () {
      // "quem receitou" digitado à mão com CRM; o cadastro antigo não tinha
      // número — o nome continua confirmando quem é (completar depois).
      final catalog = [doctorOf('Dr. João Silva')];
      expect(
        findDoctorInCatalog(
          catalog,
          name: 'Dr. João Silva',
          crm: '123456',
          crmState: 'SP',
        ),
        isNotNull,
      );
    });

    test('CRM+UF idêntico de dois cadastros devolve o primeiro', () {
      final catalog = [
        doctorOf('Dr. A', crm: '123456', crmState: 'SP'),
        doctorOf('Dr. B', crm: '123456', crmState: 'SP'),
      ];
      final match = findDoctorInCatalog(
        catalog,
        name: 'Dr. B',
        crm: '123456',
        crmState: 'SP',
      );
      expect(match!.name, 'Dr. A'); // primeiro do catálogo vence
    });

    test('sem correspondente devolve null', () {
      expect(findDoctorInCatalog([doctorOf('Dra. Ana')], name: 'Dr. Bruno'),
          isNull);
      expect(findDoctorInCatalog(const [], name: 'Dra. Ana'), isNull);
      expect(findDoctorInCatalog([doctorOf('Dra. Ana')], name: '   '), isNull);
      // Nome vazio com CRM que não existe no catálogo: nada confirmado.
      expect(
        findDoctorInCatalog(
          [doctorOf('Dra. Ana', crm: '999999', crmState: 'RJ')],
          name: '',
          crm: '123456',
          crmState: 'SP',
        ),
        isNull,
      );
    });
  });

  group('normalizePersonName', () {
    test('caixa baixa, trim e espaços colapsados', () {
      expect(normalizePersonName('  Maria   da  SILVA '), 'maria da silva');
    });
  });
}
