import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'providers/consultation_provider.dart';
import 'providers/doctor_provider.dart';
import 'providers/health_plan_provider.dart';
import 'providers/therapy_provider.dart';
import 'providers/user_profile_provider.dart';
import 'screens/main_shell.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');

  // No-op on web; on mobile it also asks for the notification permission
  // (Android 13+) and creates the dose channel before any alarm is set.
  final notifications = NotificationService.instance;
  await notifications.init();

  final therapyProvider = TherapyProvider(notifications: notifications);
  final doctorProvider = DoctorProvider();
  final consultationProvider = ConsultationProvider();
  final healthPlanProvider = HealthPlanProvider();
  final userProfileProvider = UserProfileProvider();
  await therapyProvider.initialize();
  await doctorProvider.initialize();
  await consultationProvider.initialize();
  await healthPlanProvider.initialize();
  await userProfileProvider.initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: therapyProvider),
        ChangeNotifierProvider.value(value: doctorProvider),
        ChangeNotifierProvider.value(value: consultationProvider),
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
