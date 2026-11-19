import 'dart:async';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design/app_tokens.dart';
import '../models/dose_event.dart';
import '../providers/consultation_provider.dart';
import '../providers/doctor_provider.dart';
import '../providers/therapy_provider.dart';
import '../widgets/app_snack_bar.dart';
import '../widgets/empty_illustration.dart';
import '../widgets/empty_state.dart';
import '../widgets/section_header.dart';

import 'today/widgets/capsule_confetti.dart';
import 'today/widgets/consultation_card.dart';
import 'today/widgets/dose_card.dart';
import 'today/widgets/dose_timeline.dart';
import 'today/widgets/today_header.dart';

// DoseCard é público e usado fora (testes); reexportado para não
// quebrar imports existentes.
export 'today/widgets/dose_card.dart';

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
              child: TodayHeader(
                selectedDay: _selectedDay,
                isToday: isToday,
                adherence: adherence,
                showProgressCard: !hasNothing,
                streak: streak,
                events: events,
                consultationCount: consultations.length,
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
                    final doctor = doctorProvider.doctors
                        .where((d) => d.id == consultation.doctorId)
                        .firstOrNull;
                    return TodayConsultationCard(
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
                    final treatment = therapyProvider.treatmentById(
                      event.treatmentId,
                    );
                    if (treatment == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: DoseTimelineRow(
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
                                onPressed: () => therapyProvider.setDoseStatus(
                                  event,
                                  DoseStatus.pending,
                                ),
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
