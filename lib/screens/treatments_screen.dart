import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/treatment.dart';
import '../models/treatment_draft.dart';
import '../providers/therapy_provider.dart';
import '../providers/user_profile_provider.dart';
import '../screens/prescription_review_screen.dart';
import '../services/prescription_reader_service.dart';
import '../core/design/app_tokens.dart';
import '../widgets/app_snack_bar.dart';
import '../widgets/empty_illustration.dart';
import '../widgets/skeleton.dart';
import '../widgets/empty_state.dart';
import '../widgets/info_chip.dart';
import '../widgets/media_source_sheet.dart';
import '../widgets/privacy_notice.dart';
import '../widgets/reading_dialog.dart';
import '../widgets/section_header.dart';
import '../widgets/stepped_form_sheet.dart';
import '../widgets/treatment_form_dialog.dart';

class TreatmentsScreen extends StatelessWidget {
  const TreatmentsScreen({super.key});

  Future<void> _openTreatmentForm(
    BuildContext context, {
    Treatment? treatment,
  }) async {
    final result = await showSteppedFormSheet<Treatment>(
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
    unawaited(HapticFeedback.mediumImpact());
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      treatment == null ? 'Tratamento salvo. Bom começo!' : 'Tratamento atualizado.',
      type: AppSnackType.success,
    );
  }

  /// Foto da receita: ler, conferir e salvar um tratamento por medicamento.
  /// Cada rascunho passa pelo formulário de tratamento — a leitura só
  /// preenche, quem salva é o usuário.
  Future<void> _startPrescriptionFlow(BuildContext context) async {
    final consented = await _ensurePrescriptionConsent(context);
    if (!consented || !context.mounted) return;

    final source = await _pickImageSource(context);
    if (source == null || !context.mounted) return;

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
      return;
    }
    if (file == null) return;

    final bytes = await file.readAsBytes();
    if (!context.mounted) return;

    // Diálogo sem await: só é dispensado quando a leitura termina, e awaitar
    // aqui travaria a tela sem nunca enviar a imagem (padrão da leitura de
    // cartão).
    unawaited(showReadingDialog(context));

    PrescriptionReadResult? result;
    String? error;
    try {
      result = await PrescriptionReaderService().readPrescription(
        imageBytes: bytes,
        mimeType: _mimeTypeOf(file),
      );
    } on PrescriptionReaderException catch (e) {
      error = e.message;
    } catch (_) {
      error =
          'Não foi possível ler a receita. Tente outra foto ou cadastre '
          'manualmente.';
    }

    if (!context.mounted) return;
    Navigator.of(
      context,
      rootNavigator: true,
    ).pop(); // fecha o diálogo de leitura

    if (result == null) {
      _showSnack(context, error!);
      return;
    }

    final drafts = await Navigator.of(context).push<List<TreatmentDraft>>(
      MaterialPageRoute(
        builder: (_) => PrescriptionReviewScreen(result: result!),
      ),
    );
    if (drafts == null || drafts.isEmpty || !context.mounted) return;

    final provider = context.read<TherapyProvider>();
    for (final draft in drafts) {
      if (!context.mounted) return;
      final saved = await showSteppedFormSheet<Treatment>(
        context: context,
        builder: (_) => TreatmentFormDialog(draft: draft),
      );
      if (saved != null) {
        await provider.addTreatment(saved);
      }
    }
  }

  Future<bool> _ensurePrescriptionConsent(BuildContext context) async {
    final userProvider = context.read<UserProfileProvider>();
    if (userProvider.profile?.consentAt != null) return true;

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Autorização necessária'),
            content: const SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Para ler a foto da receita, a imagem é enviada ao nosso '
                    'servidor e descartada após a leitura por OCR. Essa opção '
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
    return showImageSourceSheet(
      context,
      cameraLabel: 'Tirar foto da receita',
      galleryLabel: 'Escolher imagem da galeria',
    );
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  static String _mimeTypeOf(XFile file) {
    final path = file.path.toLowerCase();
    if (path.endsWith('.png')) return 'image/png';
    if (path.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
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
                  onAction: () => _openTreatmentForm(context),
                  secondaryActionLabel: 'Usar foto da receita',
                  onSecondaryAction: () => _startPrescriptionFlow(context),
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
                      onEdit:
                          () =>
                              _openTreatmentForm(context, treatment: treatment),
                      onArchive: () => _confirmArchive(context, treatment),
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
                    onPressed: () => _startPrescriptionFlow(context),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Foto da receita'),
                  ),
                  const SizedBox(height: 12),
                  FloatingActionButton.extended(
                    heroTag: 'add-treatment-fab',
                    onPressed: () => _openTreatmentForm(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Adicionar'),
                  ),
                ],
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
