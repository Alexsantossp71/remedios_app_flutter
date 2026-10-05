import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/emergency_contact.dart';
import '../models/user_profile.dart';
import '../providers/user_profile_provider.dart';
import '../screens/health_plans_screen.dart';
import '../widgets/br_input_formatters.dart';
import '../widgets/privacy_notice.dart';
import '../widgets/section_header.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();

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
    _pesoController.text =
        profile?.peso != null ? _formatNumber(profile!.peso!) : '';
    _alturaController.text =
        profile?.altura != null ? _formatNumber(profile!.altura!) : '';
    _observacoesController.text = profile?.observacoes ?? '';
    _dataNascimento = profile?.dataNascimento;
    _tipoSanguineo = profile?.tipoSanguineo;
    _alergias = List.of(profile?.alergias ?? const []);
    _condicoesCronicas = List.of(profile?.condicoesCronicas ?? const []);
    _consentAt = profile?.consentAt;
    _consentGranted = profile?.consentAt != null;
  }

  String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.roundToDouble().toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }

  double? _parseNumber(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed.replaceAll(',', '.'));
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
    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<UserProfileProvider>();
    final now = DateTime.now().toUtc().toIso8601String();

    // LGPD: dados sensíveis só podem ser tratados com consentimento
    // específico e destacado (art. 11).
    if (!_consentGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Autorize o tratamento dos seus dados de saúde para salvar '
              'o perfil.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
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
        peso: _parseNumber(_pesoController.text),
        altura: _parseNumber(_alturaController.text),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Perfil salvo com sucesso!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
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
      builder: (context) => _EmergencyContactDialog(contact: contact),
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
    await context.read<UserProfileProvider>().removeEmergencyContact(contact.id);
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
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
          children: [
            Text(
              'Meu Perfil',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 5),
            Text(
              'Seus dados de saúde, sempre à mão.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            if (profile != null) ...[
              const SizedBox(height: 24),
              _EmergencyCard(profile: profile, contacts: contacts),
            ],
            const SizedBox(height: 28),
            const SectionHeader(title: 'Dados pessoais'),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _nomeController,
                      decoration: const InputDecoration(
                        labelText: 'Nome',
                        hintText: 'Como você quer ser chamado',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      textCapitalization: TextCapitalization.words,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Informe seu nome';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
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
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
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
                          .map((tipo) => DropdownMenuItem(
                                value: tipo,
                                child: Text(tipo.value),
                              ))
                          .toList(),
                      onChanged: (value) {
                        setState(() => _tipoSanguineo = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    _StringListEditor(
                      label: 'Alergias',
                      icon: Icons.warning_amber_outlined,
                      hint: 'Ex: Dipirona, frutos do mar',
                      values: _alergias,
                      onChanged: (values) =>
                          setState(() => _alergias = values),
                    ),
                    const SizedBox(height: 16),
                    _StringListEditor(
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
                            controller: _pesoController,
                            decoration: const InputDecoration(
                              labelText: 'Peso (kg)',
                              hintText: 'Ex: 70',
                              prefixIcon: Icon(Icons.monitor_weight_outlined),
                            ),
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                            validator: _validatePeso,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _alturaController,
                            decoration: const InputDecoration(
                              labelText: 'Altura (m)',
                              hintText: 'Ex: 1.70',
                              prefixIcon: Icon(Icons.height_outlined),
                            ),
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
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
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    if (contacts.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 12),
                        child: Text(
                          'Nenhum contato cadastrado. Adicione alguém de '
                          'confiança.',
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      )
                    else
                      ...[
                        for (var i = 0; i < contacts.length; i++) ...[
                          if (i > 0)
                            const Divider(height: 1, indent: 64, endIndent: 12),
                          ListTile(
                            leading: Icon(
                              Icons.contact_emergency_outlined,
                              color: Theme.of(context).colorScheme.primary,
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
            const SectionHeader(title: 'Planos de saúde'),
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  child: Icon(
                    Icons.health_and_safety,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
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
            ),
            const SizedBox(height: 28),
            const SectionHeader(title: 'Dados e privacidade'),
            const SizedBox(height: 10),
            Card(
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
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
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
  /// verificadores válidos.
  String? _validateCpf(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 11) return 'CPF deve ter 11 dígitos';
    if (RegExp(r'^(\d)\1{10}$').hasMatch(digits)) return 'CPF inválido';

    int sum = 0;
    for (var i = 0; i < 9; i++) {
      sum += int.parse(digits[i]) * (10 - i);
    }
    final d1 = (sum * 10) % 11;
    if ((d1 == 10 ? 0 : d1) != int.parse(digits[9])) return 'CPF inválido';

    sum = 0;
    for (var i = 0; i < 10; i++) {
      sum += int.parse(digits[i]) * (11 - i);
    }
    final d2 = (sum * 10) % 11;
    if ((d2 == 10 ? 0 : d2) != int.parse(digits[10])) return 'CPF inválido';

    return null;
  }

  /// Telefone opcional: se preenchido, precisa ter 10 ou 11 dígitos.
  String? _validateTelefone(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10 || digits.length > 11) {
      return 'Telefone deve ter 10 ou 11 dígitos';
    }
    return null;
  }

  /// Peso opcional: se preenchido, deve ser um número entre 1 e 500 kg.
  String? _validatePeso(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final peso = _parseNumber(value);
    if (peso == null) return 'Informe um peso válido';
    if (peso < 1 || peso > 500) return 'Peso deve estar entre 1 e 500 kg';
    return null;
  }

  /// Altura opcional: se preenchida, deve ser um número entre 0,30 e
  /// 3,00 metros.
  String? _validateAltura(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final altura = _parseNumber(value);
    if (altura == null) return 'Informe uma altura válida';
    if (altura < 0.3 || altura > 3) {
      return 'Altura deve estar entre 0,30 e 3,00 m';
    }
    return null;
  }
}

/// Cartão de emergência com resumo rápido do perfil.
class _EmergencyCard extends StatelessWidget {
  const _EmergencyCard({required this.profile, required this.contacts});

  final UserProfile profile;
  final List<EmergencyContact> contacts;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final mainContact = contacts.isNotEmpty ? contacts.first : null;

    return Card(
      color: colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.medical_information_outlined,
                    color: colorScheme.onErrorContainer, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Cartão de emergência',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _EmergencyRow(
              label: 'Tipo sanguíneo',
              value: profile.tipoSanguineo?.value ?? 'Não informado',
            ),
            const SizedBox(height: 6),
            _EmergencyRow(
              label: 'Alergias',
              value: profile.alergias.isEmpty
                  ? 'Nenhuma'
                  : profile.alergias.length <= 2
                      ? profile.alergias.join(', ')
                      : '${profile.alergias.take(2).join(', ')} (+${profile.alergias.length - 2})',
            ),
            const SizedBox(height: 6),
            _EmergencyRow(
              label: 'Contato de emergência',
              value: mainContact != null
                  ? '${mainContact.nome} — ${mainContact.telefone}'
                  : 'Nenhum cadastrado',
            ),
          ],
        ),
      ),
    );
  }
}

class _EmergencyRow extends StatelessWidget {
  const _EmergencyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color:
                      colorScheme.onErrorContainer.withValues(alpha: 0.75),
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onErrorContainer,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ],
    );
  }
}

/// Editor simples de lista de textos: chips com remoção + campo para adicionar.
class _StringListEditor extends StatefulWidget {
  const _StringListEditor({
    required this.label,
    required this.icon,
    required this.hint,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final String hint;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_StringListEditor> createState() => _StringListEditorState();
}

class _StringListEditorState extends State<_StringListEditor> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (widget.values
        .any((v) => v.toLowerCase() == text.toLowerCase())) {
      _controller.clear();
      return;
    }
    widget.onChanged([...widget.values, text]);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: Icon(widget.icon),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.values.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: widget.values
                    .map((value) => InputChip(
                          label: Text(value),
                          onDeleted: () => widget.onChanged(
                            widget.values
                                .where((v) => v != value)
                                .toList(),
                          ),
                          deleteIcon: const Icon(Icons.close, size: 18),
                        ))
                    .toList(),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 8),
              child: Text('Nenhum item adicionado'),
            ),
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: widget.hint,
              isDense: true,
              border: InputBorder.none,
              suffixIcon: IconButton(
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Adicionar',
                onPressed: _add,
              ),
            ),
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _add(),
          ),
        ],
      ),
    );
  }
}

/// Dialog para criar/editar um contato de emergência.
class _EmergencyContactDialog extends StatefulWidget {
  const _EmergencyContactDialog({this.contact});

  final EmergencyContact? contact;

  @override
  State<_EmergencyContactDialog> createState() =>
      _EmergencyContactDialogState();
}

class _EmergencyContactDialogState extends State<_EmergencyContactDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nomeController;
  late final TextEditingController _parentescoController;
  late final TextEditingController _telefoneController;

  bool get _isEditing => widget.contact != null;

  @override
  void initState() {
    super.initState();
    _nomeController = TextEditingController(text: widget.contact?.nome ?? '');
    _parentescoController =
        TextEditingController(text: widget.contact?.parentesco ?? '');
    _telefoneController =
        TextEditingController(text: widget.contact?.telefone ?? '');
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _parentescoController.dispose();
    _telefoneController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final contact = _isEditing
        ? widget.contact!.copyWith(
            nome: _nomeController.text.trim(),
            parentesco: _parentescoController.text.trim(),
            telefone: _telefoneController.text.trim(),
          )
        : EmergencyContact.create(
            nome: _nomeController.text.trim(),
            parentesco: _parentescoController.text.trim(),
            telefone: _telefoneController.text.trim(),
          );
    Navigator.of(context).pop(contact);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Editar contato' : 'Adicionar contato'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nomeController,
                decoration: const InputDecoration(
                  labelText: 'Nome *',
                  hintText: 'Ex: Maria Silva',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Informe o nome';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _parentescoController,
                decoration: const InputDecoration(
                  labelText: 'Parentesco',
                  hintText: 'Ex: Cônjuge, filho(a), amigo(a)',
                  prefixIcon: Icon(Icons.family_restroom_outlined),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _telefoneController,
                decoration: const InputDecoration(
                  labelText: 'Telefone *',
                  hintText: '(11) 91234-5678',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                keyboardType: TextInputType.phone,
                inputFormatters: [PhoneInputFormatter()],
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Informe o telefone';
                  }
                  final digits =
                      value.replaceAll(RegExp(r'\D'), '');
                  if (digits.length < 10 || digits.length > 11) {
                    return 'Telefone deve ter 10 ou 11 dígitos';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(_isEditing ? 'Salvar' : 'Adicionar'),
        ),
      ],
    );
  }
}
