import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/design/app_tokens.dart';
import '../core/theme/app_theme.dart';
import '../models/consultation.dart';
import '../models/doctor.dart';
import '../models/dose_event.dart';
import '../models/treatment.dart';
import '../providers/consultation_provider.dart';
import '../providers/doctor_provider.dart';
import '../providers/therapy_provider.dart';
import '../widgets/app_snack_bar.dart';
import '../widgets/empty_illustration.dart';
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

  /// Dias consecutivos (incluindo hoje) com TODAS as doses tomadas.
  /// Para no primeiro dia com doses pendentes/puladas ou sem programa.
  static int _fullDaysStreak(TherapyProvider provider) {
    var streak = 0;
    final today = _dateOnly(DateTime.now());
    for (var offset = 0; offset < 60; offset++) {
      final day = today.subtract(Duration(days: offset));
      final adherence = provider.adherenceForDay(day);
      if (adherence.total == 0) break;
      if (adherence.taken < adherence.total) break;
      streak++;
    }
    return streak;
  }

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
    final consultations = consultationProvider.getConsultationsFromDay(
      _selectedDay,
    );
    final isToday = _dateOnly(DateTime.now()) == _selectedDay;
    final adherence = therapyProvider.adherenceForDay(_selectedDay);

    final hasNothing = events.isEmpty && consultations.isEmpty;
    final streak = isToday ? _fullDaysStreak(therapyProvider) : 0;

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
                showProgressCard: !hasNothing,
                streak: streak,
                events: events,
                onSelectDay: _selectDay,
              ),
            ),
          ),
          if (hasNothing)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.wb_sunny_outlined,
                illustration: EmptyIllustrationKind.freeDay,
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
                    final doctor =
                        doctorProvider.doctors
                            .where((d) => d.id == consultation.doctorId)
                            .firstOrNull;
                    return _TodayConsultationCard(
                      consultation: consultation,
                      doctor: doctor,
                      selectedDay: _selectedDay,
                      onStatusChanged: (newStatus) async {
                        final updated = consultation.copyWith(
                          status: newStatus,
                        );
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
                    title:
                        isToday
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
                    final treatment = therapyProvider.treatmentById(
                      event.treatmentId,
                    );
                    if (treatment == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _DoseTimelineRow(
                        event: event,
                        isFirst: index == 0,
                        isLast: index == events.length - 1,
                        child: DoseCard(
                          event: event,
                          treatment: treatment,
                          onStatusChanged: (status) async {
                            unawaited(HapticFeedback.lightImpact());
                            await therapyProvider.setDoseStatus(event, status);
                            // Zerou o dia de hoje? Confete calmo de cápsulas.
                            final adherence = therapyProvider.adherenceForDay(
                              _selectedDay,
                            );
                            if (!context.mounted) return;
                            if (isToday &&
                                status == DoseStatus.taken &&
                                adherence.total > 0 &&
                                adherence.taken == adherence.total) {
                              showCapsuleConfetti(context);
                              return;
                            }
                            if (!context.mounted) return;
                            showAppSnackBar(
                              context,
                              status == DoseStatus.taken
                                  ? 'Dose marcada como tomada.'
                                  : 'Dose pulada.',
                              action: SnackBarAction(
                                label: 'Desfazer',
                                onPressed: () => therapyProvider
                                    .setDoseStatus(event, DoseStatus.pending),
                              ),
                            );
                          },
                        ),
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
    required this.showProgressCard,
    required this.streak,
    required this.events,
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
              _StreakPill(days: streak),
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
                  _NextDoseBadge(events: events),
                ],
              ],
            ),
          ),
        ],
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
    final semantic = AppSemanticColors.of(context);
    final timeFormat = DateFormat('HH:mm');

    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (consultation.status) {
      case ConsultationStatus.completed:
        statusColor = semantic.success;
        statusIcon = Icons.check_circle_outline;
        statusText = 'Realizada';
        break;
      case ConsultationStatus.cancelled:
        statusColor = semantic.danger;
        statusIcon = Icons.cancel_outlined;
        statusText = 'Cancelada';
        break;
      default:
        statusColor = semantic.warning;
        statusIcon = Icons.medical_services_outlined;
        statusText = 'Agendada';
    }

    // Contagem regressiva até a consulta (em relação ao dia selecionado).
    final daysUntil = _daysUntil();
    final countdownBadge =
        consultation.status == ConsultationStatus.scheduled
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
          color: semantic.warning.withValues(alpha: .55),
          width: 1.5,
        ),
      ),
      color: semantic.warning.withValues(alpha: 0.08),
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
                    color: semantic.warning.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(statusIcon, color: statusColor, size: 26),
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
                              color: statusColor,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (daysUntil > 0) ...[
                            const SizedBox(width: 4),
                            Text(
                              DateFormat(
                                'dd/MM',
                                'pt_BR',
                              ).format(consultation.date),
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
                  itemBuilder:
                      (context) => [
                        if (consultation.status != ConsultationStatus.completed)
                          const PopupMenuItem(
                            value: ConsultationStatus.completed,
                            child: ListTile(
                              leading: Icon(
                                Icons.check_circle_outline,
                                color: Colors.green,
                              ),
                              title: Text('Marcar como realizada'),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        if (consultation.status != ConsultationStatus.scheduled)
                          const PopupMenuItem(
                            value: ConsultationStatus.scheduled,
                            child: ListTile(
                              leading: Icon(
                                Icons.schedule_outlined,
                                color: Colors.blue,
                              ),
                              title: Text('Marcar como agendada'),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        if (consultation.status != ConsultationStatus.cancelled)
                          const PopupMenuItem(
                            value: ConsultationStatus.cancelled,
                            child: ListTile(
                              leading: Icon(
                                Icons.cancel_outlined,
                                color: Colors.red,
                              ),
                              title: Text('Cancelar consulta'),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                      ],
                  child: Icon(Icons.more_vert, color: statusColor),
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
                  color: semantic.warning.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: statusColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        consultation.notes,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: statusColor,
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
    final isPending = event.status == DoseStatus.pending;
    final semantic = AppSemanticColors.of(context);
    final statusColor =
        isTaken
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

    return Card(
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
                      decoration:
                          isSkipped || isTaken
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
                  _DoseRoundAction(
                    icon: Icons.check_rounded,
                    tooltip: 'Tomei',
                    color: semantic.success,
                    onPressed: () => onStatusChanged(DoseStatus.taken),
                  ),
                  const SizedBox(height: 6),
                  _DoseRoundAction(
                    icon: Icons.skip_next_rounded,
                    tooltip: 'Pular',
                    color: semantic.danger,
                    onPressed: () => onStatusChanged(DoseStatus.skipped),
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
    );
  }
}

/// Botão de ação circular e preenchido da dose (verde "Tomei",
/// vermelho "Pular").
class _DoseRoundAction extends StatelessWidget {
  const _DoseRoundAction({
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
        fixedSize: const Size(44, 44),
        shape: const CircleBorder(),
      ),
    );
  }
}

/// Linha da trilha do dia: um ponto ligado por fios verticais à esquerda de
/// cada card — a "timeline" V4. Doses resolvidas pintam o ponto com a cor
/// do desfecho (verde/vermelho); pendente respira no azul de ação.
class _DoseTimelineRow extends StatelessWidget {
  const _DoseTimelineRow({
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
    final dotColor =
        isTaken
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
                    color:
                        isFirst
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
                    color:
                        isLast
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
class _StreakPill extends StatelessWidget {
  const _StreakPill({required this.days});

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

/// Contagem viva para a próxima dose pendente de hoje — atualiza sozinha
/// a cada 30 segundos. Some quando não há nada pendente.
class _NextDoseBadge extends StatefulWidget {
  const _NextDoseBadge({required this.events});

  final List<DoseEvent> events;

  @override
  State<_NextDoseBadge> createState() => _NextDoseBadgeState();
}

class _NextDoseBadgeState extends State<_NextDoseBadge> {
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
            'Próxima dose em ${_countdownFor(next.scheduledAt)}',
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

/// Confete V4: cápsulas e comprimidos caindo de verdade (CustomPainter),
/// nas cores verde-saúde do tema — comemora sem virar carnaval.
void showCapsuleConfetti(BuildContext context) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _CapsuleConfetti(onDone: () => entry.remove()),
  );
  overlay.insert(entry);
}

class _CapsuleConfetti extends StatefulWidget {
  const _CapsuleConfetti({required this.onDone});

  final VoidCallback onDone;

  @override
  State<_CapsuleConfetti> createState() => _CapsuleConfettiState();
}

class _CapsuleConfettiState extends State<_CapsuleConfetti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_ConfettiParticle> _particles;
  static final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppDurations.slow * 4,
    );
    _controller.forward().whenComplete(widget.onDone);
    _particles = List.generate(26, (_) => _ConfettiParticle.random(_random));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder:
            (context, _) => CustomPaint(
              painter: _ConfettiPainter(
                progress: _controller.value,
                particles: _particles,
                baseColor: semantic.success,
              ),
              size: MediaQuery.sizeOf(context),
            ),
      ),
    );
  }
}

class _ConfettiParticle {
  _ConfettiParticle({
    required this.startX,
    required this.delay,
    required this.fallSpeed,
    required this.drift,
    required this.rotation,
    required this.spin,
    required this.size,
    required this.isCapsule,
    required this.shade,
  });

  factory _ConfettiParticle.random(math.Random random) {
    return _ConfettiParticle(
      startX: random.nextDouble(),
      delay: random.nextDouble() * .35,
      fallSpeed: .55 + random.nextDouble() * .45,
      drift: (random.nextDouble() - .5) * .18,
      rotation: random.nextDouble() * math.pi * 2,
      spin: (random.nextDouble() - .5) * 5,
      size: 7 + random.nextDouble() * 7,
      isCapsule: random.nextBool(),
      shade: random.nextDouble(),
    );
  }

  final double startX;
  final double delay;
  final double fallSpeed;
  final double drift;
  final double rotation;
  final double spin;
  final double size;
  final bool isCapsule;
  final double shade;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({
    required this.progress,
    required this.particles,
    required this.baseColor,
  });

  final double progress;
  final List<_ConfettiParticle> particles;
  final Color baseColor;

  @override
  void paint(Canvas canvas, Size size) {
    for (final particle in particles) {
      final local = (progress - particle.delay) / (1 - particle.delay);
      if (local <= 0 || local >= 1) continue;
      final y = -30 + local * particle.fallSpeed * (size.height + 60);
      final x =
          particle.startX * size.width + particle.drift * local * size.width;
      final angle = particle.rotation + particle.spin * local * math.pi;
      final opacity = local > .8 ? (1 - local) / .2 : 1.0;
      final color = Color.lerp(
        baseColor,
        baseColor.withValues(alpha: .55),
        particle.shade,
      )!.withValues(alpha: opacity);

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle);
      final paint = Paint()..color = color;
      if (particle.isCapsule) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: particle.size * 1.8,
              height: particle.size * .8,
            ),
            Radius.circular(particle.size * .4),
          ),
          paint,
        );
      } else {
        canvas.drawCircle(Offset.zero, particle.size * .45, paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
