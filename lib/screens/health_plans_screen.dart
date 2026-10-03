import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/health_plan.dart';
import '../providers/health_plan_provider.dart';
import '../widgets/empty_state.dart';
import '../widgets/health_plan_form_dialog.dart';
import '../widgets/section_header.dart';

/// Screen for managing health plans and medical insurance.
class HealthPlansScreen extends StatelessWidget {
  const HealthPlansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Consumer<HealthPlanProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
            children: [
              Text(
                'Meus Planos de Saúde',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 5),
              Text(
                'Gerencie seus convênios e planos médicos.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 24),

              // Summary card
              if (provider.healthPlans.isNotEmpty) ...[
                _SummaryCard(count: provider.healthPlans.length),
                const SizedBox(height: 24),
              ],

              // Health plans list
              if (provider.healthPlans.isEmpty)
                EmptyState(
                  icon: Icons.health_and_safety_outlined,
                  title: 'Nenhum plano cadastrado',
                  description: 'Toque no + para adicionar seu primeiro plano de saúde.',
                  actionLabel: 'Adicionar plano',
                  onAction: () => _addPlan(context),
                )
              else ...[
                const SectionHeader(title: 'Planos Cadastrados'),
                const SizedBox(height: 10),
                ...provider.healthPlans.map((plan) => _HealthPlanCard(
                      plan: plan,
                      onEdit: () => _editPlan(context, provider, plan),
                      onDelete: () => _deletePlan(context, provider, plan),
                    )),
              ],
            ],
          );
        },
      ),
    );
  }

  void _addPlan(BuildContext context) async {
    final provider = context.read<HealthPlanProvider>();
    final plan = await showDialog<HealthPlan>(
      context: context,
      builder: (context) => const HealthPlanFormDialog(),
    );

    if (plan != null) {
      await provider.saveHealthPlan(plan);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${plan.name} adicionado com sucesso!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _editPlan(
    BuildContext context,
    HealthPlanProvider provider,
    HealthPlan plan,
  ) async {
    final updated = await showDialog<HealthPlan>(
      context: context,
      builder: (context) => HealthPlanFormDialog(healthPlan: plan),
    );

    if (updated != null) {
      await provider.saveHealthPlan(updated);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${updated.name} atualizado!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _deletePlan(
    BuildContext context,
    HealthPlanProvider provider,
    HealthPlan plan,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir plano?'),
        content: Text('Deseja realmente excluir "${plan.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await provider.removeHealthPlan(plan.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${plan.name} removido.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(
                Icons.health_and_safety,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count ${count == 1 ? 'plano cadastrado' : 'planos cadastrados'}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Seus convênios médicos organizados.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthPlanCard extends StatelessWidget {
  const _HealthPlanCard({
    required this.plan,
    required this.onEdit,
    required this.onDelete,
  });

  final HealthPlan plan;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.name,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        plan.provider,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    if (value == 'edit') onEdit();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 20),
                          SizedBox(width: 12),
                          Text('Editar'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline,
                            size: 20,
                            color: Colors.red,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Excluir',
                            style: TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // Details
            if (plan.cardNumber != null || plan.validity != null) ...[
              const Divider(height: 24),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  if (plan.cardNumber != null)
                    _InfoChip(
                      icon: Icons.credit_card_outlined,
                      label: plan.maskedCardNumber ?? plan.cardNumber!,
                    ),
                  if (plan.validity != null)
                    _InfoChip(
                      icon: Icons.calendar_today_outlined,
                      label: 'Validade: ${plan.validity}',
                    ),
                  if (plan.coverageType != null)
                    _InfoChip(
                      icon: Icons.shield_outlined,
                      label: plan.coverageType!,
                    ),
                ],
              ),
            ],

            // Specialties
            if (plan.specialties.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: plan.specialties.take(5).map((s) {
                  return Chip(
                    label: Text(
                      s,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 16,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}