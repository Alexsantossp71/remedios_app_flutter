import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/dose_event.dart';
import '../models/treatment.dart';
import '../providers/therapy_provider.dart';
import '../widgets/empty_state.dart';
import '../widgets/section_header.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  DateTime _selectedDay = _dateOnly(DateTime.now());

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  Future<void> _selectDay() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Escolha um dia',
    );
    if (selected == null || !mounted) return;
    final provider = context.read<TherapyProvider>();
    await provider.ensureDoseEventsFor(selected);
    if (mounted) setState(() => _selectedDay = _dateOnly(selected));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TherapyProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final events = provider.doseEventsForDay(_selectedDay);
        final isToday = _dateOnly(DateTime.now()) == _selectedDay;
        final adherence = provider.adherenceForDay(_selectedDay);

        return SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: _TodayHeader(
                    selectedDay: _selectedDay,
                    isToday: isToday,
                    adherence: adherence,
                    onSelectDay: _selectDay,
                  ),
                ),
              ),
              if (events.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.wb_sunny_outlined,
                    title: 'Seu dia está livre',
                    description:
                        'Adicione um tratamento para organizar seus horários.',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
                  sliver: SliverList.builder(
                    itemCount: events.length,
                    itemBuilder: (context, index) {
                      final event = events[index];
                      final treatment = provider.treatmentById(event.treatmentId);
                      if (treatment == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: DoseCard(
                          event: event,
                          treatment: treatment,
                          onStatusChanged: (status) =>
                              provider.setDoseStatus(event, status),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TodayHeader extends StatelessWidget {
  const _TodayHeader({
    required this.selectedDay,
    required this.isToday,
    required this.adherence,
    required this.onSelectDay,
  });

  final DateTime selectedDay;
  final bool isToday;
  final DayAdherence adherence;
  final VoidCallback onSelectDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final greeting = isToday ? 'Bom dia!' : 'Sua agenda';
    final formattedDate = DateFormat("EEEE, d 'de' MMMM", 'pt_BR')
        .format(selectedDay);

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
            IconButton.filledTonal(
              onPressed: onSelectDay,
              tooltip: 'Escolher data',
              icon: const Icon(Icons.calendar_month_outlined),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.primary,
                theme.colorScheme.primary.withValues(alpha: .78),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.favorite_rounded, color: Colors.white),
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
        ),
        const SizedBox(height: 26),
        const SectionHeader(title: 'Sua rotina de hoje'),
      ],
    );
  }
}

class DoseCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTaken = event.status == DoseStatus.taken;
    final isSkipped = event.status == DoseStatus.skipped;
    final statusColor = isTaken
        ? Colors.green.shade700
        : isSkipped
            ? theme.colorScheme.onSurfaceVariant
            : theme.colorScheme.primary;

    return Card(
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
            const SizedBox(width: 8),
            PopupMenuButton<DoseStatus>(
              tooltip: 'Atualizar dose',
              onSelected: onStatusChanged,
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: DoseStatus.taken,
                  child: Text('Tomei'),
                ),
                PopupMenuItem(
                  value: DoseStatus.skipped,
                  child: Text('Pular'),
                ),
                PopupMenuItem(
                  value: DoseStatus.pending,
                  child: Text('Pendente'),
                ),
              ],
              child: Icon(
                isTaken ? Icons.check_circle : Icons.more_vert,
                color: statusColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
