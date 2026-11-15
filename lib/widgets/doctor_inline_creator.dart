import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design/app_tokens.dart';
import '../models/doctor.dart';
import '../models/doctor_draft.dart';
import '../providers/doctor_provider.dart';
import 'doctor_form_dialog.dart';
import 'stepped_form_sheet.dart';

/// Cadastro de médico POR CIMA de outro formulário (consulta, exame,
/// tratamento): abre o formulário de médico, salva direto no catálogo e
/// devolve quem foi salvo. O formulário chamador seleciona o médico novo
/// na hora — o usuário não recomeça o que já tinha digitado.
///
/// Regra do produto: consulta, tratamento e exame exigem médico cadastrado
/// antes de serem salvos — este helper é o que torna a exigência possível
/// sem virar beco sem saída dentro do formulário.
///
/// [draft] pré-preenche o formulário de médico (ex.: nome lido da receita
/// ou já digitado em "quem receitou") — preencher não é salvar; a
/// conferência continua sendo do usuário.
Future<Doctor?> createDoctorInline(
  BuildContext context, {
  DoctorDraft? draft,
}) async {
  final provider = context.read<DoctorProvider>();
  final result = await showSteppedFormSheet<Doctor>(
    context: context,
    builder: (_) => DoctorFormDialog(draft: draft),
  );
  if (result == null || !context.mounted) return null;
  await provider.saveDoctor(result);
  if (!context.mounted) return null;
  return result;
}

/// Aviso "nenhum médico cadastrado" com o botão que resolve ali mesmo.
/// Usado nos formulários que exigem médico (consulta, exame e o trecho
/// "Quem receitou" do tratamento quando o catálogo está vazio). Ao salvar
/// o médico novo, [onDoctorCreated] entrega o médico já gravado no
/// catálogo para o formulário selecionar.
class InlineDoctorBanner extends StatelessWidget {
  const InlineDoctorBanner({
    super.key,
    this.draft,
    required this.onDoctorCreated,
  });

  /// Pré-preenchimento opcional do formulário de médico.
  final DoctorDraft? draft;

  final ValueChanged<Doctor> onDoctorCreated;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
              const SizedBox(width: AppSpacing.sm + 2),
              Expanded(
                child: Text(
                  'Nenhum médico cadastrado. O médico é obrigatório — '
                  'cadastre aqui para continuar.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton.icon(
            onPressed: () async {
              final created = await createDoctorInline(context, draft: draft);
              if (created != null) onDoctorCreated(created);
            },
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Cadastrar médico'),
          ),
        ],
      ),
    );
  }
}
