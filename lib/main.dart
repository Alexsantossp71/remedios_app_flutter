import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/app_bootstrap.dart';
import 'core/observability.dart';
import 'core/service_locator.dart';
import 'services/notification_service.dart';

// Re-export para que testes e integration tests que importam main.dart
// continuem tendo acesso a RemediosApp e bootstrapApp (agora em
// app_bootstrap.dart).
export 'core/app_bootstrap.dart' show RemediosApp, bootstrapApp;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');

  // P1-5: Flutter web defaulta para semantics OFF até o usuário clicar no
  // botão "Enable accessibility" do canto do canvas. Para um app de saúde
  // onde o público-alvo inclui idosos, baixa visão e usuários de screen
  // reader (VoiceOver/NVDA), isso é gap de acessibilidade.
  if (kIsWeb) {
    await SystemChannels.accessibility.send('enable');
  }

  setupServiceLocator();
  await setupObservability();

  final notifications = sl<NotificationService>();
  await notifications.init();

  // Web: WelcomeScreen first → "Começar" (gate) ou "Ver demo" (demo mode).
  // Native: bootstrap direto (Keystore resolve a chave transparente).
  if (kIsWeb) {
    runWelcomeScreen(notifications);
    return;
  }
  await bootstrapApp(notifications);
}
