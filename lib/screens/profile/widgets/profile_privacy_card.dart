import 'package:flutter/material.dart';

import '../../../core/design/record_card.dart';

/// Card "Dados e privacidade": zona de perigo com o botão de apagar
/// todos os dados (LGPD). A confirmação e a exclusão ficam na tela.
class ProfilePrivacyCard extends StatelessWidget {
  const ProfilePrivacyCard({super.key, required this.onDeleteAll});

  final VoidCallback onDeleteAll;

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
              'Seus dados ficam armazenados apenas neste dispositivo. '
              'A qualquer momento você pode apagá-los por completo '
              '(LGPD).',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                side: BorderSide(color: Theme.of(context).colorScheme.error),
              ),
              onPressed: onDeleteAll,
              icon: const Icon(Icons.delete_forever_outlined),
              label: const Text('Apagar meus dados'),
            ),
          ],
        ),
      ),
    );
  }
}
