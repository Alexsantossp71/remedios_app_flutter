import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../core/lab_values.dart';
import '../models/consultation.dart';
import '../models/doctor.dart';
import '../models/doctor_draft.dart';
import '../models/exam.dart';
import '../models/health_plan.dart';
import '../models/prescription_record.dart';
import '../models/treatment.dart';
import '../providers/consultation_provider.dart';
import '../providers/doctor_provider.dart';
import '../providers/exam_provider.dart';
import '../providers/health_plan_provider.dart';
import '../providers/lab_result_provider.dart';
import '../providers/therapy_provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/ai_proxy_client.dart';
import '../services/ai_service.dart';
import '../services/card_reader_service.dart';
import '../services/doctor_matching.dart';
import '../services/prescription_reader_service.dart';
import '../widgets/add_health_plan_sheet.dart';
import '../widgets/app_snack_bar.dart';
import '../widgets/consultation_form_dialog.dart';
import '../widgets/doctor_form_dialog.dart';
import '../widgets/exam_form_dialog.dart';
import '../widgets/health_plan_form_dialog.dart';
import '../widgets/lab_result_review_sheet.dart';
import '../widgets/media_source_sheet.dart';
import '../widgets/privacy_notice.dart';
import '../widgets/reading_dialog.dart';
import '../widgets/stepped_form_sheet.dart';
import '../widgets/treatment_form_dialog.dart';
import 'health_plan_review_screen.dart';
import 'prescription_review_screen.dart';

/// Fluxos de cadastro compartilhados pelo menu central “+” e pelas telas.
///
/// Regra de ouro (igual em todos): a leitura por IA só PREENCHE — quem revisa
/// e salva é sempre o usuário. As telas chamam estas funções em vez de
/// manter cópias locais, e o menu central “+” ganha o mesmo poder das telas:
/// qualquer cadastro com leitura de foto está a um toque daqui.
///
/// ⚠️ Os fluxos de foto dependem de [ImagePicker], que não funciona nos
/// testes de widget — os testes cobrem até a folha de escolha/fonte.

// ── Infra compartilhada ────────────────────────────────────────────────────

/// LGPD: a leitura por IA envia a imagem ao servidor, então o consentimento
/// específico é obrigatório antes de abrir o seletor. Pergunta uma vez e
/// grava o consentimento no perfil.
Future<bool> ensureImageReadingConsent(
  BuildContext context, {
  required String explanation,
}) async {
  final userProvider = context.read<UserProfileProvider>();
  if (userProvider.profile?.consentAt != null) return true;

  final accepted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Autorização necessária'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(explanation),
            const SizedBox(height: 12),
            const PrivacyNoticeCard(),
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

/// Câmera × galeria, com rótulos do contexto (receita, cartão, laudo…).
Future<ImageSource?> pickReadingImageSource(
  BuildContext context, {
  required String cameraLabel,
  required String galleryLabel,
}) {
  return showImageSourceSheet(
    context,
    cameraLabel: cameraLabel,
    galleryLabel: galleryLabel,
  );
}

/// Abre o seletor de imagem com os limites padrão de leitura
/// (1600px, qualidade 85). `null` = cancelou ou o seletor falhou.
Future<XFile?> pickReadingImage(
  BuildContext context,
  ImageSource source,
) async {
  try {
    return await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
  } catch (_) {
    if (context.mounted) {
      showAppSnackBar(context, 'Não foi possível acessar a imagem.');
    }
    return null;
  }
}

/// MIME da imagem para o proxy: atributo real quando existe, extensão do
/// arquivo como plano B e JPEG como rede de segurança.
String imageMimeTypeOf(XFile file) {
  final mimeType = file.mimeType;
  if (mimeType != null && mimeType.startsWith('image/')) return mimeType;
  final name = file.name.toLowerCase();
  if (name.endsWith('.png')) return 'image/png';
  if (name.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}

/// Diálogo de leitura sem await: `showDialog` só completa quando a rota é
/// dispensada, e quem a dispensa é o pop depois da leitura. Awaitar travaria
/// a tela para sempre sem nunca enviar a imagem.
void showUnawaitedReadingDialog(
  BuildContext context, {
  String title = 'Lendo receita…',
  String subtitle = 'Pode levar alguns segundos.',
}) {
  unawaited(showReadingDialog(context, title: title, subtitle: subtitle));
}

void closeReadingDialog(BuildContext context) {
  Navigator.of(context, rootNavigator: true).pop();
}

// ── Medicamentos ───────────────────────────────────────────────────────────

/// Cadastro manual de tratamento: formulário em passos e salvamento. O
/// catálogo de médicos acompanha o formulário para a seção "Quem receitou".
Future<void> createTreatmentManually(BuildContext context) async {
  final result = await showSteppedFormSheet<Treatment>(
    context: context,
    builder: (_) => TreatmentFormDialog(
      doctorCatalog: context.read<DoctorProvider>().doctors.toList(),
    ),
  );
  if (result == null || !context.mounted) return;

  await saveTreatmentWithPrescriber(context, result);
  unawaited(HapticFeedback.mediumImpact());
  if (!context.mounted) return;
  showAppSnackBar(
    context,
    'Tratamento salvo. Bom começo!',
    type: AppSnackType.success,
  );
}

/// Salva o tratamento (novo ou edição) e mantém o registro de "quem
/// receitou e em que dia": vincula ao catálogo de médicos (encontra pelo
/// nome/CRM ou cria) e grava um registro no histórico quando há receita.
/// Na edição, o registro só nasce quando a receita mudou (renovação) —
/// salvar sem mexer não multiplica registros idênticos.
///
/// Ordem importa: o tratamento é gravado **antes** do registro de receita —
/// `treatment_prescriptions` tem foreign key para `treatments` e o banco
/// roda com `PRAGMA foreign_keys = ON`; registrar a receita antes de o
/// tratamento existir viola a constraint (code 787) e perde o cadastro.
Future<void> saveTreatmentWithPrescriber(
  BuildContext context,
  Treatment treatment, {
  Treatment? previous,
  PrescriptionSource source = PrescriptionSource.manual,
}) async {
  final therapy = context.read<TherapyProvider>();
  var finalTreatment = treatment;

  if (treatment.hasPrescriber) {
    final doctor = await _findOrCreatePrescriberDoctor(context, treatment);
    finalTreatment = treatment.copyWith(prescriberDoctorId: doctor.id);
  }

  // 1. Tratamento primeiro — o registro de receita referencia o seu id.
  if (previous == null) {
    await therapy.addTreatment(finalTreatment);
  } else {
    await therapy.updateTreatment(finalTreatment);
  }

  // 2. Registro no histórico, quando há receita (e mudou, na edição).
  if (finalTreatment.hasPrescriber) {
    final unchanged =
        previous != null &&
        Treatment.samePrescription(previous, finalTreatment);
    if (!unchanged) {
      await therapy.recordPrescription(
        PrescriptionRecord(
          id: const Uuid().v4(),
          treatmentId: finalTreatment.id,
          doctorId: finalTreatment.prescriberDoctorId,
          doctorName: finalTreatment.prescriberName,
          doctorCrm: finalTreatment.prescriberCrm,
          doctorCrmState: finalTreatment.prescriberCrmState,
          prescribedOn: finalTreatment.prescribedOn ?? DateTime.now(),
          source: source,
          createdAt: DateTime.now(),
        ),
      );
    }
  }
}

/// Médico do registro de receita: reutiliza quem já está no catálogo
/// (mesmo nome e, quando o usuário digitou CRM, o mesmo CRM); só cria
/// quando não há correspondente — CRM diferente não vira "atualização
/// silenciosa" de outro médico, vira registro novo conferido. A regra de
/// casamento é a compartilhada em [findDoctorInCatalog] (CRM+UF forte e
/// nome normalizado) — a mesma usada pela foto da receita e pelo pedido
/// de exame.
Future<Doctor> _findOrCreatePrescriberDoctor(
  BuildContext context,
  Treatment treatment,
) async {
  final provider = context.read<DoctorProvider>();
  final name = treatment.prescriberName.trim();
  final crm = treatment.prescriberCrm.trim();
  final existing = findDoctorInCatalog(
    provider.doctors,
    name: name,
    crm: crm,
    crmState: treatment.prescriberCrmState,
  );
  if (existing != null) return existing;
  final created = Doctor(
    id: const Uuid().v4(),
    name: name,
    crm: crm,
    crmState: treatment.prescriberCrmState.trim().toUpperCase(),
  );
  await provider.saveDoctor(created);
  return created;
}

/// Texto LGPD do fluxo de receita (compartilhado por medicamentos e médicos).
const String prescriptionConsentText =
    'Para ler a foto da receita, a imagem é enviada ao nosso servidor e '
    'descartada após a leitura por OCR. Essa opção usa a internet; o '
    'cadastro manual não envia nada.';

/// Foto da receita: ler, conferir e salvar um tratamento por medicamento.
/// Cada rascunho passa pelo formulário de tratamento — a leitura só
/// preenche, quem salva é o usuário.
Future<void> createTreatmentFromPrescription(BuildContext context) async {
  final consented = await ensureImageReadingConsent(
    context,
    explanation: prescriptionConsentText,
  );
  if (!consented || !context.mounted) return;

  final source = await pickReadingImageSource(
    context,
    cameraLabel: 'Tirar foto da receita',
    galleryLabel: 'Escolher imagem da galeria',
  );
  if (source == null || !context.mounted) return;

  final file = await pickReadingImage(context, source);
  if (file == null || !context.mounted) return;

  final bytes = await file.readAsBytes();
  if (!context.mounted) return;

  showUnawaitedReadingDialog(context);

  PrescriptionReadResult? result;
  String? error;
  try {
    result = await PrescriptionReaderService().readPrescription(
      imageBytes: bytes,
      mimeType: imageMimeTypeOf(file),
    );
  } on PrescriptionReaderException catch (e) {
    error = e.message;
  } catch (_) {
    error =
        'Não foi possível ler a receita. Tente outra foto ou cadastre '
        'manualmente.';
  }

  if (!context.mounted) return;
  closeReadingDialog(context); // fecha o diálogo de leitura

  if (result == null) {
    showAppSnackBar(context, error!);
    return;
  }

  final drafts = await Navigator.of(context).push<PrescriptionReviewOutcome>(
    MaterialPageRoute(
      builder: (_) => PrescriptionReviewScreen(result: result!),
    ),
  );
  if (drafts == null || drafts.drafts.isEmpty || !context.mounted) return;

  final doctorCatalog = context.read<DoctorProvider>().doctors.toList();
  for (final draft in drafts.drafts) {
    if (!context.mounted) return;
    final saved = await showSteppedFormSheet<Treatment>(
      context: context,
      builder: (_) => TreatmentFormDialog(
        draft: draft,
        prescriptionDoctor: drafts.medico,
        doctorCatalog: doctorCatalog,
      ),
    );
    if (saved == null || !context.mounted) continue;
    await saveTreatmentWithPrescriber(
      context,
      saved,
      source: PrescriptionSource.prescriptionPhoto,
    );
  }
}

// ── Consultas ──────────────────────────────────────────────────────────────

/// Cadastro de consulta (sem leitura de foto — o pedido vem do usuário).
Future<void> createConsultation(BuildContext context) async {
  final result = await showSteppedFormSheet<Consultation>(
    context: context,
    builder: (_) => const ConsultationFormDialog(),
  );
  if (result == null || !context.mounted) return;
  await context.read<ConsultationProvider>().saveConsultation(result);
  if (!context.mounted) return;
  showAppSnackBar(context, 'Consulta agendada.', type: AppSnackType.success);
}

// ── Exames ─────────────────────────────────────────────────────────────────

/// Cadastro de exame. A leitura do pedido por IA vive DENTRO do formulário
/// (1º passo), então aqui o formulário abre direto.
Future<void> createExam(BuildContext context) async {
  final result = await showSteppedFormSheet<Exam>(
    context: context,
    builder: (_) => const ExamFormDialog(),
  );
  if (result == null || !context.mounted) return;
  await context.read<ExamProvider>().saveExam(result);
  if (!context.mounted) return;
  showAppSnackBar(context, 'Exame registrado.', type: AppSnackType.success);
}

// ── Laudos (resultados de laboratório) ─────────────────────────────────────

/// Laudo digitado à mão: folha de revisão sem leitura prévia.
Future<void> createLabResultManually(BuildContext context) async {
  final saved = await showLabResultReviewSheet(context);
  if (saved == null || !context.mounted) return;

  await context.read<LabResultProvider>().saveResult(saved);
  if (!context.mounted) return;
  showAppSnackBar(context, 'Laudo salvo.', type: AppSnackType.success);
}

/// Foto do laudo: a IA transcreve os valores impressos e a folha de revisão
/// abre preenchida para conferência.
Future<void> createLabResultFromPhoto(BuildContext context) async {
  final source = await pickReadingImageSource(
    context,
    cameraLabel: 'Tirar foto do laudo',
    galleryLabel: 'Escolher imagem da galeria',
  );
  if (source == null || !context.mounted) return;

  final file = await pickReadingImage(context, source);
  if (file == null || !context.mounted) return;

  final bytes = await file.readAsBytes();
  if (!context.mounted) return;

  showUnawaitedReadingDialog(
    context,
    title: 'Lendo laudo…',
    subtitle: 'A IA transcreve os valores impressos no laudo.',
  );

  LabScanResult? scan;
  String? error;
  try {
    scan = await AiService().extractLabValues(
      imageBytes: bytes,
      mimeType: imageMimeTypeOf(file),
    );
  } on AiException catch (e) {
    error = e.message;
  } catch (_) {
    error =
        'Não foi possível ler o laudo. Tente outra foto ou preencha '
        'manualmente.';
  }

  if (!context.mounted) return;
  closeReadingDialog(context); // diálogo de leitura

  if (scan == null) {
    showAppSnackBar(context, error!);
    return;
  }

  final result = await showLabResultReviewSheet(
    context,
    scannedLabName: scan.labName,
    scannedExamDate: scan.examDate,
    scannedValues: scan.values,
    photoBytes: bytes,
  );
  if (result == null || !context.mounted) return;

  await context.read<LabResultProvider>().saveResult(result);
  if (!context.mounted) return;
  showAppSnackBar(context, 'Laudo salvo.', type: AppSnackType.success);
}

// ── Planos de saúde ────────────────────────────────────────────────────────

/// Texto LGPD do fluxo de carteirinha.
const String cardScanConsentText =
    'Para ler a foto do cartão, a imagem é enviada ao serviço de leitura '
    'automática do próprio app e descartada após a leitura — nada vai para '
    'terceiros. Essa opção usa a internet; o cadastro manual não envia nada.';

/// Entrada canônica de novo plano de saúde: pergunta foto do cartão × manual,
/// lê a carteirinha com IA e abre a tela de conferência.
///
/// [cardReaderFactory] existe só para os testes injetarem um cliente HTTP —
/// sem ela, qualquer teste que chegue à leitura dispararia uma chamada real.
Future<void> addHealthPlan(
  BuildContext context, {
  CardReaderService Function()? cardReaderFactory,
}) async {
  final provider = context.read<HealthPlanProvider>();
  final choice = await showAddHealthPlanSheet(context);
  if (choice == null || !context.mounted) return;

  if (choice == AddPlanChoice.manual) {
    await _openHealthPlanForm(context, provider);
    return;
  }

  final scan = await scanHealthPlanCard(
    context,
    cardReaderFactory: cardReaderFactory,
  );
  if (scan == null || !context.mounted) return;

  final plan = await Navigator.of(context).push<HealthPlan>(
    MaterialPageRoute(
      builder: (_) => HealthPlanReviewScreen(
        scan: scan,
        onRescan: () =>
            scanHealthPlanCard(context, cardReaderFactory: cardReaderFactory),
        onManualEntry: (scan) => _leavePlanReviewForManual(context, scan),
      ),
    ),
  );

  if (plan == null) return;
  await provider.saveHealthPlan(plan);
  if (!context.mounted) return;
  showAppSnackBar(context, '${plan.name} adicionado com sucesso!');
}

/// Formulário manual de plano (novo, sem rascunho).
Future<void> _openHealthPlanForm(
  BuildContext context,
  HealthPlanProvider provider,
) async {
  final plan = await showSteppedFormSheet<HealthPlan>(
    context: context,
    builder: (_) => HealthPlanFormDialog(),
  );

  if (plan == null || !context.mounted) return;
  await provider.saveHealthPlan(plan);
  if (!context.mounted) return;
  showAppSnackBar(context, '${plan.name} adicionado com sucesso!');
}

/// Escolhe a imagem do cartão, garante o consentimento e faz a leitura.
/// Retorna `null` quando o usuário cancela, não consentiu ou a leitura
/// falha.
Future<CardScanResult?> scanHealthPlanCard(
  BuildContext context, {
  CardReaderService Function()? cardReaderFactory,
}) async {
  final consented = await ensureImageReadingConsent(
    context,
    explanation: cardScanConsentText,
  );
  if (!consented || !context.mounted) return null;

  final source = await pickReadingImageSource(
    context,
    cameraLabel: 'Tirar foto do cartão',
    galleryLabel: 'Escolher imagem da galeria',
  );
  if (source == null || !context.mounted) return null;

  final file = await pickReadingImage(context, source);
  if (file == null || !context.mounted) return null;

  final bytes = await file.readAsBytes();
  if (!context.mounted) return null;

  showUnawaitedReadingDialog(
    context,
    title: 'Lendo o cartão…',
    subtitle: 'Procurando operadora e número de carteirinha.',
  );

  CardReadResult? data;
  String? error;
  try {
    data = await (cardReaderFactory?.call() ?? CardReaderService()).readCard(
      imageBytes: bytes,
      mimeType: imageMimeTypeOf(file),
    );
  } on CardReaderException catch (e) {
    error = e.message;
  } catch (_) {
    error =
        'Não foi possível ler o cartão. Tente outra foto ou cadastre '
        'manualmente.';
  }

  if (!context.mounted) return null;
  closeReadingDialog(context); // fecha o diálogo de leitura

  if (data == null) {
    showAppSnackBar(
      context,
      error ?? 'Não foi possível ler o cartão.',
      action: SnackBarAction(
        label: 'Cadastrar manualmente',
        onPressed: () {
          final provider = context.read<HealthPlanProvider>();
          _openHealthPlanForm(context, provider);
        },
      ),
    );
    return null;
  }

  return CardScanResult(data: data, imageBytes: bytes);
}

/// Volta da revisão da foto para o cadastro manual levando os dados lidos:
/// o formulário abre preenchido como rascunho — nada do que a IA leu é
/// descartado na troca de caminho.
Future<void> _leavePlanReviewForManual(
  BuildContext context,
  CardScanResult scan,
) async {
  Navigator.of(context).pop();
  await Future<void>.delayed(const Duration(milliseconds: 250));
  if (!context.mounted) return;
  final plan = await showSteppedFormSheet<HealthPlan>(
    context: context,
    builder: (_) => HealthPlanFormDialog(draft: scan.data),
  );
  if (plan == null || !context.mounted) return;
  await context.read<HealthPlanProvider>().saveHealthPlan(plan);
  if (!context.mounted) return;
  showAppSnackBar(context, '${plan.name} adicionado com sucesso!');
}

// ── Médicos ────────────────────────────────────────────────────────────────

/// Cadastro manual de médico.
Future<void> createDoctorManually(BuildContext context) async {
  final provider = context.read<DoctorProvider>();
  final result = await showSteppedFormSheet<Doctor>(
    context: context,
    builder: (_) => const DoctorFormDialog(),
  );
  if (result == null || !context.mounted) return;
  await provider.saveDoctor(result);
  if (!context.mounted) return;
  showAppSnackBar(
    context,
    'Médico salvo no seu catálogo.',
    type: AppSnackType.success,
  );
}

/// Foto da receita: identifica o médico emissor (nome + CRM) por OCR.
/// Quem o catálogo já confirma (CRM+UF ou nome) volta a abrir para
/// CONFERIR E COMPLETAR — não duplica; quem é novo abre preenchido para
/// conferência. A leitura só preenche, quem salva é o usuário.
Future<void> createDoctorFromPrescription(BuildContext context) async {
  final consented = await ensureImageReadingConsent(
    context,
    explanation: prescriptionConsentText,
  );
  if (!consented || !context.mounted) return;

  final source = await pickReadingImageSource(
    context,
    cameraLabel: 'Tirar foto da receita',
    galleryLabel: 'Escolher imagem da galeria',
  );
  if (source == null || !context.mounted) return;

  final file = await pickReadingImage(context, source);
  if (file == null || !context.mounted) return;

  final bytes = await file.readAsBytes();
  if (!context.mounted) return;

  showUnawaitedReadingDialog(
    context,
    subtitle: 'Procurando o médico que assinou.',
  );

  PrescriptionDoctor? medico;
  String? error;
  try {
    medico = await PrescriptionReaderService().readDoctorFromImage(
      imageBytes: bytes,
      mimeType: imageMimeTypeOf(file),
    );
  } on PrescriptionReaderException catch (e) {
    error = e.message;
  } catch (_) {
    error =
        'Não foi possível ler a receita. Tente outra foto ou cadastre '
        'manualmente.';
  }

  if (!context.mounted) return;
  closeReadingDialog(context); // fecha o diálogo de leitura

  if (medico == null) {
    showAppSnackBar(context, error!);
    return;
  }

  final provider = context.read<DoctorProvider>();
  // Variável final: a promoção de nulos sobrevive à captura do builder.
  final medicoDraft = medico;

  // O mesmo médico não vira dois cadastros: quem o CRM (ou o nome) já
  // confirma reabre para completar o cadastro, nunca para duplicar.
  final existing = findDoctorInCatalog(
    provider.doctors,
    name: medicoDraft.nome,
    crm: medicoDraft.crm,
    crmState: medicoDraft.uf,
  );

  if (existing != null) {
    final updated = await showSteppedFormSheet<Doctor>(
      context: context,
      builder: (_) => DoctorFormDialog(initialDoctor: existing),
    );
    if (!context.mounted) return;
    if (updated != null) {
      await provider.saveDoctor(updated);
      if (!context.mounted) return;
      showAppSnackBar(
        context,
        'Dados de ${updated.name} conferidos e salvos.',
        type: AppSnackType.success,
      );
    } else {
      showAppSnackBar(
        context,
        '${existing.name} já está no seu catálogo — nada foi alterado.',
      );
    }
    return;
  }

  final saved = await showSteppedFormSheet<Doctor>(
    context: context,
    builder: (dialogContext) => DoctorFormDialog(
      draft: DoctorDraft(
        name: medicoDraft.nome,
        crm: medicoDraft.crm,
        crmState: medicoDraft.uf,
      ),
    ),
  );
  if (saved != null && context.mounted) {
    await provider.saveDoctor(saved);
  }
}
