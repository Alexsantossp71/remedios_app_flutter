/// Algoritmo de progresso da tela de carregamento (BootLoader).
///
/// Espelho 1:1 do `src/utils/bootProgress.ts` do PWA irmão
/// (`alexsantossp71-lgtm/remedios_app`): o percentual exibido é a parcela
/// de tempo da animação (ease-out cúbico), limitada por um teto (ceiling)
/// derivado das etapas reais já concluídas.
///
/// Garantias do modelo:
/// - A barra nunca adianta trabalho que não aconteceu (o teto só sobe quando
///   uma etapa real termina);
/// - Uma etapa lenta não trava a barra no lugar — ela continua animando até
///   o teto atual;
/// - O teto só abre para 100% quando TODAS as etapas terminam, e a partir
///   daí a animação corre até o fim;
/// - Totalmente determinístico e independente de widget — 100% testável.
library;

import 'dart:math' as math;

/// Duração da animação de 0→100% (após todas as etapas reais concluídas).
///
/// Mesmo valor do PWA irmão: a barra faz o percurso completo em 1,8 s com
/// ease-out cúbico (rápida no início, desacelera perto do fim).
const Duration bootAnimationDuration = Duration(milliseconds: 1800);

/// Tempo máximo de espera por cada etapa real de boot.
///
/// Uma etapa que estoura o timeout é considerada concluída (fail-open): a
/// tela de carregamento nunca deve impedir o usuário de entrar no app.
const Duration bootStepTimeout = Duration(milliseconds: 1500);

/// Tempo em que "Tudo pronto!" fica visível antes de liberar o app.
const Duration bootDoneHold = Duration(milliseconds: 450);

/// Rótulos em pt-BR das etapas reais de boot, na ordem de execução.
///
/// As etapas correspondem às tarefas definidas em `boot_steps.dart`.
const List<String> bootStepLabels = <String>[
  'Verificando armazenamento local…',
  'Preparando o modo offline…',
  'Carregando seus dados…',
];

/// Rótulo exibido quando o progresso chega a 100%.
const String bootDoneLabel = 'Tudo pronto!';

/// Calcula o percentual (0–100) exibido pelo BootLoader.
///
/// - [elapsed]: tempo decorrido desde o início da animação;
/// - [stepsDone]: quantidade de etapas reais já concluídas;
/// - [totalSteps]: total de etapas (padrão: [bootStepLabels.length]).
///
/// O valor é a parcela de tempo (ease-out cúbico) travada no teto das
/// etapas concluídas — o mesmo contrato do PWA irmão.
int bootProgress({
  required Duration elapsed,
  required int stepsDone,
  int? totalSteps,
  Duration animationDuration = bootAnimationDuration,
}) {
  final int total = totalSteps ?? bootStepLabels.length;
  if (total <= 0) return 100;
  if (stepsDone < 0) return 0;

  final int ceiling = stepsDone >= total
      ? 100
      : (stepsDone / total * 100).floor();
  if (ceiling == 0) return 0;

  final double t = (elapsed.inMilliseconds / animationDuration.inMilliseconds)
      .clamp(0.0, 1.0);
  final int timeShare = (_easeOutCubic(t) * 100).round();

  final int nonNegative = math.max(timeShare, 0);
  return math.min(nonNegative, ceiling);
}

double _easeOutCubic(double t) => 1 - math.pow(1 - t, 3).toDouble();
