import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../core/design/app_tokens.dart';
import '../models/health_plan.dart';
import '../services/card_reader_service.dart';
import 'stepped_form_sheet.dart';

/// Cadastro de plano de saúde em PASSOS (padrão V4 "jornada"): Qual plano →
/// Carteirinha → Cobertura. Atalhos de preenchimento (chips de operadoras e
/// rascunho da foto da carteirinha) preservados; só o nome é obrigatório.
class HealthPlanFormDialog extends StatefulWidget {
  const HealthPlanFormDialog({
    super.key,
    this.healthPlan,
    this.initialProvider,
    this.draft,
  });

  final HealthPlan? healthPlan;

  final String? initialProvider;

  /// Rascunho de leitura automática (foto da carteirinha): preenche o
  /// formulário de um plano NOVO — nunca usado quando [healthPlan] existe.
  final CardReadResult? draft;

  @override
  State<HealthPlanFormDialog> createState() => _HealthPlanFormDialogState();
}

class _HealthPlanFormDialogState extends State<HealthPlanFormDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _providerController;
  late final TextEditingController _cardNumberController;
  late final TextEditingController _groupNumberController;
  late final TextEditingController _beneficiaryCodeController;
  late final TextEditingController _validityController;
  late final TextEditingController _notesController;

  String? _selectedCoverageType;
  final Set<String> _selectedSpecialties = {};

  /// Aviso de origem quando o formulário abre preenchido pela foto.
  String? _draftMessage;

  bool get _isEditing => widget.healthPlan != null;

  @override
  void initState() {
    super.initState();
    final plan = widget.healthPlan;
    if (plan != null) {
      _nameController = TextEditingController(text: plan.name);
      _providerController = TextEditingController(text: plan.provider);
      _cardNumberController = TextEditingController(
        text: plan.cardNumber ?? '',
      );
      _groupNumberController = TextEditingController(
        text: plan.groupNumber ?? '',
      );
      _beneficiaryCodeController = TextEditingController(
        text: plan.beneficiaryCode ?? '',
      );
      _validityController = TextEditingController(text: plan.validity ?? '');
      _notesController = TextEditingController(text: plan.notes ?? '');
      _selectedCoverageType = plan.coverageType;
      _selectedSpecialties.addAll(plan.specialties);
      return;
    }

    _nameController = TextEditingController();
    _providerController = TextEditingController(
      text: widget.initialProvider ?? '',
    );
    _cardNumberController = TextEditingController();
    _groupNumberController = TextEditingController();
    _beneficiaryCodeController = TextEditingController();
    _validityController = TextEditingController();
    _notesController = TextEditingController();

    // Rascunho da foto da carteirinha: preenche um plano NOVO e avisa que é
    // confiança por conferência — preencher não é salvar.
    final draft = widget.draft;
    if (draft != null) {
      var touched = false;
      if (draft.name.trim().isNotEmpty) {
        _nameController.text = draft.name;
        touched = true;
      }
      if (draft.provider.trim().isNotEmpty) {
        _providerController.text = draft.provider;
        touched = true;
      }
      if ((draft.cardNumber ?? '').trim().isNotEmpty) {
        _cardNumberController.text = draft.cardNumber!;
        touched = true;
      }
      if ((draft.groupNumber ?? '').trim().isNotEmpty) {
        _groupNumberController.text = draft.groupNumber!;
        touched = true;
      }
      if ((draft.beneficiaryCode ?? '').trim().isNotEmpty) {
        _beneficiaryCodeController.text = draft.beneficiaryCode!;
        touched = true;
      }
      if ((draft.validity ?? '').trim().isNotEmpty) {
        _validityController.text = draft.validity!;
        touched = true;
      }
      if (kCoverageTypes.contains(draft.coverageType)) {
        _selectedCoverageType = draft.coverageType;
        touched = true;
      }
      if ((draft.notes ?? '').trim().isNotEmpty) {
        _notesController.text = draft.notes!;
        touched = true;
      }
      if (touched) {
        _draftMessage =
            'Preenchido pela foto do cartão — confira antes de salvar.';
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _providerController.dispose();
    _cardNumberController.dispose();
    _groupNumberController.dispose();
    _beneficiaryCodeController.dispose();
    _validityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ── Operadoras conhecidas ─────────────────────────────────────────────────

  bool _hasProvider(String provider) =>
      _providerController.text.trim().toLowerCase() == provider.toLowerCase();

  /// Um toque preenche a operadora (e o nome, se estiver vazio), outro
  /// desmarca — sem digitar para o caso comum (Unimed, Amil, Bradesco...).
  void _toggleProvider(String provider) {
    setState(() {
      if (_hasProvider(provider)) {
        _providerController.clear();
        return;
      }
      _providerController.text = provider;
      if (_nameController.text.trim().isEmpty) {
        _nameController.text = provider;
      }
    });
  }

  // ── Validação e salvamento ────────────────────────────────────────────────

  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Informe o nome do plano';
    }
    return null;
  }

  static String? _optional(String value) =>
      value.trim().isEmpty ? null : value.trim();

  void _save() {
    // Os passos validam por trecho; nome é o único obrigatório.
    if (_validateName(_nameController.text) != null) return;

    final now = DateTime.now().toUtc().toIso8601String();
    final name = _nameController.text.trim();
    // Sem operadora informada, o nome do plano serve de operadora — o
    // cadastro nunca trava por um campo que o usuário não tem em mãos.
    final provider = _optional(_providerController.text) ?? name;

    final plan = HealthPlan(
      id: widget.healthPlan?.id ?? const Uuid().v4(),
      name: name,
      provider: provider,
      cardNumber: _optional(_cardNumberController.text),
      groupNumber: _optional(_groupNumberController.text),
      beneficiaryCode: _optional(_beneficiaryCodeController.text),
      validity: _optional(_validityController.text),
      coverageType: _selectedCoverageType,
      specialties: _selectedSpecialties.toList(),
      notes: _optional(_notesController.text),
      createdAt: widget.healthPlan?.createdAt ?? now,
      updatedAt: now,
    );

    Navigator.of(context).pop(plan);
  }

  InputDecoration _decoration(String label, {String? hint}) {
    return InputDecoration(labelText: label, hintText: hint);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SteppedFormShell(
      title: _isEditing ? 'Editar plano' : 'Novo plano de saúde',
      intro:
          'Só o nome do plano é obrigatório. O restante pode ser completado '
          'depois.',
      saveLabel: _isEditing ? 'Salvar' : 'Cadastrar',
      progressMessage: _draftMessage,
      steps: [
        // ── Passo 1: qual plano ────────────────────────────────────────────
        FormStep(
          title: 'Qual plano',
          validate: () => _validateName(_nameController.text),
          children: [
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofocus: !_isEditing,
              decoration: _decoration(
                'Nome do plano',
                hint: 'Ex.: Unimed Nacional',
              ),
              validator: _validateName,
            ),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: 4,
                children: [
                  // "Outros" não é operadora — é a ausência dela.
                  for (final provider in kCommonProviders.where(
                    (p) => p != 'Outros',
                  ))
                    FilterChip(
                      label: Text(provider),
                      selected: _hasProvider(provider),
                      onSelected: (_) => _toggleProvider(provider),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _providerController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: _decoration(
                'Operadora',
                hint: 'Ex.: Unimed, Bradesco Saúde',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
        // ── Passo 2: carteirinha ───────────────────────────────────────────
        FormStep(
          title: 'Carteirinha',
          children: [
            TextFormField(
              controller: _cardNumberController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                _CardNumberFormatter(),
              ],
              decoration: _decoration(
                'Número do cartão',
                hint: '0000 0000 0000 0000',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _groupNumberController,
                    keyboardType: TextInputType.number,
                    decoration: _decoration('Nº do grupo', hint: '001234'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextFormField(
                    controller: _beneficiaryCodeController,
                    keyboardType: TextInputType.number,
                    decoration: _decoration(
                      'Cód. beneficiário',
                      hint: '000123456',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _validityController,
              keyboardType: TextInputType.datetime,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                _ValidityFormatter(),
              ],
              decoration: _decoration('Validade', hint: 'MM/AAAA'),
            ),
          ],
        ),
        // ── Passo 3: cobertura ─────────────────────────────────────────────
        FormStep(
          title: 'Cobertura',
          children: [
            DropdownButtonFormField<String>(
              initialValue: _selectedCoverageType,
              isExpanded: true,
              hint: const Text('Selecione'),
              decoration: _decoration('Tipo de cobertura'),
              items: [
                for (final type in kCoverageTypes)
                  DropdownMenuItem(value: type, child: Text(type)),
              ],
              onChanged:
                  (value) => setState(() => _selectedCoverageType = value),
            ),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Especialidades cobertas',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: 4,
                children: [
                  for (final specialty in kMedicalSpecialties)
                    FilterChip(
                      label: Text(specialty),
                      selected: _selectedSpecialties.contains(specialty),
                      onSelected:
                          (selected) => setState(() {
                            selected
                                ? _selectedSpecialties.add(specialty)
                                : _selectedSpecialties.remove(specialty);
                          }),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _notesController,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: _decoration(
                'Observações (opcional)',
                hint: 'Ex.: plano empresarial, restrições',
              ),
            ),
          ],
        ),
      ],
      onSave: _save,
    );
  }
}

/// Formats card number with spaces (0000 0000 0000 0000)
class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(' ', '');
    final buffer = StringBuffer();

    for (var i = 0; i < text.length && i < 16; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(text[i]);
    }

    return TextEditingValue(
      text: buffer.toString(),
      selection: TextSelection.collapsed(offset: buffer.length),
    );
  }
}

/// Formats validity as MM/AAAA
class _ValidityFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll('/', '');
    final buffer = StringBuffer();

    for (var i = 0; i < text.length && i < 6; i++) {
      if (i == 2) buffer.write('/');
      buffer.write(text[i]);
    }

    return TextEditingValue(
      text: buffer.toString(),
      selection: TextSelection.collapsed(offset: buffer.length),
    );
  }
}
