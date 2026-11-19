import 'package:flutter/material.dart';

import '../../../core/design/brand_colors.dart';
import '../../../core/design/record_card.dart';
import '../../../models/emergency_contact.dart';

/// Card "Contatos de emergência": lista de contatos com ações de
/// edição/remoção e botão para adicionar. As operações ficam na tela
/// (provider); este widget é a apresentação pura.
class EmergencyContactsCard extends StatelessWidget {
  const EmergencyContactsCard({
    super.key,
    required this.contacts,
    required this.isDark,
    required this.onAdd,
    required this.onEdit,
    required this.onRemove,
  });

  final List<EmergencyContact> contacts;
  final bool isDark;
  final VoidCallback onAdd;
  final void Function(EmergencyContact contact) onEdit;
  final void Function(EmergencyContact contact) onRemove;

  @override
  Widget build(BuildContext context) {
    return RecordCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            if (contacts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 12,
                ),
                child: Text(
                  'Nenhum contato cadastrado. Adicione alguém de '
                  'confiança.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else ...[
              for (var i = 0; i < contacts.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 64, endIndent: 12),
                ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      // Caixa de ícone com véu vermelho — contexto
                      // de emergência no PWA usa o brand.red.
                      color: BrandColors.red.withValues(
                        alpha: isDark ? .16 : .10,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.contact_emergency_outlined,
                      color: BrandColors.red,
                      size: 22,
                    ),
                  ),
                  title: Text(contacts[i].nome),
                  subtitle: Text(
                    [
                      if (contacts[i].parentesco.isNotEmpty)
                        contacts[i].parentesco,
                      contacts[i].telefone,
                    ].join(' • '),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Editar',
                        onPressed: () => onEdit(contacts[i]),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Remover',
                        onPressed: () => onRemove(contacts[i]),
                      ),
                    ],
                  ),
                ),
              ],
            ],
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('Adicionar contato'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
