import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/design/app_tokens.dart';
import '../core/theme/app_theme.dart';
import '../core/design/brand_colors.dart';
import '../core/design/record_card.dart';
import '../core/design/stat_card.dart';
import '../models/exam.dart';
import '../providers/exam_provider.dart';
import 'lab_results_screen.dart';
import '../widgets/app_snack_bar.dart';
import '../widgets/empty_illustration.dart';
import '../widgets/empty_state.dart';
import '../widgets/exam_form_dialog.dart';
import '../widgets/section_header.dart';
import '../widgets/skeleton.dart';
import '../widgets/stepped_form_sheet.dart';

/// Módulo de exames — portado do PWA: acompanha do pedido do médico ao
/// laudo, com leitura do pedido por IA e foto anexada ao registro.
class ExamsScreen extends StatelessWidget {
  const ExamsScreen({super.key});

  Future<void> _openExamForm(BuildContext context, {Exam? exam}) async {
    final result = await showSteppedFormSheet<Exam>(
      context: context,
      builder: (_) => ExamFormDialog(initialExam: exam),
    );
    if (result == null || !context.mounted) return;

    final provider = context.read<ExamProvider>();
    await provider.saveExam(result);
    unawaited(HapticFeedback.mediumImpact());
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      exam == null ? 'Exame registrado.' : 'Exame atualizado.',
      type: AppSnackType.success,
    );
  }

  Future<void> _confirmDelete(BuildContext context, Exam exam) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir exame?'),
        content: Text(
          'O registro de "${exam.name}" será removido permanentemente.',
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
      await context.read<ExamProvider>().removeExam(exam.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ExamProvider>();
    final semantic = AppSemanticColors.of(context);

    final pending = provider.pendingExams;
    final done = provider.doneExams;
    final hasExams = pending.isNotEmpty || done.isNotEmpty;

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
                            'Exames',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Do pedido do médico ao resultado do laudo.',
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
                    IconButton(
                      tooltip: 'Resultados de laboratório',
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const LabResultsScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.biotech_outlined),
                    ),
                    IconButton(
                      tooltip: 'Novo exame',
                      onPressed: () => _openExamForm(context),
                      icon: const Icon(Icons.add_circle_outline),
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
            else if (!hasExams)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.science_outlined,
                  illustration: EmptyIllustrationKind.calendarHeart,
                  title: 'Nenhum exame registrado',
                  description:
                      'Registre o pedido do médico (ou leia a foto dele com '
                      'IA) para acompanhar do pedido ao laudo.',
                  actionLabel: 'Registrar exame',
                  actionIcon: Icons.science_outlined,
                  onAction: () => _openExamForm(context),
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
                          icon: Icons.pending_actions_outlined,
                          value: '${provider.requestedCount}',
                          label: 'Solicitados',
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: StatCard(
                          icon: Icons.event_available_outlined,
                          value: '${provider.scheduledCount}',
                          label: 'Agendados',
                          iconColor: BrandColors.yellow,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: StatCard(
                          icon: Icons.task_alt_outlined,
                          value: '${provider.doneCount}',
                          label: 'Realizados',
                          iconColor: semantic.success,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (pending.isNotEmpty) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 26, 20, 10),
                  sliver: SliverToBoxAdapter(
                    child: SectionHeader(title: 'Pendentes'),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  sliver: SliverList.separated(
                    itemCount: pending.length,
                    itemBuilder: (context, index) => _ExamCard(
                      exam: pending[index],
                      onEdit: () =>
                          _openExamForm(context, exam: pending[index]),
                      onDelete: () => _confirmDelete(context, pending[index]),
                    ),
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: AppSpacing.md),
                  ),
                ),
              ],
              if (done.isNotEmpty) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 26, 20, 10),
                  sliver: SliverToBoxAdapter(
                    child: SectionHeader(title: 'Realizados'),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  sliver: SliverList.separated(
                    itemCount: done.length,
                    itemBuilder: (context, index) => _ExamCard(
                      exam: done[index],
                      onEdit: () => _openExamForm(context, exam: done[index]),
                      onDelete: () => _confirmDelete(context, done[index]),
                    ),
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: AppSpacing.md),
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

Color _statusColor(String status) {
  switch (status) {
    case ExamStatus.requested:
      return BrandColors.teal700;
    case ExamStatus.scheduled:
      return BrandColors.yellow;
    case ExamStatus.done:
      return const Color(0xFF0D9488);
    default:
      return BrandColors.teal700;
  }
}

class _ExamCard extends StatelessWidget {
  const _ExamCard({
    required this.exam,
    required this.onEdit,
    required this.onDelete,
  });

  final Exam exam;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  void _viewPhoto(BuildContext context) {
    final bytes = exam.photo == null ? null : base64Decode(exam.photo!);
    if (bytes == null) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: GestureDetector(
          onTap: () => Navigator.of(dialogContext).pop(),
          child: InteractiveViewer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _statusColor(exam.status);
    final mutedColor = isDark ? BrandColors.darkMuted : BrandColors.muted;

    final dateFormat = DateFormat('dd/MM/yyyy', 'pt_BR');
    final timeSuffix = exam.isScheduled && exam.time != null
        ? ' às ${exam.time}'
        : '';

    return RecordCard(
      accentColor: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (exam.photo != null)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.md),
                  child: GestureDetector(
                    onTap: () => _viewPhoto(context),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: Builder(
                        builder: (context) {
                          final Uint8List bytes = base64Decode(exam.photo!);
                          return Image.memory(
                            bytes,
                            width: 52,
                            height: 52,
                            fit: BoxFit.cover,
                          );
                        },
                      ),
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
                      color: accent.withValues(alpha: isDark ? .18 : .12),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(Icons.science_outlined, color: accent),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exam.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _StatusChip(label: exam.statusLabel, color: accent),
                        if (exam.category.isNotEmpty)
                          _CategoryChip(label: exam.category),
                      ],
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
          const SizedBox(height: 10),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _DetailLine(
                icon: Icons.event_outlined,
                text:
                    '${exam.datePrefix} ${dateFormat.format(exam.date)}$timeSuffix',
              ),
              if (exam.doctorName.isNotEmpty)
                _DetailLine(
                  icon: Icons.medical_information_outlined,
                  text: 'Solicitado por ${exam.doctorName}',
                ),
              if (exam.place.isNotEmpty)
                _DetailLine(icon: Icons.place_outlined, text: exam.place),
            ],
          ),
          if (exam.results.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              exam.results,
              style: theme.textTheme.bodySmall?.copyWith(
                color: mutedColor,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 15,
          color: isDark ? BrandColors.darkMuted : BrandColors.muted,
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: isDark ? BrandColors.darkInk : BrandColors.ink,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? .20 : .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: isDark ? color : Color.lerp(color, Colors.black, .25),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: .08)
            : Colors.black.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: isDark ? BrandColors.darkInk : BrandColors.ink,
        ),
      ),
    );
  }
}
