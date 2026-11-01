import 'package:flutter/material.dart';

import 'empty_illustration.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.illustration,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.secondaryActionIcon,
  });

  final IconData icon;
  final String title;
  final String description;

  /// Se presente, uma ilustração de linha substitui o círculo com ícone —
  /// dá personalidade ao estado vazio sem perder a informação do ícone.
  final EmptyIllustrationKind? illustration;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Ícone do CTA primário (padrão: adicionar).
  final IconData? actionIcon;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  /// Ícone do CTA secundário (padrão: câmera — em geral a receita).
  final IconData? secondaryActionIcon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (illustration != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: EmptyIllustration(kind: illustration!),
              )
            else ...[
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 34,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ],
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onAction,
                icon: Icon(actionIcon ?? Icons.add),
                label: Text(actionLabel!),
              ),
            ],
            if (secondaryActionLabel != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onSecondaryAction,
                icon: Icon(secondaryActionIcon ?? Icons.photo_camera_outlined),
                label: Text(secondaryActionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
