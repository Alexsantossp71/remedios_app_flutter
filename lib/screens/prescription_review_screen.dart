import 'package:flutter/material.dart';

import '../data/medicine_data.dart';
import '../models/medicine.dart';
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
  const PrescriptionReviewScreen({
    super.key,
    required this.result,
    this.catalogFuture,
  });

  final PrescriptionReadResult result;

  /// Sobrescrita para testes: sem ela, o catálogo real (25 mil itens) é lido
  /// do asset via [MedicineData.load].
  final Future<List<Medicine>>? catalogFuture;

  @override
  State<PrescriptionReviewScreen> createState() =>
      _PrescriptionReviewScreenState();
}

class _EditableMed {
  _EditableMed(this.original)
      : name = TextEditingController(text: original.nome),
        dosage = TextEditingController(text: original.dosagem),
        presentation = original.apresentacao,
        times = original.suggestedDoseTimes.isEmpty
            ? <DoseTime>[const DoseTime(hour: 8, minute: 0)]
            : original.suggestedDoseTimes.toList(),
        frequency = original.diasAlternados
            ? TreatmentFrequency.everyOtherDay
            : null;

  final PrescriptionMedication original;
  final TextEditingController name;
  final TextEditingController dosage;

  /// Nasce com o que o parser achou e pode ganhar apresentação do catálogo.
  String presentation;
  final List<DoseTime> times;
  bool selected = true;

  /// Frequência lida da receita ("dia sim, dia não"); nula = nada dito.
  TreatmentFrequency? frequency;

  void dispose() {
    name.dispose();
    dosage.dispose();
  }

  bool get hasName => name.text.trim().isNotEmpty;

  TreatmentDraft toDraft(DateTime today) {
    return TreatmentDraft(
      name: name.text.trim(),
      dosage: dosage.text.trim(),
      presentation: presentation,
      instructions: original.observacao.trim(),
      doseTimes: List.unmodifiable(times),
      endDate: original.duracaoDias == null
          ? null
          : today.add(Duration(days: original.duracaoDias!)),
      frequency: frequency,
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

  TimeOfDay _firstDoseTime(_EditableMed med) => med.times.isEmpty
      ? const TimeOfDay(hour: 8, minute: 0)
      : TimeOfDay(hour: med.times.first.hour, minute: med.times.first.minute);

  /// "A cada Xh" na conferência, igual ao formulário: pergunta a 1ª toma e
  /// gera o dia inteiro de uma vez. A convenção médica ancora na primeira
  /// dose (1ª às 22:00 → 22:00, 06:00 e 14:00), não no relógio. A frequência
  /// (dia sim, dia não) é outro eixo e não é mexida aqui.
  Future<void> _applyInterval(_EditableMed med, int intervalHours) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _firstDoseTime(med),
      helpText: 'Horário da primeira dose',
    );
    if (picked == null) return;
    setState(() {
      med.times
        ..clear()
        ..addAll(
          DoseSchedulePresets.everyIntervalHours(
            firstDose: DoseTime(hour: picked.hour, minute: picked.minute),
            intervalHours: intervalHours,
          ),
        );
    });
  }

  /// "3x ao dia" sem intervalo: distribui as tomas igualmente, ancoradas na
  /// 1ª dose — o par do "a cada Xh" para o que a receita diz em vezes.
  Future<void> _applyTimesPerDay(_EditableMed med, int timesPerDay) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _firstDoseTime(med),
      helpText: 'Horário da primeira dose',
    );
    if (picked == null) return;
    setState(() {
      med.times
        ..clear()
        ..addAll(
          DoseSchedulePresets.everyTimesPerDay(
            firstDose: DoseTime(hour: picked.hour, minute: picked.minute),
            timesPerDay: timesPerDay,
          ),
        );
    });
  }

  /// Chips geradores: os de rotina do formulário (8/12/24h) mais o intervalo
  /// que a receita trouxe, quando não está entre eles. É o atalho que
  /// faltava para posologias do tipo "de 6 em 6 horas": um toque substitui a
  /// montagem manual de cada horário.
  List<int> _intervalChips(_EditableMed med) {
    final intervals = <int>[8, 12, 24];
    final prescriptionInterval = med.original.intervaloHoras;
    if (prescriptionInterval != null &&
        !intervals.contains(prescriptionInterval)) {
      intervals.add(prescriptionInterval);
      intervals.sort();
    }
    return intervals;
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

  /// Casamento do nome lido com o catálogo ANVISA: corrige grafia de OCR e
  /// completa apresentação/dosagem vazias com um toque. Nunca aplica sozinho —
  /// a conferência existe para o usuário decidir.
  Widget _buildCatalogSuggestion(_EditableMed med) {
    return FutureBuilder<List<Medicine>>(
      future: widget.catalogFuture ?? MedicineData.load(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final suggestion =
            MedicineData.bestMatch(snapshot.data!, med.name.text);
        if (suggestion == null || !_hasSomethingToGain(med, suggestion)) {
          return const SizedBox.shrink();
        }
        final details = [
          if (suggestion.presentation.isNotEmpty) suggestion.presentation,
        ].join(' · ');
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () =>
                  setState(() => _applyCatalogSuggestion(med, suggestion)),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Catálogo: ${suggestion.name}'
                        '${details.isEmpty ? '' : ' · $details'}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Icon(
                      Icons.touch_app_outlined,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Só há o que ganhar se o catálogo corrige a grafia OU completa campo
  /// vazio — sugerir o que já está certo é ruído na conferência.
  bool _hasSomethingToGain(_EditableMed med, Medicine suggestion) {
    if (!_sameFold(med.name.text, suggestion.name)) return true;
    final catalogDosage =
        suggestion.dosage.isNotEmpty ? suggestion.dosage : suggestion.listedDosage;
    if (med.dosage.text.trim().isEmpty && catalogDosage.isNotEmpty) return true;
    if (med.presentation.isEmpty && suggestion.presentation.isNotEmpty) {
      return true;
    }
    return false;
  }

  void _applyCatalogSuggestion(_EditableMed med, Medicine suggestion) {
    if (!_sameFold(med.name.text, suggestion.name)) {
      med.name.text = suggestion.name;
    }
    final catalogDosage =
        suggestion.dosage.isNotEmpty ? suggestion.dosage : suggestion.listedDosage;
    if (med.dosage.text.trim().isEmpty && catalogDosage.isNotEmpty) {
      med.dosage.text = catalogDosage;
    }
    if (med.presentation.isEmpty && suggestion.presentation.isNotEmpty) {
      med.presentation = suggestion.presentation;
    }
  }

  static bool _sameFold(String first, String second) =>
      normalizeMedicineText(first) == normalizeMedicineText(second);

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
                    'Lido da receita'
                    '${badges.isEmpty ? '' : ' · ${badges.join(' · ')}'}',
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
            _buildCatalogSuggestion(med),
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
                  for (final intervalHours in _intervalChips(med))
                    ActionChip(
                      avatar: const Icon(Icons.autorenew, size: 18),
                      tooltip:
                          'Gera o dia inteiro a partir da 1ª dose (troca os '
                          'horários atuais)',
                      label: Text(
                        'A cada ${intervalHours}h'
                        '${intervalHours == med.original.intervaloHoras ? ' (receita)' : ''}',
                      ),
                      onPressed: () => _applyInterval(med, intervalHours),
                    ),
                  if (med.original.intervaloHoras == null &&
                      (med.original.vezesAoDia ?? 0) > 1)
                    ActionChip(
                      avatar: const Icon(Icons.autorenew, size: 18),
                      tooltip:
                          'Distribui as tomas igualmente a partir da 1ª dose',
                      label: Text(
                        'Distribuir ${med.original.vezesAoDia}x ao dia',
                      ),
                      onPressed: () =>
                          _applyTimesPerDay(med, med.original.vezesAoDia!),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
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
