import 'package:flutter_driver/flutter_driver.dart';
import 'package:test/test.dart';

void main() {
  group('Remedios App E2E Tests', () {
    late FlutterDriver driver;

    setUpAll(() async {
      driver = await FlutterDriver.connect();
    });

    tearDownAll(() async {
      await driver.close();
    });

    test('App loads with title', () async {
      // Wait for app to load
      await driver.waitFor(find.text('Remédio na Hora'));

      // Verify main navigation exists
      await driver.waitFor(find.text('Médicos'));
      await driver.waitFor(find.text('Medicamentos'));
      await driver.waitFor(find.text('Hoje'));
      await driver.waitFor(find.text('Consultas'));
      await driver.waitFor(find.text('Planos'));
    });

    test('Navigate to Médicos tab', () async {
      await driver.tap(find.text('Médicos'));
      await driver.waitFor(find.text('Seus médicos'));
      await driver.waitFor(find.text('Seu catálogo começa aqui'));
    });

    test('Navigate to Medicamentos tab', () async {
      await driver.tap(find.text('Medicamentos'));
      await driver.waitFor(find.text('Seus medicamentos'));
    });

    test('Navigate to Consultas tab', () async {
      await driver.tap(find.text('Consultas'));
      await driver.waitFor(find.text('Suas consultas'));
    });
  });
}
