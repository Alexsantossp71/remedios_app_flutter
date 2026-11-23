import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/emergency_contact.dart';
import '../models/user_profile.dart';
import '../providers/consultation_provider.dart';
import '../providers/doctor_provider.dart';
import '../providers/health_plan_provider.dart';
import '../providers/therapy_provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/backup_file.dart';
import '../services/backup_crypto_service.dart';
import '../services/backup_service.dart';
import '../services/web_reminder_service.dart';
import '../widgets/app_snack_bar.dart';
import '../widgets/section_header.dart';
import 'profile/profile_validators.dart';
import 'profile/widgets/emergency_card.dart';
import 'profile/widgets/emergency_contact_dialog.dart';
import 'profile/widgets/emergency_contacts_card.dart';
import 'profile/widgets/profile_backup_card.dart';
import 'profile/widgets/profile_form_card.dart';
import 'profile/widgets/profile_privacy_card.dart';
import 'profile/widgets/profile_registry_card.dart';
import 'profile/widgets/web_reminder_card.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  // Chave por campo: permite rolar a tela até o primeiro erro de
  // validação quando o usuário toca em "Salvar perfil" — sem isso,
  // um CPF/peso inválido bem acima do botão deixava o toque sem
  // reação visível (o erro aparecia fora da viewport).
  final _nomeFieldKey = GlobalKey();
  final _cpfFieldKey = GlobalKey();
  final _telefoneFieldKey = GlobalKey();
  final _pesoFieldKey = GlobalKey();
  final _alturaFieldKey = GlobalKey();

  /// Primeiro campo que falhou na validação corrente. Os validadores
  /// rodam na ordem visual do formulário, então o primeiro a registrar
  /// é o mais alto na tela — é até lá que a rolagem leva o usuário.
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
  DateTime? _consentAt;

  /// True enquanto um backup está sendo exportado/restaurado.
  bool _backupBusy = false;

  @override
  void initState() {
    super.initState();
    _nomeController = TextEditingController();
    _cpfController = TextEditingController();
    _telefoneController = TextEditingController();
    _pesoController = TextEditingController();
    _alturaController = TextEditingController();
    _observacoesController = TextEditingController();
    _loadFromProfile(context.read<UserProfileProvider>().profile);
  }

  void _loadFromProfile(UserProfile? profile) {
    _nomeController.text = profile?.nome ?? '';
    _cpfController.text = profile?.cpf ?? '';
    _telefoneController.text = profile?.telefone ?? '';
    _pesoController.text = profile?.peso != null
        ? formatNumber(profile!.peso!)
        : '';
    _alturaController.text = profile?.altura != null
        ? formatNumber(profile!.altura!)
        : '';
    _observacoesController.text = profile?.observacoes ?? '';
    _dataNascimento = profile?.dataNascimento;
    _tipoSanguineo = profile?.tipoSanguineo;
    _alergias = List.of(profile?.alergias ?? const []);
    _condicoesCronicas = List.of(profile?.condicoesCronicas ?? const []);
    _consentAt = profile?.consentAt;
    _consentGranted = profile?.consentAt != null;
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

  Future<void> _saveProfile() async {
    _firstInvalidFieldKey = null;
    if (!_formKey.currentState!.validate()) {
      await _revealInvalidField();
      if (mounted) {
        showAppSnackBar(
          context,
          'Verifique os campos destacados em vermelho para salvar o perfil.',
          type: AppSnackType.error,
        );
      }
      return;
    }

    final provider = context.read<UserProfileProvider>();
    final now = DateTime.now().toUtc().toIso8601String();

    // LGPD: dados sensíveis só podem ser tratados com consentimento
    // específico e destacado (art. 11).
    if (!_consentGranted) {
      if (mounted) {
        showAppSnackBar(
          context,
          'Autorize o tratamento dos seus dados de saúde para salvar o '
          'perfil.',
        );
      }
      return;
    }

    final consentAt = provider.profile?.consentAt ?? DateTime.now().toUtc();

    await provider.saveProfile(
      UserProfile(
        nome: _nomeController.text.trim(),
        cpf: _cpfController.text.trim().isNotEmpty
            ? _cpfController.text.trim()
            : null,
        dataNascimento: _dataNascimento,
        fotoPath: provider.profile?.fotoPath,
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
        consentAt: consentAt,
        createdAt: provider.profile?.createdAt ?? now,
        updatedAt: now,
      ),
    );

    if (mounted) {
      setState(() => _consentAt = consentAt);
      showAppSnackBar(
        context,
        'Perfil salvo com sucesso!',
        type: AppSnackType.success,
      );
    }
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

  /// Solicita uma senha que nunca é armazenada pelo aplicativo.
  Future<String?> _askBackupPassword({required bool confirm}) async {
    final password = TextEditingController();
    final confirmation = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(confirm ? 'Proteger backup' : 'Desbloquear backup'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: password,
                obscureText: true,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Senha do backup',
                  helperText: 'Use pelo menos 12 caracteres.',
                ),
                validator: (value) => (value ?? '').length < 12
                    ? 'A senha precisa ter ao menos 12 caracteres.'
                    : null,
              ),
              if (confirm) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: confirmation,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Confirme a senha',
                  ),
                  validator: (value) => value != password.text
                      ? 'As senhas não coincidem.'
                      : null,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(dialogContext).pop(password.text);
              }
            },
            child: Text(confirm ? 'Criptografar' : 'Desbloquear'),
          ),
        ],
      ),
    );
    password.dispose();
    confirmation.dispose();
    return result;
  }

  /// Exporta todos os dados em um envelope criptografado com senha.
  Future<void> _exportBackup() async {
    final password = await _askBackupPassword(confirm: true);
    if (password == null || !mounted) return;
    setState(() => _backupBusy = true);
    try {
      final envelope = await BackupService.instance.exportAll();
      final encrypted = await BackupCryptoService.instance.encrypt(
        envelope.toJson(),
        password,
      );
      final savedAs = await saveBackupJson(jsonEncode(encrypted));
      if (!mounted) return;
      showAppSnackBar(
        context,
        'Backup criptografado salvo: $savedAs. Guarde a senha em local seguro.',
        type: AppSnackType.success,
      );
    } on BackupCryptoException catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, e.message, type: AppSnackType.error);
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        'Não foi possível gerar o backup criptografado. Tente novamente.',
        type: AppSnackType.error,
      );
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  /// Restaura um backup .json escolhido pelo usuário, substituindo todos
  /// os dados atuais, e recarrega os cinco providers.
  Future<void> _restoreBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restaurar backup'),
        content: const Text(
          'Restaurar substitui TUDO que está no app hoje (tratamentos, '
          'doses, médicos, consultas, planos e perfil) pelo conteúdo do '
          'arquivo escolhido. Esta ação não pode ser desfeita. Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Escolher arquivo e restaurar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final String? text;
    try {
      text = await pickBackupJsonText();
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          'Não foi possível ler o arquivo escolhido.',
          type: AppSnackType.error,
        );
      }
      return;
    }
    if (text == null || !mounted) return; // usuário cancelou o seletor

    setState(() => _backupBusy = true);
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw const BackupFormatException('O arquivo não contém um backup.');
      }
      final Map<String, dynamic> backup;
      if (BackupCryptoService.instance.isEncrypted(decoded)) {
        final password = await _askBackupPassword(confirm: false);
        if (password == null || !mounted) return;
        backup = await BackupCryptoService.instance.decrypt(decoded, password);
      } else {
        // Compatibilidade: backups JSON antigos continuam restauráveis.
        backup = decoded;
      }
      final envelope = BackupEnvelope.fromJson(backup);
      final summary = await BackupService.instance.restore(envelope);
      if (!mounted) return;

      // Captura os cinco providers antes dos awaits (BuildContext não
      // atravessa gaps assíncronos) e recarrega a partir do banco restaurado.
      final therapy = context.read<TherapyProvider>();
      final doctor = context.read<DoctorProvider>();
      final consultation = context.read<ConsultationProvider>();
      final healthPlan = context.read<HealthPlanProvider>();
      final userProfile = context.read<UserProfileProvider>();
      await therapy.initialize();
      await doctor.initialize();
      await consultation.initialize();
      await healthPlan.initialize();
      await userProfile.initialize();
      if (!mounted) return;
      setState(() {
        _loadFromProfile(userProfile.profile);
      });
      showAppSnackBar(
        context,
        'Backup restaurado: ${summary.describe()}.',
        type: AppSnackType.success,
      );
    } on BackupFormatException catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          'Arquivo inválido: ${e.message}',
          type: AppSnackType.error,
        );
      }
    } on BackupCryptoException catch (e) {
      if (mounted) {
        showAppSnackBar(context, e.message, type: AppSnackType.error);
      }
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          'Falha ao restaurar o backup. Nada foi alterado.',
          type: AppSnackType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _confirmDeleteAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apagar meus dados'),
        content: const Text(
          'Seu perfil e seus contatos de emergência serão apagados '
          'permanentemente deste dispositivo. Esta ação não pode ser '
          'desfeita. Deseja continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Apagar tudo'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await context.read<UserProfileProvider>().deleteAllData();
      setState(() => _loadFromProfile(null));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Seus dados foram apagados.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _editContact([EmergencyContact? contact]) async {
    final provider = context.read<UserProfileProvider>();
    final result = await showDialog<EmergencyContact>(
      context: context,
      builder: (context) => EmergencyContactDialog(contact: contact),
    );
    if (result == null) return;

    if (contact == null) {
      await provider.addEmergencyContact(result);
    } else {
      await provider.updateEmergencyContact(result);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            contact == null
                ? '${result.nome} adicionado aos contatos de emergência.'
                : 'Contato atualizado.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _removeContact(EmergencyContact contact) async {
    await context.read<UserProfileProvider>().removeEmergencyContact(
      contact.id,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${contact.nome} removido.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UserProfileProvider>();
    final profile = provider.profile;
    final contacts = provider.emergencyContacts;

    return SafeArea(
      child: Center(
        // Design audit: em desktop (1440px), formulário de coluna única com
        // 1300px de largura é anti-ergonômico. Constrain a 560px e centraliza.
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Form(
            key: _formKey,
            child: Scrollbar(
              child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
          children: [
            Text(
              'Meu Perfil',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            Text(
              'Seus dados de saúde, sempre à mão.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            // Cartão de emergência ao vivo: reflete o que está no formulário
            // agora (não só o que já foi salvo) — alergia adicionada aparece
            // no cartão no mesmo instante. Aparece desde o primeiro uso
            // quando o usuário começa a preencher dados de emergência.
            if (profile != null ||
                _tipoSanguineo != null ||
                _alergias.isNotEmpty ||
                _condicoesCronicas.isNotEmpty) ...[
              const SizedBox(height: 18),
              EmergencyCard(
                tipoSanguineo: _tipoSanguineo,
                alergias: _alergias,
                condicoesCronicas: _condicoesCronicas,
                contacts: contacts,
              ),
            ],
            const SizedBox(height: 20),
            const SectionHeader(title: 'Dados pessoais'),
            const SizedBox(height: 10),
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
              consentAt: _consentAt,
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
              onSave: _saveProfile,
              onInvalidField: (fieldKey) => _firstInvalidFieldKey ??= fieldKey,
              validateCpf: _validateCpf,
              validateTelefone: _validateTelefone,
              validatePeso: _validatePeso,
              validateAltura: _validateAltura,
            ),
            const SizedBox(height: 20),
            const SectionHeader(title: 'Contatos de emergência'),
            const SizedBox(height: 10),
            EmergencyContactsCard(
              contacts: contacts,
              isDark: Theme.of(context).brightness == Brightness.dark,
              onAdd: () => _editContact(),
              onEdit: (contact) => _editContact(contact),
              onRemove: (contact) => _removeContact(contact),
            ),
            const SizedBox(height: 20),
            const SectionHeader(title: 'Meus cadastros'),
            const SizedBox(height: 10),
            const ProfileRegistryCard(),
            const SizedBox(height: 20),
            if (WebReminderService.instance.isSupported) ...[
              const SectionHeader(title: 'Lembretes no navegador'),
              const SizedBox(height: 10),
              WebReminderCard(),
              const SizedBox(height: 20),
            ],
            const SectionHeader(title: 'Backup e restauração'),
            const SizedBox(height: 10),
            ProfileBackupCard(
              busy: _backupBusy,
              onExport: _exportBackup,
              onRestore: _restoreBackup,
            ),
            const SizedBox(height: 20),
            const SectionHeader(title: 'Dados e privacidade'),
            const SizedBox(height: 10),
            ProfilePrivacyCard(onDeleteAll: _confirmDeleteAllData),
            const SizedBox(height: 18),
            Center(
              child: Text(
                'Remédio na Hora v3.0',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
        ),
      ),
      ),
    );
  }

  /// CPF opcional: se preenchido, precisa ter 11 dígitos com dígitos
  /// verificadores válidos. Registra o campo como primeiro inválido.
  String? _validateCpf(String? value) {
    final error = cpfError(value);
    if (error != null) _firstInvalidFieldKey ??= _cpfFieldKey;
    return error;
  }

  /// Telefone opcional: se preenchido, precisa ter 10 ou 11 dígitos.
  String? _validateTelefone(String? value) {
    final error = telefoneError(value);
    if (error != null) _firstInvalidFieldKey ??= _telefoneFieldKey;
    return error;
  }

  /// Peso opcional: se preenchido, deve ser um número entre 1 e 500 kg.
  String? _validatePeso(String? value) {
    final error = pesoError(value);
    if (error != null) _firstInvalidFieldKey ??= _pesoFieldKey;
    return error;
  }

  /// Altura opcional: se preenchida, deve ser um número entre 0,30 e
  /// 3,00 metros.
  String? _validateAltura(String? value) {
    final error = alturaError(value);
    if (error != null) _firstInvalidFieldKey ??= _alturaFieldKey;
    return error;
  }
}
