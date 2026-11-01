import 'package:flutter/material.dart';

import '../core/design/app_tokens.dart';
import '../core/theme/app_theme.dart';

/// Chip informativo único do app: ícone + rótulo dentro de um contêiner
/// arredondado suave.
///
/// Substitui as duas versões antigas (badge com fundo em Tratamentos e
/// ícone solto em Planos). `isWarning` usa a cor semântica de alerta do
/// tema — sobrevive ao dark mode, diferente do laranja fixo anterior.
class InfoChip extends StatelessWidget {
  const InfoChip({
    super.key,
    required this.icon,
    required this.label,
    this.isWarning = false,
    this.color,
  });

  final IconData icon;
  final String label;

  /// Destaque de atenção (estoque baixo, validade vencendo).
  final bool isWarning;

  /// Cor alternativa para o par ícone/texto (padrão: neutro do tema).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);
    final effectiveColor =
        isWarning
            ? semantic.warning
            : (color ?? Theme.of(context).colorScheme.onSurfaceVariant);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color:
            isWarning
                ? semantic.warning.withValues(alpha: .12)
                : (color?.withValues(alpha: .10) ??
                    Theme.of(context).colorScheme.surfaceContainerHighest),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: effectiveColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: effectiveColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Badge de status pill (Realizada, Cancelada, Agendada…).
///
/// Uniformiza os badges duplicados de Hoje e Consultas com o mesmo desenho:
/// fundo na cor com alpha e texto na cor plena.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
