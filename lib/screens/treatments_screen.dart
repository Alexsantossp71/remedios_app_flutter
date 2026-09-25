import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/treatment.dart';
import '../providers/therapy_provider.dart';
import '../widgets/empty_state.dart';
import '../widgets/section_header.dart';
import '../widgets/treatment_form_dialog.dart';

class TreatmentsScreen extends StatelessWidget {
  const TreatmentsScreen({super.key});

  Future<void> _openTreatmentForm(
    BuildContext context, {
    Treatment? treatment,
  }) async {
    final result = await showDialog<Treatment>(
      context: context,
      builder: (_) => TreatmentFormDialog(initialTreatment: treatment),
    );
    if (result == null || !context.mounted) return;

    final provider = context.read<TherapyProvider>();
    if (treatment == null) {
      await provider.addTreatment(result);
    } else {
      await provider.updateTreatment(result);
    }
  }

  Future<void> _confirmArchive(
    BuildContext context,
    Treatment treatment,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Medicamentos, horários e estoque em um só lugar.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                    if (treatments.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      _TreatmentSummary(
                        activeCount: treatments.length,
                        lowStockCount: lowStockCount,
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
                child: Center(child: CircularProgressIndicator()),
              )
            else if (treatments.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.medication_outlined,
                  title: 'Comece seu tratamento',
                  description:
                      'Cadastre seu primeiro medicamento para receber uma rotina organizada de doses.',
                  actionLabel: 'Adicionar medicamento',
                  onAction: () => _openTreatmentForm(context),
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
                      onEdit: () => _openTreatmentForm(
                        context,
                        treatment: treatment,
                      ),
                      onArchive: () => _confirmArchive(context, treatment),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: treatments.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openTreatmentForm(context),
              icon: const Icon(Icons.add),
              label: const Text('Adicionar'),
            ),
    );
  }
}

class _TreatmentSummary extends StatelessWidget {
  const _TreatmentSummary({
    required this.activeCount,
    required this.lowStockCount,
  });

  final int activeCount;
  final int lowStockCount;

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
              Icons.health_and_safety_outlined,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$activeCount ${activeCount == 1 ? 'tratamento ativo' : 'tratamentos ativos'}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  lowStockCount == 0
                      ? 'Seus estoques estão em dia.'
                      : '$lowStockCount ${lowStockCount == 1 ? 'item precisa' : 'itens precisam'} de reposição.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
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

class TreatmentCard extends StatelessWidget {
  const TreatmentCard({
    super.key,
    required this.treatment,
    required this.onEdit,
    required this.onArchive,
  });

  final Treatment treatment;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formattedTimes = treatment.doseTimes
        .map(
          (time) => DateFormat.Hm().format(
            DateTime(2024, 1, 1, time.hour, time.minute),
          ),
        )
        .join(' · ');

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  _presentationIcon(treatment.presentation),
                  color: theme.colorScheme.onSecondaryContainer,
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
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'edit',
                              child: ListTile(
                                leading: Icon(Icons.edit_outlined),
                                title: Text('Editar'),
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
                      [treatment.dosage, treatment.presentation]
                          .where((part) => part.trim().isNotEmpty)
                          .join(' · '),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _InfoChip(
                          icon: Icons.schedule,
                          label: formattedTimes,
                        ),
                        _InfoChip(
                          icon: Icons.repeat,
                          label: _frequencyLabel(treatment.frequency),
                        ),
                        if (treatment.stock != null)
                          _InfoChip(
                            icon: treatment.needsRefill
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
        ),
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

  static String _frequencyLabel(TreatmentFrequency frequency) {
    switch (frequency) {
      case TreatmentFrequency.daily:
        return 'Diariamente';
      case TreatmentFrequency.weekdays:
        return 'Dias úteis';
      case TreatmentFrequency.everyOtherDay:
        return 'Dias alternados';
    }
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    this.isWarning = false,
  });

  final IconData icon;
  final String label;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    final color = isWarning
        ? Colors.orange.shade800
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isWarning
            ? Colors.orange.withValues(alpha: .12)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
