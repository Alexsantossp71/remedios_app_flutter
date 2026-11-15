import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../core/design/app_tokens.dart';
import '../models/doctor.dart';
import '../models/doctor_draft.dart';
import '../models/exam.dart';
import '../providers/doctor_provider.dart';
import '../services/ai_proxy_client.dart';
import '../services/ai_service.dart';
import '../services/doctor_matching.dart';
import '../widgets/app_snack_bar.dart';
import '../widgets/doctor_inline_creator.dart';
import '../widgets/media_source_sheet.dart';
import '../widgets/reading_dialog.dart';
import '../widgets/stepped_form_sheet.dart';
import 'ai_sheet_shell.dart';

/// Formulário de exame em passos (pedido → agendamento → realização).
/// A leitura por IA só PREENCHE — quem revisa e salva é o usuário, igual
/// ao fluxo de receitas. O exame exige médico solicitante: escolhe do
/// catálogo, cadastra ali mesmo (banner com criação inline) ou aceita o
/// convite de cadastro quando a leitura identifica médico fora do catálogo.
class ExamFormDialog extends StatefulWidget {
  const ExamFormDialog({super.key, this.initialExam, this.initialScan});

  final Exam? initialExam;
  final AiExamScan? initialScan;

  @override
  State<ExamFormDialog> createState() => _ExamFormDialogState();
}

class _ExamFormDialogState extends State<ExamFormDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _placeController;
  late final TextEditingController _doctorNameController;
  late final TextEditingController _resultsController;
  late String _category;
  late String _status;
  late DateTime _date;
  TimeOfDay? _time;
  String? _selectedDoctorId;

  /// Médico lido da foto do pedido que NÃO casou com o catálogo: vira o
  /// convite [ScannedDoctorCta] de cadastro — nada criado sem conferência.
  String? _scannedDoctorName;
  Uint8List? _photoBytes;
  bool _isEditing = false;
  bool _isReading = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.initialExam;
    _isEditing = existing != null;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _placeController = TextEditingController(text: existing?.place ?? '');
    _doctorNameController =
        TextEditingController(text: existing?.doctorName ?? '');
    _resultsController =
        TextEditingController(text: existing?.results ?? '');
    _category = existing?.category ?? widget.initialScan?.category ?? '';
    _status = existing?.status ?? ExamStatus.requested;
    _date = existing?.date ?? _parseScanDate(widget.initialScan?.date) ?? DateTime.now();
    _time = _parseTime(existing?.time);
    _selectedDoctorId =
        (existing?.doctorId.isNotEmpty ?? false) ? existing!.doctorId : null;
    if (existing?.photo != null) {
      _photoBytes = base64Decode(existing!.photo!);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _placeController.dispose();
    _doctorNameController.dispose();
    _resultsController.dispose();
    super.dispose();
  }

  bool _doctorMatchTried = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Uma única tentativa de casar o nome do médico (registro antigo sem
    // vínculo) com o catálogo: casa pelo nome e pré-seleciona — o campo
    // obrigatório não pede de novo quem já é conhecido.
    if (_doctorMatchTried) return;
    _doctorMatchTried = true;
    _tryMatchDoctorByName(_doctorNameController.text);
  }

  void _tryMatchDoctorByName(String name) {
    if (_selectedDoctorId != null && _selectedDoctorId!.isNotEmpty) return;
    // Mesma regra de casamento do resto do app (nome normalizado; CRM+UF
    // quando existe) — o pedido de exame não cria regra própria.
    final match = findDoctorInCatalog(
      context.read<DoctorProvider>().doctors,
      name: name,
    );
    if (match != null) {
      setState(() => _selectedDoctorId = match.id);
    }
  }

  DateTime? _parseScanDate(String? value) {
    if (value == null || value.length != 10) return null;
    final year = int.tryParse(value.substring(0, 4));
    final month = int.tryParse(value.substring(5, 7));
    final day = int.tryParse(value.substring(8, 10));
    if (year == null || month == null || day == null) return null;
    return DateTime(year, month, day);
  }

  TimeOfDay? _parseTime(String? value) {
    if (value == null) return null;
    final parts = value.split(':');
    final hour = int.tryParse(parts.first);
    final minute = parts.length > 1 ? int.tryParse(parts[1]) : null;
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  // ── Leitura por IA ────────────────────────────────────────────────────

  Future<void> _readFromPhoto() async {
    if (_isReading) return;
    final consented = await ensureAiConsent(context);
    if (!consented || !mounted) return;

    final source = await showImageSourceSheet(
      context,
      cameraLabel: 'Tirar foto do pedido',
      galleryLabel: 'Escolher imagem da galeria',
    );
    if (source == null || !mounted) return;

    final XFile? file;
    try {
      file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
    } catch (_) {
      if (mounted) {
        showAppSnackBar(context, 'Não foi possível acessar a imagem.');
      }
      return;
    }
    if (file == null) return;

    final bytes = await file.readAsBytes();
    final mimeType = _mimeTypeOf(file);
    if (!mounted) return;

    setState(() => _isReading = true);
    unawaited(showReadingDialog(
      context,
      title: 'Lendo pedido…',
      subtitle: 'A IA extrai os dados impressos no pedido.',
    ));

    AiExamScan? scan;
    String? error;
    try {
      scan = await AiService().scanExamRequest(
        imageBytes: bytes,
        mimeType: mimeType,
      );
    } on AiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Não foi possível ler o pedido. Tente outra foto ou preencha '
          'manualmente.';
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // diálogo de leitura
    setState(() => _isReading = false);

    if (scan == null) {
      showAppSnackBar(context, error!);
      return;
    }

    setState(() {
      _photoBytes = bytes;
      if (scan!.name.isNotEmpty) _nameController.text = scan.name;
      if (scan.category.isNotEmpty) _category = scan.category;
      if (scan.place.isNotEmpty) _placeController.text = scan.place;
      if (scan.doctorName.isNotEmpty && _selectedDoctorId == null) {
        _doctorNameController.text = scan.doctorName;
        // O nome lido pode já existir no catálogo — casa e pré-seleciona.
        _tryMatchDoctorByName(scan.doctorName);
        // Sem casamento: o médico lido vira CONVITE de cadastro, nunca
        // criação automática — quem decide é o usuário.
        _scannedDoctorName =
            _selectedDoctorId == null ? scan.doctorName : null;
      }
      final parsedDate = _parseScanDate(scan.date);
      if (parsedDate != null) _date = parsedDate;
    });
    if (mounted) {
      showAppSnackBar(
        context,
        'Pedido lido. Confira os campos antes de salvar.',
        type: AppSnackType.success,
      );
    }
  }

  String _mimeTypeOf(XFile file) {
    final mimeType = file.mimeType;
    if (mimeType != null && mimeType.startsWith('image/')) return mimeType;
    final name = file.name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  // ── Salvamento ────────────────────────────────────────────────────────

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    // Exame exige médico (regra do produto): o passo 3 já barrou; a
    // re-checagem é barata e protege qualquer caminho alternativo.
    final doctorId = _selectedDoctorId;
    if (doctorId == null || doctorId.isEmpty) return;

    final existing = widget.initialExam;
    // Snapshot do nome: o texto digitado vale quando difere do catálogo
    // (ex.: abreviação no pedido). Vazio, cai para o nome do médico
    // selecionado — o exame nunca fica sem médico identificado.
    final typedName = _doctorNameController.text.trim();
    String doctorName = typedName;
    if (doctorName.isEmpty) {
      for (final Doctor doctor in context.read<DoctorProvider>().doctors) {
        if (doctor.id == doctorId) {
          doctorName = doctor.name;
          break;
        }
      }
    }

    final result = Exam(
      id: existing?.id ?? const Uuid().v4(),
      name: name,
      category: _category,
      status: _status,
      date: _date,
      time: _status == ExamStatus.scheduled && _time != null
          ? '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}'
          : null,
      photo: _photoBytes == null ? null : base64Encode(_photoBytes!),
      doctorId: doctorId,
      doctorName: doctorName,
      place: _placeController.text.trim(),
      results: _resultsController.text.trim(),
      createdAt: existing?.createdAt,
    );

    Navigator.of(context).pop(result);
  }

  // ── UI helpers ────────────────────────────────────────────────────────

  InputDecoration _decoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      alignLabelWithHint: true,
    );
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  String get _dateLabel {
    switch (_status) {
      case ExamStatus.requested:
        return 'Data do pedido';
      case ExamStatus.scheduled:
        return 'Data agendada';
      case ExamStatus.done:
        return 'Data de realização';
      default:
        return 'Data';
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(_date.year - 5),
      lastDate: DateTime(_date.year + 5),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay.now(),
    );
    if (picked != null) setState(() => _time = picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final doctors = context.watch<DoctorProvider>().doctors;

    return SteppedFormShell(
      title: _isEditing ? 'Editar exame' : 'Registrar exame',
      intro:
          'Acompanhe do pedido ao resultado — o exame e o médico são '
          'obrigatórios.',
      saveLabel: _isEditing ? 'Salvar' : 'Registrar exame',
      steps: [
        // ── Passo 1: o que foi pedido ────────────────────────────────────
        FormStep(
          title: 'O que foi pedido',
          validate: () =>
              _nameController.text.trim().isEmpty
                  ? 'Informe o nome do exame (ou leia a foto do pedido).'
                  : null,
          children: [
            OutlinedButton.icon(
              onPressed: _isReading ? null : _readFromPhoto,
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(
                _photoBytes == null
                    ? 'Ler foto do pedido com IA'
                    : 'Trocar foto (lê com IA)',
              ),
            ),
            if (_photoBytes != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: Image.memory(
                      _photoBytes!,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Foto anexada. Ela fica salva junto do exame.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remover foto',
                    onPressed: () => setState(() => _photoBytes = null),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              decoration: _decoration(
                'Exame(s)',
                hint: 'Ex.: Hemograma completo, Glicemia',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: 4,
                children: [
                  for (final category in examCategories)
                    FilterChip(
                      label: Text(category),
                      selected: _category == category,
                      onSelected: (_) =>
                          setState(() => _category = category),
                    ),
                ],
              ),
            ),
          ],
        ),
        // ── Passo 2: situação, quando e onde ─────────────────────────────
        FormStep(
          title: 'Situação, quando e onde',
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: ExamStatus.requested,
                  label: Text('Solicitado'),
                ),
                ButtonSegment(
                  value: ExamStatus.scheduled,
                  label: Text('Agendado'),
                ),
                ButtonSegment(
                  value: ExamStatus.done,
                  label: Text('Realizado'),
                ),
              ],
              selected: {_status},
              onSelectionChanged: (selection) =>
                  setState(() => _status = selection.first),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.event_outlined),
                    label: Text(
                      '$_dateLabel\n${_formatDate(_date)}',
                      textAlign: TextAlign.left,
                    ),
                  ),
                ),
                if (_status == ExamStatus.scheduled) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickTime,
                      icon: const Icon(Icons.schedule_outlined),
                      label: Text(
                        'Horário\n${_time?.format(context) ?? 'definir'}',
                        textAlign: TextAlign.left,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _placeController,
              textCapitalization: TextCapitalization.sentences,
              decoration: _decoration(
                'Laboratório ou clínica',
                hint: 'Opcional — onde realizar ou onde foi realizado',
              ),
            ),
          ],
        ),
        // ── Passo 3: médico e resultado ──────────────────────────────────
        FormStep(
          title: 'Médico e resultado',
          validate:
              () => (_selectedDoctorId == null || _selectedDoctorId!.isEmpty)
                  ? 'Selecione ou cadastre o médico solicitante.'
                  : null,
          children: [
            if (doctors.isEmpty) ...[
              // Exame exige médico: com o catálogo vazio, o cadastro
              // acontece ali mesmo — o nome lido do pedido (OCR) já vai
              // pré-preenchido para conferir e salvar.
              InlineDoctorBanner(
                draft:
                    _doctorNameController.text.trim().isEmpty
                        ? null
                        : DoctorDraft(name: _doctorNameController.text.trim()),
                onDoctorCreated: (created) {
                  setState(() {
                    _selectedDoctorId = created.id;
                    _doctorNameController.text = created.name;
                  });
                },
              ),
              const SizedBox(height: AppSpacing.md),
            ] else if (_selectedDoctorId == null &&
                _scannedDoctorName != null) ...[
              // A leitura achou um médico que não está no catálogo: convite
              // de cadastro com o nome lido — um toque resolve sem beco.
              ScannedDoctorCta(
                scannedName: _scannedDoctorName!,
                onDoctorCreated: (created) {
                  setState(() {
                    _selectedDoctorId = created.id;
                    _doctorNameController.text = created.name;
                    _scannedDoctorName = null;
                  });
                },
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            DropdownButtonFormField<String>(
              initialValue: _selectedDoctorId,
              isExpanded: true,
              decoration: _decoration('Médico', hint: 'Selecione'),
              items: [
                for (final Doctor doctor in doctors)
                  DropdownMenuItem<String>(
                    value: doctor.id,
                    child: Text(
                      doctor.specialty.isEmpty
                          ? doctor.name
                          : '${doctor.name} (${doctor.specialty})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedDoctorId = value;
                  // Selecionou do catálogo: o convite deixa de fazer sentido.
                  _scannedDoctorName = null;
                  if (value != null) {
                    final match = doctors.firstWhere(
                      (doctor) => doctor.id == value,
                    );
                    _doctorNameController.text = match.name;
                  }
                });
              },
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Selecione ou cadastre o médico solicitante';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _doctorNameController,
              textCapitalization: TextCapitalization.words,
              decoration: _decoration(
                'Nome no pedido (opcional)',
                hint: 'Se for diferente do nome no catálogo',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _resultsController,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 3,
              decoration: _decoration(
                'Resultado / laudo resumido',
                hint: 'Opcional — preencha quando o exame ficar pronto',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Valores detalhados ficam nos Resultados de laboratório.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
      onSave: _save,
    );
  }
}
