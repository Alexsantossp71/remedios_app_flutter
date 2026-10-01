import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/consultation.dart';
import '../models/doctor.dart';
import '../models/dose_event.dart';
import '../models/treatment.dart';
import '../providers/consultation_provider.dart';
import '../providers/doctor_provider.dart';
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
    final therapyProvider = context.watch<TherapyProvider>();
    final consultationProvider = context.watch<ConsultationProvider>();
    final doctorProvider = context.watch<DoctorProvider>();

    if (therapyProvider.isLoading || consultationProvider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final events = therapyProvider.doseEventsForDay(_selectedDay);
    final consultations =
        consultationProvider.getConsultationsFromDay(_selectedDay);
    final isToday = _dateOnly(DateTime.now()) == _selectedDay;
    final adherence = therapyProvider.adherenceForDay(_selectedDay);

    final hasNothing = events.isEmpty && consultations.isEmpty;

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
          if (hasNothing)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.wb_sunny_outlined,
                title: 'Seu dia está livre',
                description:
                    'Nenhum medicamento ou consulta programada para este dia.',
              ),
            )
          else ...[
            // Seção de Consultas Médicas do Dia
            if (consultations.isNotEmpty) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                sliver: SliverToBoxAdapter(
                  child: SectionHeader(
                    title: 'Consultas Agendadas (${consultations.length})',
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                sliver: SliverList.separated(
                  itemCount: consultations.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final consultation = consultations[index];
                    final doctor = doctorProvider.doctors
                        .where((d) => d.id == consultation.doctorId)
                        .firstOrNull;
                    return _TodayConsultationCard(
                      consultation: consultation,
                      doctor: doctor,
                      selectedDay: _selectedDay,
                      onStatusChanged: (newStatus) async {
                        final updated =
                            consultation.copyWith(status: newStatus);
                        await consultationProvider.saveConsultation(updated);
                      },
                    );
                  },
                ),
              ),
            ],

            // Seção de Medicamentos
            if (events.isNotEmpty) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                sliver: SliverToBoxAdapter(
                  child: SectionHeader(
                    title: isToday
                        ? 'Medicamentos de Hoje (${events.length})'
                        : 'Medicamentos Programados (${events.length})',
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                sliver: SliverList.builder(
                  itemCount: events.length,
                  itemBuilder: (context, index) {
                    final event = events[index];
                    final treatment =
                        therapyProvider.treatmentById(event.treatmentId);
                    if (treatment == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: DoseCard(
                        event: event,
                        treatment: treatment,
                        onStatusChanged: (status) =>
                            therapyProvider.setDoseStatus(event, status),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ],
      ),
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
      ],
    );
  }
}

class _TodayConsultationCard extends StatelessWidget {
  const _TodayConsultationCard({
    required this.consultation,
    required this.doctor,
    required this.selectedDay,
    required this.onStatusChanged,
  });

  final Consultation consultation;
  final Doctor? doctor;
  final DateTime selectedDay;
  final ValueChanged<String> onStatusChanged;

  int _daysUntil() {
    final target = DateTime(
      consultation.date.year,
      consultation.date.month,
      consultation.date.day,
    );
    final today = DateTime(
      selectedDay.year,
      selectedDay.month,
      selectedDay.day,
    );
    return target.difference(today).inDays;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeFormat = DateFormat('HH:mm');

    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (consultation.status) {
      case ConsultationStatus.completed:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle_outline;
        statusText = 'Realizada';
        break;
      case ConsultationStatus.cancelled:
        statusColor = Colors.red;
        statusIcon = Icons.cancel_outlined;
        statusText = 'Cancelada';
        break;
      default:
        statusColor = Colors.amber.shade800;
        statusIcon = Icons.medical_services_outlined;
        statusText = 'Agendada';
    }

    // Contagem regressiva até a consulta (em relação ao dia selecionado).
    final daysUntil = _daysUntil();
    final countdownBadge = consultation.status == ConsultationStatus.scheduled
        ? (daysUntil == 0
            ? 'Hoje'
            : daysUntil == 1
                ? 'Amanhã'
                : 'Em $daysUntil dias')
        : null;

    final doctorName = doctor?.name ?? 'Médico não informado';
    final doctorSpecialty = doctor?.specialty ?? '';

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: Colors.amber.shade300,
          width: 1.5,
        ),
      ),
      color: Colors.amber.shade50.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    statusIcon,
                    color: Colors.amber.shade900,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            timeFormat.format(consultation.date),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: Colors.amber.shade900,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (daysUntil > 0) ...[
                            const SizedBox(width: 4),
                            Text(
                              DateFormat('dd/MM', 'pt_BR')
                                  .format(consultation.date),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              countdownBadge ?? statusText,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        consultation.title.isNotEmpty
                            ? consultation.title
                            : (doctorSpecialty.isNotEmpty
                                ? 'Consulta de $doctorSpecialty'
                                : 'Consulta médica'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        doctorSpecialty.isNotEmpty
                            ? '$doctorName · $doctorSpecialty'
                            : doctorName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Status da consulta',
                  onSelected: onStatusChanged,
                  itemBuilder: (context) => [
                    if (consultation.status != ConsultationStatus.completed)
                      const PopupMenuItem(
                        value: ConsultationStatus.completed,
                        child: ListTile(
                          leading: Icon(Icons.check_circle_outline,
                              color: Colors.green),
                          title: Text('Marcar como realizada'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    if (consultation.status != ConsultationStatus.scheduled)
                      const PopupMenuItem(
                        value: ConsultationStatus.scheduled,
                        child: ListTile(
                          leading:
                              Icon(Icons.schedule_outlined, color: Colors.blue),
                          title: Text('Marcar como agendada'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    if (consultation.status != ConsultationStatus.cancelled)
                      const PopupMenuItem(
                        value: ConsultationStatus.cancelled,
                        child: ListTile(
                          leading: Icon(Icons.cancel_outlined, color: Colors.red),
                          title: Text('Cancelar consulta'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                  ],
                  child: Icon(
                    Icons.more_vert,
                    color: Colors.amber.shade900,
                  ),
                ),
              ],
            ),
            if (consultation.notes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Colors.amber.shade900,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        consultation.notes,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
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
            if (event.status == DoseStatus.pending) ...[
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
                ],
                child: Icon(Icons.more_vert, color: statusColor),
              ),
            ] else
              Icon(
                isTaken ? Icons.check_circle : Icons.remove_circle_outline,
                color: statusColor,
              ),
          ],
        ),
      ),
    );
  }
}
