import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:remedios_app_flutter/core/service_locator.dart';
import 'package:remedios_app_flutter/main.dart';
import 'package:remedios_app_flutter/services/backup_crypto_service.dart';
import 'package:remedios_app_flutter/services/backup_service.dart';
import 'package:remedios_app_flutter/services/consultation_storage_service.dart';
import 'package:remedios_app_flutter/services/database_service.dart';
import 'package:remedios_app_flutter/services/doctor_storage_service.dart';
import 'package:remedios_app_flutter/services/exam_storage_service.dart';
import 'package:remedios_app_flutter/services/health_plan_storage_service.dart';
import 'package:remedios_app_flutter/services/lab_result_storage_service.dart';
import 'package:remedios_app_flutter/services/notification_service.dart';
import 'package:remedios_app_flutter/services/therapy_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    sl.reset();
  });

  group('setupServiceLocator', () {
    test('registra todas as dependências do app', () {
      setupServiceLocator();

      // Infraestrutura compartilhada (instâncias únicas do app).
      expect(sl<DatabaseService>(), same(DatabaseService.instance));
      expect(sl<NotificationService>(), same(NotificationService.instance));

      // Lazy singletons: mesma instância em resoluções repetidas.
      expect(sl<BackupService>(), same(sl<BackupService>()));
      expect(sl<BackupCryptoService>(), same(BackupCryptoService.instance));
      expect(sl<TherapyStorageService>(), same(sl<TherapyStorageService>()));
      expect(sl<DoctorStorageService>(), same(sl<DoctorStorageService>()));
      expect(
        sl<ConsultationStorageService>(),
        same(sl<ConsultationStorageService>()),
      );
      expect(sl<ExamStorageService>(), same(sl<ExamStorageService>()));
      expect(
        sl<LabResultStorageService>(),
        same(sl<LabResultStorageService>()),
      );
      expect(
        sl<HealthPlanStorageService>(),
        same(sl<HealthPlanStorageService>()),
      );
    });

    test(
      'sl.reset() permite re-registro (contrato para fakes em teste)',
      () async {
        setupServiceLocator();
        // get_it 8: reset é assíncrono (descarta singletons registrados).
        await sl.reset();
        setupServiceLocator();

        expect(sl.isRegistered<BackupService>(), isTrue);
        expect(sl.isRegistered<TherapyStorageService>(), isTrue);
      },
    );
  });

  group('bootstrapApp (P2-2: bootstrap testável)', () {
    testWidgets('resolve providers do locator e monta a árvore', (
      tester,
    ) async {
      // runAsync roda fora da zona fake: o IO do SQLite em memória completa
      // (mesma estratégia de widget_test.dart) e runApp anexa a árvore real.
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        await DatabaseService.instance.initInMemoryDatabase();
        setupServiceLocator();

        await bootstrapApp(sl<NotificationService>());
      });

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(RemediosApp), findsOneWidget);
    });

    testWidgets('falha claramente quando o locator não foi configurado', (
      tester,
    ) async {
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        await DatabaseService.instance.initInMemoryDatabase();
      });

      // Sem setupServiceLocator: get_it lança erro explícito em vez de
      // construir providers com dependências silenciosamente erradas.
      expect(
        () => bootstrapApp(NotificationService.instance),
        throwsStateError,
      );
    });
  });
}
