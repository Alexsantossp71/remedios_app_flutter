import 'package:material_ui/material_ui.dart';

import '../../../core/design/record_card.dart';

/// Card "Backup e restauração": exportação/importação de envelope
/// criptografado com senha. O fluxo (diálogos, providers) fica na tela;
/// este widget é a apresentação pura.
class ProfileBackupCard extends StatelessWidget {
  const ProfileBackupCard({
    super.key,
    required this.busy,
    required this.onExport,
    required this.onRestore,
  });

  /// True enquanto um backup está sendo exportado/restaurado —
  /// desabilita os botões e mostra o spinner no exportar.
  final bool busy;
  final VoidCallback onExport;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return RecordCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Exporte um backup criptografado com senha para guardar ou levar '
              'para outro aparelho. A senha não é salva pelo app; '
              'sem ela, não será possível restaurar o arquivo. '
              'Backups JSON antigos também podem ser restaurados.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy ? null : onExport,
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_outlined),
                    label: const Text('Exportar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onRestore,
                    icon: const Icon(Icons.restore_outlined),
                    label: const Text('Restaurar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
