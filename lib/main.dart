import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalMaterialLocalizations, GlobalCupertinoLocalizations;
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'core/observability.dart';
import 'core/service_locator.dart';
import 'core/theme/app_theme.dart';
import 'providers/consultation_provider.dart';
import 'providers/doctor_provider.dart';
import 'providers/exam_provider.dart';
import 'providers/health_plan_provider.dart';
import 'providers/lab_result_provider.dart';
import 'providers/therapy_provider.dart';
import 'providers/user_profile_provider.dart';
import 'screens/main_shell.dart';
import 'services/consultation_storage_service.dart';
import 'services/database_service.dart';
import 'services/doctor_storage_service.dart';
import 'services/exam_storage_service.dart';
import 'services/health_plan_storage_service.dart';
import 'services/lab_result_storage_service.dart';
import 'services/notification_service.dart';
import 'services/therapy_storage_service.dart';
import 'services/web_reminder_service.dart';
import 'widgets/database_unlock_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');

  // P2-2: dependências de infraestrutura registradas no service locator;
  // o bootstrap abaixo resolve tudo a partir dele (testável via fakes).
  setupServiceLocator();

  // P3-2: observabilidade de falhas. Dormant por default — só ativa com
  // --dart-define=SENTRY_DSN=... no build; sem o DSN é no-op.
  await setupObservability();

  // No-op on web; on mobile it also asks for the notification permission
  // (Android 13+) and creates the dose channel before any alarm is set.
  final notifications = sl<NotificationService>();
  await notifications.init();

  // Web: the encrypted database requires explicit unlock before any
  // provider touches the database. The gate handles setup, unlock and
  // recovery-envelope restoration; the app boots only after it succeeds.
  // Android/desktop resolve the key transparently (Keystore) and skip the
  // gate entirely.
  if (kIsWeb) {
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        locale: const Locale('pt', 'BR'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('pt', 'BR'), Locale('en', 'US')],
        home: DatabaseUnlockGate(
          onDatabaseReady: () {
            bootstrapApp(notifications);
          },
        ),
      ),
    );
    return;
  }
  await bootstrapApp(notifications);
}

Future<void> bootstrapApp(NotificationService notifications) async {
  // Todos os providers recebem suas dependências explicitamente do service
  // locator; em testes, registre fakes antes de chamar esta função.
  final therapyProvider = TherapyProvider(
    notifications: notifications,
    storage: sl<TherapyStorageService>(),
  );
  final doctorProvider = DoctorProvider(storage: sl<DoctorStorageService>());
  final consultationProvider = ConsultationProvider(
    storage: sl<ConsultationStorageService>(),
  );
  final examProvider = ExamProvider(storage: sl<ExamStorageService>());
  final labResultProvider = LabResultProvider(
    storage: sl<LabResultStorageService>(),
  );
  final healthPlanProvider = HealthPlanProvider(
    storage: sl<HealthPlanStorageService>(),
  );
  final userProfileProvider = UserProfileProvider(
    dbService: sl<DatabaseService>(),
  );
  await therapyProvider.initialize();
  await doctorProvider.initialize();
  await consultationProvider.initialize();
  await examProvider.initialize();
  await labResultProvider.initialize();
  await healthPlanProvider.initialize();
  await userProfileProvider.initialize();

  // Web: lembrete de dose enquanto o app está aberto no navegador (no-op
  // em mobile, onde os alarmes do sistema fazem esse papel — ADR 0005).
  WebReminderService.instance.attach(therapyProvider);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: therapyProvider),
        ChangeNotifierProvider.value(value: doctorProvider),
        ChangeNotifierProvider.value(value: consultationProvider),
        ChangeNotifierProvider.value(value: examProvider),
        ChangeNotifierProvider.value(value: labResultProvider),
        ChangeNotifierProvider.value(value: healthPlanProvider),
        ChangeNotifierProvider.value(value: userProfileProvider),
      ],
      child: const RemediosApp(),
    ),
  );
}

class RemediosApp extends StatelessWidget {
  const RemediosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Remédio na Hora',
      debugShowCheckedModeBanner: false,
      // V3 "Clínico calmo": claro e escuro com o mesmo seed; o modo segue o
      // sistema do dispositivo (ThemeMode.system).
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      locale: const Locale('pt', 'BR'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('pt', 'BR'), Locale('en', 'US')],
      home: const MainShell(),
    );
  }
}
