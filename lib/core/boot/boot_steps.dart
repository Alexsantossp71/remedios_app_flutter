/// Etapas reais de boot exibidas pelo [BootLoader].
///
/// Cada etapa tem um rótulo em pt-BR (mostrado sob a barra de progresso) e
/// uma tarefa assíncrona REAL — as mesmas tarefas já desempenhadas no início
/// do app, agora sequenciadas para que o percentual tenha significado:
///
/// 1. **Verificando armazenamento local…** — sonda o storage de preferências
///    (localStorage no web; plataforma nativa no mobile). Prova que o
///    persistimento básico está vivo antes de qualquer tela tocar nele.
/// 2. **Preparando o modo offline…** — inicializa a base de fusos horários
///    usada pelo planejador de lembretes de dose (offline-first).
/// 3. **Carregando seus dados…** — pré-carrega o catálogo de medicamentos
///    (asset JSON) que as telas de tratamento consomem.
///
/// Falha em uma etapa não bloqueia o app: o BootLoader trata erro/timeout
/// como etapa concluída (fail-open) e segue para a próxima.
library;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

import '../../data/medicine_data.dart';
import 'boot_progress.dart' show bootStepLabels;

// Reexportado para que testes que mockam etapas usem os mesmos rótulos
// constantes do algoritmo (evita strings soltas duplicadas).
export 'boot_progress.dart' show bootStepLabels, bootDoneLabel;

/// Uma etapa do boot: rótulo para a UI + trabalho assíncrono real.
class BootStep {
  const BootStep(this.label, this.task);

  /// Rótulo em pt-BR exibido enquanto a etapa roda.
  final String label;

  /// Tarefa assíncrona. Deve ser idempotente e rápida (< bootStepTimeout).
  final Future<void> Function() task;
}

/// Constrói as etapas reais de boot, na ordem exibida na tela de carregamento.
List<BootStep> buildBootSteps() => <BootStep>[
  BootStep(bootStepLabels[0], () async {
    final prefs = await SharedPreferences.getInstance();
    // Sonda de leitura: tocar o storage prova que ele responde.
    prefs.get('remedios.boot_probe');
  }),
  BootStep(bootStepLabels[1], () async {
    // Base de fusos usada pelo planejador de lembretes (dose_notification_planner).
    tz_data.initializeTimeZones();
  }),
  BootStep(bootStepLabels[2], () async {
    // Pré-carrega o catálogo de medicamentos (MedicineData faz cache).
    await MedicineData.load();
  }),
];
