import 'package:material_ui/material_ui.dart';

import '../../models/user_profile.dart';
import '../../widgets/app_snack_bar.dart';
import 'profile_validators.dart';
import 'widgets/profile_form_card.dart';

/// Convite de preenchimento do perfil — tela única exibida logo depois da
/// criação do cofre, na primeira interação com o app (web).
///
/// Fluxo: BootLoader ("Entrar") → DatabaseUnlockGate (criação do PIN) →
/// ESTA tela → diário (MainShell). Ela roda exatamente uma vez por aparelho,
/// porque o gate só cria cofre quando não há envelope em localStorage.
///
/// É uma tela coletora: NÃO toca no banco. O [UserProfile] montado no
/// formulário é entregue via [onFinish] e persistido pelo bootstrap assim
/// que os providers sobem (`bootstrapApp(initialProfile:)` em
/// `app_bootstrap.dart`). Ao pular, entrega null — nenhum dado é gravado e
/// o usuário pode preencher depois na aba Perfil.
///
/// Reaproveita o mesmo [ProfileFormCard] da aba Perfil (mesmos campos,
/// validadores e aviso LGPD), com o botão "Salvar e começar".
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key, required this.onFinish});

  /// Entrega o resultado da tela: [UserProfile] preenchido quando o usuário
  /// salva, ou null quando pula. Chamado no máximo uma vez.
  final ValueChanged<UserProfile?> onFinish;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();

  // Mesma estratégia da ProfileScreen: chave por campo para rolar até o
  // primeiro erro de validação quando o usuário toca em "Salvar e começar".
  final _nomeFieldKey = GlobalKey();
  final _cpfFieldKey = GlobalKey();
  final _telefoneFieldKey = GlobalKey();
  final _pesoFieldKey = GlobalKey();
  final _alturaFieldKey = GlobalKey();

  GlobalKey? _firstInvalidFieldKey;

  late final TextEditingController _nomeController;
  late final TextEditingController _cpfController;
  late final TextEditingController _telefoneController;
  late final TextEditingController _pesoController;
  late final TextEditingController _alturaController;
  late final TextEditingController _observacoesController;

  DateTime? _dataNascimento;
  TipoSanguineo? _tipoSanguineo;
  List<String> _alergias = [];
  List<String> _condicoesCronicas = [];
  bool _consentGranted = false;

  @override
  void initState() {
    super.initState();
    _nomeController = TextEditingController();
    _cpfController = TextEditingController();
    _telefoneController = TextEditingController();
    _pesoController = TextEditingController();
    _alturaController = TextEditingController();
    _observacoesController = TextEditingController();
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _cpfController.dispose();
    _telefoneController.dispose();
    _pesoController.dispose();
    _alturaController.dispose();
    _observacoesController.dispose();
    super.dispose();
  }

  Future<void> _selectBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dataNascimento ?? DateTime(now.year - 30),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Data de nascimento',
      cancelText: 'Cancelar',
      confirmText: 'Confirmar',
    );
    if (picked != null) {
      setState(() => _dataNascimento = picked);
    }
  }

  /// Valida o formulário e entrega o [UserProfile] preenchido. O
  /// consentimento LGPD é obrigatório para salvar dados de saúde — mesma
  /// regra da aba Perfil (art. 11).
  void _saveAndStart() {
    FocusScope.of(context).unfocus();
    _firstInvalidFieldKey = null;
    if (!_formKey.currentState!.validate()) {
      _revealInvalidField();
      showAppSnackBar(
        context,
        'Verifique os campos destacados em vermelho para salvar o perfil.',
        type: AppSnackType.error,
      );
      return;
    }
    if (!_consentGranted) {
      showAppSnackBar(
        context,
        'Autorize o tratamento dos seus dados de saúde para salvar o '
        'perfil — ou toque em "Pular por agora".',
      );
      return;
    }

    final now = DateTime.now().toUtc();
    final nowIso = now.toIso8601String();
    widget.onFinish(
      UserProfile(
        nome: _nomeController.text.trim(),
        cpf: _cpfController.text.trim().isNotEmpty
            ? _cpfController.text.trim()
            : null,
        dataNascimento: _dataNascimento,
        tipoSanguineo: _tipoSanguineo,
        alergias: _alergias,
        condicoesCronicas: _condicoesCronicas,
        peso: parseNumber(_pesoController.text),
        altura: parseNumber(_alturaController.text),
        telefone: _telefoneController.text.trim().isNotEmpty
            ? _telefoneController.text.trim()
            : null,
        observacoes: _observacoesController.text.trim().isNotEmpty
            ? _observacoesController.text.trim()
            : null,
        consentAt: now,
        createdAt: nowIso,
        updatedAt: nowIso,
      ),
    );
  }

  /// Fecha a tela sem gravar nada — o usuário pode preencher depois na
  /// aba Perfil.
  void _skip() {
    FocusScope.of(context).unfocus();
    widget.onFinish(null);
  }

  /// Traz à viewport o primeiro campo com erro de validação.
  Future<void> _revealInvalidField() async {
    final target = _firstInvalidFieldKey?.currentContext;
    if (target == null) return;
    await Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      alignment: 0.2,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Form(
              key: _formKey,
              child: Scrollbar(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                  children: [
                    Center(child: _SetupMark()),
                    const SizedBox(height: 20),
                    Text(
                      'Quem vai usar o app?',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Preencha seu perfil para o app montar seu cartão de '
                      'emergência e personalizar o diário. Tudo fica salvo '
                      'somente neste aparelho — e você pode pular agora e '
                      'completar depois na aba Perfil.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ProfileFormCard(
                      nomeFieldKey: _nomeFieldKey,
                      nomeController: _nomeController,
                      cpfFieldKey: _cpfFieldKey,
                      cpfController: _cpfController,
                      telefoneFieldKey: _telefoneFieldKey,
                      telefoneController: _telefoneController,
                      pesoFieldKey: _pesoFieldKey,
                      pesoController: _pesoController,
                      alturaFieldKey: _alturaFieldKey,
                      alturaController: _alturaController,
                      observacoesController: _observacoesController,
                      dataNascimento: _dataNascimento,
                      tipoSanguineo: _tipoSanguineo,
                      alergias: _alergias,
                      condicoesCronicas: _condicoesCronicas,
                      consentGranted: _consentGranted,
                      consentAt: null,
                      saveLabel: 'Salvar e começar',
                      onTipoSanguineoChanged: (value) {
                        setState(() => _tipoSanguineo = value);
                      },
                      onAlergiasChanged: (values) {
                        setState(() => _alergias = values);
                      },
                      onCondicoesCronicasChanged: (values) {
                        setState(() => _condicoesCronicas = values);
                      },
                      onConsentChanged: (value) {
                        setState(() => _consentGranted = value ?? false);
                      },
                      onSelectBirthDate: _selectBirthDate,
                      onSave: _saveAndStart,
                      onInvalidField: (fieldKey) =>
                          _firstInvalidFieldKey ??= fieldKey,
                      validateCpf: (value) {
                        final error = cpfError(value);
                        if (error != null) _firstInvalidFieldKey ??= _cpfFieldKey;
                        return error;
                      },
                      validateTelefone: (value) {
                        final error = telefoneError(value);
                        if (error != null) {
                          _firstInvalidFieldKey ??= _telefoneFieldKey;
                        }
                        return error;
                      },
                      validatePeso: (value) {
                        final error = pesoError(value);
                        if (error != null) _firstInvalidFieldKey ??= _pesoFieldKey;
                        return error;
                      },
                      validateAltura: (value) {
                        final error = alturaError(value);
                        if (error != null) {
                          _firstInvalidFieldKey ??= _alturaFieldKey;
                        }
                        return error;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: _skip,
                      icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                      label: const Text('Pular por agora'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Marca visual do convite — mesma identidade do carregamento (pílula teal
/// com gradiente), com ícone de pessoa para sinalizar o perfil.
class _SetupMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF15857A), Color(0xFF1A5276)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: isDark ? const Color(0x3315857A) : const Color(0x1A15857A),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: const Icon(
        Icons.person_add_alt_1_rounded,
        size: 36,
        color: Colors.white,
      ),
    );
  }
}
