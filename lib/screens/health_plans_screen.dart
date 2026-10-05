import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../models/health_plan.dart';
import '../providers/health_plan_provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/card_reader_service.dart';
import '../widgets/add_health_plan_sheet.dart';
import '../widgets/empty_state.dart';
import '../widgets/health_plan_form_dialog.dart';
import '../widgets/privacy_notice.dart';
import '../widgets/section_header.dart';
import 'health_plan_review_screen.dart';

/// Screen for managing health plans and medical insurance.
class HealthPlansScreen extends StatelessWidget {
  const HealthPlansScreen({super.key, this.cardReaderFactory});

  /// Fábrica do serviço de leitura do cartão.
  ///
  /// Existe apenas para permitir injetar um cliente HTTP nos testes de widget;
  /// sem isso, qualquer teste que chegue ao `_scanCard` dispararia uma chamada
  /// real para o endpoint de produção.
  final CardReaderService Function()? cardReaderFactory;

  @override
  Widget build(BuildContext context) {
    return Consumer<HealthPlanProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          appBar: AppBar(title: const Text('Meus Planos de Saúde')),
          floatingActionButton: provider.isLoading ||
                  provider.healthPlans.isEmpty
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _addPlan(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar plano'),
                ),
          body: SafeArea(
            child: provider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildList(context, provider),
          ),
        );
      },
    );
  }

  Widget _buildList(BuildContext context, HealthPlanProvider provider) {
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
            description:
                'Toque no + para adicionar seu primeiro plano de saúde.',
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
  }

  /// Inicia o cadastro de um novo plano: imagem do cartão (com leitura e
  /// conferência) ou preenchimento manual.
  Future<void> _addPlan(BuildContext context) async {
    final provider = context.read<HealthPlanProvider>();
    final choice = await showAddHealthPlanSheet(context);
    if (choice == null || !context.mounted) return;

    if (choice == AddPlanChoice.manual) {
      await _openManualForm(context, provider);
      return;
    }

    final scan = await _scanCard(context);
    if (scan == null || !context.mounted) return;

    final plan = await Navigator.of(context).push<HealthPlan>(
      MaterialPageRoute(
        builder: (_) => HealthPlanReviewScreen(
          scan: scan,
          onRescan: () => _scanCard(context),
          onManualEntry: () => _leaveReviewForManual(context),
        ),
      ),
    );

    if (plan == null) return;
    await provider.saveHealthPlan(plan);
    if (!context.mounted) return;
    _showSnack(context, '${plan.name} adicionado com sucesso!');
  }

  /// Abre o formulário manual (cadastro ou edição).
  Future<void> _openManualForm(
    BuildContext context,
    HealthPlanProvider provider, [
    HealthPlan? existing,
  ]) async {
    final plan = await showDialog<HealthPlan>(
      context: context,
      builder: (_) => HealthPlanFormDialog(healthPlan: existing),
    );

    if (plan == null || !context.mounted) return;
    await provider.saveHealthPlan(plan);
    if (!context.mounted) return;
    _showSnack(
      context,
      existing == null
          ? '${plan.name} adicionado com sucesso!'
          : '${plan.name} atualizado!',
    );
  }

  /// Escolhe a imagem, faz a leitura e devolve os dados extraídos.
  /// Retorna `null` quando o usuário cancela, não consentiu ou a leitura
  /// falha.
  Future<CardScanResult?> _scanCard(BuildContext context) async {
    // LGPD: a foto do cartão sai do dispositivo para a leitura por IA, então
    // o consentimento específico é obrigatório antes de abrir o seletor.
    final consented = await _ensureScanConsent(context);
    if (!consented || !context.mounted) return null;

    final source = await _pickImageSource(context);
    if (source == null || !context.mounted) return null;

    final XFile? file;
    try {
      file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
    } catch (_) {
      if (context.mounted) {
        _showSnack(context, 'Não foi possível acessar a imagem.');
      }
      return null;
    }
    if (file == null) return null;

    final bytes = await file.readAsBytes();
    if (!context.mounted) return null;

    // O diálogo é empurrado sem await: showDialog só completa quando a rota
    // é dispensada, e a única linha que a dispensa (o pop no fim do fluxo)
    // depende da leitura terminar. Awaitar aqui trava a tela para sempre sem
    // nunca enviar a imagem.
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _ReadingCardDialog(),
      ),
    );

    CardReadResult? data;
    String? error;
    try {
      data = await (cardReaderFactory?.call() ?? CardReaderService()).readCard(
        imageBytes: bytes,
        mimeType: _mimeTypeOf(file),
      );
    } on CardReaderException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Não foi possível ler o cartão. Tente outra foto ou cadastre '
          'manualmente.';
    }

    if (!context.mounted) return null;
    Navigator.of(context).pop(); // fecha o diálogo de leitura

    if (data == null) {
      _showSnack(
        context,
        error ?? 'Não foi possível ler o cartão.',
        action: SnackBarAction(
          label: 'Cadastrar manualmente',
          onPressed: () {
            final provider = context.read<HealthPlanProvider>();
            _openManualForm(context, provider);
          },
        ),
      );
      return null;
    }

    return CardScanResult(data: data, imageBytes: bytes);
  }

  /// Garante o consentimento LGPD antes do envio da imagem. Retorna `true`
  /// quando o usuário já consentiu ou acabou de consentir.
  Future<bool> _ensureScanConsent(BuildContext context) async {
    final userProvider = context.read<UserProfileProvider>();
    if (userProvider.profile?.consentAt != null) return true;

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Autorização necessária'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Para ler a foto do cartão, a imagem é enviada a um '
                'serviço de IA e descartada após a leitura. Essa opção '
                'usa a internet; o cadastro manual não envia nada.',
              ),
              SizedBox(height: 12),
              PrivacyNoticeCard(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Aceito e autorizo'),
          ),
        ],
      ),
    );

    if (accepted != true || !context.mounted) return false;
    await userProvider.grantConsent();
    return true;
  }

  Future<ImageSource?> _pickImageSource(BuildContext context) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tirar foto do cartão'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Escolher imagem da galeria'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Sai da tela de conferência e abre o cadastro manual.
  Future<void> _leaveReviewForManual(BuildContext context) async {
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!context.mounted) return;
    await _openManualForm(context, context.read<HealthPlanProvider>());
  }

  String _mimeTypeOf(XFile file) {
    final mimeType = file.mimeType;
    if (mimeType != null && mimeType.startsWith('image/')) return mimeType;
    final name = file.name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  void _showSnack(
    BuildContext context,
    String message, {
    SnackBarAction? action,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        action: action,
      ),
    );
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

/// Diálogo modal exibido enquanto o cartão está sendo lido.
class _ReadingCardDialog extends StatelessWidget {
  const _ReadingCardDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Row(
        children: [
          const CircularProgressIndicator(strokeWidth: 3),
          const SizedBox(width: 20),
          Expanded(
            child: Text(
              'Lendo o cartão…',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ],
      ),
    );
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