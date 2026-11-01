import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/medicine_data.dart';
import '../models/medicine.dart';
import '../models/treatment.dart';
import '../models/treatment_draft.dart';
import '../screens/barcode_scan_screen.dart';
import '../services/dose_schedule_presets.dart';

class TreatmentFormDialog extends StatefulWidget {
  const TreatmentFormDialog({super.key, this.initialTreatment, this.draft});

  final Treatment? initialTreatment;

  /// Rascunho de leitura automática (receita por OCR): preenche o formulário
  /// de um tratamento NOVO — nunca usado quando [initialTreatment] existe.
  final TreatmentDraft? draft;

  @override
  State<TreatmentFormDialog> createState() => _TreatmentFormDialogState();
}

class _TreatmentFormDialogState extends State<TreatmentFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _dosageController = TextEditingController();
  final _presentationController = TextEditingController();
  final _instructionsController = TextEditingController();
  final _stockController = TextEditingController();
  final _thresholdController = TextEditingController();
  final List<DoseTime> _doseTimes = [];

  late final Future<List<Medicine>> _medicineCatalogFuture;
  String _medicineQuery = '';
  TreatmentFrequency _frequency = TreatmentFrequency.daily;

  /// Dias escolhidos quando a frequência é semanal (DateTime.weekday:
  /// 1 = segunda … 7 = domingo). Sem dia, sem dose — a validação exige um.
  final Set<int> _weekdays = {};
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;

  /// Rótulos curtos dos dias para os chips — mesma ordem de DateTime.weekday.
  static const List<String> _weekdayLabels = [
    'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom',
  ];

  bool get _isEditing => widget.initialTreatment != null;

  @override
  void initState() {
    super.initState();
    _medicineCatalogFuture = MedicineData.load();
    final treatment = widget.initialTreatment;
    if (treatment == null) {
      // Rascunho de leitura automática: preenche e deixa o usuário conferir.
      final draft = widget.draft;
      if (draft != null) {
        _nameController.text = draft.name;
        _dosageController.text = draft.dosage;
        _presentationController.text = draft.presentation;
        _instructionsController.text = draft.instructions;
        if (draft.doseTimes.isNotEmpty) {
          _doseTimes.addAll(draft.doseTimes);
        } else {
          _doseTimes.add(const DoseTime(hour: 8, minute: 0));
        }
        _endDate = draft.endDate;
        // Frequência lida da receita ("dia sim, dia não" vira
        // "Dia sim, dia não"): pré-selecionada, nunca escondida do usuário.
        if (draft.frequency != null) _frequency = draft.frequency!;
        // "Aos sábados" na receita vem junto: os dias abrem marcados.
        if (draft.frequency == TreatmentFrequency.weekly) {
          _weekdays.addAll(draft.weekdays);
        }
        return;
      }
      _doseTimes.add(const DoseTime(hour: 8, minute: 0));
      return;
    }
    _nameController.text = treatment.name;
    _dosageController.text = treatment.dosage;
    _presentationController.text = treatment.presentation;
    _instructionsController.text = treatment.instructions;
    if (treatment.stock != null) _stockController.text = '${treatment.stock}';
    if (treatment.refillThreshold != null) {
      _thresholdController.text = '${treatment.refillThreshold}';
    }
    _doseTimes.addAll(treatment.doseTimes);
    _frequency = treatment.frequency;
    _weekdays.addAll(treatment.weekdays);
    _startDate = treatment.startDate;
    _endDate = treatment.endDate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dosageController.dispose();
    _presentationController.dispose();
    _instructionsController.dispose();
    _stockController.dispose();
    _thresholdController.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate,
      firstDate: _startDate,
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  Future<void> _addTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 8, minute: 0),
    );
    if (picked == null) return;
    _addDoseTime(DoseTime(hour: picked.hour, minute: picked.minute));
  }

  void _addDoseTime(DoseTime time) {
    if (_doseTimes.any(
        (item) => item.minutesSinceMidnight == time.minutesSinceMidnight)) {
      return;
    }
    setState(() {
      _doseTimes.add(time);
      _doseTimes.sort((first, second) =>
          first.minutesSinceMidnight.compareTo(second.minutesSinceMidnight));
    });
  }

  bool _hasDoseTime(DoseTime time) =>
      _doseTimes.any((item) => item.minutesSinceMidnight == time.minutesSinceMidnight);

  /// Um toque nos presets de rotina marca, outro desmarca — sem passar pelo
  /// time picker para o caso comum (café/almoço/janta/dormir).
  void _toggleDoseTime(DoseTime time) {
    if (_hasDoseTime(time)) {
      setState(() => _doseTimes.removeWhere(
          (item) => item.minutesSinceMidnight == time.minutesSinceMidnight));
      return;
    }
    _addDoseTime(time);
  }

  /// "A cada Xh" é âncora na primeira dose (convenção médica), não no
  /// relógio: pergunta a 1ª toma e gera o dia inteiro de uma vez.
  Future<void> _applyInterval(int intervalHours) async {
    final anchor = _doseTimes.isNotEmpty
        ? TimeOfDay(
            hour: _doseTimes.first.hour, minute: _doseTimes.first.minute)
        : const TimeOfDay(hour: 8, minute: 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: anchor,
      helpText: 'Horário da primeira dose',
    );
    if (picked == null) return;
    final firstDose = DoseTime(hour: picked.hour, minute: picked.minute);
    setState(() {
      _doseTimes
        ..clear()
        ..addAll(
          DoseSchedulePresets.everyIntervalHours(
            firstDose: firstDose,
            intervalHours: intervalHours,
          ),
        );
      _doseTimes.sort((first, second) =>
          first.minutesSinceMidnight.compareTo(second.minutesSinceMidnight));
    });
  }

  /// Lê o EAN com a câmera e preenche o que o catálogo local souber. O
  /// usuário sempre confere: preencher não é salvar.
  Future<void> _scanBarcode() async {
    final ean = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScanScreen()),
    );
    if (ean == null || !mounted) return;
    final match = await MedicineData.findByEan(ean);
    if (!mounted) return;
    if (match == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Código $ean não está no catálogo local. Digite o nome do remédio.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _nameController.text = match.name;
      final dosage =
          match.dosage.isNotEmpty ? match.dosage : match.listedDosage;
      if (dosage.isNotEmpty) _dosageController.text = dosage;
      if (match.presentation.isNotEmpty) {
        _presentationController.text = match.presentation;
      }
      _medicineQuery = '';
    });
  }

  void _selectMedicine(Medicine medicine) {
    setState(() {
      _nameController.text = medicine.name;
      _dosageController.text =
          medicine.dosage.isNotEmpty ? medicine.dosage : medicine.listedDosage;
      _presentationController.text = medicine.presentation;
      _medicineQuery = '';
    });
  }

  InputDecoration _medicineInputDecoration() {
    return InputDecoration(
      labelText: 'Buscar medicamento',
      hintText: 'Nome comercial ou princípio ativo',
      prefixIcon: const Icon(Icons.search),
      // Scanner de barras só existe onde existe câmera (APK).
      suffixIcon: kIsWeb
          ? null
          : IconButton(
              tooltip: 'Escanear código de barras',
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: _scanBarcode,
            ),
    );
  }

  Widget _buildMedicineSearch() {
    return FutureBuilder<List<Medicine>>(
      future: _medicineCatalogFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return TextFormField(
            controller: _nameController,
            decoration: _medicineInputDecoration(),
            validator: _validateMedicineName,
          );
        }

        final medicines = snapshot.data!;
        final results = MedicineData.search(medicines, _medicineQuery);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: _medicineInputDecoration(),
              validator: _validateMedicineName,
              onChanged: (value) => setState(() => _medicineQuery = value),
            ),
            if (_medicineQuery.isNotEmpty && results.isNotEmpty) ...[
              const SizedBox(height: 6),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    primary: false,
                    shrinkWrap: true,
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      final medicine = results[index];
                      final details = [
                        if (medicine.activeIngredient.isNotEmpty)
                          medicine.activeIngredient,
                        if (medicine.presentation.isNotEmpty)
                          medicine.presentation,
                        if (medicine.requiresManualDetails)
                          'Confira e informe a apresentação',
                      ].join(' · ');
                      return ListTile(
                        dense: true,
                        title: Text(
                          medicine.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          details,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _selectMedicine(medicine),
                      );
                    },
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  String? _validateMedicineName(String? value) =>
      value == null || value.trim().isEmpty
          ? 'Informe o nome do remédio'
          : null;

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false) || _doseTimes.isEmpty) {
      if (_doseTimes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Adicione pelo menos um horário.')),
        );
      }
      return;
    }
    // Semanal sem dia não tem quando agendar: a escolha é do usuário, não
    // nossa — "1x por semana" não diz qual dia.
    if (_frequency == TreatmentFrequency.weekly && _weekdays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escolha pelo menos um dia da semana.')),
      );
      return;
    }

    int? parseOptionalInt(String value) =>
        value.trim().isEmpty ? null : int.tryParse(value.trim());

    final existing = widget.initialTreatment;
    final treatment = Treatment(
      id: existing?.id ?? const Uuid().v4(),
      name: _nameController.text.trim(),
      dosage: _dosageController.text.trim(),
      presentation: _presentationController.text.trim(),
      instructions: _instructionsController.text.trim(),
      startDate: _startDate,
      endDate: _endDate,
      frequency: _frequency,
      doseTimes: List.unmodifiable(_doseTimes),
      weekdays: _frequency == TreatmentFrequency.weekly
          ? List.unmodifiable(_weekdays.toList()..sort())
          : const [],
      stock: parseOptionalInt(_stockController.text),
      refillThreshold: parseOptionalInt(_thresholdController.text),
      isArchived: existing?.isArchived ?? false,
    );
    Navigator.of(context).pop(treatment);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Editar tratamento' : 'Novo tratamento'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildMedicineSearch(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _dosageController,
                        decoration: const InputDecoration(labelText: 'Dosagem'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _presentationController,
                        decoration:
                            const InputDecoration(labelText: 'Apresentação'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<TreatmentFrequency>(
                  initialValue: _frequency,
                  decoration: const InputDecoration(labelText: 'Frequência'),
                  items: const [
                    DropdownMenuItem(
                      value: TreatmentFrequency.daily,
                      child: Text('Todos os dias'),
                    ),
                    DropdownMenuItem(
                      value: TreatmentFrequency.weekdays,
                      child: Text('Dias úteis'),
                    ),
                    DropdownMenuItem(
                      value: TreatmentFrequency.everyOtherDay,
                      child: Text('Dia sim, dia não'),
                    ),
                    DropdownMenuItem(
                      value: TreatmentFrequency.weekly,
                      child: Text('Semanal'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _frequency = value);
                  },
                ),
                // Semanal: "1x por semana" não diz qual dia — os chips são
                // onde o usuário escolhe (a receita pode ter deixado marcado).
                if (_frequency == TreatmentFrequency.weekly) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (var day = 1; day <= 7; day++)
                          FilterChip(
                            label: Text(_weekdayLabels[day - 1]),
                            selected: _weekdays.contains(day),
                            onSelected: (selected) => setState(
                              () => selected
                                  ? _weekdays.add(day)
                                  : _weekdays.remove(day),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Horários',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final intervalHours in const [8, 12, 24])
                        ActionChip(
                          label: Text('A cada ${intervalHours}h'),
                          onPressed: () => _applyInterval(intervalHours),
                        ),
                      for (final preset in DoseSchedulePresets.routinePresets)
                        _PresetChip(
                          label: preset.label,
                          active: _hasDoseTime(preset.time),
                          onPressed: () => _toggleDoseTime(preset.time),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      ..._doseTimes.map(
                        (time) => Chip(
                          label: Text(
                            '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                          ),
                          onDeleted: () =>
                              setState(() => _doseTimes.remove(time)),
                        ),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 18),
                        label: const Text('Adicionar'),
                        onPressed: _addTime,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _buildUpcomingPreview(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickStartDate,
                        icon: const Icon(Icons.event_outlined),
                        label: Text(
                          'Início\n${_startDate.day.toString().padLeft(2, '0')}/${_startDate.month.toString().padLeft(2, '0')}',
                          textAlign: TextAlign.left,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickEndDate,
                        icon: const Icon(Icons.event_available_outlined),
                        label: Text(
                          _endDate == null
                              ? 'Sem término'
                              : 'Fim\n${_endDate!.day.toString().padLeft(2, '0')}/${_endDate!.month.toString().padLeft(2, '0')}',
                          textAlign: TextAlign.left,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _stockController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Estoque',
                          suffixText: 'un.',
                        ),
                        validator: (value) => _validNumber(value),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _thresholdController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Avisar com',
                          suffixText: 'un.',
                        ),
                        validator: (value) => _validNumber(value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _instructionsController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Observações (opcional)',
                    hintText: 'Ex.: após o almoço',
                  ),
                ),
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
        FilledButton(onPressed: _save, child: const Text('Salvar')),
      ],
    );
  }

  /// Mostra as próximas doses reais antes de salvar — o feedback que tira a
  /// dúvida de "a cada 8h a partir de quando?" e de frequências especiais.
  Widget _buildUpcomingPreview() {
    if (_doseTimes.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();
    // O Treatment de regra só existe para reusar isScheduledOn (fonte única
    // de verdade da frequência). Os campos obrigatórios não vazios são
    // placeholders: nada disto é exibido além da regra de frequência.
    final rule = Treatment(
      id: 'preview',
      name: 'prévia',
      dosage: '1x',
      presentation: 'un',
      instructions: '',
      startDate: _startDate,
      endDate: _endDate,
      frequency: _frequency,
      doseTimes: List.unmodifiable(_doseTimes),
      weekdays: _frequency == TreatmentFrequency.weekly
          ? List.unmodifiable(_weekdays.toList())
          : const [],
      stock: null,
      refillThreshold: null,
    );
    final instants = DoseSchedulePresets.upcomingInstants(
      doseTimes: _doseTimes,
      isScheduledOn: rule.isScheduledOn,
      now: now,
    );
    if (instants.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        'Próximas doses: ${DoseSchedulePresets.formatInstants(instants, now)}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  String? _validNumber(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    if (int.tryParse(value.trim()) == null) return 'Use um número inteiro';
    return null;
  }
}

/// Chip de horário predefinido ("Café 08:00"). Ação e estado no mesmo
/// componente: quando o horário já está na lista, o chip fica PREENCHIDO
/// com o azul de ação e troca o + por um check — seleção impossível de
/// não ver (antes só o ícone mudava e o chip parecia sempre desligado).
class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.active,
    required this.onPressed,
  });

  final String label;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ActionChip(
      avatar: Icon(
        active ? Icons.check_rounded : Icons.add,
        size: 18,
        color: active ? colorScheme.onPrimary : colorScheme.primary,
      ),
      label: Text(label),
      labelStyle: TextStyle(
        fontFamily: 'Nunito',
        fontWeight: FontWeight.w700,
        color: active ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
      ),
      backgroundColor: active ? colorScheme.primary : null,
      side: active
          ? BorderSide.none
          : BorderSide(color: colorScheme.outlineVariant.withValues(alpha: .5)),
      onPressed: onPressed,
    );
  }
}
