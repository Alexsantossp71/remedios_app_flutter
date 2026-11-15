import 'package:flutter/material.dart';

/// Uma opção da folha "como você quer cadastrar?".
class CreateChoiceOption<T> {
  const CreateChoiceOption({
    required this.value,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final T value;
  final IconData icon;
  final String title;
  final String subtitle;
}

/// Folha inferior genérica que pergunta COMO cadastrar: manual ou com foto
/// lida por IA. Segue o padrão visual da folha de plano de saúde — os
/// cadastros pelo menu central “+” nunca abrem o formulário sem perguntar
/// quando existe um caminho com leitura de imagem.
///
/// Retorna `null` se o usuário fechar sem escolher.
Future<T?> showCreateChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<CreateChoiceOption<T>> options,
}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final colorScheme = theme.colorScheme;

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            for (final option in options)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: colorScheme.primaryContainer,
                  foregroundColor: colorScheme.onPrimaryContainer,
                  child: Icon(option.icon),
                ),
                title: Text(option.title),
                subtitle: Text(option.subtitle),
                onTap: () => Navigator.of(sheetContext).pop(option.value),
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
