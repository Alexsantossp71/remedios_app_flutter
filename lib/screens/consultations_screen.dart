import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/consultation.dart';
import '../models/doctor.dart';
import '../providers/consultation_provider.dart';
import '../providers/doctor_provider.dart';
import '../widgets/consultation_form_dialog.dart';
import '../widgets/empty_state.dart';
import '../widgets/section_header.dart';

class ConsultationsScreen extends StatelessWidget {
  const ConsultationsScreen({super.key});

  Future<void> _openConsultationForm(
    BuildContext context, {
    Consultation? consultation,
    String? initialDoctorId,
  }) async {
    final result = await showDialog<Consultation>(
      context: context,
      builder: (_) => ConsultationFormDialog(
        initialConsultation: consultation,
        initialDoctorId: initialDoctorId,
      ),
    );
    if (result == null || !context.mounted) return;

    final provider = context.read<ConsultationProvider>();
    await provider.saveConsultation(result);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    Consultation consultation,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir consulta?'),
        content: Text(
          'A consulta de ${_formatDateTime(consultation.date)} será removida permanentemente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<ConsultationProvider>().removeConsultation(consultation.id);
    }
  }

  Future<void> _changeStatus(
    BuildContext context,
    Consultation consultation,
    String newStatus,
  ) async {
    final provider = context.read<ConsultationProvider>();
    final updated = consultation.copyWith(status: newStatus);
    await provider.saveConsultation(updated);
  }

  String _formatDateTime(DateTime dateTime) {
    final dateFormat = DateFormat('dd/MM/yyyy', 'pt_BR');
    final timeFormat = DateFormat('HH:mm');
    return '${dateFormat.format(dateTime)} às ${timeFormat.format(dateTime)}';
  }

  @override
  Widget build(BuildContext context) {
    final consultationProvider = context.watch<ConsultationProvider>();
    final doctorProvider = context.watch<DoctorProvider>();

    final allUpcoming = consultationProvider.upcomingConsultations;
    final past = consultationProvider.pastConsultations;

    // Próximos 5 dias (inclui hoje até 5 dias adiante)
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final limit5Days = todayStart.add(const Duration(days: 6)); // cobre 5 dias completos adiante

    final highlighted = allUpcoming
        .where((c) => c.date.isAfter(todayStart.subtract(const Duration(seconds: 1))) && c.date.isBefore(limit5Days))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final otherUpcoming = allUpcoming
        .where((c) => c.date.isAfter(limit5Days) || c.date.isAtSameMomentAs(limit5Days))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final hasConsultations = allUpcoming.isNotEmpty || past.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.transparent,
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
                      'Consultas',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Agendamentos e histórico de atendimentos médicos.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                    if (hasConsultations) ...[
                      const SizedBox(height: 22),
                      _ConsultationsSummary(
                        upcomingCount: allUpcoming.length,
                        pastCount: past.length,
                      ),
                      const SizedBox(height: 26),
                    ],
                  ],
                ),
              ),
            ),
            if (consultationProvider.isLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (!hasConsultations)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.calendar_month_outlined,
                  title: 'Nenhuma consulta agendada',
                  description:
                      'Agende sua primeira consulta médica e acompanhe o histórico de atendimentos.',
                  actionLabel: doctorProvider.doctors.isEmpty
                      ? 'Cadastrar médico'
                      : 'Agendar consulta',
                  onAction: () {
                    if (doctorProvider.doctors.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Vá na aba "Médicos" para cadastrar um médico primeiro.'),
                        ),
                      );
                    } else {
                      _openConsultationForm(context);
                    }
                  },
                ),
              )
            else ...[
              // Seção em Destaque: Próximos 5 dias
              if (highlighted.isNotEmpty) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.notification_important_rounded,
                            size: 18,
                            color: Colors.amber,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Atenção: Consultas nos Próximos 5 Dias (${highlighted.length})',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.amber.shade900,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  sliver: SliverList.separated(
                    itemCount: highlighted.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final consultation = highlighted[index];
                      final doctor = doctorProvider.doctors
                          .where((d) => d.id == consultation.doctorId)
                          .firstOrNull;
                      return _ConsultationTile(
                        consultation: consultation,
                        doctor: doctor,
                        isHighlighted: true,
                        onEdit: () => _openConsultationForm(
                          context,
                          consultation: consultation,
                        ),
                        onDelete: () => _confirmDelete(context, consultation),
                        onComplete: () => _changeStatus(
                          context,
                          consultation,
                          ConsultationStatus.completed,
                        ),
                        onCancel: () => _changeStatus(
                          context,
                          consultation,
                          ConsultationStatus.cancelled,
                        ),
                        onReopen: () => _changeStatus(
                          context,
                          consultation,
                          ConsultationStatus.scheduled,
                        ),
                      );
                    },
                  ),
                ),
              ],

              // Demais Consultas Agendadas
              if (otherUpcoming.isNotEmpty) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  sliver: SliverToBoxAdapter(
                    child: SectionHeader(title: 'Próximas Consultas (${otherUpcoming.length})'),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  sliver: SliverList.separated(
                    itemCount: otherUpcoming.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final consultation = otherUpcoming[index];
                      final doctor = doctorProvider.doctors
                          .where((d) => d.id == consultation.doctorId)
                          .firstOrNull;
                      return _ConsultationTile(
                        consultation: consultation,
                        doctor: doctor,
                        isHighlighted: false,
                        onEdit: () => _openConsultationForm(
                          context,
                          consultation: consultation,
                        ),
                        onDelete: () => _confirmDelete(context, consultation),
                        onComplete: () => _changeStatus(
                          context,
                          consultation,
                          ConsultationStatus.completed,
                        ),
                        onCancel: () => _changeStatus(
                          context,
                          consultation,
                          ConsultationStatus.cancelled,
                        ),
                        onReopen: () => _changeStatus(
                          context,
                          consultation,
                          ConsultationStatus.scheduled,
                        ),
                      );
                    },
                  ),
                ),
              ],

              // Histórico
              if (past.isNotEmpty) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  sliver: SliverToBoxAdapter(
                    child: SectionHeader(title: 'Histórico (${past.length})'),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
                  sliver: SliverList.separated(
                    itemCount: past.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final consultation = past[index];
                      final doctor = doctorProvider.doctors
                          .where((d) => d.id == consultation.doctorId)
                          .firstOrNull;
                      return _ConsultationTile(
                        consultation: consultation,
                        doctor: doctor,
                        isHighlighted: false,
                        onEdit: () => _openConsultationForm(
                          context,
                          consultation: consultation,
                        ),
                        onDelete: () => _confirmDelete(context, consultation),
                        onComplete: () => _changeStatus(
                          context,
                          consultation,
                          ConsultationStatus.completed,
                        ),
                        onCancel: () => _changeStatus(
                          context,
                          consultation,
                          ConsultationStatus.cancelled,
                        ),
                        onReopen: () => _changeStatus(
                          context,
                          consultation,
                          ConsultationStatus.scheduled,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
      floatingActionButton: hasConsultations
          ? FloatingActionButton.extended(
              onPressed: () => _openConsultationForm(context),
              icon: const Icon(Icons.add),
              label: const Text('Agendar'),
            )
          : null,
    );
  }
}

class _ConsultationsSummary extends StatelessWidget {
  const _ConsultationsSummary({
    required this.upcomingCount,
    required this.pastCount,
  });

  final int upcomingCount;
  final int pastCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: .7),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.medical_services_outlined,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$upcomingCount ${upcomingCount == 1 ? 'próxima consulta' : 'próximas consultas'}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$pastCount ${pastCount == 1 ? 'consulta no histórico' : 'consultas no histórico'}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer
                        .withValues(alpha: .8),
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

class _ConsultationTile extends StatelessWidget {
  const _ConsultationTile({
    required this.consultation,
    required this.doctor,
    required this.onEdit,
    required this.onDelete,
    required this.onComplete,
    required this.onCancel,
    required this.onReopen,
    this.isHighlighted = false,
  });

  final Consultation consultation;
  final Doctor? doctor;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onComplete;
  final VoidCallback onCancel;
  final VoidCallback onReopen;
  final bool isHighlighted;

  String _formatDateTime(DateTime dateTime) {
    final dateFormat = DateFormat('dd/MM/yyyy', 'pt_BR');
    final timeFormat = DateFormat('HH:mm');
    return '${dateFormat.format(dateTime)} às ${timeFormat.format(dateTime)}';
  }

  int _daysUntil(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    return target.difference(today).inDays;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUpcoming = consultation.status == ConsultationStatus.scheduled &&
        consultation.date.isAfter(DateTime.now());

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
        if (isHighlighted) {
          statusColor = Colors.amber.shade800;
          statusIcon = Icons.priority_high_rounded;
          final days = _daysUntil(consultation.date);
          if (days == 0) {
            statusText = 'Hoje!';
          } else if (days == 1) {
            statusText = 'Amanhã!';
          } else {
            statusText = 'Em $days dias';
          }
        } else if (isUpcoming) {
          statusColor = theme.colorScheme.primary;
          statusIcon = Icons.schedule_outlined;
          statusText = 'Agendada';
        } else {
          statusColor = Colors.orange;
          statusIcon = Icons.pending_outlined;
          statusText = 'Pendente';
        }
    }

    final doctorName = doctor?.name ?? 'Médico não encontrado';
    final doctorSpecialty = doctor?.specialty ?? '';

    return Card(
      elevation: isHighlighted ? 2 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: isHighlighted
            ? BorderSide(color: Colors.amber.shade400, width: 1.5)
            : BorderSide.none,
      ),
      color: isHighlighted
          ? Colors.amber.shade50.withValues(alpha: 0.5)
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: statusColor.withValues(alpha: .15),
                  foregroundColor: statusColor,
                  child: Icon(statusIcon),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            Icons.person_outline,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              doctorName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: .15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              statusText,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Mais ações',
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        onEdit();
                        break;
                      case 'delete':
                        onDelete();
                        break;
                      case 'complete':
                        onComplete();
                        break;
                      case 'cancel':
                        onCancel();
                        break;
                      case 'reopen':
                        onReopen();
                        break;
                    }
                  },
                  itemBuilder: (context) {
                    final items = <PopupMenuEntry<String>>[
                      const PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Editar'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ];

                    if (consultation.status != ConsultationStatus.completed) {
                      items.add(const PopupMenuItem(
                        value: 'complete',
                        child: ListTile(
                          leading: Icon(Icons.check_circle_outline, color: Colors.green),
                          title: Text('Marcar como realizada'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ));
                    }

                    if (consultation.status != ConsultationStatus.cancelled) {
                      items.add(const PopupMenuItem(
                        value: 'cancel',
                        child: ListTile(
                          leading: Icon(Icons.cancel_outlined, color: Colors.red),
                          title: Text('Cancelar'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ));
                    }

                    if (consultation.status != ConsultationStatus.scheduled) {
                      items.add(const PopupMenuItem(
                        value: 'reopen',
                        child: ListTile(
                          leading: Icon(Icons.schedule_outlined, color: Colors.blue),
                          title: Text('Reagendar'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ));
                    }

                    items.add(const PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(Icons.delete_outline, color: Colors.red),
                        title: Text('Excluir'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ));

                    return items;
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  _formatDateTime(consultation.date),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (consultation.returnDate != null) ...[
                  const SizedBox(width: 16),
                  Icon(
                    Icons.event_repeat_outlined,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Retorno: ${DateFormat("dd/MM/yyyy", "pt_BR").format(consultation.returnDate!)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
            if (consultation.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.notes_outlined,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        consultation.notes,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
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
