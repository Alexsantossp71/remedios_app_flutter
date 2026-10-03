import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/medicine_data.dart';
import '../models/medicine.dart';
import '../models/treatment.dart';

class TreatmentFormDialog extends StatefulWidget {
  const TreatmentFormDialog({super.key, this.initialTreatment});

  final Treatment? initialTreatment;

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
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;

  bool get _isEditing => widget.initialTreatment != null;

  @override
  void initState() {
    super.initState();
    _medicineCatalogFuture = MedicineData.load();
    final treatment = widget.initialTreatment;
    if (treatment == null) {
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

  static const _quickPickTimes = [
    DoseTime(hour: 8, minute: 0),
    DoseTime(hour: 12, minute: 0),
    DoseTime(hour: 18, minute: 0),
  ];

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
    return const InputDecoration(
      labelText: 'Buscar medicamento',
      hintText: 'Nome comercial ou princípio ativo',
      prefixIcon: Icon(Icons.search),
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
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _frequency = value);
                  },
                ),
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
                      for (final time in _quickPickTimes)
                        ActionChip(
                          label: Text(
                            '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                          ),
                          onPressed: () => _addDoseTime(time),
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

  String? _validNumber(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    if (int.tryParse(value.trim()) == null) return 'Use um número inteiro';
    return null;
  }
}
