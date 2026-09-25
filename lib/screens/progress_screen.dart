import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../providers/therapy_provider.dart';
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

        return SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Progresso',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Acompanhe sua constância e cuide da sua saúde.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                            onDaySelected: (selectedDay, focusedDay) {
                              setState(() {
                                _selectedDay = selectedDay;
                                _focusedDay = focusedDay;
                              });
                            },
                            onPageChanged: (focusedDay) => _focusedDay = focusedDay,
                            calendarFormat: CalendarFormat.month,
                            headerStyle: const HeaderStyle(
                              formatButtonVisible: false,
                              titleCentered: true,
                            ),
                            calendarStyle: CalendarStyle(
                              todayDecoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: .22),
                                shape: BoxShape.circle,
                              ),
                              todayTextStyle: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontWeight: FontWeight.w800,
                              ),
                              selectedDecoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            calendarBuilders: CalendarBuilders(
                              markerBuilder: (context, day, events) {
                                final adherence = provider.adherenceForDay(day);
                                if (adherence.total == 0) return null;
                                final color = adherence.taken == adherence.total
                                    ? Colors.green.shade600
                                    : adherence.completed == 0
                                        ? Colors.orange.shade600
                                        : Theme.of(context).colorScheme.primary;
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
                      const SizedBox(height: 24),
                      _SelectedDayCard(adherence: selectedAdherence, day: _selectedDay),
                      const SizedBox(height: 28),
                    ],
                  ),
                ),
              ),
            ],
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
            value: todayAdherence.total == 0
                ? '—'
                : '${(todayAdherence.adherenceRate * 100).round()}%',
            label: 'hoje',
            color: Colors.green.shade700,
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
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
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
    final message = adherence.total == 0
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
