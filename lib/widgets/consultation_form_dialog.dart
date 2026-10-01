import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/consultation.dart';
import '../models/doctor.dart';
import '../providers/doctor_provider.dart';

class ConsultationFormDialog extends StatefulWidget {
  const ConsultationFormDialog({
    super.key,
    this.initialConsultation,
    this.initialDoctorId,
  });

  final Consultation? initialConsultation;
  final String? initialDoctorId;

  @override
  State<ConsultationFormDialog> createState() => _ConsultationFormDialogState();
}

class _ConsultationFormDialogState extends State<ConsultationFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;

  String? _selectedDoctorId;
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  String _status = ConsultationStatus.scheduled;
  DateTime? _returnDate;
  bool _hasReturn = false;

  bool get _isEditing => widget.initialConsultation != null;

  @override
  void initState() {
    super.initState();
    final consultation = widget.initialConsultation;
    _titleController = TextEditingController(text: consultation?.title ?? '');
    _notesController = TextEditingController(text: consultation?.notes ?? '');
    _selectedDoctorId = consultation?.doctorId ?? widget.initialDoctorId;

    if (consultation != null) {
      _selectedDate = consultation.date;
      _selectedTime = TimeOfDay(
        hour: consultation.date.hour,
        minute: consultation.date.minute,
      );
      _status = consultation.status;
      _returnDate = consultation.returnDate;
      _hasReturn = consultation.returnDate != null;
    } else {
      _selectedDate = DateTime.now().add(const Duration(days: 1));
      _selectedTime = const TimeOfDay(hour: 9, minute: 0);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  Future<void> _pickReturnDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _returnDate ?? _selectedDate.add(const Duration(days: 30)),
      firstDate: _selectedDate,
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _returnDate = picked);
    }
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedDoctorId == null || _selectedDoctorId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione um médico para a consulta.')),
      );
      return;
    }

    final consultationDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    final existing = widget.initialConsultation;
    final result = Consultation(
      id: existing?.id ?? const Uuid().v4(),
      doctorId: _selectedDoctorId!,
      date: consultationDateTime,
      title: _titleController.text.trim(),
      notes: _notesController.text.trim(),
      status: _status,
      returnDate: _hasReturn ? _returnDate : null,
    );

    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final doctorProvider = context.watch<DoctorProvider>();
    final doctors = doctorProvider.doctors;

    final dateFormat = DateFormat('dd/MM/yyyy', 'pt_BR');

    return AlertDialog(
      title: Text(_isEditing ? 'Editar consulta' : 'Agendar consulta'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (doctors.isEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: theme.colorScheme.error),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Nenhum médico cadastrado. Cadastre um médico antes de agendar.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                DropdownButtonFormField<String>(
                  initialValue: _selectedDoctorId != null &&
                          doctors.any((d) => d.id == _selectedDoctorId)
                      ? _selectedDoctorId
                      : (doctors.isNotEmpty ? doctors.first.id : null),
                  decoration: const InputDecoration(
                    labelText: 'Médico',
                    prefixIcon: Icon(Icons.medical_services_outlined),
                  ),
                  items: doctors.map((Doctor doctor) {
                    final subtitle = [
                      doctor.specialty,
                      if (doctor.crm.isNotEmpty) 'CRM ${doctor.crm}'
                    ].where((s) => s.isNotEmpty).join(' · ');

                    return DropdownMenuItem<String>(
                      value: doctor.id,
                      child: Text(
                        subtitle.isEmpty
                            ? doctor.name
                            : '${doctor.name} ($subtitle)',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => _selectedDoctorId = value);
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Selecione um médico';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _titleController,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Motivo / Especialidade',
                    hintText: 'Ex.: Retorno, Rotina, Exames...',
                    prefixIcon: Icon(Icons.edit_note_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _pickDate,
                        borderRadius: BorderRadius.circular(16),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Data',
                            prefixIcon: Icon(Icons.calendar_today_outlined),
                          ),
                          child: Text(
                            dateFormat.format(_selectedDate),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: _pickTime,
                        borderRadius: BorderRadius.circular(16),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Horário',
                            prefixIcon: Icon(Icons.access_time_outlined),
                          ),
                          child: Text(
                            _selectedTime.format(context),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_isEditing) ...[
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _status,
                    decoration: const InputDecoration(
                      labelText: 'Status da consulta',
                      prefixIcon: Icon(Icons.flag_outlined),
                    ),
                    items: ConsultationStatus.values.map((status) {
                      return DropdownMenuItem(
                        value: status,
                        child: Text(ConsultationStatus.label(status)),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _status = value);
                    },
                  ),
                ],
                const SizedBox(height: 14),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Previsão de Retorno'),
                  subtitle: const Text('Definir data para consulta de retorno'),
                  value: _hasReturn,
                  onChanged: (val) {
                    setState(() {
                      _hasReturn = val;
                      if (_hasReturn && _returnDate == null) {
                        _returnDate =
                            _selectedDate.add(const Duration(days: 30));
                      }
                    });
                  },
                ),
                if (_hasReturn) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _pickReturnDate,
                    borderRadius: BorderRadius.circular(16),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Data de Retorno',
                        prefixIcon: Icon(Icons.event_repeat_outlined),
                      ),
                      child: Text(
                        _returnDate != null
                            ? dateFormat.format(_returnDate!)
                            : 'Selecionar data',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                TextFormField(
                  controller: _notesController,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Observações / Recomendações',
                    hintText: 'Ex.: Levar exames de sangue, jejum de 8h...',
                    alignLabelWithHint: true,
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
        FilledButton.icon(
          onPressed: doctors.isEmpty ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(_isEditing ? 'Salvar' : 'Agendar'),
        ),
      ],
    );
  }
}