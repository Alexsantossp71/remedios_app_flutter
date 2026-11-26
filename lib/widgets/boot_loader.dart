import 'package:flutter/scheduler.dart' show Ticker;
import 'package:material_ui/material_ui.dart';

import '../core/boot/boot_progress.dart';
import '../core/boot/boot_steps.dart';
import '../core/design/app_tokens.dart';

/// Tela de carregamento com porcentagem (0–100%) que roda em TODA abertura
/// do app — web e nativo.
///
/// Resolve o mesmo problema corrigido no PWA irmão: antes, o carregamento
/// com % só aparecia para novos usuários, e quem já usava o app nunca via
/// nada entre o toque no ícone e a primeira tela. Aqui o BootLoader é o
/// primeiro widget rodado em `main()`, incondicionalmente, então a
/// animação acontece a cada abertura.
///
/// Comportamento (mesmo contrato do PWA):
/// - Percentual = parcela de tempo da animação (ease-out cúbico, 1,8 s)
///   travada no teto das etapas reais concluídas — ver [bootProgress];
/// - Cada etapa real exibe seu rótulo em pt-BR sob a barra;
/// - Etapa que estoura timeout ou falha é tratada como concluída
///   (fail-open — o app nunca fica preso no carregamento);
/// - Ao completar, exibe "Tudo pronto!" por [doneHold] e chama [onDone],
///   que despacha para o fluxo da plataforma (web → WelcomeScreen,
///   nativo → bootstrapApp);
/// - Respeita "reduzir animações" do sistema ([MediaQueryData.disableAnimations]):
///   sem animação, o percentual salta direto para o teto das etapas e o
///   app é liberado assim que as tarefas reais terminam;
/// - Exposta à árvore de semântica como região viva (screen reader anuncia
///   o andamento) com value de progresso.
class BootLoader extends StatefulWidget {
  const BootLoader({
    super.key,
    required this.steps,
    required this.onDone,
    this.animationDuration = bootAnimationDuration,
    this.stepTimeout = bootStepTimeout,
    this.doneHold = bootDoneHold,
  });

  /// Etapas reais de boot (rótulo + tarefa), em ordem de execução.
  final List<BootStep> steps;

  /// Chamado quando o carregamento terminou (100% + "Tudo pronto!" já
  /// exibidos). Deve navegar para o próximo fluxo do app.
  final VoidCallback onDone;

  /// Duração total da animação 0→100% (padrão: [bootAnimationDuration]).
  final Duration animationDuration;

  /// Timeout por etapa real (padrão: [bootStepTimeout]).
  final Duration stepTimeout;

  /// Tempo em que "Tudo pronto!" fica na tela (padrão: [bootDoneHold]).
  final Duration doneHold;

  @override
  State<BootLoader> createState() => _BootLoaderState();
}

class _BootLoaderState extends State<BootLoader>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  int _stepsDone = 0;
  int _percent = 0;
  bool _doneShown = false;
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _runSteps();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // "Reduzir animações" (acessibilidade): sem easing, o percentual segue
    // direto o teto das etapas reais — espelho do prefers-reduced-motion
    // tratado no PWA irmão.
    _reducedMotion = MediaQuery.of(context).disableAnimations;
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// Executa as etapas reais em sequência. Erro/timeout = etapa concluída
  /// (fail-open), nunca bloqueia a entrada no app.
  Future<void> _runSteps() async {
    for (final BootStep step in widget.steps) {
      try {
        await step.task().timeout(widget.stepTimeout);
      } on Exception {
        // Fail-open: etapa lenta ou quebrada não pode prender o usuário.
      } catch (_) {
        // Errors assíncronos também são engolidos — mesmo contrato.
      }
      if (!mounted) return;
      setState(() => _stepsDone++);
    }
  }

  void _onTick(Duration elapsed) {
    if (!mounted || _doneShown) return;

    final int total = widget.steps.length;
    final bool allDone = _stepsDone >= total;
    if (allDone && (elapsed >= widget.animationDuration || _reducedMotion)) {
      _finish();
      return;
    }

    final int next = _reducedMotion
        ? _ceilingFor(_stepsDone)
        : bootProgress(
            elapsed: elapsed,
            stepsDone: _stepsDone,
            totalSteps: total,
            animationDuration: widget.animationDuration,
          );
    if (next != _percent) {
      setState(() => _percent = next);
    }
  }

  void _finish() {
    _ticker.stop();
    setState(() {
      _percent = 100;
      _doneShown = true;
    });
    // "Tudo pronto!" fica visível por um instante antes de liberar o app.
    Future<void>.delayed(widget.doneHold, () {
      if (mounted) widget.onDone();
    });
  }

  int _ceilingFor(int stepsDone) {
    final int total = widget.steps.length;
    if (total <= 0) return 100;
    if (stepsDone >= total) return 100;
    return (stepsDone / total * 100).floor();
  }

  String get _currentLabel {
    if (_doneShown) return bootDoneLabel;
    if (widget.steps.isEmpty) return bootStepLabels.first;
    if (_stepsDone >= widget.steps.length) return widget.steps.last.label;
    return widget.steps[_stepsDone].label;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: _BootMark(isDark: isDark)),
                  const SizedBox(height: AppSpacing.huge),
                  Text(
                    'Remédio na Hora',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface,
                      letterSpacing: -0.01,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  Semantics(
                    liveRegion: true,
                    textDirection: TextDirection.ltr,
                    label: _currentLabel,
                    value: '$_percent%',
                    child: Column(
                      children: [
                        Text(
                          '$_percent%',
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.primary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          child: LinearProgressIndicator(
                            value: _percent / 100,
                            minHeight: 8,
                            backgroundColor: theme
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.6),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        AnimatedSwitcher(
                          duration: AppDurations.medium,
                          child: Text(
                            _currentLabel,
                            key: ValueKey<String>(_currentLabel),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_doneShown) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Icon(
                      Icons.check_circle_rounded,
                      color: theme.colorScheme.primary,
                      size: 28,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Marca visual do carregamento — mesma identidade da WelcomeScreen
/// (pílula teal com ícone de remédio), em tamanho menor.
class _BootMark extends StatelessWidget {
  const _BootMark({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
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
        Icons.medication_rounded,
        size: 36,
        color: Colors.white,
      ),
    );
  }
}
