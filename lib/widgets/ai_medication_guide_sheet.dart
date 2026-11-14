import 'package:flutter/material.dart';

import '../core/design/app_tokens.dart';
import '../core/design/brand_colors.dart';
import '../models/treatment.dart';
import '../services/ai_service.dart';
import '../widgets/ai_sheet_shell.dart';

/// Bula simplificada por IA — port do BulaModal do PWA: para que serve,
/// como usar, efeitos comuns, avisos e nota de rodapé. O resultado é
/// educativo e leigo; a bula do fabricante prevalece.
Future<void> showAiMedicationGuideSheet(
  BuildContext context,
  Treatment treatment,
) async {
  await showAiSheet<AiMedicationGuide>(
    context: context,
    title: 'Explicação da IA',
    subtitle: treatment.name,
    icon: Icons.auto_awesome_outlined,
    loadingMessage: 'Consultando a bula simplificada…',
    load: () => AiService().explainMedication(treatment),
    buildResult: (context, guide) => AiMedicationGuideView(guide: guide),
  );
}

class AiMedicationGuideView extends StatelessWidget {
  const AiMedicationGuideView({super.key, required this.guide});

  final AiMedicationGuide guide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _GuideSection(
          icon: Icons.help_outline_rounded,
          title: 'Para que serve',
          body: guide.whatFor,
        ),
        const SizedBox(height: 14),
        _GuideSection(
          icon: Icons.medication_rounded,
          title: 'Como se toma',
          body: guide.howToUse,
        ),
        if (guide.commonSideEffects.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            'Efeitos colaterais comuns',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final effect in guide.commonSideEffects)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color:
                        theme.brightness == Brightness.dark
                            ? BrandColors.darkInputFill
                            : const Color(0xFFF1F5F6),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
                  child: Text(
                    effect,
                    style: theme.textTheme.labelMedium,
                  ),
                ),
            ],
          ),
        ],
        if (guide.warnings.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            'Atenção',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          for (final warning in guide.warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
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
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (guide.note.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            guide.note,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }
}

class _GuideSection extends StatelessWidget {
  const _GuideSection({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: BrandColors.teal700),
            const SizedBox(width: 8),
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          body.isEmpty ? 'A IA não trouxe este conteúdo.' : body,
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
        ),
      ],
    );
  }
}
