import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../data/medical_specialties.dart';
import '../models/doctor.dart';
import '../services/cep_lookup_service.dart';
import 'br_input_formatters.dart';

class DoctorFormDialog extends StatefulWidget {
  const DoctorFormDialog({
    super.key,
    this.initialDoctor,
    this.knownSpecialties = const [],
    this.cepLookup,
  });

  final Doctor? initialDoctor;
  final Iterable<String> knownSpecialties;
  final CepLookupService? cepLookup;

  @override
  State<DoctorFormDialog> createState() => _DoctorFormDialogState();
}

class _DoctorFormDialogState extends State<DoctorFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final CepLookupService _cepLookup;
  late final TextEditingController _nameController;
  late final TextEditingController _specialtyController;
  late final TextEditingController _crmController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _clinicController;
  late final TextEditingController _streetController;
  late final TextEditingController _numberController;
  late final TextEditingController _complementController;
  late final TextEditingController _neighborhoodController;
  late final TextEditingController _cityController;
  late final TextEditingController _postalCodeController;
  late final TextEditingController _healthPlansController;
  late final TextEditingController _notesController;

  String? _crmState;
  String? _addressState;
  bool _showAddress = false;
  bool _showExtras = false;
  bool _lookingUpCep = false;
  String? _cepMessage;
  String? _lastLookedCep;

  bool get _isEditing => widget.initialDoctor != null;

  @override
  void initState() {
    super.initState();
    _cepLookup = widget.cepLookup ?? CepLookupService();
    final doctor = widget.initialDoctor;
    _nameController = TextEditingController(text: doctor?.name ?? '');
    _specialtyController = TextEditingController(text: doctor?.specialty ?? '');
    _crmController = TextEditingController(text: doctor?.crm ?? '');
    _phoneController = TextEditingController(text: doctor?.phone ?? '');
    _emailController = TextEditingController(text: doctor?.email ?? '');
    _clinicController = TextEditingController(text: doctor?.clinic ?? '');
    _streetController = TextEditingController(text: doctor?.street ?? '');
    _numberController = TextEditingController(text: doctor?.number ?? '');
    _complementController = TextEditingController(text: doctor?.complement ?? '');
    _neighborhoodController =
        TextEditingController(text: doctor?.neighborhood ?? '');
    _cityController = TextEditingController(text: doctor?.city ?? '');
    _postalCodeController = TextEditingController(text: doctor?.postalCode ?? '');
    _healthPlansController =
        TextEditingController(text: doctor?.healthPlans ?? '');
    _notesController = TextEditingController(text: doctor?.notes ?? '');
    _crmState = _normalizedUf(doctor?.crmState);
    _addressState = _normalizedUf(doctor?.state);
    _showAddress = doctor != null &&
        [
          doctor.street,
          doctor.number,
          doctor.neighborhood,
          doctor.city,
          doctor.state,
          doctor.postalCode,
        ].any((value) => value.trim().isNotEmpty);
    _showExtras = doctor != null &&
        [doctor.email, doctor.healthPlans, doctor.notes]
            .any((value) => value.trim().isNotEmpty);
  }

  String? _normalizedUf(String? value) {
    if (value == null) return null;
    final uf = value.trim().toUpperCase();
    return isValidBrazilianUf(uf) ? uf : null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _specialtyController.dispose();
    _crmController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _clinicController.dispose();
    _streetController.dispose();
    _numberController.dispose();
    _complementController.dispose();
    _neighborhoodController.dispose();
    _cityController.dispose();
    _postalCodeController.dispose();
    _healthPlansController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _lookupCep({bool force = false}) async {
    final digits = digitsOnly(_postalCodeController.text);
    if (digits.length != 8) return;
    if (!force && digits == _lastLookedCep) return;

    setState(() {
      _lookingUpCep = true;
      _cepMessage = null;
    });

    final address = await _cepLookup.lookup(digits);
    if (!mounted) return;

    setState(() {
      _lookingUpCep = false;
      _lastLookedCep = digits;
      if (address == null) {
        _cepMessage = 'CEP não encontrado. Preencha o endereço.';
        _showAddress = true;
        return;
      }

      if (address.street.isNotEmpty) _streetController.text = address.street;
      if (address.neighborhood.isNotEmpty) {
        _neighborhoodController.text = address.neighborhood;
      }
      if (address.city.isNotEmpty) _cityController.text = address.city;
      if (address.uf.isNotEmpty) _addressState = address.uf;
      if (address.complement.isNotEmpty && _complementController.text.isEmpty) {
        _complementController.text = address.complement;
      }
      _showAddress = true;
      _cepMessage = 'Endereço preenchido pelo CEP.';
    });
  }

  Future<void> _verifyOnCfm() async {
    final searchTerms = [
      if (_nameController.text.trim().isNotEmpty)
        'Nome: ${_nameController.text.trim()}',
      if (_crmController.text.trim().isNotEmpty)
        'CRM: ${_crmController.text.trim()}',
      if (_crmState != null) 'UF: $_crmState',
    ].join('\n');
    if (searchTerms.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: searchTerms));
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Nome, CRM e UF copiados. Cole na busca do CFM para conferir.',
        ),
      ),
    );
  }

  void _toggleHealthPlan(String plan) {
    final current = _healthPlansController.text
        .split(RegExp(r'[,;]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    final exists = current.any((item) => item.toLowerCase() == plan.toLowerCase());
    if (exists) {
      current.removeWhere((item) => item.toLowerCase() == plan.toLowerCase());
    } else {
      current.add(plan);
    }
    setState(() => _healthPlansController.text = current.join(', '));
  }

  bool _hasHealthPlan(String plan) {
    return _healthPlansController.text
        .split(RegExp(r'[,;]'))
        .map((item) => item.trim().toLowerCase())
        .contains(plan.toLowerCase());
  }

  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Informe o nome do médico';
    }
    return null;
  }

  String? _validateCrm(String? value) {
    final crm = value?.trim() ?? '';
    if (crm.isEmpty && (_crmState == null || _crmState!.isEmpty)) return null;
    if (crm.isEmpty) return 'Informe o CRM';
    if (!isValidCrmNumber(crm)) return 'CRM deve ter 4 a 7 dígitos';
    if (_crmState == null || _crmState!.isEmpty) return 'Selecione a UF do CRM';
    return null;
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final existing = widget.initialDoctor;
    Navigator.of(context).pop(
      Doctor(
        id: existing?.id ?? const Uuid().v4(),
        name: _nameController.text.trim(),
        specialty: _specialtyController.text.trim(),
        crm: digitsOnly(_crmController.text),
        crmState: (_crmState ?? '').toUpperCase(),
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        clinic: _clinicController.text.trim(),
        street: _streetController.text.trim(),
        number: _numberController.text.trim(),
        complement: _complementController.text.trim(),
        neighborhood: _neighborhoodController.text.trim(),
        city: _cityController.text.trim(),
        state: (_addressState ?? '').toUpperCase(),
        postalCode: _postalCodeController.text.trim(),
        healthPlans: _healthPlansController.text.trim(),
        notes: _notesController.text.trim(),
      ),
    );
  }

  InputDecoration _decoration(String label, {String? hint, Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      suffixIcon: suffix,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(_isEditing ? 'Editar médico' : 'Cadastrar médico'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Só o nome é obrigatório. O restante pode ser completado depois.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  autofocus: !_isEditing,
                  decoration: _decoration(
                    'Nome do médico',
                    hint: 'Ex.: Dra. Ana Silva',
                  ),
                  validator: _validateName,
                ),
                const SizedBox(height: 12),
                Autocomplete<String>(
                  initialValue: TextEditingValue(text: _specialtyController.text),
                  optionsBuilder: (value) {
                    return suggestSpecialties(
                      value.text,
                      extra: widget.knownSpecialties,
                    ).take(8);
                  },
                  onSelected: (value) {
                    _specialtyController.text = value;
                  },
                  fieldViewBuilder:
                      (context, controller, focusNode, onFieldSubmitted) {
                    return TextFormField(
                      controller: controller,
                      focusNode: focusNode,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.next,
                      onChanged: (value) {
                        _specialtyController.text = value;
                      },
                      decoration: _decoration(
                        'Especialidade',
                        hint: 'Comece a digitar, ex.: cardio',
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _crmController,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        inputFormatters: [CrmInputFormatter()],
                        decoration: _decoration('CRM', hint: '123456'),
                        validator: _validateCrm,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        key: const ValueKey('crmStateUf'),
                        initialValue: _crmState,
                        hint: const Text('Selecione'),
                        decoration: _decoration('UF do CRM'),
                        items: [
                          ...kBrazilianStates.map(
                            (uf) => DropdownMenuItem(
                              value: uf,
                              child: Text(uf),
                            ),
                          ),
                        ],
                        onChanged: (value) => setState(() => _crmState = value),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copiar dados para conferir no CFM',
                      onPressed: _verifyOnCfm,
                      icon: const Icon(Icons.verified_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [PhoneInputFormatter()],
                  decoration: _decoration(
                    'Telefone',
                    hint: '(11) 99999-0000',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _clinicController,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: _decoration(
                    'Clínica ou consultório',
                    hint: 'Opcional',
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Endereço',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _postalCodeController,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [CepInputFormatter()],
                  decoration: _decoration(
                    'CEP',
                    hint: '00000-000',
                    suffix: _lookingUpCep
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            tooltip: 'Buscar endereço',
                            onPressed: () => _lookupCep(force: true),
                            icon: const Icon(Icons.search),
                          ),
                  ),
                  onChanged: (_) => _lookupCep(),
                ),
                if (_cepMessage != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _cepMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
                if (!_showAddress) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => setState(() => _showAddress = true),
                    icon: const Icon(Icons.add_location_alt_outlined),
                    label: const Text('Preencher endereço sem CEP'),
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _streetController,
                    textCapitalization: TextCapitalization.words,
                    decoration: _decoration('Rua ou avenida'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _numberController,
                          decoration: _decoration('Número'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _complementController,
                          decoration: _decoration('Complemento'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _neighborhoodController,
                    textCapitalization: TextCapitalization.words,
                    decoration: _decoration('Bairro'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _cityController,
                          textCapitalization: TextCapitalization.words,
                          decoration: _decoration('Cidade'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 108,
                        child: DropdownButtonFormField<String>(
                          key: const ValueKey('addressUf'),
                          initialValue: _addressState,
                          hint: const Text('Selecione'),
                          decoration: _decoration('UF'),
                          items: [
                            ...kBrazilianStates.map(
                              (uf) => DropdownMenuItem(
                                value: uf,
                                child: Text(uf),
                              ),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _addressState = value),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => setState(() => _showExtras = !_showExtras),
                  icon: Icon(
                    _showExtras
                        ? Icons.expand_less
                        : Icons.expand_more,
                  ),
                  label: Text(
                    _showExtras
                        ? 'Ocultar e-mail, convênios e notas'
                        : 'E-mail, convênios e observações',
                  ),
                ),
                if (_showExtras) ...[
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: _decoration('E-mail'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Convênios atendidos',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: kCommonHealthPlans
                        .map(
                          (plan) => FilterChip(
                            label: Text(plan),
                            selected: _hasHealthPlan(plan),
                            onSelected: (_) => _toggleHealthPlan(plan),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _healthPlansController,
                    decoration: _decoration(
                      'Outros convênios',
                      hint: 'Separe por vírgula',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _notesController,
                    maxLines: 3,
                    decoration: _decoration(
                      'Observações',
                      hint: 'Ex.: atende só pela manhã',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(_isEditing ? 'Salvar' : 'Cadastrar'),
        ),
      ],
    );
  }
}
