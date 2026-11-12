import 'dart:async';

import 'package:flutter/foundation.dart';

import '../providers/therapy_provider.dart';
import 'web_reminder_platform_web.dart'
    if (dart.library.io) 'web_reminder_platform_stub.dart';
import 'dose_notification_planner.dart';

/// Lembrete de dose para a WEB, enquanto o app está aberto no navegador.
///
/// O `NotificationService` (alarmes do sistema) é no-op na web por política
/// (ADR 0005): sem service worker de push + servidor de sincronização, o
/// navegador não acorda o app fechado. O que a web PODE fazer hoje — e que
/// ficava em silêncio — é avisar com a aba aberta, mesmo em segundo plano.
/// Este serviço cobre exatamente esse buraco:
///
/// - observa o [TherapyProvider] e replaneia via [DoseNotificationPlanner]
///   (a mesma projeção dos alarmes do APK, então as duas plataformas nunca
///   divergem sobre quando a dose é);
/// - a cada [checkInterval] dispara `Notification` do navegador para as
///   doses que venceram dentro da [graceWindow] e ainda não foram avisadas;
/// - permissão é pedida por gesto do usuário (botão no Perfil).
///
/// Best-effort por contrato: qualquer falha do navegador é engolida — o
/// fluxo de tratamento nunca depende do lembrete.
class WebReminderService {
  WebReminderService._();

  static final WebReminderService instance = WebReminderService._();

  /// Frequência da varredura por doses vencidas.
  static const Duration checkInterval = Duration(seconds: 30);

  /// Quanto tempo depois do horário ainda vale avisar (fecha a janela:
  /// abrir o app 2h depois da dose não solta um aviso atrasado).
  static const Duration graceWindow = Duration(minutes: 5);

  TherapyProvider? _provider;
  Timer? _timer;
  List<PlannedDose> _planned = const [];
  final Set<String> _fired = {};
  bool _attached = false;

  /// O navegador deste acesso suporta Notification API?
  bool get isSupported => reminderSupported;

  /// A permissão já foi concedida neste navegador?
  bool get isPermissionGranted => reminderPermissionGranted;

  /// O usuário/site bloqueou as notificações? (só há "denied" explícito na
  /// web; no stub é sempre falso).
  bool get isPermissionDenied => reminderPermissionDenied;

  /// Liga o serviço ao provider. Sem suporte, é no-op. Sem permissão,
  /// ainda assim observa e planeia: assim que o usuário conceder (botão no
  /// Perfil), os avisos começam sem precisar religar nada.
  void attach(TherapyProvider provider) {
    if (_attached || !reminderSupported) return;
    _attached = true;
    _provider = provider;
    provider.addListener(_replan);
    _replan();
    _timer = Timer.periodic(checkInterval, (_) => _tick());
  }

  /// Pede permissão ao navegador (precisa de gesto do usuário).
  /// Se concedida, avisa imediatamente o que já venceu dentro da janela.
  Future<bool> requestPermission() async {
    final granted = await requestReminderPermission();
    if (granted) _tick();
    return granted;
  }

  void _replan() {
    final provider = _provider;
    if (provider == null) return;
    try {
      _planned = const DoseNotificationPlanner().plan(
        treatments: provider.activeTreatments.toList(),
        now: DateTime.now(),
      );
    } catch (_) {
      _planned = const [];
    }
  }

  void _tick() {
    final due = dueDoses(
      planned: _planned,
      now: DateTime.now(),
      fired: _fired,
    );
    for (final dose in due) {
      _fired.add(keyOf(dose));
      try {
        showDoseNotification(
          title: 'Hora do remédio',
          body: '${dose.treatmentName} — ${dose.dosage}',
        );
      } catch (_) {
        // Best-effort.
      }
    }
  }

  /// Chave de deduplicação de um aviso (mesmo tratamento + mesmo instante).
  static String keyOf(PlannedDose dose) =>
      '${dose.treatmentId}@${dose.scheduledAt.millisecondsSinceEpoch}';

  /// Pura e testável: as doses vencidas dentro da janela de carência que
  /// ainda não foram avisadas, em ordem de horário.
  static List<PlannedDose> dueDoses({
    required List<PlannedDose> planned,
    required DateTime now,
    required Set<String> fired,
    Duration grace = graceWindow,
  }) {
    final due = <PlannedDose>[];
    for (final dose in planned) {
      if (fired.contains(keyOf(dose))) continue;
      final late = now.difference(dose.scheduledAt);
      if (late < Duration.zero || late > grace) continue;
      due.add(dose);
    }
    due.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return due;
  }

  /// Para testes.
  @visibleForTesting
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _provider?.removeListener(_replan);
    _provider = null;
    _attached = false;
  }
}
