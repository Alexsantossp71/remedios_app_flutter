/// Linha da trilha do dia (timeline V4) e pill de constância.
library;

import 'package:material_ui/material_ui.dart';

import '../../../core/design/app_tokens.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/dose_event.dart';

/// Linha da trilha do dia: um ponto ligado por fios verticais à esquerda de
/// cada card — a "timeline" V4. Doses resolvidas pintam o ponto com a cor
/// do desfecho (verde/vermelho); pendente respira no azul de ação.
class DoseTimelineRow extends StatelessWidget {
  const DoseTimelineRow({
    super.key,
    required this.event,
    required this.isFirst,
    required this.isLast,
    required this.child,
  });

  final DoseEvent event;
  final bool isFirst;
  final bool isLast;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final isTaken = event.status == DoseStatus.taken;
    final isSkipped = event.status == DoseStatus.skipped;
    final dotColor = isTaken
        ? semantic.success
        : isSkipped
        ? semantic.danger
        : theme.colorScheme.primary;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 18,
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    width: 2.5,
                    color: isFirst
                        ? Colors.transparent
                        : dotColor.withValues(alpha: .35),
                  ),
                ),
                AnimatedContainer(
                  duration: AppDurations.medium,
                  curve: AppCurves.emphasized,
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.colorScheme.surface,
                      width: 2,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2.5,
                    color: isLast
                        ? Colors.transparent
                        : dotColor.withValues(alpha: .35),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Pill de constância: chama calma + "N dias em dia".
class StreakPill extends StatelessWidget {
  const StreakPill({super.key, required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: semantic.success.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.local_fire_department_rounded,
            size: 16,
            color: semantic.success,
          ),
          const SizedBox(width: 4),
          Text(
            '$days dias em dia',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: semantic.success,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
