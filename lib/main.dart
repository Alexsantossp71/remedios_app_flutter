import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'providers/therapy_provider.dart';
import 'screens/main_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');

  final therapyProvider = TherapyProvider();
  await therapyProvider.initialize();

  runApp(
    ChangeNotifierProvider.value(
      value: therapyProvider,
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
