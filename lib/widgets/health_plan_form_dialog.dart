import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../models/health_plan.dart';

/// Dialog form for creating or editing a HealthPlan.
/// Provides quick selection for common providers and coverage types.
class HealthPlanFormDialog extends StatefulWidget {
  const HealthPlanFormDialog({
    super.key,
    this.healthPlan,
    this.initialProvider,
  });

  final HealthPlan? healthPlan;
  final String? initialProvider;

  @override
  State<HealthPlanFormDialog> createState() => _HealthPlanFormDialogState();
}

class _HealthPlanFormDialogState extends State<HealthPlanFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _providerController;
  late final TextEditingController _cardNumberController;
  late final TextEditingController _groupNumberController;
  late final TextEditingController _beneficiaryCodeController;
  late final TextEditingController _validityController;
  late final TextEditingController _notesController;

  String? _selectedCoverageType;
  final Set<String> _selectedSpecialties = {};

  bool get isEditing => widget.healthPlan != null;

  @override
  void initState() {
    super.initState();
    final plan = widget.healthPlan;
    _nameController = TextEditingController(text: plan?.name ?? '');
    _providerController = TextEditingController(
        text: plan?.provider ?? widget.initialProvider ?? '');
    _cardNumberController = TextEditingController(text: plan?.cardNumber ?? '');
    _groupNumberController =
        TextEditingController(text: plan?.groupNumber ?? '');
    _beneficiaryCodeController =
        TextEditingController(text: plan?.beneficiaryCode ?? '');
    _validityController = TextEditingController(text: plan?.validity ?? '');
    _notesController = TextEditingController(text: plan?.notes ?? '');
    _selectedCoverageType = plan?.coverageType;
    _selectedSpecialties.addAll(plan?.specialties ?? []);
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

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final now = DateTime.now().toUtc().toIso8601String();
    final plan = HealthPlan(
      id: widget.healthPlan?.id ?? const Uuid().v4(),
      name: _nameController.text.trim(),
      provider: _providerController.text.trim(),
      cardNumber: _cardNumberController.text.trim().isNotEmpty
          ? _cardNumberController.text.trim()
          : null,
      groupNumber: _groupNumberController.text.trim().isNotEmpty
          ? _groupNumberController.text.trim()
          : null,
      beneficiaryCode: _beneficiaryCodeController.text.trim().isNotEmpty
          ? _beneficiaryCodeController.text.trim()
          : null,
      validity: _validityController.text.trim().isNotEmpty
          ? _validityController.text.trim()
          : null,
      coverageType: _selectedCoverageType,
      specialties: _selectedSpecialties.toList(),
      notes: _notesController.text.trim().isNotEmpty
          ? _notesController.text.trim()
          : null,
      createdAt: widget.healthPlan?.createdAt ?? now,
      updatedAt: now,
    );

    Navigator.of(context).pop(plan);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(isEditing ? 'Editar Plano' : 'Novo Plano de Saúde'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Name field (required)
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nome do Plano *',
                  hintText: 'Ex: Unimed, Bradesco Saúde',
                  prefixIcon: Icon(Icons.health_and_safety_outlined),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Informe o nome do plano';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Provider field with quick selection
              TextFormField(
                controller: _providerController,
                decoration: InputDecoration(
                  labelText: 'Operadora *',
                  hintText: 'Ex: Unimed, Bradesco',
                  prefixIcon: const Icon(Icons.business_outlined),
                  suffixIcon: PopupMenuButton<String>(
                    icon: const Icon(Icons.arrow_drop_down),
                    tooltip: 'Selecionar operadora',
                    onSelected: (value) {
                      _providerController.text = value;
                      if (_nameController.text.isEmpty) {
                        _nameController.text = value;
                      }
                    },
                    itemBuilder: (context) => kCommonProviders
                        .map((provider) => PopupMenuItem(
                              value: provider,
                              child: Text(provider),
                            ))
                        .toList(),
                  ),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Informe a operadora';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Card Number (optional)
              TextFormField(
                controller: _cardNumberController,
                decoration: const InputDecoration(
                  labelText: 'Número do Cartão',
                  hintText: 'Ex: 0000 0000 0000 0000',
                  prefixIcon: Icon(Icons.credit_card_outlined),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  _CardNumberFormatter(),
                ],
              ),
              const SizedBox(height: 16),

              // Group Number and Beneficiary Code (side by side)
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _groupNumberController,
                      decoration: const InputDecoration(
                        labelText: 'Nº do Grupo',
                        hintText: 'Ex: 001234',
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _beneficiaryCodeController,
                      decoration: const InputDecoration(
                        labelText: 'Cód. Beneficiário',
                        hintText: 'Ex: 000123456',
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Validity (MM/YY)
              TextFormField(
                controller: _validityController,
                decoration: const InputDecoration(
                  labelText: 'Validade',
                  hintText: 'MM/AAAA',
                  prefixIcon: Icon(Icons.calendar_today_outlined),
                ),
                keyboardType: TextInputType.datetime,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  _ValidityFormatter(),
                ],
              ),
              const SizedBox(height: 16),

              // Coverage Type (dropdown)
              DropdownButtonFormField<String>(
                initialValue: _selectedCoverageType,
                decoration: const InputDecoration(
                  labelText: 'Tipo de Cobertura',
                  prefixIcon: Icon(Icons.shield_outlined),
                ),
                items: kCoverageTypes
                    .map((type) => DropdownMenuItem(
                          value: type,
                          child: Text(type),
                        ))
                    .toList(),
                onChanged: (value) {
                  setState(() => _selectedCoverageType = value);
                },
              ),
              const SizedBox(height: 16),

              // Specialties (multi-select chips)
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Especialidades Cobertas',
                  prefixIcon: Icon(Icons.medical_services_outlined),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: kMedicalSpecialties.map((specialty) {
                    final isSelected = _selectedSpecialties.contains(specialty);
                    return FilterChip(
                      label: Text(specialty),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedSpecialties.add(specialty);
                          } else {
                            _selectedSpecialties.remove(specialty);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),

              // Notes (optional)
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Observações',
                  hintText: 'Ex: Plano empresarial, restrições...',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(isEditing ? 'Salvar' : 'Adicionar'),
        ),
      ],
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
