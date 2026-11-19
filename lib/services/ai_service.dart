import 'dart:convert';

import 'dart:typed_data';

import '../core/lab_values.dart';
import '../data/medical_specialties.dart';
import '../models/treatment.dart';
import 'ai/ai_models.dart';
import 'ai/ai_prompts.dart';
import 'ai/ai_sanitizers.dart';
import 'ai_proxy_client.dart';

// Re-exporta modelos e sanitizadores para não quebrar quem importa
// `ai_service.dart` diretamente (widgets, providers e testes).
export 'ai/ai_models.dart';
export 'ai/ai_sanitizers.dart';

/// Ferramentas de IA do PWA "Remédio na Hora" portadas para o Flutter via
/// mesmo proxy (Cloudflare Worker). As funções são informativas: nenhum
/// resultado altera dados do app por conta própria — a decisão é sempre do
/// usuário, e os avisos reforçam a confirmação com médico/farmacêutico.
///
/// As respostas do modelo são sempre sanitizadas antes de chegar à
/// interface: texto cortado em limites definidos, listas filtradas e,
/// no consultor de horários, checagens determinísticas (contagem de doses
/// e intervalo mínimo) que não dependem da honestidade do modelo.
class AiService {
  AiService({AiProxyClient? proxyClient})
    : _proxy = proxyClient ?? AiProxyClient();

  final AiProxyClient _proxy;

  // ===== Interações e duplicidades =====

  /// Analisa duplicidades de princípio ativo e interações entre os
  /// tratamentos ativos. Exige pelo menos dois tratamentos com nome.
  Future<AiInteractionReport> analyzeInteractions(
    List<Treatment> treatments,
  ) async {
    final list = treatments
        .map((item) => (name: item.name.trim(), dosage: item.dosage.trim()))
        .where((item) => item.name.isNotEmpty)
        .toList();
    if (list.length < 2) {
      throw AiException(
        'Cadastre pelo menos dois tratamentos para a análise de interações.',
      );
    }

    final medicationLines = <String>[];
    for (var index = 0; index < list.length; index++) {
      final dosage = list[index].dosage.isEmpty
          ? ''
          : ' — ${list[index].dosage}';
      medicationLines.add('${index + 1}. ${list[index].name}$dosage');
    }

    final content = await _proxy.chatCompletion(
      messages: [
        {
          'role': 'user',
          'content':
              '$interactionsPrompt\n\nMedicamentos em uso:\n${medicationLines.join('\n')}',
        },
      ],
      model: AiProxyClient.defaultTextModel,
      maxTokens: 1800,
      temperature: 0.1,
    );

    return sanitizeInteractionReport(aiExtractJson(content));
  }

  // ===== Bula simplificada =====

  /// Explica um medicamento em linguagem leiga, considerando a dosagem e
  /// as instruções cadastradas no tratamento.
  Future<AiMedicationGuide> explainMedication(Treatment treatment) async {
    final name = treatment.name.trim();
    if (name.isEmpty) {
      throw AiException('Informe o nome do medicamento.');
    }
    final context = [
      name,
      treatment.dosage.trim().isNotEmpty
          ? 'dosagem: ${treatment.dosage.trim()}'
          : '',
      treatment.instructions.trim().isNotEmpty
          ? 'instruções: ${treatment.instructions.trim()}'
          : '',
    ].where((part) => part.isNotEmpty).join(' | ');

    final content = await _proxy.chatCompletion(
      messages: [
        {'role': 'user', 'content': '$guidePrompt\n\nMedicamento: $context'},
      ],
      model: AiProxyClient.defaultTextModel,
      maxTokens: 1200,
      temperature: 0.3,
    );

    return sanitizeMedicationGuide(aiExtractJson(content));
  }

  // ===== Consultor de horários =====

  /// Sugere redistribuição de horários entre as doses do dia, sem alterar
  /// dose, frequência ou duração. Cada sugestão referencia o id do
  /// tratamento; sugestões para ids desconhecidos são descartadas.
  Future<AiScheduleAdvice> suggestSchedule(List<Treatment> treatments) async {
    final meds = treatments.map(scheduleMedFromTreatment).toList();
    if (meds.isEmpty) {
      throw AiException(
        'Cadastre tratamentos com horários para a IA sugerir melhorias.',
      );
    }

    // Tarefa de JSON curto: prioriza um modelo Flash rápido (igual ao PWA).
    final content = await _proxy.chatCompletion(
      messages: [
        {
          'role': 'user',
          'content': '$schedulePrompt\n\n${buildScheduleDataBlock(meds)}',
        },
      ],
      model: 'z-ai/glm-5.3-flash',
      maxTokens: 1100,
      temperature: 0.2,
      requestTimeout: const Duration(seconds: 9),
      maxModels: 2,
    );

    return sanitizeScheduleAdvice(aiExtractJson(content), meds);
  }

  // ===== Perguntas para a consulta =====

  /// Sugere de 3 a 5 perguntas personalizadas para levar à consulta,
  /// combinando tratamentos, adesão e dificuldades recentes.
  Future<List<String>> suggestConsultationQuestions(
    AiConsultationContext context,
  ) async {
    final payload = [
      context.medications.isNotEmpty
          ? 'Medicamentos em uso:\n${context.medications.map((m) => '- $m').join('\n')}'
          : 'Medicamentos: nenhum cadastrado.',
      'Adesão últimos 7 dias: ${context.adherence7}',
      'Adesão últimos 30 dias: ${context.adherence30}',
      context.difficulties.isNotEmpty
          ? 'Doses com mais perda:\n${context.difficulties.map((d) => '- $d').join('\n')}'
          : 'Doses com mais perda: nenhuma.',
      context.pendingExams.isNotEmpty
          ? 'Exames pendentes:\n${context.pendingExams.map((e) => '- $e').join('\n')}'
          : 'Exames pendentes: nenhum.',
    ].join('\n\n');

    final content = await _proxy.chatCompletion(
      messages: [
        {
          'role': 'user',
          'content': '$questionsPrompt\n\nDados do paciente:\n$payload',
        },
      ],
      model: AiProxyClient.defaultTextModel,
      maxTokens: 700,
      temperature: 0.4,
    );

    return sanitizeConsultationQuestions(aiExtractJson(content));
  }

  // ===== Leitura do pedido de exame (modelo de visão) =====

  /// Lê a foto de um pedido médico de exames e devolve os campos
  /// reconhecidos para preencher o formulário — quem revisa e salva é
  /// sempre o usuário. Porta do `scanExamRequest` do PWA.
  Future<AiExamScan> scanExamRequest({
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    final base64Image = base64Encode(imageBytes);
    final content = await _proxy.chatCompletion(
      messages: [
        {
          'role': 'user',
          'content': [
            {
              'type': 'image_url',
              'image_url': {'url': 'data:$mimeType;base64,$base64Image'},
            },
            {'type': 'text', 'text': examScanPrompt},
          ],
        },
      ],
      model: AiProxyClient.defaultVisionModel,
      hasImages: true,
      // Modelos de raciocínio (nemotron-super-vl) gastam centenas de
      // tokens raciocinando antes do JSON final — 500 esgotava o limite
      // no raciocínio e devolvia content vazio. 2000 = paridade com
      // extractLabValues.
      maxTokens: 2000,
      temperature: 0.1,
    );

    final parsed = aiExtractJson(content);
    if (parsed['error'] == 'not_a_request') {
      throw AiException(
        'A foto não parece ser um pedido de exame. Tente outra imagem com '
        'melhor luz e enquadramento.',
      );
    }

    final scan = sanitizeExamScan(parsed);
    if (scan.name.isEmpty) {
      throw AiException(
        'A IA não reconheceu os dados do pedido. Tente uma foto mais '
        'nítida, sem reflexos, ou preencha manualmente.',
      );
    }
    return scan;
  }

  // ===== Extração de valores do laudo (modelo de visão) =====

  /// Lê a foto de um laudo de laboratório e devolve os valores medidos —
  /// a IA só TRANSCREVE (nunca classifica); as flags são calculadas no
  /// app a partir das faixas impressas. Porta do `extractLabValues` do PWA.
  Future<LabScanResult> extractLabValues({
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    final base64Image = base64Encode(imageBytes);
    final content = await _proxy.chatCompletion(
      messages: [
        {
          'role': 'user',
          'content': [
            {
              'type': 'image_url',
              'image_url': {'url': 'data:$mimeType;base64,$base64Image'},
            },
            {'type': 'text', 'text': labScanPrompt},
          ],
        },
      ],
      model: AiProxyClient.defaultVisionModel,
      hasImages: true,
      // O nemotron-super-vl raciocina ANTES do JSON e o raciocínio varia
      // muito com o número de marcadores: um laudo real de 8 itens queimou
      // 2.624 tokens só pensando (E2E 16/11/2026) — o orçamento antigo de
      // 2.000 cortava a resposta no meio do JSON (finish=length) e a
      // leitura falhava sempre. 5.000 cobre raciocínio pesado + até 40
      // itens (~4.400 tokens no pior caso medido).
      maxTokens: 5000,
      temperature: 0.1,
    );

    final parsed = aiExtractJson(content);
    if (parsed['error'] == 'not_a_report') {
      throw AiException(
        'A foto não parece ser um laudo de laboratório com valores. Tente '
        'outra imagem com melhor luz e enquadramento.',
      );
    }

    final result = sanitizeLabScan(parsed);
    if (result.values.isEmpty) {
      throw AiException(
        'A IA não reconheceu valores neste laudo. Tente uma foto mais '
        'nítida, sem reflexos, ou preencha manualmente.',
      );
    }
    return result;
  }

  // ===== Dados do médico a partir de texto colado/digitado =====

  /// Extrai nome, CRM, UF, especialidade e telefone de um texto livre
  /// (ex.: "Dra. Ana Silva, CRM 123456-SP, cardiologista"). A IA só
  /// transcreve: campos ausentes ficam vazios e a especialidade volta
  /// APENAS se casar com a lista fixa do cadastro — nada é inventado.
  Future<DoctorAiData> extractDoctorData(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty) {
      throw AiException('Cole ou digite os dados do médico primeiro.');
    }

    final content = await _proxy.chatCompletion(
      messages: [
        {
          'role': 'user',
          'content':
              '$doctorExtractPrompt\n\nLista de especialidades válidas:\n'
              '${kMedicalSpecialties.join(', ')}\n\n'
              'Texto do usuário:\n$text',
        },
      ],
      model: AiProxyClient.defaultTextModel,
      maxTokens: 400,
      temperature: 0.1,
    );

    final parsed = aiExtractJson(content);
    if (parsed['error'] == 'not_a_doctor') {
      throw AiException(
        'O texto não parece conter dados de um médico. Confira e tente de '
        'novo, ou preencha os campos manualmente.',
      );
    }

    final result = sanitizeDoctorData(parsed);
    if (result.isEmpty) {
      throw AiException(
        'A IA não encontrou dados do médico nesse texto. Preencha os campos '
        'manualmente.',
      );
    }
    return result;
  }
}
