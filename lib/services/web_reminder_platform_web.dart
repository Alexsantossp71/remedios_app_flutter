import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Implementação real para web: Notification API do navegador.
///
/// O lembrete funciona enquanto o app está aberto (mesmo com a aba em
/// segundo plano). Fora disso — app fechado — continua sendo território do
/// APK (ADR 0005): a web não tem alarmes locais sem um service worker com
/// push server, que exige infraestrutura de sincronização.

bool get reminderSupported {
  // `typeof window.Notification` na prática: se a API não existe, acessar
  // o membro estático `permission` lança TypeError do lado JS.
  try {
    web.Notification.permission;
    return true;
  } catch (_) {
    return false;
  }
}

bool get reminderPermissionGranted =>
    reminderSupported && web.Notification.permission == 'granted';

bool get reminderPermissionDenied =>
    reminderSupported && web.Notification.permission == 'denied';

Future<bool> requestReminderPermission() async {
  if (!reminderSupported) return false;
  switch (web.Notification.permission) {
    case 'granted':
      return true;
    case 'denied':
      return false;
  }
  try {
    // Precisa de gesto do usuário (chamado do botão no Perfil).
    final result = await web.Notification.requestPermission().toDart;
    return result.toDart == 'granted';
  } catch (_) {
    return false;
  }
}

void showDoseNotification({required String title, required String body}) {
  if (!reminderPermissionGranted) return;
  try {
    web.Notification(
      title,
      web.NotificationOptions(body: body, tag: 'remedios-dose'),
    );
  } catch (_) {
    // Best-effort: nunca derruba o app por causa de uma notificação.
  }
}
