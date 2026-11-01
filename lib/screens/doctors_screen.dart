import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/doctor.dart';
import '../models/doctor_draft.dart';
import '../providers/doctor_provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/prescription_reader_service.dart';
import '../widgets/doctor_form_dialog.dart';
import '../widgets/empty_illustration.dart';
import '../widgets/empty_state.dart';
import '../widgets/media_source_sheet.dart';
import '../widgets/privacy_notice.dart';
import '../widgets/reading_dialog.dart';

class DoctorsScreen extends StatefulWidget {
  const DoctorsScreen({super.key});

  @override
  State<DoctorsScreen> createState() => _DoctorsScreenState();
}

class _DoctorsScreenState extends State<DoctorsScreen> {
  final _searchController = TextEditingController();
  String _selectedSpecialty = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Foto da receita: identifica o médico emissor (nome + CRM) por OCR e
  /// abre o formulário preenchido para conferência — a leitura só preenche,
  /// quem salva é o usuário.
  Future<void> _startDoctorReceiptFlow(BuildContext context) async {
    final consented = await _ensurePrescriptionConsent(context);
    if (!consented || !context.mounted) return;

    final source = await _pickImageSource(context);
    if (source == null || !context.mounted) return;

    final XFile? file;
    try {
      file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
    } catch (_) {
      if (context.mounted) {
        _showMessage('Não foi possível acessar a imagem.');
      }
      return;
    }
    if (file == null) return;

    final bytes = await file.readAsBytes();
    if (!context.mounted) return;

    // Diálogo sem await: só é dispensado quando a leitura termina (padrão
    // do fluxo de tratamentos).
    unawaited(
      showReadingDialog(context, subtitle: 'Procurando o médico que assinou.'),
    );

    PrescriptionDoctor? medico;
    String? error;
    try {
      medico = await PrescriptionReaderService().readDoctorFromImage(
        imageBytes: bytes,
        mimeType: _mimeTypeOf(file),
      );
    } on PrescriptionReaderException catch (e) {
      error = e.message;
    } catch (_) {
      error =
          'Não foi possível ler a receita. Tente outra foto ou cadastre '
          'manualmente.';
    }

    if (!context.mounted) return;
    Navigator.of(
      context,
      rootNavigator: true,
    ).pop(); // fecha o diálogo de leitura

    if (medico == null) {
      _showMessage(error!);
      return;
    }

    final provider = context.read<DoctorProvider>();
    // Variável final: a promoção de nulos sobrevive à captura do builder.
    final medicoDraft = medico;
    final saved = await showDialog<Doctor>(
      context: context,
      builder:
          (dialogContext) => DoctorFormDialog(
            draft: DoctorDraft(
              name: medicoDraft.nome,
              crm: medicoDraft.crm,
              crmState: medicoDraft.uf,
            ),
            knownSpecialties:
                provider.doctors
                    .map((item) => item.specialty)
                    .where((specialty) => specialty.trim().isNotEmpty)
                    .toList(),
          ),
    );
    if (saved != null && context.mounted) {
      await provider.saveDoctor(saved);
    }
  }

  Future<bool> _ensurePrescriptionConsent(BuildContext context) async {
    final userProvider = context.read<UserProfileProvider>();
    if (userProvider.profile?.consentAt != null) return true;

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Autorização necessária'),
            content: const SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Para ler a foto da receita, a imagem é enviada ao nosso '
                    'servidor e descartada após a leitura por OCR. Essa opção '
                    'usa a internet; o cadastro manual não envia nada.',
                  ),
                  SizedBox(height: 12),
                  PrivacyNoticeCard(),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Aceito e autorizo'),
              ),
            ],
          ),
    );

    if (accepted != true || !context.mounted) return false;
    await userProvider.grantConsent();
    return true;
  }

  Future<ImageSource?> _pickImageSource(BuildContext context) {
    return showImageSourceSheet(
      context,
      cameraLabel: 'Tirar foto da receita',
      galleryLabel: 'Escolher imagem da galeria',
    );
  }

  static String _mimeTypeOf(XFile file) {
    final path = file.path.toLowerCase();
    if (path.endsWith('.png')) return 'image/png';
    if (path.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _editDoctor(DoctorProvider provider, [Doctor? doctor]) async {
    final result = await showDialog<Doctor>(
      context: context,
      builder:
          (context) => DoctorFormDialog(
            initialDoctor: doctor,
            knownSpecialties:
                provider.doctors
                    .map((item) => item.specialty)
                    .where((specialty) => specialty.trim().isNotEmpty)
                    .toList(),
          ),
    );
    if (result != null) await provider.saveDoctor(result);
  }

  Future<void> _deleteDoctor(DoctorProvider provider, Doctor doctor) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Excluir médico?'),
            content: Text(
              'Os dados de ${doctor.name} serão removidos deste aparelho.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Excluir'),
              ),
            ],
          ),
    );
    if (confirmed == true) await provider.removeDoctor(doctor.id);
  }

  Future<void> _openMaps(Doctor doctor) async {
    final query = [
      doctor.clinic,
      doctor.fullAddress,
    ].where((part) => part.trim().isNotEmpty).join(', ');
    if (query.isEmpty) {
      _showMessage('Adicione o endereço para abrir o mapa.');
      return;
    }

    final uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': query,
    });
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      _showMessage('Não foi possível abrir o Google Maps.');
    }
  }

  Future<void> _callDoctor(Doctor doctor) async {
    final phone = doctor.phone.replaceAll(RegExp(r'[^+\d]'), '');
    if (phone.isEmpty) {
      _showMessage('Adicione um telefone para ligar.');
      return;
    }

    if (!await launchUrl(Uri(scheme: 'tel', path: phone)) && mounted) {
      _showMessage('Não foi possível iniciar a ligação neste dispositivo.');
    }
  }

  Future<void> _verifyOnCfm(Doctor doctor) async {
    final searchTerms = [
      'Nome: ${doctor.name}',
      if (doctor.crm.isNotEmpty) 'CRM: ${doctor.crm}',
      if (doctor.crmState.isNotEmpty) 'UF: ${doctor.crmState}',
    ].join('\n');
    final launch = launchUrl(
      Uri.https('portal.cfm.org.br', '/busca-medicos/'),
      mode: LaunchMode.externalApplication,
    );

    await Clipboard.setData(ClipboardData(text: searchTerms));
    if (!await launch && mounted) {
      _showMessage(
        'Dados de busca copiados, mas não foi possível abrir o CFM.',
      );
      return;
    }
    _showMessage('Nome, CRM e UF copiados. Preencha a busca no site do CFM.');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DoctorProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final specialties =
            provider.doctors
                .map((doctor) => doctor.specialty.trim())
                .where((specialty) => specialty.isNotEmpty)
                .toSet()
                .toList()
              ..sort();
        if (_selectedSpecialty.isNotEmpty &&
            !specialties.contains(_selectedSpecialty)) {
          _selectedSpecialty = '';
        }
        final doctors = provider.search(
          _searchController.text,
          specialty: _selectedSpecialty,
        );

        return Scaffold(
          appBar: AppBar(title: const Text('Seus médicos')),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${provider.doctors.length} ${provider.doctors.length == 1 ? 'contato salvo' : 'contatos salvos'}',
                            style: Theme.of(
                              context,
                            ).textTheme.bodyMedium?.copyWith(
                              color:
                                  Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: () => _startDoctorReceiptFlow(context),
                              icon: const Icon(Icons.photo_camera_outlined),
                              label: const Text('Foto da receita'),
                            ),
                            FilledButton.icon(
                              onPressed: () => _editDoctor(provider),
                              icon: const Icon(Icons.person_add_alt_1),
                              label: const Text('Adicionar'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Buscar nome, especialidade, CRM ou endereço',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon:
                            _searchController.text.isEmpty
                                ? null
                                : IconButton(
                                  tooltip: 'Limpar busca',
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {});
                                  },
                                  icon: const Icon(Icons.close),
                                ),
                      ),
                    ),
                    if (specialties.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedSpecialty,
                        decoration: const InputDecoration(
                          labelText: 'Filtrar por especialidade',
                          prefixIcon: Icon(Icons.filter_list),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Todas as especialidades'),
                          ),
                          ...specialties.map(
                            (specialty) => DropdownMenuItem(
                              value: specialty,
                              child: Text(specialty),
                            ),
                          ),
                        ],
                        onChanged:
                            (value) => setState(
                              () => _selectedSpecialty = value ?? '',
                            ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    if (provider.doctors.isEmpty)
                      EmptyState(
                        icon: Icons.medical_services_outlined,
                        illustration: EmptyIllustrationKind.stethoscope,
                        title: 'Seu catálogo começa aqui',
                        description:
                            'Salve médicos, especialidades, contatos e endereços.',
                        actionLabel: 'Cadastrar primeiro médico',
                        actionIcon: Icons.person_add_alt_1,
                        onAction: () => _editDoctor(provider),
                        secondaryActionLabel: 'Foto da receita',
                        onSecondaryAction:
                            () => _startDoctorReceiptFlow(context),
                      )
                    else if (doctors.isEmpty)
                      const _NoSearchResults()
                    else
                      ...doctors.map(
                        (doctor) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _DoctorTile(
                            doctor: doctor,
                            onCall: () => _callDoctor(doctor),
                            onVerifyCfm: () => _verifyOnCfm(doctor),
                            onMaps: () => _openMaps(doctor),
                            onEdit: () => _editDoctor(provider, doctor),
                            onDelete: () => _deleteDoctor(provider, doctor),
                          ),
                        ),
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
}

class _DoctorTile extends StatelessWidget {
  const _DoctorTile({
    required this.doctor,
    required this.onCall,
    required this.onVerifyCfm,
    required this.onMaps,
    required this.onEdit,
    required this.onDelete,
  });

  final Doctor doctor;
  final VoidCallback onCall;
  final VoidCallback onVerifyCfm;
  final VoidCallback onMaps;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = [
      doctor.specialty,
      doctor.crmLabel,
    ].where((value) => value.isNotEmpty).join(' · ');
    final location = [
      doctor.clinic,
      doctor.fullAddress,
    ].where((value) => value.isNotEmpty).join(' · ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              foregroundColor: theme.colorScheme.onPrimaryContainer,
              child: const Icon(Icons.medical_services_outlined),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doctor.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          subtitle.isEmpty
                              ? 'Consulta pública no CFM'
                              : subtitle,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Verificar gratuitamente no CFM',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 36,
                          height: 36,
                        ),
                        onPressed: onVerifyCfm,
                        icon: const Icon(Icons.verified_outlined, size: 20),
                      ),
                    ],
                  ),
                  if (doctor.phone.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(doctor.phone, style: theme.textTheme.bodyMedium),
                  ],
                  if (location.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      location,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (doctor.healthPlans.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      'Convênios: ${doctor.healthPlans}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Ligar',
              onPressed: doctor.phone.isEmpty ? null : onCall,
              icon: const Icon(Icons.call_outlined),
            ),
            IconButton(
              tooltip: 'Abrir no Google Maps',
              onPressed:
                  doctor.fullAddress.isEmpty && doctor.clinic.isEmpty
                      ? null
                      : onMaps,
              icon: const Icon(Icons.map_outlined),
            ),
            PopupMenuButton<String>(
              tooltip: 'Mais ações',
              onSelected: (value) {
                if (value == 'edit') onEdit();
                if (value == 'delete') onDelete();
              },
              itemBuilder:
                  (context) => const [
                    PopupMenuItem(value: 'edit', child: Text('Editar')),
                    PopupMenuItem(value: 'delete', child: Text('Excluir')),
                  ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NoSearchResults extends StatelessWidget {
  const _NoSearchResults();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Text(
        'Nenhum médico corresponde a essa busca.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
