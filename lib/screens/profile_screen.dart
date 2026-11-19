import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/emergency_contact.dart';
import '../models/user_profile.dart';
import '../providers/consultation_provider.dart';
import '../providers/doctor_provider.dart';
import '../providers/health_plan_provider.dart';
import '../providers/therapy_provider.dart';
import '../providers/user_profile_provider.dart';
import '../core/design/brand_colors.dart';
import '../core/design/record_card.dart';
import '../screens/doctors_screen.dart';
import '../screens/exams_screen.dart';
import '../screens/lab_results_screen.dart';
import '../screens/health_plans_screen.dart';
import '../screens/progress_screen.dart';
import '../services/backup_file.dart';
import '../services/backup_crypto_service.dart';
import '../services/backup_service.dart';
import '../services/web_reminder_service.dart';
import '../widgets/app_snack_bar.dart';
import '../widgets/br_input_formatters.dart';
import '../widgets/privacy_notice.dart';
import '../widgets/section_header.dart';
import 'profile/profile_validators.dart';
import 'profile/widgets/cadastro_icon_box.dart';
import 'profile/widgets/emergency_card.dart';
import 'profile/widgets/emergency_contact_dialog.dart';
import 'profile/widgets/string_list_editor.dart';
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

  final _dateFormat = DateFormat('dd/MM/yyyy', 'pt_BR');

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
      final data = await BackupService.instance.exportAll();
      final encrypted = await BackupCryptoService.instance.encrypt(
        data,
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
      final summary = await BackupService.instance.restore(backup);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
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
              const SizedBox(height: 24),
              EmergencyCard(
                tipoSanguineo: _tipoSanguineo,
                alergias: _alergias,
                condicoesCronicas: _condicoesCronicas,
                contacts: contacts,
              ),
            ],
            const SizedBox(height: 28),
            const SectionHeader(title: 'Dados pessoais'),
            const SizedBox(height: 10),
            RecordCard(
              padding: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      key: _nomeFieldKey,
                      controller: _nomeController,
                      decoration: const InputDecoration(
                        labelText: 'Nome',
                        hintText: 'Como você quer ser chamado',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      textCapitalization: TextCapitalization.words,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          _firstInvalidFieldKey ??= _nomeFieldKey;
                          return 'Informe seu nome';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: _cpfFieldKey,
                      controller: _cpfController,
                      decoration: const InputDecoration(
                        labelText: 'CPF',
                        hintText: '000.000.000-00',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [CpfInputFormatter()],
                      validator: _validateCpf,
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _selectBirthDate,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Data de nascimento',
                          prefixIcon: Icon(Icons.cake_outlined),
                          suffixIcon: Icon(Icons.calendar_today_outlined),
                        ),
                        child: Text(
                          _dataNascimento != null
                              ? _dateFormat.format(_dataNascimento!)
                              : 'Toque para selecionar',
                          style: _dataNascimento != null
                              ? null
                              : TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: _telefoneFieldKey,
                      controller: _telefoneController,
                      decoration: const InputDecoration(
                        labelText: 'Telefone',
                        hintText: '(11) 91234-5678',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                      keyboardType: TextInputType.phone,
                      inputFormatters: [PhoneInputFormatter()],
                      validator: _validateTelefone,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<TipoSanguineo>(
                      initialValue: _tipoSanguineo,
                      decoration: const InputDecoration(
                        labelText: 'Tipo sanguíneo',
                        prefixIcon: Icon(Icons.bloodtype_outlined),
                      ),
                      items: TipoSanguineo.values
                          .map(
                            (tipo) => DropdownMenuItem(
                              value: tipo,
                              child: Text(tipo.value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() => _tipoSanguineo = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    StringListEditor(
                      label: 'Alergias',
                      icon: Icons.warning_amber_outlined,
                      hint: 'Ex: Dipirona, frutos do mar',
                      values: _alergias,
                      onChanged: (values) => setState(() => _alergias = values),
                    ),
                    const SizedBox(height: 16),
                    StringListEditor(
                      label: 'Condições crônicas',
                      icon: Icons.monitor_heart_outlined,
                      hint: 'Ex: Hipertensão, diabetes',
                      values: _condicoesCronicas,
                      onChanged: (values) =>
                          setState(() => _condicoesCronicas = values),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: _pesoFieldKey,
                            controller: _pesoController,
                            decoration: const InputDecoration(
                              labelText: 'Peso (kg)',
                              hintText: 'Ex: 70',
                              prefixIcon: Icon(Icons.monitor_weight_outlined),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            validator: _validatePeso,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            key: _alturaFieldKey,
                            controller: _alturaController,
                            decoration: const InputDecoration(
                              labelText: 'Altura (m)',
                              hintText: 'Ex: 1.70',
                              prefixIcon: Icon(Icons.height_outlined),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            validator: _validateAltura,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _observacoesController,
                      decoration: const InputDecoration(
                        labelText: 'Observações',
                        hintText: 'Informações relevantes sobre sua saúde',
                        prefixIcon: Icon(Icons.notes_outlined),
                      ),
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 20),
                    const PrivacyNoticeCard(),
                    const SizedBox(height: 12),
                    ConsentCheckbox(
                      value: _consentGranted,
                      grantedAt: _consentAt,
                      onChanged: (value) {
                        setState(() => _consentGranted = value ?? false);
                      },
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _saveProfile,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Salvar perfil'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            const SectionHeader(title: 'Contatos de emergência'),
            const SizedBox(height: 10),
            RecordCard(
              padding: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    if (contacts.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 12,
                        ),
                        child: Text(
                          'Nenhum contato cadastrado. Adicione alguém de '
                          'confiança.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      )
                    else ...[
                      for (var i = 0; i < contacts.length; i++) ...[
                        if (i > 0)
                          const Divider(height: 1, indent: 64, endIndent: 12),
                        ListTile(
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              // Caixa de ícone com véu vermelho — contexto
                              // de emergência no PWA usa o brand.red.
                              color: BrandColors.red.withValues(
                                alpha: isDark ? .16 : .10,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.contact_emergency_outlined,
                              color: BrandColors.red,
                              size: 22,
                            ),
                          ),
                          title: Text(contacts[i].nome),
                          subtitle: Text(
                            [
                              if (contacts[i].parentesco.isNotEmpty)
                                contacts[i].parentesco,
                              contacts[i].telefone,
                            ].join(' • '),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: 'Editar',
                                onPressed: () => _editContact(contacts[i]),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: 'Remover',
                                onPressed: () => _removeContact(contacts[i]),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _editContact(),
                        icon: const Icon(Icons.add),
                        label: const Text('Adicionar contato'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            const SectionHeader(title: 'Meus cadastros'),
            const SizedBox(height: 10),
            RecordCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: CadastroIconBox(
                      icon: Icons.medical_services_outlined,
                      isDark: isDark,
                    ),
                    title: const Text('Médicos'),
                    subtitle: const Text('Seu catálogo de médicos e contatos'),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const DoctorsScreen(),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: CadastroIconBox(
                      icon: Icons.science_outlined,
                      isDark: isDark,
                    ),
                    title: const Text('Exames'),
                    subtitle: const Text(
                      'Do pedido do médico ao laudo, com leitura por IA',
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const ExamsScreen(),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: CadastroIconBox(
                      icon: Icons.biotech_outlined,
                      isDark: isDark,
                    ),
                    title: const Text('Resultados de laboratório'),
                    subtitle: const Text(
                      'Laudos, valores e evolução dos exames',
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const LabResultsScreen(),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: CadastroIconBox(
                      icon: Icons.health_and_safety,
                      isDark: isDark,
                    ),
                    title: const Text('Planos e convênios'),
                    subtitle: const Text('Gerencie seus planos de saúde'),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const HealthPlansScreen(),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: CadastroIconBox(
                      icon: Icons.insights_outlined,
                      isDark: isDark,
                    ),
                    title: const Text('Progresso'),
                    subtitle: const Text('Constância e histórico de doses'),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const ProgressScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            if (WebReminderService.instance.isSupported) ...[
              const SectionHeader(title: 'Lembretes no navegador'),
              const SizedBox(height: 10),
              WebReminderCard(),
              const SizedBox(height: 28),
            ],
            const SectionHeader(title: 'Backup e restauração'),
            const SizedBox(height: 10),
            RecordCard(
              padding: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Exporte um backup criptografado com senha para guardar ou levar '
                      'para outro aparelho. A senha não é salva pelo app; '
                      'sem ela, não será possível restaurar o arquivo. '
                      'Backups JSON antigos também podem ser restaurados.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _backupBusy ? null : _exportBackup,
                            icon: _backupBusy
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.download_outlined),
                            label: const Text('Exportar'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _backupBusy ? null : _restoreBackup,
                            icon: const Icon(Icons.restore_outlined),
                            label: const Text('Restaurar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            const SectionHeader(title: 'Dados e privacidade'),
            const SizedBox(height: 10),
            RecordCard(
              padding: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Seus dados ficam armazenados apenas neste dispositivo. '
                      'A qualquer momento você pode apagá-los por completo '
                      '(LGPD).',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      onPressed: _confirmDeleteAllData,
                      icon: const Icon(Icons.delete_forever_outlined),
                      label: const Text('Apagar meus dados'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
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
