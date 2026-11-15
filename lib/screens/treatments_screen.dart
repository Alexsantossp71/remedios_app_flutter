import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/treatment.dart';
import '../providers/therapy_provider.dart';
import '../core/design/app_tokens.dart';
import '../core/design/brand_colors.dart';
import '../core/design/quick_action.dart';
import '../core/design/record_card.dart';
import '../core/design/stat_card.dart';
import 'create_flows.dart';
import '../widgets/ai_interactions_sheet.dart';
import '../widgets/ai_medication_guide_sheet.dart';
import '../widgets/ai_schedule_advisor_sheet.dart';
import '../widgets/app_snack_bar.dart';
import '../widgets/empty_illustration.dart';
import '../widgets/skeleton.dart';
import '../widgets/empty_state.dart';
import '../widgets/info_chip.dart';
import '../widgets/section_header.dart';
import '../widgets/stepped_form_sheet.dart';
import '../widgets/treatment_form_dialog.dart';

class TreatmentsScreen extends StatelessWidget {
  const TreatmentsScreen({super.key});

  /// Edição de um tratamento existente. O cadastro (manual ou pela foto da
  /// receita) vive em [createTreatmentManually] e
  /// [createTreatmentFromPrescription] — usados pela tela e pelo menu central.
  Future<void> _editTreatment(BuildContext context, Treatment treatment) async {
    final result = await showSteppedFormSheet<Treatment>(
      context: context,
      builder: (_) => TreatmentFormDialog(initialTreatment: treatment),
    );
    if (result == null || !context.mounted) return;

    await context.read<TherapyProvider>().updateTreatment(result);
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      'Tratamento atualizado.',
      type: AppSnackType.success,
    );
  }

  Future<void> _confirmArchive(
    BuildContext context,
    Treatment treatment,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Arquivar tratamento?'),
            content: Text(
              '${treatment.name} deixará de gerar novas doses, mas o histórico será preservado.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton.tonal(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Arquivar'),
              ),
            ],
          ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<TherapyProvider>().archiveTreatment(treatment.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TherapyProvider>();
    final treatments = provider.activeTreatments;
    final lowStockCount = treatments.where((item) => item.needsRefill).length;

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
                      'Tratamentos',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Medicamentos, horários e estoque em um só lugar.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (treatments.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      _TreatmentStats(
                        activeCount: treatments.length,
                        lowStockCount: lowStockCount,
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: QuickAction(
                              icon: Icons.health_and_safety_outlined,
                              label: 'Checar interações',
                              onTap: () => showAiInteractionsSheet(context),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: QuickAction(
                              icon: Icons.schedule_rounded,
                              label: 'Consultor de horários',
                              onTap: () => showAiScheduleAdvisorSheet(context),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),
                      const SectionHeader(title: 'Em uso'),
                    ],
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
            else if (treatments.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.medication_outlined,
                  illustration: EmptyIllustrationKind.pillBottle,
                  title: 'Comece seu tratamento',
                  description:
                      'Cadastre seu primeiro medicamento para receber uma rotina organizada de doses.',
                  actionLabel: 'Adicionar medicamento',
                  onAction: () => createTreatmentManually(context),
                  secondaryActionLabel: 'Usar foto da receita',
                  onSecondaryAction: () => createTreatmentFromPrescription(context),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
                sliver: SliverList.separated(
                  itemCount: treatments.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final treatment = treatments[index];
                    return TreatmentCard(
                      treatment: treatment,
                      onEdit: () => _editTreatment(context, treatment),
                      onArchive: () => _confirmArchive(context, treatment),
                      onGuide: () => showAiMedicationGuideSheet(
                        context,
                        treatment,
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      floatingActionButton:
          treatments.isEmpty
              ? null
              : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FloatingActionButton.extended(
                    heroTag: 'prescription-scan-fab',
                    onPressed: () => createTreatmentFromPrescription(context),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Foto da receita'),
                  ),
                  const SizedBox(height: 12),
                  FloatingActionButton.extended(
                    heroTag: 'add-treatment-fab',
                    onPressed: () => createTreatmentManually(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Adicionar'),
                  ),
                ],
              ),
    );
  }
}

/// Fileira de estatísticas da tela — a linha de `.app-stat-card` do PWA:
/// tratamentos ativos e itens que precisam de reposição, cada um em seu
/// cartão de estatística com o ícone em caixa arredondada.
class _TreatmentStats extends StatelessWidget {
  const _TreatmentStats({
    required this.activeCount,
    required this.lowStockCount,
  });

  final int activeCount;
  final int lowStockCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: StatCard(
            icon: Icons.medication_rounded,
            value: '$activeCount',
            label: activeCount == 1 ? 'tratamento ativo' : 'tratamentos ativos',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatCard(
            icon:
                lowStockCount > 0
                    ? Icons.inventory_2_rounded
                    : Icons.check_circle_outline_rounded,
            value: '$lowStockCount',
            label:
                lowStockCount == 0
                    ? 'estoque em dia'
                    : lowStockCount == 1
                    ? 'item para repor'
                    : 'itens para repor',
            iconColor:
                lowStockCount > 0 ? BrandColors.yellow : BrandColors.teal600,
          ),
        ),
      ],
    );
  }
}

class TreatmentCard extends StatelessWidget {
  const TreatmentCard({
    super.key,
    required this.treatment,
    required this.onEdit,
    required this.onArchive,
    required this.onGuide,
  });

  final Treatment treatment;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  /// Explica o medicamento com IA (bula simplificada).
  final VoidCallback onGuide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final formattedTimes = treatment.doseTimes
        .map(
          (time) => DateFormat.Hm().format(
            DateTime(2024, 1, 1, time.hour, time.minute),
          ),
        )
        .join(' · ');

    return RecordCard(
      onTap: onEdit,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              // Caixa de ícone `.stat-icon` do PWA: véu teal com anel fino.
              color:
                  isDark
                      ? BrandColors.teal700.withValues(alpha: .18)
                      : BrandColors.accentSoft,
              borderRadius: BorderRadius.circular(AppRadius.iconBox),
              border: Border.all(
                color: BrandColors.teal700.withValues(alpha: .07),
              ),
            ),
            child: Icon(
              _presentationIcon(treatment.presentation),
              color: BrandColors.teal700,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        treatment.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Opções do tratamento',
                      padding: EdgeInsets.zero,
                      onSelected: (value) {
                        if (value == 'edit') onEdit();
                        if (value == 'archive') onArchive();
                        if (value == 'guide') onGuide();
                      },
                      itemBuilder:
                          (_) => const [
                            PopupMenuItem(
                              value: 'edit',
                              child: ListTile(
                                leading: Icon(Icons.edit_outlined),
                                title: Text('Editar'),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                            PopupMenuItem(
                              value: 'guide',
                              child: ListTile(
                                leading: Icon(Icons.auto_awesome_outlined),
                                title: Text('Explicar com IA'),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                            PopupMenuItem(
                              value: 'archive',
                              child: ListTile(
                                leading: Icon(Icons.archive_outlined),
                                title: Text('Arquivar'),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ],
                      child: const Icon(Icons.more_horiz),
                    ),
                  ],
                ),
                Text(
                  [
                    treatment.dosage,
                    treatment.presentation,
                  ].where((part) => part.trim().isNotEmpty).join(' · '),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    InfoChip(icon: Icons.schedule, label: formattedTimes),
                    InfoChip(
                      icon: Icons.repeat,
                      label: _frequencyLabel(treatment),
                    ),
                    if (treatment.stock != null)
                      InfoChip(
                        icon:
                            treatment.needsRefill
                                ? Icons.warning_amber_rounded
                                : Icons.inventory_2_outlined,
                        label: '${treatment.stock} un.',
                        isWarning: treatment.needsRefill,
                      ),
                  ],
                ),
                if (treatment.instructions.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    treatment.instructions,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static IconData _presentationIcon(String presentation) {
    final value = presentation.toLowerCase();
    if (value.contains('gota') ||
        value.contains('xarope') ||
        value.contains('spray')) {
      return Icons.medication_liquid_outlined;
    }
    return Icons.medication_outlined;
  }

  /// Rótulos curtos dos dias — mesma ordem de DateTime.weekday (1=seg … 7=dom).
  static const List<String> _weekdayLabels = [
    'seg',
    'ter',
    'qua',
    'qui',
    'sex',
    'sáb',
    'dom',
  ];

  static String _frequencyLabel(Treatment treatment) {
    switch (treatment.frequency) {
      case TreatmentFrequency.daily:
        return 'Diariamente';
      case TreatmentFrequency.weekdays:
        return 'Dias úteis';
      case TreatmentFrequency.everyOtherDay:
        return 'Dias alternados';
      case TreatmentFrequency.weekly:
        final days = treatment.weekdays
            .map((day) => _weekdayLabels[day - 1])
            .join(', ');
        // "Semanal (sáb)" — o dia é a informação que importa na lista.
        return days.isEmpty ? 'Semanal' : 'Semanal ($days)';
    }
  }
}
