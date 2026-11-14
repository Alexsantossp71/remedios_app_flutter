import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design/app_tokens.dart';
import '../core/design/brand_colors.dart';
import '../providers/therapy_provider.dart';
import '../services/ai_service.dart';
import '../widgets/ai_sheet_shell.dart';

/// Relatório de interações e duplicidades — port do InteractionsModal do
/// PWA: resumo, alertas por gravidade (vermelho/amarelo/teal) e fontes
/// declaradas pelo modelo.
Future<void> showAiInteractionsSheet(BuildContext context) async {
  await showAiSheet<AiInteractionReport>(
    context: context,
    title: 'Checagem de interações',
    subtitle: 'Duplicidades e combinações que merecem atenção',
    icon: Icons.health_and_safety_outlined,
    loadingMessage: 'Analisando seus tratamentos…',
    load: () {
      final treatments =
          context.read<TherapyProvider>().activeTreatments.toList();
      return AiService().analyzeInteractions(treatments);
    },
    buildResult: (context, report) => AiInteractionReportView(report: report),
  );
}

class AiInteractionReportView extends StatelessWidget {
  const AiInteractionReportView({super.key, required this.report});

  final AiInteractionReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (report.summary.isNotEmpty)
          Text(
            report.summary,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
        if (report.interactions.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Interações (${report.interactions.length})',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          for (final alert in report.interactions) ...[
            _InteractionAlertCard(alert: alert),
            const SizedBox(height: 10),
          ],
        ],
        if (report.duplicates.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Possíveis duplicidades (${report.duplicates.length})',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          for (final duplicate in report.duplicates) ...[
            _DuplicateCard(duplicate: duplicate),
            const SizedBox(height: 10),
          ],
        ],
        if (report.interactions.isEmpty && report.duplicates.isEmpty) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.check_circle_outline_rounded,
                color: BrandColors.teal600,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Nenhum alerta conhecido para esta combinação de '
                  'medicamentos. Ausência de alertas não exclui interações '
                  'raras ou específicas.',
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
              ),
            ],
          ),
        ],
        if (report.sources.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final source in report.sources)
                Chip(
                  avatar: const Icon(Icons.menu_book_outlined, size: 16),
                  label: Text(source, style: theme.textTheme.bodySmall),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _InteractionAlertCard extends StatelessWidget {
  const _InteractionAlertCard({required this.alert});

  final AiInteractionAlert alert;

  Color get _severityColor => switch (alert.severity) {
    AiInteractionSeverity.alta => BrandColors.red,
    AiInteractionSeverity.moderada => BrandColors.yellow,
    AiInteractionSeverity.baixa => BrandColors.teal600,
  };

  String get _severityLabel => switch (alert.severity) {
    AiInteractionSeverity.alta => 'Gravidade alta',
    AiInteractionSeverity.moderada => 'Gravidade moderada',
    AiInteractionSeverity.baixa => 'Gravidade baixa',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _severityColor.withValues(alpha: isDark ? .12 : .08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: _severityColor.withValues(alpha: .40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: _severityColor.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _severityLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: _severityColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final medication in alert.medications)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color:
                        isDark
                            ? BrandColors.darkInputFill
                            : const Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
                  child: Text(
                    medication,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            alert.description,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
          if (alert.recommendation.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    alert.recommendation,
                    style: theme.textTheme.bodySmall?.copyWith(
                      height: 1.4,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DuplicateCard extends StatelessWidget {
  const _DuplicateCard({required this.duplicate});

  final AiDuplicateGroup duplicate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            duplicate.activeIngredient,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            duplicate.medications.join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (duplicate.note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              duplicate.note,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}
