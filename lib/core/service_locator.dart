import 'package:get_it/get_it.dart';

import '../services/backup_crypto_service.dart';
import '../services/backup_service.dart';
import '../services/consultation_storage_service.dart';
import '../services/database_service.dart';
import '../services/doctor_storage_service.dart';
import '../services/exam_storage_service.dart';
import '../services/health_plan_storage_service.dart';
import '../services/lab_result_storage_service.dart';
import '../services/notification_service.dart';
import '../services/therapy_storage_service.dart';

/// Service locator global do app (P2-2 da auditoria arquitetural).
///
/// O bootstrap em `main.dart` registra as dependências de infraestrutura
/// aqui e resolve os providers a partir deste ponto único. Testes registram
/// os pares (fakes/banco em memória) e chamam [bootstrapApp] sem precisar
/// executar `main` — a inicialização passa a ser testável.
///
/// Camadas superiores continuam recebendo dependências via construtor (os
/// providers já aceitam os services como parâmetros opcionais); o locator
/// substitui a construção dispersa por wiring explícito e centralizado.
final GetIt sl = GetIt.instance;

/// Registra as dependências do app no service locator.
///
/// Chame uma única vez no boot ([main]). Em testes, use `sl.reset()` antes
/// de chamar novamente para re-registrar fakes.
void setupServiceLocator() {
  // Infraestrutura compartilhada.
  sl.registerLazySingleton<DatabaseService>(() => DatabaseService.instance);
  sl.registerLazySingleton<NotificationService>(
    () => NotificationService.instance,
  );

  // Storage services (um por agregado de dados).
  sl.registerLazySingleton<TherapyStorageService>(
    () => TherapyStorageService(),
  );
  sl.registerLazySingleton<DoctorStorageService>(() => DoctorStorageService());
  sl.registerLazySingleton<ConsultationStorageService>(
    () => ConsultationStorageService(),
  );
  sl.registerLazySingleton<ExamStorageService>(() => ExamStorageService());
  sl.registerLazySingleton<LabResultStorageService>(
    () => LabResultStorageService(),
  );
  sl.registerLazySingleton<HealthPlanStorageService>(
    () => HealthPlanStorageService(),
  );

  // Serviços de aplicação (bootstrap e telas de perfil/backup).
  sl.registerLazySingleton<BackupService>(() => BackupService());
  sl.registerLazySingleton<BackupCryptoService>(
    () => BackupCryptoService.instance,
  );
}
