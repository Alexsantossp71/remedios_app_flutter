import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/design/app_tokens.dart';
import '../core/lab_values.dart';
import '../core/theme/app_theme.dart';
import '../core/design/brand_colors.dart';
import '../core/design/record_card.dart';
import '../core/design/stat_card.dart';
import '../models/lab_result.dart';
import '../providers/lab_result_provider.dart';
import '../widgets/app_snack_bar.dart';
import '../widgets/empty_illustration.dart';
import '../widgets/empty_state.dart';
import '../widgets/lab_result_review_sheet.dart';
import '../widgets/section_header.dart';
import '../widgets/skeleton.dart';
import 'create_flows.dart';

/// Módulo de Resultados de laboratório — portado do PWA: histórico de
/// laudos com valores por marcador, comparação com a faixa impressa
/// (calculada no app, nunca pela IA) e evolução dos exames repetidos.
class LabResultsScreen extends StatelessWidget {
  const LabResultsScreen({super.key});

  // ── Cadastro ────────────────────────────────────────────────────────────
  //
  // Os dois caminhos de criação (foto lida por IA e digitação manual) vivem
  // em create_flows.dart — compartilhados com o menu central “+”.

  /// Edição de um laudo existente.
  Future<void> _editLabResult(BuildContext context, LabResult result) async {
    final saved = await showLabResultReviewSheet(
      context,
      initialResult: result,
    );
    if (saved == null || !context.mounted) return;

    await context.read<LabResultProvider>().saveResult(saved);
    if (context.mounted) {
      showAppSnackBar(context, 'Laudo atualizado.', type: AppSnackType.success);
    }
  }

  Future<void> _confirmDelete(BuildContext context, LabResult result) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir laudo?'),
        content: Text(
          'O laudo de ${DateFormat('dd/MM/yyyy').format(result.date)} e seus '
          '${result.values.length} valores serão removidos permanentemente.',
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
      await context.read<LabResultProvider>().removeResult(result.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LabResultProvider>();
    final semantic = AppSemanticColors.of(context);

    final results = provider.resultsByDate;
    final trends = provider.trends;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Resultados de laboratório',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Laudos, valores por marcador e evolução ao longo do tempo.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (provider.isLoading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                  child: Center(child: SkeletonList()),
                ),
              )
            else if (provider.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.biotech_outlined,
                  illustration: EmptyIllustrationKind.calendarHeart,
                  title: 'Nenhum laudo registrado',
                  description:
                      'Leia a foto do laudo com IA ou digite os valores à '
                      'mão para acompanhar a evolução dos seus exames.',
                  actionLabel: 'Digitar manualmente',
                  actionIcon: Icons.edit_outlined,
                  onAction: () => createLabResultManually(context),
                  secondaryActionLabel: 'Ler foto com IA',
                  secondaryActionIcon: Icons.photo_camera_outlined,
                  onSecondaryAction: () => createLabResultFromPhoto(context),
                ),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Expanded(
                        child: StatCard(
                          icon: Icons.biotech_outlined,
                          value: '${results.length}',
                          label: results.length == 1 ? 'laudo' : 'laudos',
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: StatCard(
                          icon: Icons.warning_amber_outlined,
                          value: '${provider.alteredCount}',
                          label: 'fora da faixa',
                          iconColor: semantic.danger,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => createLabResultFromPhoto(context),
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Ler foto com IA'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => createLabResultManually(context),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Digitar'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 26, 20, 10),
                sliver: SliverToBoxAdapter(
                  child: SectionHeader(title: 'Histórico'),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                sliver: SliverList.separated(
                  itemCount: results.length,
                  itemBuilder: (context, index) => _LabResultCard(
                    result: results[index],
                    onEdit: () => _editLabResult(context, results[index]),
                    onDelete: () => _confirmDelete(context, results[index]),
                  ),
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: AppSpacing.md),
                ),
              ),
              if (trends.isNotEmpty) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 26, 20, 10),
                  sliver: SliverToBoxAdapter(
                    child: SectionHeader(title: 'Evolução'),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  sliver: SliverList.separated(
                    itemCount: trends.length,
                    itemBuilder: (context, index) =>
                        _TrendCard(trend: trends[index]),
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: AppSpacing.sm),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

Color? _flagColor(String flag, AppSemanticColors semantic) {
  switch (flag) {
    case 'high':
      return semantic.danger;
    case 'low':
      return semantic.warning;
    case 'normal':
      return semantic.success;
    default:
      return null;
  }
}

String _flagLabel(String flag) {
  switch (flag) {
    case 'high':
      return 'acima';
    case 'low':
      return 'abaixo';
    case 'normal':
      return 'na faixa';
    default:
      return 'sem faixa';
  }
}

class _LabResultCard extends StatelessWidget {
  const _LabResultCard({
    required this.result,
    required this.onEdit,
    required this.onDelete,
  });

  final LabResult result;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dateFormat = DateFormat('dd/MM/yyyy', 'pt_BR');

    final accent = result.highCount > 0
        ? semantic.danger
        : result.lowCount > 0
        ? semantic.warning
        : null;

    return RecordCard(
      accentColor: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (result.photo != null)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.md),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: Image.memory(
                      base64Decode(result.photo!),
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.md),
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: BrandColors.teal700.withValues(
                        alpha: isDark ? .18 : .10,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(
                      Icons.biotech_outlined,
                      color: BrandColors.teal700,
                    ),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dateFormat.format(result.date),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (result.labName.isNotEmpty)
                      Text(
                        result.labName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? BrandColors.darkMuted
                              : BrandColors.muted,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      result.valuesSummary,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isDark ? BrandColors.darkInk : BrandColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Editar',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 20),
              ),
              IconButton(
                tooltip: 'Excluir',
                onPressed: onDelete,
                icon: Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: theme.brightness == Brightness.dark
                      ? BrandColors.red.withValues(alpha: .8)
                      : BrandColors.red,
                ),
              ),
            ],
          ),
          if (result.values.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final value in result.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        value.examName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${value.valueText.isEmpty ? '—' : value.valueText}'
                      '${value.unit.isEmpty ? '' : ' ${value.unit}'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color:
                            (_flagColor(value.flag, semantic) ??
                                    (isDark ? Colors.white : Colors.black)
                                        .withValues(alpha: .06))
                                .withValues(alpha: isDark ? .16 : .10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _flagLabel(value.flag),
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color:
                              _flagColor(value.flag, semantic) ??
                              (isDark
                                  ? BrandColors.darkMuted
                                  : BrandColors.muted),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (result.notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              result.notes,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isDark ? BrandColors.darkMuted : BrandColors.muted,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.trend});

  final ExamTrend trend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final first = trend.first;
    final last = trend.last;
    if (first == null || last == null) return const SizedBox.shrink();

    final dateFormat = DateFormat('dd/MM/yyyy', 'pt_BR');
    final directionLabel = switch (trend.direction) {
      'up' => 'subiu',
      'down' => 'desceu',
      _ => 'estável',
    };
    final directionColor = switch (trend.direction) {
      'up' => semantic.danger,
      'down' => semantic.success,
      _ => isDark ? BrandColors.darkMuted : BrandColors.muted,
    };
    final pct = trend.pctChange == null
        ? ''
        : ' ($directionLabel ~${trend.pctChange!.abs().round()}%)';

    return RecordCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trend.examName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatLabNumber(first.value)} → ${formatLabNumber(last.value)}'
                  '${last.unit.isEmpty ? '' : ' ${last.unit}'}$pct',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDark ? BrandColors.darkInk : BrandColors.ink,
                  ),
                ),
                Text(
                  'entre ${dateFormat.format(DateTime.parse(first.date))} e '
                  '${dateFormat.format(DateTime.parse(last.date))}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark ? BrandColors.darkMuted : BrandColors.muted,
                  ),
                ),
              ],
            ),
          ),
          Icon(switch (trend.direction) {
            'up' => Icons.trending_up_rounded,
            'down' => Icons.trending_down_rounded,
            _ => Icons.trending_flat_rounded,
          }, color: directionColor),
        ],
      ),
    );
  }
}
