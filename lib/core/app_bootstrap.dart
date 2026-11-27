import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalMaterialLocalizations, GlobalCupertinoLocalizations;
import 'package:provider/provider.dart';

import '../core/service_locator.dart';
import '../core/theme/app_theme.dart';
import '../providers/consultation_provider.dart';
import '../providers/doctor_provider.dart';
import '../providers/exam_provider.dart';
import '../providers/health_plan_provider.dart';
import '../providers/lab_result_provider.dart';
import '../providers/therapy_provider.dart';
import '../providers/user_profile_provider.dart';
import '../screens/main_shell.dart';
import '../services/consultation_storage_service.dart';
import '../services/database_key/database_key_service.dart';
import '../services/database_key/database_key_store.dart';
import '../services/database_service.dart';
import '../services/doctor_storage_service.dart';
import '../services/exam_storage_service.dart';
import '../services/health_plan_storage_service.dart';
import '../services/lab_result_storage_service.dart';
import '../services/notification_service.dart';
import '../services/therapy_storage_service.dart';
import '../services/web_reminder_service.dart';
import '../widgets/boot_loader.dart';
import '../widgets/database_unlock_gate.dart';
import 'boot/boot_steps.dart';

/// Bootstrap da app em diferentes modos.
///
/// Separado de `main.dart` para que [MainShell] possa chamar [exitDemoMode]
/// quando o usuário sai do demo, sem criar dependência circular com o
/// entry point.

/// Configuração comum de MaterialApp (tema, locale, semantics).
MaterialApp _materialApp({required Widget home}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
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
    home: home,
  );
}

/// Mostra o BootLoader — tela de carregamento com porcentagem (0–100%)
/// que roda em TODA abertura do app, web e nativo.
///
/// Ao chegar a 100% o carregamento PARA — não navega sozinho. Na própria
/// tela aparecem os botões:
/// - **Entrar** → [enterPersistentApp]: web leva à criação do cofre
///   ([runUnlockGate]) na primeira interação do aparelho ou abre o app
///   direto quando o cofre já está desbloqueado (espelho da chave);
///   nativo → [bootstrapApp] (cofre do SO resolve a chave);
/// - **Demo (não salva dados)** → [runDemoMode] (banco em memória).
void runBootLoader(NotificationService notifications) {
  runApp(
    _materialApp(
      home: BootLoader(
        steps: buildBootSteps(),
        onEnter: () => enterPersistentApp(notifications),
        onDemo: () => runDemoMode(notifications),
      ),
    ),
  );
}

/// Trata o botão **Entrar** do [BootLoader].
///
/// Web: se o aparelho já tem o cofre resolvido (espelho da chave em
/// localStorage), entra direto no app — nenhum prompt. Caso contrário
/// (primeira interação → criação do PIN; espelho ausente → desbloqueio;
/// material corrompido → recuperação), mostra o [DatabaseUnlockGate].
/// Nativo: o cofre do SO resolve a chave transparentemente.
void enterPersistentApp(NotificationService notifications) {
  if (kIsWeb) {
    final state = DatabaseKeyService.instance.webState;
    if (state == DatabaseKeyState.unlocked) {
      bootstrapApp(notifications);
      return;
    }
    runUnlockGate(notifications);
    return;
  }
  bootstrapApp(notifications);
}

/// Mostra o DatabaseUnlockGate — fluxo persistente com cofre criptográfico.
void runUnlockGate(NotificationService notifications) {
  runApp(
    _materialApp(
      home: DatabaseUnlockGate(
        onDatabaseReady: () => bootstrapApp(notifications),
      ),
    ),
  );
}

/// Ativa o modo demo: banco em memória + dados mock, sem cofre.
/// O visitante explora a UI completa sem precisar criar senha.
void runDemoMode(NotificationService notifications) {
  DatabaseService.enableDemoMode();
  bootstrapApp(notifications);
}

/// Sai do modo demo: fecha banco em memória, desativa flag e volta para
/// o BootLoader (tela de % com os botões Entrar/Demo). Chamado pelo banner
/// "Sair do demo" no MainShell.
Future<void> exitDemoMode(NotificationService notifications) async {
  DatabaseService.disableDemoMode();
  await DatabaseService.instance.close();
  runBootLoader(notifications);
}

/// Inicializa os 7 providers, registra via MultiProvider e roda RemediosApp.
/// Chamado por [enterPersistentApp] (botão Entrar do BootLoader) e por
/// [runDemoMode] para o modo demo.
Future<void> bootstrapApp(NotificationService notifications) async {
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
