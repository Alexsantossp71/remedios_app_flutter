import 'package:flutter/material.dart';

/// Opções oferecidas ao iniciar um novo plano de saúde.
enum AddPlanChoice {
  /// Enviar a foto do cartão para leitura automática.
  image,

  /// Preencher o formulário manualmente.
  manual,
}

/// Folha inferior com as duas formas de adicionar um plano de saúde.
///
/// Retorna `null` se o usuário fechar sem escolher.
Future<AddPlanChoice?> showAddHealthPlanSheet(BuildContext context) {
  return showModalBottomSheet<AddPlanChoice>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final colorScheme = theme.colorScheme;

      Widget option({
        required IconData icon,
        required String title,
        required String subtitle,
        required AddPlanChoice choice,
      }) {
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: colorScheme.primaryContainer,
            foregroundColor: colorScheme.onPrimaryContainer,
            child: Icon(icon),
          ),
          title: Text(title),
          subtitle: Text(subtitle),
          onTap: () => Navigator.of(sheetContext).pop(choice),
        );
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Adicionar plano de saúde',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            option(
              icon: Icons.photo_camera_outlined,
              title: 'Enviar imagem do cartão',
              subtitle:
                  'Tire ou escolha uma foto e confira os dados lidos antes de '
                  'salvar.',
              choice: AddPlanChoice.image,
            ),
            option(
              icon: Icons.edit_outlined,
              title: 'Cadastrar manualmente',
              subtitle: 'Preencha o formulário campo a campo.',
              choice: AddPlanChoice.manual,
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}