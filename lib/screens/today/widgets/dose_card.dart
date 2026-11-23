/// Card de dose do painel "Hoje": ação principal (tomei/pular) e
/// botão circular de desfecho.
library;

import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/dose_event.dart';
import '../../../models/treatment.dart';

/// Design audit: StatefulWidget para hover elevation no desktop.
class DoseCard extends StatefulWidget {
  const DoseCard({
    super.key,
    required this.event,
    required this.treatment,
    required this.onStatusChanged,
  });

  final DoseEvent event;
  final Treatment treatment;
  final ValueChanged<DoseStatus> onStatusChanged;

  @override
  State<DoseCard> createState() => _DoseCardState();
}

class _DoseCardState extends State<DoseCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final treatment = widget.treatment;
    final theme = Theme.of(context);
    final isTaken = event.status == DoseStatus.taken;
    final isSkipped = event.status == DoseStatus.skipped;
    final isPending = event.status == DoseStatus.pending;
    final semantic = AppSemanticColors.of(context);
    final statusColor = isTaken
        ? semantic.success
        : isSkipped
        ? semantic.danger
        : theme.colorScheme.primary;

    final BorderSide side;
    if (isPending) {
      // Hierarquia: a dose pendente é o estado que pede ação — contorno
      // sutil no azul de ação.
      side = BorderSide(color: statusColor.withValues(alpha: .45), width: 1.5);
    } else {
      // Resolvida comunica o desfecho em cores semânticas: verde para
      // tomada, vermelho para pulada.
      side = BorderSide(color: statusColor, width: 2);
    }

    return MouseRegion(
      // Design audit: hover elevation no desktop.
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
        child: Card(
          elevation: _hovered ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: side,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                isTaken
                    ? Icons.check_circle_rounded
                    : isSkipped
                    ? Icons.remove_circle_outline
                    : Icons.medication_liquid_outlined,
                color: statusColor,
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    DateFormat.Hm().format(event.scheduledAt),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    treatment.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      decoration: isSkipped || isTaken
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${treatment.dosage} · ${treatment.presentation}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (isPending) ...[
              const SizedBox(width: 10),
              // Ações no mesmo eixo do medicamento: dois botões circulares
              // empilhados — um toque marca a dose, sem abrir menu.
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DoseRoundAction(
                    icon: Icons.local_drink_outlined,
                    tooltip: 'Tomei',
                    color: semantic.success,
                    onPressed: () => widget.onStatusChanged(DoseStatus.taken),
                  ),
                  const SizedBox(height: 2),
                  // Design audit: label visível distingue ação de status.
                  Text(
                    'Tomar',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: semantic.success,
                    ),
                  ),
                  const SizedBox(height: 4),
                  DoseRoundAction(
                    icon: Icons.skip_next_rounded,
                    tooltip: 'Pular',
                    color: semantic.warning,
                    onPressed: () => widget.onStatusChanged(DoseStatus.skipped),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Pular',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: semantic.warning,
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(width: 8),
              Icon(
                isTaken ? Icons.check_circle : Icons.remove_circle_outline,
                color: statusColor,
              ),
            ],
          ],
        ),
      ),
        ),
      ),
    );
  }
}

/// Botão de ação circular e preenchido da dose (verde "Tomei",
/// vermelho "Pular").
class DoseRoundAction extends StatelessWidget {
  const DoseRoundAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 22),
      color: Colors.white,
      style: IconButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        // 48px: alvo de toque recomendado — "Tomei/Pular" é a ação crítica.
        fixedSize: const Size(48, 48),
        shape: const CircleBorder(),
      ),
    );
  }
}
