import 'package:flutter/material.dart';

import '../models/treatment.dart';
import '../models/treatment_draft.dart';
import '../services/dose_schedule_presets.dart';
import '../services/prescription_reader_service.dart';

/// Conferência do que o OCR leu na receita, antes de salvar qualquer coisa.
///
/// Preencher não é salvar: cada medicamento vem com nome e dosagem editáveis,
/// horários em chips (um toque marca, outro desmarca) e uma caixa para
/// excluir o que o parser inventou. "Continuar" devolve um [TreatmentDraft]
/// por medicamento selecionado — o formulário de tratamento continua sendo
/// a última palavra.
class PrescriptionReviewScreen extends StatefulWidget {
  const PrescriptionReviewScreen({super.key, required this.result});

  final PrescriptionReadResult result;

  @override
  State<PrescriptionReviewScreen> createState() =>
      _PrescriptionReviewScreenState();
}

class _EditableMed {
  _EditableMed(this.original)
      : name = TextEditingController(text: original.nome),
        dosage = TextEditingController(text: original.dosagem),
        times = original.suggestedDoseTimes.isEmpty
            ? <DoseTime>[const DoseTime(hour: 8, minute: 0)]
            : original.suggestedDoseTimes.toList();

  final PrescriptionMedication original;
  final TextEditingController name;
  final TextEditingController dosage;
  final List<DoseTime> times;
  bool selected = true;

  void dispose() {
    name.dispose();
    dosage.dispose();
  }

  bool get hasName => name.text.trim().isNotEmpty;

  TreatmentDraft toDraft(DateTime today) {
    return TreatmentDraft(
      name: name.text.trim(),
      dosage: dosage.text.trim(),
      presentation: original.apresentacao,
      instructions: original.observacao.trim(),
      doseTimes: List.unmodifiable(times),
      endDate: original.duracaoDias == null
          ? null
          : today.add(Duration(days: original.duracaoDias!)),
    );
  }
}

class _PrescriptionReviewScreenState extends State<PrescriptionReviewScreen> {
  late final List<_EditableMed> _meds;

  @override
  void initState() {
    super.initState();
    _meds = widget.result.medicamentos.map(_EditableMed.new).toList();
  }

  @override
  void dispose() {
    for (final med in _meds) {
      med.dispose();
    }
    super.dispose();
  }

  bool _hasTime(_EditableMed med, DoseTime time) => med.times.any(
      (item) => item.minutesSinceMidnight == time.minutesSinceMidnight);

  void _toggleTime(_EditableMed med, DoseTime time) {
    setState(() {
      if (_hasTime(med, time)) {
        if (med.times.length > 1) {
          med.times.removeWhere((item) =>
              item.minutesSinceMidnight == time.minutesSinceMidnight);
        }
        return;
      }
      med.times.add(time);
      med.times.sort((first, second) =>
          first.minutesSinceMidnight.compareTo(second.minutesSinceMidnight));
    });
  }

  Future<void> _addTime(_EditableMed med) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 8, minute: 0),
    );
    if (picked == null) return;
    _toggleTime(med, DoseTime(hour: picked.hour, minute: picked.minute));
  }

  List<TreatmentDraft> _buildDrafts() {
    final today = DateTime.now();
    return [
      for (final med in _meds)
        if (med.selected && med.hasName) med.toDraft(today),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Conferir receita')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            '${_meds.length} medicamentos lidos da receita. '
            'Confira o nome, a dosagem e os horários antes de continuar.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          for (final med in _meds) _medCard(med, theme),
          ExpansionTile(
            title: const Text('Texto lido da receita'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  widget.result.rawText.trim().isEmpty
                      ? '(nenhum texto reconhecido)'
                      : widget.result.rawText.trim(),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(_buildDrafts()),
            icon: const Icon(Icons.check),
            label: Text('Continuar com ${_buildDrafts().length} tratamento(s)'),
          ),
        ),
      ),
    );
  }

  Widget _medCard(_EditableMed med, ThemeData theme) {
    final original = med.original;
    final badges = <String>[
      if (original.intervaloHoras != null)
        'a cada ${original.intervaloHoras}h'
      else if (original.vezesAoDia != null)
        '${original.vezesAoDia}x ao dia',
      if (original.usoContinuo)
        'uso contínuo'
      else if (original.duracaoDias != null)
        'por ${original.duracaoDias} dias',
      if (original.apresentacao.isNotEmpty) original.apresentacao,
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: med.selected,
                  onChanged: (value) =>
                      setState(() => med.selected = value ?? false),
                ),
                Expanded(
                  child: Text(
                    'Lido da receita' +
                        (badges.isEmpty ? '' : ' · ${badges.join(' · ')}'),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            TextFormField(
              controller: med.name,
              decoration: const InputDecoration(labelText: 'Medicamento'),
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: med.dosage,
              decoration:
                  const InputDecoration(labelText: 'Dosagem (opcional)'),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Horários',
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final preset in DoseSchedulePresets.routinePresets)
                    ActionChip(
                      avatar: Icon(
                        _hasTime(med, preset.time) ? Icons.check : Icons.add,
                        size: 18,
                      ),
                      label: Text(preset.label),
                      onPressed: () => _toggleTime(med, preset.time),
                    ),
                  for (final time in med.times)
                    Chip(
                      label: Text(
                        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                      ),
                      onDeleted: med.times.length > 1
                          ? () => _toggleTime(med, time)
                          : null,
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.schedule, size: 18),
                    label: const Text('Adicionar'),
                    onPressed: () => _addTime(med),
                  ),
                ],
              ),
            ),
            if (original.observacao.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                original.observacao,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
