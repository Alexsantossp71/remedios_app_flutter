import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design/app_tokens.dart';
import '../core/design/brand_colors.dart';
import '../models/dose_event.dart';
import '../models/treatment.dart';
import '../providers/therapy_provider.dart';
import '../services/ai_service.dart';
import '../widgets/ai_sheet_shell.dart';

/// Perguntas sugeridas para a consulta — port do ConsultationSummary do
/// PWA. O contexto monta-se localmente (tratamentos + adesão dos últimos
/// 7 e 30 dias); apenas o resumo em texto vai ao modelo.
Future<void> showAiConsultationQuestionsSheet(BuildContext context) async {
  final therapy = context.read<TherapyProvider>();
  final treatments = therapy.activeTreatments.toList();
  final questions = await showAiSheet<List<String>>(
    context: context,
    title: 'Preparar consulta',
    subtitle: 'Perguntas sugeridas a partir da sua rotina',
    icon: Icons.medical_information_outlined,
    loadingMessage: 'Montando sugestões para sua consulta…',
    load: () => AiService().suggestConsultationQuestions(
      buildConsultationContext(therapy, treatments),
    ),
    buildResult: (context, questions) =>
        AiConsultationQuestionsView(questions: questions),
  );
  // Resultado vazio (resposta fora do formato) recebe feedback direto.
  if (questions != null && questions.isEmpty && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'A IA não devolveu perguntas úteis desta vez. Tente novamente.',
        ),
      ),
    );
  }
}

/// Agrega tratamentos + adesão local no formato que o modelo entende.
AiConsultationContext buildConsultationContext(
  TherapyProvider therapy,
  List<Treatment> treatments,
) {
  final now = DateTime.now();

  final medicationLines = <String>[];
  for (final treatment in treatments) {
    final times = treatment.doseTimes
        .map((time) =>
            '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}')
        .join(', ');
    final frequency = switch (treatment.frequency) {
      TreatmentFrequency.daily => 'todos os dias',
      TreatmentFrequency.weekdays => 'dias úteis',
      TreatmentFrequency.everyOtherDay => 'dias alternados',
      TreatmentFrequency.weekly => 'dias da semana escolhidos',
    };
    medicationLines.add(
      '${treatment.name}'
      '${treatment.dosage.trim().isNotEmpty ? ' ${treatment.dosage.trim()}' : ''}'
      ' — $frequency às $times'
      '${treatment.endDate == null ? ' (uso contínuo)' : ''}',
    );
  }

  final summary7 = _adherenceSummary(therapy, now, 7);
  final summary30 = _adherenceSummary(therapy, now, 30);
  final difficulties = _bandDifficulties(therapy, now, 30);

  return AiConsultationContext(
    medications: medicationLines,
    adherence7: summary7,
    adherence30: summary30,
    difficulties: difficulties,
  );
}

String _adherenceSummary(TherapyProvider therapy, DateTime now, int days) {
  var total = 0;
  var taken = 0;
  for (var offset = 0; offset < days; offset++) {
    final day = DateTime(now.year, now.month, now.day).subtract(
      Duration(days: offset),
    );
    final adherence = therapy.adherenceForDay(day);
    total += adherence.total;
    taken += adherence.taken;
  }
  if (total == 0) {
    return 'sem doses registradas nos últimos $days dias';
  }
  final percent = (taken * 100 / total).round();
  return '$percent% das doses tomadas ($taken de $total)';
}

/// Faixas do dia com mais doses perdidas (puladas), em 30 dias — port das
/// "dificuldades" do contexto de consulta do PWA.
List<String> _bandDifficulties(TherapyProvider therapy, DateTime now, int days) {
  const bands = [
    (label: 'Madrugada (0h–6h)', min: 0, max: 6),
    (label: 'Manhã (6h–12h)', min: 6, max: 12),
    (label: 'Tarde (12h–18h)', min: 12, max: 18),
    (label: 'Noite (18h–24h)', min: 18, max: 24),
  ];
  final missed = List.filled(bands.length, 0);
  final scheduled = List.filled(bands.length, 0);

  for (var offset = 0; offset < days; offset++) {
    final day = DateTime(now.year, now.month, now.day).subtract(
      Duration(days: offset),
    );
    for (final event in therapy.doseEventsForDay(day)) {
      final bandIndex = bands.indexWhere(
        (band) => event.scheduledAt.hour >= band.min && event.scheduledAt.hour < band.max,
      );
      if (bandIndex < 0) continue;
      scheduled[bandIndex]++;
      if (event.status == DoseStatus.skipped) missed[bandIndex]++;
    }
  }

  final result = <String>[];
  for (var i = 0; i < bands.length; i++) {
    if (missed[i] > 0) {
      result.add('${bands[i].label}: ${missed[i]} doses não tomadas de ${scheduled[i]}');
    }
  }
  return result;
}

class AiConsultationQuestionsView extends StatelessWidget {
  const AiConsultationQuestionsView({super.key, required this.questions});

  final List<String> questions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Leve estas perguntas à sua consulta — em ordem de importância:',
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
        ),
        const SizedBox(height: 12),
        for (var index = 0; index < questions.length; index++)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color:
                  isDark
                      ? BrandColors.teal700.withValues(alpha: .10)
                      : BrandColors.accentSoft.withValues(alpha: .55),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: BrandColors.teal700.withValues(alpha: .18),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${index + 1}.',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: BrandColors.teal700,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    questions[index],
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                  ),
                ),
              ],
            ),
          ),
        if (questions.isEmpty)
          Text(
            'Nenhuma pergunta devolvida. Tente novamente.',
            style: theme.textTheme.bodyMedium,
          ),
      ],
    );
  }
}
