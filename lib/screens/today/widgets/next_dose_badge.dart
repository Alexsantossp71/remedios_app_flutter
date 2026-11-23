/// Contagem viva para a próxima dose pendente do dia (atualiza a cada
/// 30 segundos; some quando não há nada pendente).
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../models/dose_event.dart';

/// Contagem viva para a próxima dose pendente de hoje — atualiza sozinha
/// a cada 30 segundos. Some quando não há nada pendente.
class NextDoseBadge extends StatefulWidget {
  const NextDoseBadge({super.key, required this.events});

  final List<DoseEvent> events;

  @override
  State<NextDoseBadge> createState() => _NextDoseBadgeState();
}

class _NextDoseBadgeState extends State<NextDoseBadge> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  DoseEvent? get _nextPending {
    final now = DateTime.now();
    for (final event in widget.events) {
      if (event.status == DoseStatus.pending &&
          event.scheduledAt.isAfter(now)) {
        return event;
      }
    }
    return null;
  }

  String _countdownFor(DateTime scheduledAt) {
    final difference = scheduledAt.difference(DateTime.now());
    if (difference.inHours >= 1) {
      final minutes = difference.inMinutes % 60;
      return '${difference.inHours}h${minutes.toString().padLeft(2, '0')}';
    }
    return '${difference.inMinutes}min';
  }

  @override
  Widget build(BuildContext context) {
    final next = _nextPending;
    if (next == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined, size: 15, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            // Design audit: adicionar horário absoluto além do relativo.
            // Antes: "Próxima dose em 4h38". Agora: "Próxima às 16:00 (em 4h38)".
            'Próxima às ${_timeOfDay(next.scheduledAt)} (em ${_countdownFor(next.scheduledAt)})',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Formata um DateTime como HH:mm (horário local).
String _timeOfDay(DateTime dt) {
  String p2(int v) => v.toString().padLeft(2, '0');
  final local = dt.toLocal();
  return '${p2(local.hour)}:${p2(local.minute)}';
}
