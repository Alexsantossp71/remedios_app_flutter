import 'package:material_ui/material_ui.dart';

import '../../../core/design/record_card.dart';
import '../../../services/web_reminder_service.dart';
import '../../../widgets/app_snack_bar.dart';

/// Card "Lembretes no navegador" — só aparece na web (Notification API).
/// Três estados: concedido, bloqueado pelo site e nunca perguntado.
class WebReminderCard extends StatefulWidget {
  const WebReminderCard({super.key});

  @override
  State<WebReminderCard> createState() => _WebReminderCardState();
}

class _WebReminderCardState extends State<WebReminderCard> {
  late bool _granted = WebReminderService.instance.isPermissionGranted;
  late bool _denied = WebReminderService.instance.isPermissionDenied;
  bool _busy = false;

  Future<void> _activate() async {
    setState(() => _busy = true);
    final granted = await WebReminderService.instance.requestPermission();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _granted = granted;
      _denied = WebReminderService.instance.isPermissionDenied;
    });
    showAppSnackBar(
      context,
      granted
          ? 'Lembretes ativos neste navegador.'
          : 'O navegador não concedeu a permissão. Libere as notificações '
                'deste site e tente novamente.',
      type: granted ? AppSnackType.success : AppSnackType.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RecordCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _granted
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_outlined,
                  color: _granted
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _granted
                        ? 'Lembretes ativos neste navegador: enquanto o app '
                              'estiver aberto, você recebe o aviso na hora da '
                              'dose, mesmo com a aba em segundo plano.'
                        : _denied
                        ? 'As notificações estão bloqueadas para este '
                              'site. Libere nas permissões do navegador e '
                              'recarregue a página para ativar.'
                        : 'O navegador pode avisar na hora da dose '
                              'enquanto o app estiver aberto — mesmo com '
                              'a aba em segundo plano. No celular (APK), '
                              'os avisos já funcionam com o app fechado.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            if (!_granted && !_denied) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _activate,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.notifications_on_outlined),
                label: const Text('Ativar lembretes'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
