import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../core/design/app_tokens.dart';
import '../models/consultation.dart';
import '../models/doctor.dart';
import '../providers/doctor_provider.dart';
import 'stepped_form_sheet.dart';

/// Agendamento de consulta em PASSOS (padrão V4 "jornada"): Quem atende →
/// Quando → Motivo e retorno. Atalhos de datas próximas e motivos comuns
/// preservados; só o médico é obrigatório.
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    // O primeiro médico entra selecionado DE VERDADE: antes o dropdown só
    // mostrava o primeiro e o salvar exigia um toque no campo para funcionar.
    // Médico excluído depois de abrir o diálogo também cai aqui.
    final doctors = context.watch<DoctorProvider>().doctors;
    final hasSelection = doctors.any((d) => d.id == _selectedDoctorId);
    if (!hasSelection && doctors.isNotEmpty) {
      setState(() => _selectedDoctorId = doctors.first.id);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ── Datas e horários ──────────────────────────────────────────────────────

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

  /// Atalhos "Hoje / Amanhã / Em 1 semana" — um toque e a data muda, o
  /// horário fica como está (o picker continua disponível para o resto).
  void _setQuickDate(DateTime date) {
    setState(() => _selectedDate = date);
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // ── Motivos comuns ────────────────────────────────────────────────────────

  /// Um toque preenche o motivo, outro desmarca — sem digitar para o caso
  /// comum (rotina, retorno, exames).
  void _toggleTitle(String suggestion) {
    setState(() {
      if (_titleController.text.trim().toLowerCase() ==
          suggestion.toLowerCase()) {
        _titleController.clear();
        return;
      }
      _titleController.text = suggestion;
    });
  }

  bool _hasTitle(String suggestion) =>
      _titleController.text.trim().toLowerCase() == suggestion.toLowerCase();

  // ── Salvamento ────────────────────────────────────────────────────────────

  void _save() {
    // O passo 1 já barrou sem médico; re-checar é barato.
    if (_selectedDoctorId == null || _selectedDoctorId!.isEmpty) return;

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

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  InputDecoration _decoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      alignLabelWithHint: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final doctorProvider = context.watch<DoctorProvider>();
    final doctors = doctorProvider.doctors;

    return SteppedFormShell(
      title: _isEditing ? 'Editar consulta' : 'Agendar consulta',
      intro: 'Escolha o médico e o horário — só o médico é obrigatório.',
      saveLabel: _isEditing ? 'Salvar' : 'Agendar',
      steps: [
        // ── Passo 1: quem atende ───────────────────────────────────────────
        FormStep(
          title: 'Quem atende',
          validate:
              () =>
                  (_selectedDoctorId == null || _selectedDoctorId!.isEmpty)
                      ? 'Selecione um médico para a consulta.'
                      : null,
          children: [
            if (doctors.isEmpty) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: AppSpacing.sm + 2),
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
              const SizedBox(height: AppSpacing.md),
            ],
            DropdownButtonFormField<String>(
              initialValue: _selectedDoctorId,
              isExpanded: true,
              decoration: _decoration('Médico', hint: 'Selecione'),
              items:
                  doctors.map((Doctor doctor) {
                    final subtitle = [
                      doctor.specialty,
                      if (doctor.crm.isNotEmpty) 'CRM ${doctor.crm}',
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
          ],
        ),
        // ── Passo 2: quando ────────────────────────────────────────────────
        FormStep(
          title: 'Quando',
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: 4,
                children: [
                  for (final (label, date) in _quickDates())
                    FilterChip(
                      label: Text(label),
                      selected: _isSameDay(_selectedDate, date),
                      onSelected: (_) => _setQuickDate(date),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm + 2),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.event_outlined),
                    label: Text(
                      'Data\n${_formatDate(_selectedDate)}',
                      textAlign: TextAlign.left,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule_outlined),
                    label: Text(
                      'Horário\n${_selectedTime.format(context)}',
                      textAlign: TextAlign.left,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        // ── Passo 3: motivo e retorno ──────────────────────────────────────
        FormStep(
          title: 'Motivo e retorno',
          children: [
            TextFormField(
              controller: _titleController,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              decoration: _decoration(
                'Motivo da consulta',
                hint: 'Ex.: retorno, rotina, exames',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: 4,
                children: [
                  for (final suggestion in const [
                    'Consulta de rotina',
                    'Retorno',
                    'Exames',
                    'Primeira consulta',
                  ])
                    FilterChip(
                      label: Text(suggestion),
                      selected: _hasTitle(suggestion),
                      onSelected: (_) => _toggleTitle(suggestion),
                    ),
                ],
              ),
            ),
            if (_isEditing) ...[
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Situação',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: _decoration('Status da consulta'),
                items:
                    ConsultationStatus.values.map((status) {
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
            const SizedBox(height: AppSpacing.md),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Previsão de retorno'),
              subtitle: const Text('Definir data para consulta de retorno'),
              value: _hasReturn,
              onChanged: (val) {
                setState(() {
                  _hasReturn = val;
                  if (_hasReturn && _returnDate == null) {
                    _returnDate = _selectedDate.add(const Duration(days: 30));
                  }
                });
              },
            ),
            AnimatedSize(
              duration: AppDurations.medium,
              curve: AppCurves.emphasized,
              alignment: Alignment.topCenter,
              child:
                  _hasReturn
                      ? Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: OutlinedButton.icon(
                          onPressed: _pickReturnDate,
                          icon: const Icon(Icons.event_repeat_outlined),
                          label: Text(
                            'Data de retorno\n${_formatDate(_returnDate!)}',
                            textAlign: TextAlign.left,
                          ),
                        ),
                      )
                      : const SizedBox(width: double.infinity),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _notesController,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: _decoration(
                'Observações (opcional)',
                hint: 'Ex.: levar exames de sangue, jejum de 8h',
              ),
            ),
          ],
        ),
      ],
      onSave: _save,
    );
  }

  /// Atalhos de data relativos a hoje — recalculados a cada build para o
  /// formulário nunca oferecer um "amanhã" que já passou.
  List<(String, DateTime)> _quickDates() {
    final now = DateTime.now();
    return [
      ('Hoje', now),
      ('Amanhã', now.add(const Duration(days: 1))),
      ('Em 1 semana', now.add(const Duration(days: 7))),
    ];
  }
}
