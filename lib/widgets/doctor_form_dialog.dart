import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../data/medical_specialties.dart';
import '../models/doctor.dart';
import '../models/doctor_draft.dart';
import '../core/design/app_tokens.dart';
import '../core/theme/app_theme.dart';
import '../services/ai_proxy_client.dart';
import '../services/ai_service.dart';
import '../services/cep_lookup_service.dart';
import '../services/crm_lookup_service.dart';
import '../services/places_search_service.dart';
import 'ai_sheet_shell.dart';
import 'br_input_formatters.dart';
import 'reading_dialog.dart';
import 'stepped_form_sheet.dart';

/// Cadastro de médico em PASSOS (padrão V4 "jornada"): Quem atende →
/// Registro (CRM com consulta ao conselho e portal do CFM) → Onde atende
/// (endereço com CEP e busca OSM). Atalhos de preenchimento preservados:
/// texto colado lido pela IA e leitura da receita preenchem e avisam —
/// só o nome é obrigatório. Especialidade é lista fixa (CFM).
class DoctorFormDialog extends StatefulWidget {
  const DoctorFormDialog({
    super.key,
    this.initialDoctor,
    this.cepLookup,
    this.crmLookup,
    this.placesSearch,
    this.aiService,
    this.draft,
  });

  final Doctor? initialDoctor;

  final CepLookupService? cepLookup;

  final CrmLookupService? crmLookup;

  final PlacesSearchService? placesSearch;

  /// IA que lê o texto colado e sugere o preenchimento. Injetável para
  /// testes; em produção usa o mesmo proxy do restante do app.
  final AiService? aiService;

  /// Rascunho de leitura automática (médico identificado na receita por
  /// OCR): preenche o formulário de um médico NOVO — nunca usado quando
  /// [initialDoctor] existe.
  final DoctorDraft? draft;

  @override
  State<DoctorFormDialog> createState() => _DoctorFormDialogState();
}

class _DoctorFormDialogState extends State<DoctorFormDialog> {
  late final CepLookupService _cepLookup;
  late final CrmLookupService _crmLookup;
  late final PlacesSearchService _placesSearch;
  late final AiService _aiService;
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

  /// Texto colado/digitado que a IA lê para preencher o cadastro.
  late final TextEditingController _aiPasteController;

  String? _crmState;
  String? _addressState;

  /// Especialidade selecionada na LISTA FIXA — o cadastro não aceita
  /// especialidade fora da lista; o valor atual (legado) entra como
  /// opção extra para não perder dado antigo ao editar.
  String? _specialtyValue;
  bool _showAddress = false;
  bool _showExtras = false;
  bool _lookingUpCep = false;
  bool _lookingUpCrm = false;
  bool _readingAi = false;

  /// Deleite V4: check verde que se desenha quando o CRM é confirmado no
  /// conselho — some se o número ou a UF mudarem depois.
  bool _crmVerified = false;

  String? _cepMessage;
  String? _lastLookedCep;

  /// Busca de endereço no OSM: sugestões com debounce, preenchimento
  /// sempre conferível nos campos estruturados.
  Timer? _placesDebounce;
  List<PlaceSuggestion> _placeSuggestions = const [];
  bool _searchingPlaces = false;

  /// Aviso de origem quando o formulário abre preenchido pela receita.
  String? _draftMessage;

  bool get _isEditing => widget.initialDoctor != null;

  @override
  void initState() {
    super.initState();
    _cepLookup = widget.cepLookup ?? CepLookupService();
    _crmLookup = widget.crmLookup ?? CrmLookupService();
    _placesSearch = widget.placesSearch ?? PlacesSearchService();
    _aiService = widget.aiService ?? AiService();
    final doctor = widget.initialDoctor;
    _nameController = TextEditingController(text: doctor?.name ?? '');
    _specialtyController = TextEditingController(text: doctor?.specialty ?? '');
    _specialtyValue = _specialtyController.text.trim().isEmpty
        ? null
        : _specialtyController.text.trim();
    _aiPasteController = TextEditingController(text: '');
    _crmController = TextEditingController(text: doctor?.crm ?? '');
    _phoneController = TextEditingController(text: doctor?.phone ?? '');
    _emailController = TextEditingController(text: doctor?.email ?? '');
    _clinicController = TextEditingController(text: doctor?.clinic ?? '');
    _streetController = TextEditingController(text: doctor?.street ?? '');
    _numberController = TextEditingController(text: doctor?.number ?? '');
    _complementController = TextEditingController(
      text: doctor?.complement ?? '',
    );
    _neighborhoodController = TextEditingController(
      text: doctor?.neighborhood ?? '',
    );
    _cityController = TextEditingController(text: doctor?.city ?? '');
    _postalCodeController = TextEditingController(
      text: doctor?.postalCode ?? '',
    );
    _healthPlansController = TextEditingController(
      text: doctor?.healthPlans ?? '',
    );
    _notesController = TextEditingController(text: doctor?.notes ?? '');
    _crmState = _normalizedUf(doctor?.crmState);
    _addressState = _normalizedUf(doctor?.state);
    _showAddress =
        doctor != null &&
        [
          doctor.street,
          doctor.number,
          doctor.neighborhood,
          doctor.city,
          doctor.state,
          doctor.postalCode,
        ].any((value) => value.trim().isNotEmpty);
    _showExtras =
        doctor != null &&
        [
          doctor.email,
          doctor.healthPlans,
          doctor.notes,
        ].any((value) => value.trim().isNotEmpty);

    // Rascunho da receita: preenche um médico NOVO e avisa que é confiança
    // por conferência — preencher não é salvar.
    final draft = widget.draft;
    if (doctor == null && draft != null && !draft.isEmpty) {
      if (draft.name.trim().isNotEmpty) {
        _nameController.text = titleCaseName(draft.name);
      }
      if (draft.crm.isNotEmpty) _crmController.text = draft.crm;
      if (isValidBrazilianUf(draft.crmState.trim().toUpperCase())) {
        _crmState = draft.crmState.trim().toUpperCase();
      }
      _draftMessage =
          'Preenchido pela foto da receita — confira antes de salvar.';
    }
  }

  String? _normalizedUf(String? value) {
    if (value == null) return null;
    final uf = value.trim().toUpperCase();
    return isValidBrazilianUf(uf) ? uf : null;
  }

  @override
  void dispose() {
    _placesDebounce?.cancel();
    _nameController.dispose();
    _specialtyController.dispose();
    _aiPasteController.dispose();
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

  // ── CEP (ViaCEP) ──────────────────────────────────────────────────────────

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

  // ── CRM (CREMESP) ─────────────────────────────────────────────────────────

  void _showCrmSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _applyCrmResult(CrmLookupResult result) async {
    final nameEmpty = _nameController.text.trim().isEmpty;
    final specialtyEmpty = _specialtyController.text.trim().isEmpty;
    var replace = true;
    if (!nameEmpty || !specialtyEmpty) {
      replace =
          await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Substituir os dados atuais?'),
              content: Text(
                'Encontrado: ${result.name}. Substitui os campos preenchidos?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Manter'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Substituir'),
                ),
              ],
            ),
          ) ??
          false;
    }
    if (!mounted) return;
    setState(() {
      if (replace && result.name.isNotEmpty) {
        _nameController.text = result.name;
      }
      if (replace && result.specialty.isNotEmpty) {
        // Fonte da verdade: o controller do estado. A especialidade só
        // entra se casar com a lista fixa (mesma regra da IA) — casando,
        // grava o valor canônico da lista; sem casar, mantém o texto do
        // conselho como opção extra para o usuário conferir.
        final matched = matchFixedSpecialty(result.specialty);
        _specialtyController.text = matched.isNotEmpty
            ? matched
            : result.specialty;
        _specialtyValue = _specialtyController.text;
      }
    });
  }

  Future<void> _lookupCrm() async {
    final digits = digitsOnly(_crmController.text);
    if (digits.length < 4) {
      _showCrmSnack('Informe o CRM para consultar');
      return;
    }
    if (_crmState == null || _crmState!.isEmpty) {
      _showCrmSnack('Selecione a UF do CRM para consultar');
      return;
    }

    setState(() => _lookingUpCrm = true);
    final result = await _crmLookup.lookup(digits, _crmState!);
    if (!mounted) return;
    setState(() => _lookingUpCrm = false);

    switch (result.kind) {
      case CrmLookupKind.success:
        await _applyCrmResult(result);
        if (!mounted) return;
        setState(() => _crmVerified = true);
        _showCrmSnack(
          result.statusText == 'Ativo'
              ? 'CRM ativo: ${result.name}'
              : 'CRM ${result.statusText.toLowerCase()}: ${result.name}',
        );
      case CrmLookupKind.notFound:
        _showCrmSnack('CRM não encontrado no conselho');
      case CrmLookupKind.unsupported:
        _showCrmSnack('Estado ainda não coberto — preencha manualmente');
      case CrmLookupKind.error:
        _showCrmSnack('Falha na consulta. Tente novamente.');
    }
  }

  // ── IA: texto colado → preenchimento ─────────────────────────────────

  /// Itens do dropdown de especialidade: a lista fixa do cadastro + o
  /// valor já gravado (legado) quando estiver fora da lista, para não
  /// perder dado antigo ao editar. Ordenado alfabeticamente.
  List<String> get _specialtyItems {
    final items = List<String>.from(kMedicalSpecialties);
    final current = _specialtyController.text.trim();
    if (current.isNotEmpty &&
        !items.any((item) => item.toLowerCase() == current.toLowerCase())) {
      items.add(current);
    }
    items.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return items;
  }

  void _setSpecialty(String? value) {
    setState(() {
      _specialtyValue = value;
      _specialtyController.text = value ?? '';
    });
  }

  Future<void> _fillWithAi() async {
    if (_readingAi) return;
    final raw = _aiPasteController.text.trim();
    if (raw.isEmpty) {
      _showCrmSnack('Cole ou digite os dados do médico primeiro');
      return;
    }

    final consented = await ensureAiConsent(context);
    if (!consented || !mounted) return;

    setState(() => _readingAi = true);
    unawaited(
      showReadingDialog(
        context,
        title: 'Preenchendo com IA…',
        subtitle: 'A IA extrai os dados do texto colado.',
      ),
    );

    DoctorAiData? data;
    String? error;
    try {
      data = await _aiService.extractDoctorData(raw);
    } on AiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Não foi possível preencher com IA. Preencha manualmente.';
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // diálogo de leitura
    setState(() => _readingAi = false);

    // Local final: a promoção de nulos não sobrevive ao bloco try.
    final result = data;
    if (result == null) {
      _showCrmSnack(error!);
      return;
    }

    setState(() {
      if (result.name.isNotEmpty) {
        _nameController.text = titleCaseName(result.name);
      }
      if (result.specialty.isNotEmpty) {
        _specialtyController.text = result.specialty;
        _specialtyValue = result.specialty;
      }
      if (result.crm.isNotEmpty) _crmController.text = result.crm;
      if (result.crmState.isNotEmpty) {
        _crmState = result.crmState;
        _crmVerified = false;
      }
      if (result.phone.isNotEmpty) _phoneController.text = result.phone;
      _draftMessage = 'Preenchido pela IA — confira antes de salvar.';
    });
    _showCrmSnack('Dados aplicados. Confira antes de salvar.');
  }

  // ── Portal do CFM (consulta manual e gratuita em todas as UF) ─────────

  Future<void> _openCfmPortal() async {
    const url = 'https://portal.cfm.org.br/busca-medicos/';
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      _showCrmSnack('Não foi possível abrir o portal do CFM.');
    }
  }

  // ── Endereço por busca (OpenStreetMap) ────────────────────────────────────

  void _onPlaceQueryChanged(String value) {
    _placesDebounce?.cancel();
    final query = value.trim();
    if (query.length < 3) {
      if (_placeSuggestions.isNotEmpty) {
        setState(() => _placeSuggestions = const []);
      }
      return;
    }
    _placesDebounce = Timer(
      const Duration(milliseconds: 450),
      () => _searchPlaces(query),
    );
  }

  Future<void> _searchPlaces(String query) async {
    setState(() => _searchingPlaces = true);
    final results = await _placesSearch.search(query);
    if (!mounted) return;
    setState(() {
      _searchingPlaces = false;
      _placeSuggestions = results;
    });
  }

  /// Escolher a sugestão preenche os campos estruturados — a fonte da
  /// verdade continua sendo o formulário, editável campo a campo.
  void _selectPlace(PlaceSuggestion place) {
    setState(() {
      _placeSuggestions = const [];
      if (place.street.isNotEmpty) _streetController.text = place.street;
      if (place.number.isNotEmpty) _numberController.text = place.number;
      if (place.neighborhood.isNotEmpty) {
        _neighborhoodController.text = place.neighborhood;
      }
      if (place.city.isNotEmpty) _cityController.text = place.city;
      final cep = digitsOnly(place.postalCode);
      if (cep.length == 8) {
        _postalCodeController.text =
            '${cep.substring(0, 5)}-${cep.substring(5)}';
      }
      final uf = place.uf.trim().toUpperCase();
      if (isValidBrazilianUf(uf)) _addressState = uf;
      _showAddress = true;
    });
  }

  String _placeSubtitle(PlaceSuggestion place) {
    return [
      [place.street, place.number].where((part) => part.isNotEmpty).join(', '),
      place.neighborhood,
      [place.city, place.uf].where((part) => part.isNotEmpty).join('/'),
    ].where((part) => part.isNotEmpty).join(' · ');
  }

  // ── Convênios, validação e salvamento ─────────────────────────────────────

  void _toggleHealthPlan(String plan) {
    final current = _healthPlansController.text
        .split(RegExp(r'[,;]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    final exists = current.any(
      (item) => item.toLowerCase() == plan.toLowerCase(),
    );
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

  /// Telefone opcional: se preenchido, precisa ter 10 ou 11 dígitos.
  String? _validatePhone(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final digits = digitsOnly(trimmed);
    if (digits.length < 10 || digits.length > 11) {
      return 'Telefone deve ter 10 ou 11 dígitos';
    }
    return null;
  }

  void _setCrmVerified(bool value) {
    if (_crmVerified == value) return;
    setState(() => _crmVerified = value);
  }

  void _save() {
    // Sem Form/GlobalKey: os passos validam por trecho; aqui conferimos o
    // essencial (nome) antes de devolver o médico ao chamador.
    if (_validateName(_nameController.text) != null) return;
    if (_validateCrm(_crmController.text) != null) return;
    if (_validatePhone(_phoneController.text) != null) return;

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
    return SteppedFormShell(
      title: _isEditing ? 'Editar médico' : 'Cadastrar médico',
      intro: 'Só o nome é obrigatório. O restante pode ser completado depois.',
      saveLabel: _isEditing ? 'Salvar' : 'Cadastrar',
      progressMessage: _draftMessage,
      steps: [
        // ── Passo 1: quem é ────────────────────────────────────────────────
        FormStep(
          title: 'Quem atende você',
          validate: () =>
              _validateName(_nameController.text) ??
              _validatePhone(_phoneController.text),
          children: [
            // Atalho de preenchimento: colar/digitar e deixar a IA
            // sugerir. Preencher não é salvar — a conferência é do
            // usuário, campo a campo.
            TextFormField(
              controller: _aiPasteController,
              maxLines: 3,
              decoration: _decoration(
                'Colar ou digitar os dados do médico',
                hint:
                    'Ex.: Dra. Ana Silva, CRM 123456-SP, cardiologista, '
                    '(11) 98888-7777',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.tonalIcon(
              key: const ValueKey('fillWithAiButton'),
              onPressed: _readingAi ? null : _fillWithAi,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Preencher com IA'),
            ),
            const SizedBox(height: AppSpacing.md),
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
            const SizedBox(height: AppSpacing.md),
            // Especialidade em LISTA FIXA: sem texto livre — a IA e o
            // conselho também só entram via casamento com esta lista.
            DropdownButtonFormField<String>(
              key: const ValueKey('doctorSpecialty'),
              value: _specialtyValue,
              isExpanded: true,
              hint: const Text('Selecione'),
              decoration: _decoration('Especialidade'),
              items: _specialtyItems
                  .map(
                    (item) => DropdownMenuItem(value: item, child: Text(item)),
                  )
                  .toList(),
              onChanged: _setSpecialty,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              inputFormatters: [PhoneInputFormatter()],
              validator: _validatePhone,
              decoration: _decoration('Telefone', hint: '(11) 99999-0000'),
            ),
          ],
        ),
        // ── Passo 2: registro ──────────────────────────────────────────────
        FormStep(
          title: 'Registro profissional (opcional)',
          validate: () => _validateCrm(_crmController.text),
          children: [
            Text(
              'A busca automática pelo CRM cobre o conselho de SP; para '
              'qualquer UF, confira no portal do CFM.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
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
                    onChanged: (_) => _setCrmVerified(false),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    key: const ValueKey('crmStateUf'),
                    initialValue: _crmState,
                    isExpanded: true,
                    hint: const Text('Selecione'),
                    decoration: _decoration('UF do CRM'),
                    items: [
                      ...kBrazilianStates.map(
                        (uf) => DropdownMenuItem(value: uf, child: Text(uf)),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _crmState = value;
                        _crmVerified = false;
                      });
                    },
                  ),
                ),
                AnimatedScale(
                  scale: _crmVerified ? 1 : 0,
                  duration: AppDurations.medium,
                  curve: AppCurves.emphasized,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(
                      Icons.check_circle_rounded,
                      color: AppSemanticColors.of(context).success,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Buscar dados pelo CRM no conselho',
                  onPressed: _lookingUpCrm ? null : _lookupCrm,
                  icon: _lookingUpCrm
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search_outlined),
                ),
              ],
            ),
            // Conferência manual e gratuita em todas as UF: abre o portal
            // do CFM no navegador — a busca automática do app cobre SP.
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('cfmPortalLink'),
                onPressed: _openCfmPortal,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Conferir no portal do CFM'),
              ),
            ),
          ],
        ),
        // ── Passo 3: onde atende ───────────────────────────────────────────
        FormStep(
          title: 'Onde atende',
          children: [
            TextFormField(
              controller: _clinicController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: _decoration(
                'Clínica ou consultório',
                hint: 'Opcional',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _buildPlaceSearch(),
            if (_placeSuggestions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              _buildPlaceSuggestions(),
            ],
            const SizedBox(height: AppSpacing.md),
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
              const SizedBox(height: AppSpacing.xs),
              Text(
                _cepMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
            // Endereço surge com crescimento suave — preenchido pelo CEP ou
            // aberto à mão, os campos aparecem com a mesma animação calma.
            AnimatedSize(
              duration: AppDurations.medium,
              curve: AppCurves.emphasized,
              alignment: Alignment.topCenter,
              child: !_showAddress
                  ? Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: TextButton.icon(
                        onPressed: () => setState(() => _showAddress = true),
                        icon: const Icon(Icons.add_location_alt_outlined),
                        label: const Text('Preencher endereço sem CEP'),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: AppSpacing.md),
                        TextFormField(
                          controller: _streetController,
                          textCapitalization: TextCapitalization.words,
                          decoration: _decoration('Rua ou avenida'),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _numberController,
                                decoration: _decoration('Número'),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: TextFormField(
                                controller: _complementController,
                                decoration: _decoration('Complemento'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextFormField(
                          controller: _neighborhoodController,
                          textCapitalization: TextCapitalization.words,
                          decoration: _decoration('Bairro'),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _cityController,
                                textCapitalization: TextCapitalization.words,
                                decoration: _decoration('Cidade'),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            SizedBox(
                              width: 120,
                              child: DropdownButtonFormField<String>(
                                key: const ValueKey('addressUf'),
                                initialValue: _addressState,
                                isExpanded: true,
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
                    ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              onPressed: () => setState(() => _showExtras = !_showExtras),
              icon: Icon(_showExtras ? Icons.expand_less : Icons.expand_more),
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
              const SizedBox(height: AppSpacing.md),
              Text(
                'Convênios atendidos',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
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
              const SizedBox(height: AppSpacing.md - 2),
              TextFormField(
                controller: _healthPlansController,
                decoration: _decoration(
                  'Outros convênios',
                  hint: 'Separe por vírgula',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.md),
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
      ],
      onSave: _save,
    );
  }

  /// Campo de busca de endereço no OSM — mesmo desenho da busca de
  /// medicamento: digita, espera as sugestões, toca e confere nos campos.
  Widget _buildPlaceSearch() {
    return TextFormField(
      decoration: InputDecoration(
        labelText: 'Buscar endereço',
        hintText: 'Ex.: Rua Ada Pereira, Campinas',
        prefixIcon: const Icon(Icons.travel_explore),
        suffixIcon: _searchingPlaces
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : null,
      ),
      onChanged: _onPlaceQueryChanged,
    );
  }

  Widget _buildPlaceSuggestions() {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220),
        // Material transparente: o ink do ListTile precisa de um ancestral
        // Material — sem ele o DecoratedBox pintado esconde o toque.
        child: Material(
          type: MaterialType.transparency,
          child: ListView.builder(
            padding: EdgeInsets.zero,
            primary: false,
            shrinkWrap: true,
            itemCount: _placeSuggestions.length,
            itemBuilder: (context, index) {
              final place = _placeSuggestions[index];
              final subtitle = _placeSubtitle(place);
              return ListTile(
                dense: true,
                leading: const Icon(Icons.location_on_outlined, size: 20),
                title: Text(
                  place.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: subtitle.isEmpty
                    ? null
                    : Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                onTap: () => _selectPlace(place),
              );
            },
          ),
        ),
      ),
    );
  }
}
