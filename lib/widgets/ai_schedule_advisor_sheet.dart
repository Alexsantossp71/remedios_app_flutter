import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design/app_tokens.dart';
import '../core/design/brand_colors.dart';
import '../providers/therapy_provider.dart';
import '../services/ai_service.dart';
import '../widgets/ai_sheet_shell.dart';

/// Consultor de horários — port do ScheduleAdvisorModal do PWA. A IA apenas
/// apresenta opções de organização do relógio: nada é aplicado aqui, a
/// revisão e a aplicação (via edição do tratamento) ficam com o usuário.
Future<void> showAiScheduleAdvisorSheet(BuildContext context) async {
  await showAiSheet<AiScheduleAdvice>(
    context: context,
    title: 'Consultor de horários',
    subtitle: 'Organização das doses entre o dia — revisão humana',
    icon: Icons.schedule_rounded,
    loadingMessage: 'Organizando seus horários…',
    load: () {
      final treatments =
          context.read<TherapyProvider>().activeTreatments.toList();
      return AiService().suggestSchedule(treatments);
    },
    buildResult: (context, advice) => AiScheduleAdviceView(advice: advice),
  );
}

class AiScheduleAdviceView extends StatelessWidget {
  const AiScheduleAdviceView({super.key, required this.advice});

  final AiScheduleAdvice advice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (advice.summary.isNotEmpty)
          Text(
            advice.summary,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
        if (advice.suggestions.isEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'A IA não devolveu sugestões para seus tratamentos.',
            style: theme.textTheme.bodyMedium,
          ),
        ] else ...[
          const SizedBox(height: 16),
          for (final suggestion in advice.suggestions) ...[
            _ScheduleSuggestionCard(suggestion: suggestion),
            const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }
}

class _ScheduleSuggestionCard extends StatelessWidget {
  const _ScheduleSuggestionCard({required this.suggestion});

  final AiScheduleSuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color:
              suggestion.changed
                  ? BrandColors.teal600.withValues(alpha: .40)
                  : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  suggestion.medicationName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color:
                      suggestion.changed
                          ? BrandColors.teal600.withValues(alpha: .15)
                          : (isDark
                              ? Colors.white.withValues(alpha: .06)
                              : Colors.black.withValues(alpha: .05)),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  suggestion.changed ? 'Horário novo' : 'Mantidos',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color:
                        suggestion.changed
                            ? BrandColors.teal700
                            : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Horários sugeridos em pílulas — a proposta do modelo, sempre
          // revisável contra a coluna atual.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final time in suggestion.suggestedTimes)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color:
                        isDark
                            ? BrandColors.teal700.withValues(alpha: .18)
                            : BrandColors.accentSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    time,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: BrandColors.teal700,
                    ),
                  ),
                ),
            ],
          ),
          if (suggestion.reason.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              suggestion.reason,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
          ],
          if (suggestion.warnings.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final warning in suggestion.warnings)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: BrandColors.yellow,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        warning,
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.35,
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
    );
  }
}
