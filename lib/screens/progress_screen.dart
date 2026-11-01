import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../providers/therapy_provider.dart';
import '../core/theme/app_theme.dart';
import '../widgets/section_header.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Consumer<TherapyProvider>(
      builder: (context, provider, child) {
        final selectedAdherence = provider.adherenceForDay(_selectedDay);
        final todayAdherence = provider.adherenceForDay(DateTime.now());
        final activeCount = provider.activeTreatments.length;

        return Scaffold(
          appBar: AppBar(title: const Text('Progresso')),
          body: SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Acompanhe sua constância e cuide da sua saúde.',
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 22),
                        _StatsRow(
                          todayAdherence: todayAdherence,
                          activeCount: activeCount,
                        ),
                        const SizedBox(height: 28),
                        const SectionHeader(title: 'Histórico de doses'),
                        const SizedBox(height: 10),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                            child: TableCalendar<void>(
                              locale: 'pt_BR',
                              firstDay: DateTime.utc(2020, 1, 1),
                              lastDay: DateTime.utc(2100, 12, 31),
                              focusedDay: _focusedDay,
                              selectedDayPredicate:
                                  (day) => isSameDay(_selectedDay, day),
                              onDaySelected: (selectedDay, focusedDay) {
                                setState(() {
                                  _selectedDay = selectedDay;
                                  _focusedDay = focusedDay;
                                });
                              },
                              onPageChanged:
                                  (focusedDay) => _focusedDay = focusedDay,
                              calendarFormat: CalendarFormat.month,
                              headerStyle: const HeaderStyle(
                                formatButtonVisible: false,
                                titleCentered: true,
                              ),
                              calendarStyle: CalendarStyle(
                                todayDecoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: .22),
                                  shape: BoxShape.circle,
                                ),
                                todayTextStyle: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                  fontWeight: FontWeight.w800,
                                ),
                                selectedDecoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              calendarBuilders: CalendarBuilders(
                                markerBuilder: (context, day, events) {
                                  final semantic = AppSemanticColors.of(
                                    context,
                                  );
                                  final adherence = provider.adherenceForDay(
                                    day,
                                  );
                                  if (adherence.total == 0) return null;
                                  final color =
                                      adherence.taken == adherence.total
                                          ? semantic.success
                                          : adherence.completed == 0
                                          ? semantic.warning
                                          : Theme.of(
                                            context,
                                          ).colorScheme.primary;
                                  return Positioned(
                                    bottom: 3,
                                    child: Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: color,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        const SectionHeader(title: 'Jardim da adesão'),
                        const SizedBox(height: 10),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _AdherenceGarden(provider: provider),
                                const SizedBox(height: 8),
                                Text(
                                  'Últimos 14 dias: flor cheia = dia completo, '
                                  'broto = parcial, vaso vazio = sem doses.',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.bodySmall?.copyWith(
                                    color:
                                        Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        _SelectedDayCard(
                          adherence: selectedAdherence,
                          day: _selectedDay,
                        ),
                        const SizedBox(height: 28),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.todayAdherence, required this.activeCount});

  final DayAdherence todayAdherence;
  final int activeCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.check_circle_outline,
            value:
                todayAdherence.total == 0
                    ? '—'
                    : '${(todayAdherence.adherenceRate * 100).round()}%',
            label: 'hoje',
            color: AppSemanticColors.of(context).success,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.medication_outlined,
            value: '$activeCount',
            label: 'tratamentos ativos',
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 12),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedDayCard extends StatelessWidget {
  const _SelectedDayCard({required this.adherence, required this.day});

  final DayAdherence adherence;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final title = DateFormat("d 'de' MMMM", 'pt_BR').format(day);
    final message =
        adherence.total == 0
            ? 'Nenhuma dose programada para este dia.'
            : '${adherence.taken} de ${adherence.total} doses tomadas';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Icon(
            adherence.total > 0 && adherence.taken == adherence.total
                ? Icons.celebration_outlined
                : Icons.insights_outlined,
            color: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title[0].toUpperCase() + title.substring(1),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Jardim da adesão: os últimos 14 dias viram um canteiro line-art —
/// dia 100% floresce (pétalas verdes), dia parcial vira broto azul,
/// dia sem doses fica só o vaso.
class _AdherenceGarden extends StatelessWidget {
  const _AdherenceGarden({required this.provider});

  final TherapyProvider provider;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final days = [
      for (var i = 13; i >= 0; i--)
        DateTime(today.year, today.month, today.day - i),
    ];
    final kinds = [
      for (final day in days)
        () {
          final adherence = provider.adherenceForDay(day);
          if (adherence.total == 0) return _GardenDayKind.empty;
          return adherence.taken == adherence.total
              ? _GardenDayKind.full
              : _GardenDayKind.partial;
        }(),
    ];
    return SizedBox(
      height: 96,
      width: double.infinity,
      child: CustomPaint(
        painter: _GardenPainter(
          kinds: kinds,
          stroke: Theme.of(context).colorScheme.primary,
          bloom: AppSemanticColors.of(context).success,
          soil: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

enum _GardenDayKind { empty, partial, full }

class _GardenPainter extends CustomPainter {
  _GardenPainter({
    required this.kinds,
    required this.stroke,
    required this.bloom,
    required this.soil,
  });

  final List<_GardenDayKind> kinds;
  final Color stroke;
  final Color bloom;
  final Color soil;

  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..color = stroke;

    final cellWidth = size.width / kinds.length;
    final baseY = size.height * 0.86;

    // Linha do canteiro.
    canvas.drawLine(Offset(0, baseY), Offset(size.width, baseY), strokePaint);

    for (var i = 0; i < kinds.length; i++) {
      final cx = cellWidth * i + cellWidth / 2;
      switch (kinds[i]) {
        case _GardenDayKind.full:
          _paintFlower(canvas, cx, baseY, strokePaint);
        case _GardenDayKind.partial:
          _paintSprout(canvas, cx, baseY, strokePaint);
        case _GardenDayKind.empty:
          _paintEmptyPot(canvas, cx, baseY, strokePaint);
      }
    }
  }

  void _paintFlower(Canvas canvas, double cx, double baseY, Paint strokePaint) {
    // Haste.
    canvas.drawLine(Offset(cx, baseY), Offset(cx, baseY - 34), strokePaint);
    // Folhinha.
    canvas.drawLine(
      Offset(cx, baseY - 14),
      Offset(cx + 8, baseY - 20),
      strokePaint,
    );
    // Pétalas: cinco círculos em volta do miolo verde.
    final center = Offset(cx, baseY - 42);
    for (var p = 0; p < 5; p++) {
      final angle = -math.pi / 2 + p * 2 * math.pi / 5;
      canvas.drawCircle(
        center + Offset(math.cos(angle), math.sin(angle)) * 7,
        5,
        Paint()..color = bloom.withValues(alpha: .55),
      );
    }
    canvas.drawCircle(center, 4.5, Paint()..color = bloom);
  }

  void _paintSprout(Canvas canvas, double cx, double baseY, Paint strokePaint) {
    canvas.drawLine(Offset(cx, baseY), Offset(cx, baseY - 18), strokePaint);
    // Duas folhinhas em V.
    canvas.drawLine(
      Offset(cx, baseY - 18),
      Offset(cx - 8, baseY - 26),
      strokePaint,
    );
    canvas.drawLine(
      Offset(cx, baseY - 18),
      Offset(cx + 8, baseY - 26),
      strokePaint,
    );
  }

  void _paintEmptyPot(
    Canvas canvas,
    double cx,
    double baseY,
    Paint strokePaint,
  ) {
    final pot =
        Path()
          ..moveTo(cx - 7, baseY - 2)
          ..lineTo(cx + 7, baseY - 2)
          ..lineTo(cx + 5, baseY - 14)
          ..lineTo(cx - 5, baseY - 14)
          ..close();
    canvas.drawPath(pot, strokePaint..color = soil.withValues(alpha: .45));
  }

  @override
  bool shouldRepaint(covariant _GardenPainter oldDelegate) =>
      oldDelegate.kinds != kinds;
}
