/// Stub da plataforma (mobile/desktop/VM de teste): o lembrete de navegador
/// não existe aqui — os alarmes reais de mobile ficam no
/// `NotificationService` (flutter_local_notifications, ADR 0005).
Future<bool> requestReminderPermission() async => false;

bool get reminderPermissionGranted => false;

bool get reminderPermissionDenied => false;

bool get reminderSupported => false;

void showDoseNotification({required String title, required String body}) {}
