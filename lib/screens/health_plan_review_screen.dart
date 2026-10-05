import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/health_plan.dart';
import '../services/card_reader_service.dart';

/// Resultado de uma leitura: os dados extraídos + a imagem original.
class CardScanResult {
  const CardScanResult({required this.data, required this.imageBytes});

  final CardReadResult data;
  final Uint8List imageBytes;
}

/// Tela de conferência dos dados lidos da imagem do cartão.
///
/// Todos os campos são editáveis — a leitura por IA pode errar ou omitir
/// alguma informação. O plano só é criado quando o usuário confirma
/// ([Navigator.pop] recebe o [HealthPlan]).
class HealthPlanReviewScreen extends StatefulWidget {
  const HealthPlanReviewScreen({
    super.key,
    required this.scan,
    required this.onRescan,
    this.onManualEntry,
  });

  final CardScanResult scan;

  /// Reabre a seleção/leitura de imagem (usado em "Escanear novamente").
  final Future<CardScanResult?> Function() onRescan;

  /// Volta para o cadastro manual preenchido com os dados já lidos.
  final VoidCallback? onManualEntry;

  @override
  State<HealthPlanReviewScreen> createState() =>
      _HealthPlanReviewScreenState();
}

class _HealthPlanReviewScreenState extends State<HealthPlanReviewScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _providerController;
  late final TextEditingController _cardNumberController;
  late final TextEditingController _groupController;
  late final TextEditingController _beneficiaryController;
  late final TextEditingController _validityController;
  late final TextEditingController _notesController;

  late Uint8List _imageBytes;
  late String? _coverageType;
  late Set<String> _specialties;
  bool _rescanning = false;

  @override
  void initState() {
    super.initState();
    _apply(widget.scan);
  }

  void _apply(CardScanResult scan) {
    final data = scan.data;
    _imageBytes = scan.imageBytes;
    _nameController = TextEditingController(text: data.name);
    _providerController = TextEditingController(text: data.provider);
    _cardNumberController = TextEditingController(text: data.cardNumber ?? '');
    _groupController = TextEditingController(text: data.groupNumber ?? '');
    _beneficiaryController =
        TextEditingController(text: data.beneficiaryCode ?? '');
    _validityController = TextEditingController(text: data.validity ?? '');
    _notesController = TextEditingController(
      text: data.notes ?? (data.rawText.isEmpty ? '' : data.rawText),
    );
    _coverageType = kCoverageTypes.contains(data.coverageType)
        ? data.coverageType
        : null;
    _specialties = <String>{};
  }

  @override
  void dispose() {
    _nameController.dispose();
    _providerController.dispose();
    _cardNumberController.dispose();
    _groupController.dispose();
    _beneficiaryController.dispose();
    _validityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _rescan() async {
    setState(() => _rescanning = true);
    try {
      final result = await widget.onRescan();
      if (result == null) return;

      final controllers = [
        _nameController,
        _providerController,
        _cardNumberController,
        _groupController,
        _beneficiaryController,
        _validityController,
        _notesController,
      ];
      for (final controller in controllers) {
        controller.dispose();
      }
      setState(() => _apply(result));
    } finally {
      if (mounted) setState(() => _rescanning = false);
    }
  }

  void _confirm() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final plan = HealthPlan.create(
      name: _nameController.text.trim(),
      provider: _providerController.text.trim(),
      cardNumber: _nullIfEmpty(_digits(_cardNumberController.text)),
      groupNumber: _nullIfEmpty(_digits(_groupController.text)),
      beneficiaryCode: _nullIfEmpty(_digits(_beneficiaryController.text)),
      validity: _nullIfEmpty(_validityController.text),
      coverageType: _coverageType,
      specialties: _specialties.toList(),
      notes: _nullIfEmpty(_notesController.text),
    );

    Navigator.of(context).pop(plan);
  }

  static String _digits(String value) =>
      value.replaceAll(RegExp(r'\D'), '');

  static String? _nullIfEmpty(String value) =>
      value.isEmpty ? null : value;

  Widget _field({
    required String label,
    required TextEditingController controller,
    bool required = false,
    String? hintText,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.sentences,
    int? maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        textCapitalization: textCapitalization,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          hintText: hintText,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        validator: required
            ? (value) =>
                (value == null || value.trim().isEmpty)
                    ? 'Informe $label'
                    : null
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conferir dados do cartão'),
        actions: [
          if (widget.onManualEntry != null)
            TextButton.icon(
              onPressed: () => widget.onManualEntry!(),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Cadastro manual'),
            ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 16 / 10,
                  child: Image.memory(
                    _imageBytes,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      alignment: Alignment.center,
                      child: const Icon(Icons.broken_image_outlined, size: 40),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Confira e complete os dados antes de salvar.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _rescanning ? null : _rescan,
                    icon: _rescanning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 18),
                    label: const Text('Escanear novamente'),
                  ),
                ],
              ),
              const Divider(height: 24),
              _field(
                label: 'Nome do plano',
                controller: _nameController,
                required: true,
              ),
              _field(
                label: 'Operadora',
                controller: _providerController,
                required: true,
              ),
              _field(
                label: 'Número da carteirinha',
                controller: _cardNumberController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              Row(
                children: [
                  Expanded(
                    child: _field(
                      label: 'Grupo',
                      controller: _groupController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _field(
                      label: 'Validade',
                      controller: _validityController,
                      hintText: 'MM/AAAA',
                    ),
                  ),
                ],
              ),
              _field(
                label: 'Código do beneficiário',
                controller: _beneficiaryController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: DropdownButtonFormField<String>(
                  initialValue: _coverageType,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de cobertura',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final type in kCoverageTypes)
                      DropdownMenuItem(value: type, child: Text(type)),
                  ],
                  onChanged: (value) =>
                      setState(() => _coverageType = value),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'Especialidades',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final specialty in kMedicalSpecialties)
                      FilterChip(
                        label: Text(specialty),
                        selected: _specialties.contains(specialty),
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            _specialties.add(specialty);
                          } else {
                            _specialties.remove(specialty);
                          }
                        }),
                      ),
                  ],
                ),
              ),
              _field(
                label: 'Observações',
                controller: _notesController,
                maxLines: 3,
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _confirm,
                icon: const Icon(Icons.check),
                label: const Text('Confirmar e salvar'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}