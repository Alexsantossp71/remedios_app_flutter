import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// SnackBar unificado do app: flutuante, com cor semântica opcional e
/// suporte a ação de "Desfazer".
///
/// Substitui os 32 pontos de SnackBar inconsistentes (fixo vs flutuante,
/// sem feedback de sucesso em Tratamentos).
enum AppSnackType { neutral, success, error }

void showAppSnackBar(
  BuildContext context,
  String message, {
  AppSnackType type = AppSnackType.neutral,
  SnackBarAction? action,
}) {
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  messenger.showSnackBar(_buildSnackBar(context, message, type, action));
}

SnackBar _buildSnackBar(
  BuildContext context,
  String message,
  AppSnackType type,
  SnackBarAction? action,
) {
  final theme = Theme.of(context);
  final semantic = AppSemanticColors.of(context);

  final Color background;
  final Color foreground;
  switch (type) {
    case AppSnackType.success:
      background = semantic.successContainer;
      foreground = theme.colorScheme.onSurface;
    case AppSnackType.error:
      background = semantic.danger;
      foreground = Colors.white;
    case AppSnackType.neutral:
      background = theme.colorScheme.inverseSurface;
      foreground = theme.colorScheme.onInverseSurface;
  }

  return SnackBar(
    behavior: SnackBarBehavior.floating,
    backgroundColor: background,
    content: Text(message, style: TextStyle(color: foreground)),
    action: action,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  );
}
