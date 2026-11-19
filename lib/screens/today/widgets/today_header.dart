/// Header V4 do painel "Hoje": saudação por horário, data completa e
/// streak de constância.
library;

import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../../../core/design/app_tokens.dart';
import 'dose_timeline.dart';
import 'next_dose_badge.dart';
import '../../../core/design/brand_colors.dart';
import '../../../core/design/dashboard_hero.dart';
import '../../../core/design/stat_card.dart';
import '../../../models/dose_event.dart';
import '../../../providers/therapy_provider.dart';

class TodayHeader extends StatelessWidget {
  const TodayHeader({
    super.key,
    required this.selectedDay,
    required this.isToday,
    required this.adherence,
    required this.showProgressCard,
    required this.streak,
    required this.events,
    required this.consultationCount,
    required this.onSelectDay,
  });

  final DateTime selectedDay;
  final bool isToday;
  final DayAdherence adherence;

  /// Quando o dia está totalmente vazio, o estado ilustrado "Seu dia está
  /// livre" fala por si — esconder também o cartão de progresso evita duas
  /// mensagens de "nada aqui" competindo na mesma tela.
  final bool showProgressCard;

  /// Dias consecutivos 100% tomados (>= 2 mostra a chama).
  final int streak;

  /// Doses do dia, para o badge "próxima dose".
  final List<DoseEvent> events;

  /// Consultas do dia, para o cartão de estatística.
  final int consultationCount;

  final VoidCallback onSelectDay;

  /// Saudação viva: acompanha a hora do dia em vez de aparecer
  /// "Bom dia!" à noite.
  static String _greetingForNow() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Bom dia!';
    if (hour < 18) return 'Boa tarde!';
    return 'Boa noite!';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final greeting = isToday ? _greetingForNow() : 'Sua agenda';
    final formattedDate = DateFormat(
      "EEEE, d 'de' MMMM",
      'pt_BR',
    ).format(selectedDay);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    greeting,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${formattedDate[0].toUpperCase()}${formattedDate.substring(1)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (streak >= 2) ...[
              StreakPill(days: streak),
              const SizedBox(width: AppSpacing.sm),
            ],
            IconButton.filledTonal(
              onPressed: onSelectDay,
              tooltip: 'Escolher data',
              icon: const Icon(Icons.calendar_month_outlined),
            ),
          ],
        ),
        if (showProgressCard) ...[
          const SizedBox(height: 20),
          DashboardHero(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .18),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.favorite_rounded,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              adherence.total == 0
                                  ? 'Nenhuma dose programada'
                                  : '${adherence.taken} de ${adherence.total} doses tomadas',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              adherence.total == 0
                                  ? 'Tudo tranquilo por aqui.'
                                  : 'Cada dose é um passo importante.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white.withValues(alpha: .85),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (adherence.total > 0)
                        Text(
                          '${(adherence.adherenceRate * 100).round()}%',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                    ],
                  ),
                  if (isToday) ...[
                    const SizedBox(height: 14),
                    NextDoseBadge(events: events),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StatCard(
                  icon: Icons.medication_rounded,
                  value: '${adherence.taken}/${adherence.total}',
                  label: isToday ? 'doses de hoje' : 'doses do dia',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatCard(
                  icon: Icons.local_fire_department_rounded,
                  value: streak > 0 ? '$streak' : '0',
                  label: streak == 1 ? 'dia em sequência' : 'dias em sequência',
                  iconColor: BrandColors.yellow,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatCard(
                  icon: Icons.event_available_rounded,
                  value: '$consultationCount',
                  label: consultationCount == 1
                      ? 'consulta no dia'
                      : 'consultas no dia',
                  iconColor: BrandColors.teal600,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
