/// Card de consulta marcada para o dia selecionado no painel "Hoje".
library;


import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/consultation.dart';
import '../../../models/doctor.dart';

class TodayConsultationCard extends StatelessWidget {
  const TodayConsultationCard({
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
                  itemBuilder: (context) => [
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
