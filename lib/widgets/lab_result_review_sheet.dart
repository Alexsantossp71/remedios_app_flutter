import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../core/design/app_tokens.dart';
import '../core/lab_values.dart';
import '../core/theme/app_theme.dart';
import '../models/lab_result.dart';
import '../widgets/app_snack_bar.dart';
import '../widgets/media_source_sheet.dart';
import '../widgets/stepped_form_sheet.dart';

/// Sheet única de laudo: revisão dos valores lidos pela IA OU digitação
/// manual. Cada linha é um marcador (nome, valor, unidade, faixa) — a
/// flag de alteração é sempre recalculada no app, nunca editada.
class LabResultReviewSheet extends StatefulWidget {
  const LabResultReviewSheet({
    super.key,
    this.initialResult,
    this.scannedLabName = '',
    this.scannedExamDate = '',
    this.scannedValues = const [],
    this.photoBytes,
  });

  /// Edição de um laudo já salvo.
  final LabResult? initialResult;

  /// Campos lidos pela IA (modo revisão pós-foto).
  final String scannedLabName;
  final String scannedExamDate;
  final List<LabValue> scannedValues;
  final Uint8List? photoBytes;

  @override
  State<LabResultReviewSheet> createState() => _LabResultReviewSheetState();
}

class _LabResultReviewSheetState extends State<LabResultReviewSheet> {
  late final TextEditingController _labNameController;
  late final TextEditingController _notesController;
  late DateTime _date;
  Uint8List? _photoBytes;

  /// Cada linha editável vira um [LabValue] no salvamento — a flag é
  /// recalculada a cada mudança de valor ou faixa.
  final List<_ValueRow> _rows = [];

  @override
  void initState() {
    super.initState();
    final existing = widget.initialResult;
    _labNameController = TextEditingController(
      text: existing?.labName ?? widget.scannedLabName,
    );
    _notesController = TextEditingController(text: existing?.notes ?? '');
    _date = existing?.date ?? _parseScanDate() ?? DateTime.now();
    _photoBytes = widget.photoBytes;
    if (existing != null && existing.photo != null) {
      _photoBytes = base64Decode(existing.photo!);
    }

    if (existing != null) {
      for (final value in existing.values) {
        _rows.add(_ValueRow.fromValue(value));
      }
    } else if (widget.scannedValues.isNotEmpty) {
      for (final value in widget.scannedValues) {
        _rows.add(_ValueRow.fromValue(value));
      }
    } else {
      _rows.add(_ValueRow.empty());
    }
  }

  @override
  void dispose() {
    _labNameController.dispose();
    _notesController.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  DateTime? _parseScanDate() {
    final value = widget.scannedExamDate;
    if (value.length != 10) return null;
    final year = int.tryParse(value.substring(0, 4));
    final month = int.tryParse(value.substring(5, 7));
    final day = int.tryParse(value.substring(8, 10));
    if (year == null || month == null || day == null) return null;
    return DateTime(year, month, day);
  }

  void _addRow() {
    setState(() => _rows.add(_ValueRow.empty()));
  }

  void _removeRow(int index) {
    setState(() {
      _rows[index].dispose();
      _rows.removeAt(index);
      if (_rows.isEmpty) _rows.add(_ValueRow.empty());
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(_date.year - 20),
      lastDate: DateTime(_date.year + 5),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _attachPhoto() async {
    final source = await showImageSourceSheet(
      context,
      cameraLabel: 'Tirar foto do laudo',
      galleryLabel: 'Escolher imagem da galeria',
    );
    if (source == null || !mounted) return;
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (mounted) setState(() => _photoBytes = bytes);
    } catch (_) {
      if (mounted) {
        showAppSnackBar(context, 'Não foi possível acessar a imagem.');
      }
    }
  }

  void _save() {
    final values = <LabValue>[];
    for (final row in _rows) {
      final name = row.nameController.text.trim();
      if (name.isEmpty) continue;
      final valueText = row.valueController.text.trim();
      final referenceText = row.referenceController.text.trim();
      final numericValue = valueText.isNotEmpty
          ? parseNumericValue(valueText)
          : null;
      final parsed = parseReferenceText(referenceText);
      values.add(
        LabValue(
          examName: name,
          valueText: valueText,
          numericValue: numericValue,
          unit: row.unitController.text.trim(),
          referenceLow: parsed.low,
          referenceHigh: parsed.high,
          referenceText: referenceText,
          flag: flagOf(numericValue, parsed.low, parsed.high),
        ),
      );
    }
    if (values.isEmpty) return;

    final existing = widget.initialResult;
    final result = LabResult(
      id: existing?.id ?? const Uuid().v4(),
      date: _date,
      labName: _labNameController.text.trim(),
      photo: _photoBytes == null ? null : base64Encode(_photoBytes!),
      values: values,
      notes: _notesController.text.trim(),
      createdAt: existing?.createdAt,
    );
    Navigator.of(context).pop(result);
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final isEditing = widget.initialResult != null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
          maxWidth: 560,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              0,
              AppSpacing.xl,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEditing ? 'Editar laudo' : 'Conferir laudo',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'A IA só transcreve — confira cada valor antes de salvar. '
                  'A comparação com a faixa é calculada aqui, no app.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _pickDate,
                                icon: const Icon(Icons.event_outlined),
                                label: Text(
                                  'Data do laudo\n${_formatDate(_date)}',
                                  textAlign: TextAlign.left,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: TextFormField(
                                controller: _labNameController,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                decoration: const InputDecoration(
                                  labelText: 'Laboratório',
                                  hintText: 'Opcional',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        for (var index = 0; index < _rows.length; index++)
                          _ValueRowCard(
                            key: ValueKey(_rows[index].key),
                            row: _rows[index],
                            flagColor: _rows[index].previewFlag(
                              context,
                              semantic,
                            ),
                            onRemove: () => _removeRow(index),
                          ),
                        TextButton.icon(
                          onPressed: _addRow,
                          icon: const Icon(Icons.add_circle_outline, size: 18),
                          label: const Text('Adicionar valor'),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        OutlinedButton.icon(
                          onPressed: _attachPhoto,
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: Text(
                            _photoBytes == null
                                ? 'Anexar foto do laudo'
                                : 'Foto anexada — trocar',
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextFormField(
                          controller: _notesController,
                          textCapitalization: TextCapitalization.sentences,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Observações',
                            hintText: 'Opcional — contexto do médico',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    const Spacer(),
                    FilledButton(
                      onPressed: _save,
                      child: Text(isEditing ? 'Salvar' : 'Salvar laudo'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ValueRow {
  _ValueRow.empty() : key = DateTime.now().microsecondsSinceEpoch {
    nameController = TextEditingController();
    valueController = TextEditingController();
    unitController = TextEditingController();
    referenceController = TextEditingController();
  }

  _ValueRow.fromValue(LabValue value)
    : key = DateTime.now().microsecondsSinceEpoch {
    nameController = TextEditingController(text: value.examName);
    valueController = TextEditingController(text: value.valueText);
    unitController = TextEditingController(text: value.unit);
    referenceController = TextEditingController(text: value.referenceText);
  }

  final int key;
  late final TextEditingController nameController;
  late final TextEditingController valueController;
  late final TextEditingController unitController;
  late final TextEditingController referenceController;

  void dispose() {
    nameController.dispose();
    valueController.dispose();
    unitController.dispose();
    referenceController.dispose();
  }

  Color? previewFlag(BuildContext context, AppSemanticColors semantic) {
    final numeric = parseNumericValue(valueController.text);
    final parsed = parseReferenceText(referenceController.text);
    switch (flagOf(numeric, parsed.low, parsed.high)) {
      case 'high':
        return semantic.danger;
      case 'low':
        return semantic.warning;
      case 'normal':
        return semantic.success;
      default:
        return null;
    }
  }
}

class _ValueRowCard extends StatelessWidget {
  const _ValueRowCard({
    super.key,
    required this.row,
    required this.onRemove,
    required this.flagColor,
  });

  final _ValueRow row;
  final VoidCallback onRemove;
  final Color? flagColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: flagColor != null
              ? flagColor!.withValues(alpha: .5)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: row.nameController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Exame',
                    hintText: 'Ex.: Glicemia',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton(
                tooltip: 'Remover valor',
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: row.valueController,
                  decoration: const InputDecoration(
                    labelText: 'Valor',
                    hintText: '95',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextFormField(
                  controller: row.unitController,
                  decoration: const InputDecoration(
                    labelText: 'Unidade',
                    hintText: 'mg/dL',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextFormField(
                  controller: row.referenceController,
                  decoration: const InputDecoration(
                    labelText: 'Faixa',
                    hintText: '70 - 99',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          if (flagColor != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                row.flagLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: flagColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

extension on _ValueRow {
  String get flagLabel {
    final numeric = parseNumericValue(valueController.text);
    final parsed = parseReferenceText(referenceController.text);
    switch (flagOf(numeric, parsed.low, parsed.high)) {
      case 'high':
        return 'Acima da faixa';
      case 'low':
        return 'Abaixo da faixa';
      case 'normal':
        return 'Dentro da faixa';
      default:
        return '';
    }
  }
}

/// Abre a sheet de revisão; devolve o laudo salvo ou null quando fechado.
Future<LabResult?> showLabResultReviewSheet(
  BuildContext context, {
  LabResult? initialResult,
  String scannedLabName = '',
  String scannedExamDate = '',
  List<LabValue> scannedValues = const [],
  Uint8List? photoBytes,
}) {
  return showSteppedFormSheet<LabResult>(
    context: context,
    builder: (_) => LabResultReviewSheet(
      initialResult: initialResult,
      scannedLabName: scannedLabName,
      scannedExamDate: scannedExamDate,
      scannedValues: scannedValues,
      photoBytes: photoBytes,
    ),
  );
}
