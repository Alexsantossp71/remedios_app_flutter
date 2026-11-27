import 'package:flutter/scheduler.dart' show Ticker;
import 'package:material_ui/material_ui.dart';

import '../core/boot/boot_progress.dart';
import '../core/boot/boot_steps.dart';
import '../core/design/app_tokens.dart';

/// Tela de carregamento com porcentagem (0–100%) que roda em TODA abertura
/// do app — web e nativo. Ao chegar a 100% ela PARA e mostra os botões
/// "Entrar" e "Demo" — não navega sozinha.
///
/// Resolve o mesmo problema corrigido no PWA irmão: antes, o carregamento
/// com % só aparecia para novos usuários, e quem já usava o app nunca via
/// nada entre o toque no ícone e a primeira tela. Aqui o BootLoader é o
/// primeiro widget rodado em `main()`, incondicionalmente, então a
/// animação acontece a cada abertura.
///
/// Comportamento:
/// - Percentual = parcela de tempo da animação (ease-out cúbico, 1,8 s)
///   travada no teto das etapas reais concluídas — ver [bootProgress];
/// - Cada etapa real exibe seu rótulo em pt-BR sob a barra;
/// - Etapa que estoura timeout ou falha é tratada como concluída
///   (fail-open — o app nunca fica preso no carregamento);
/// - Ao completar, exibe "Tudo pronto!" e, após [doneHold], revela as
///   ações na própria tela: **Entrar** ([onEnter] — cria o cofre na
///   primeira interação ou abre o app direto quando o aparelho já tem o
///   cofre) e **Demo (não salva dados)** ([onDemo]). NENHUM callback é
///   disparado automaticamente: a navegação é sempre uma escolha do
///   usuário;
/// - Respeita "reduzir animações" do sistema ([MediaQueryData.disableAnimations]):
///   sem animação, o percentual salta direto para o teto das etapas e as
///   ações aparecem assim que as tarefas reais terminam;
/// - Exposta à árvore de semântica como região viva (screen reader anuncia
///   o andamento) com value de progresso.
class BootLoader extends StatefulWidget {
  const BootLoader({
    super.key,
    required this.steps,
    required this.onEnter,
    required this.onDemo,
    this.animationDuration = bootAnimationDuration,
    this.stepTimeout = bootStepTimeout,
    this.doneHold = bootDoneHold,
  });

  /// Etapas reais de boot (rótulo + tarefa), em ordem de execução.
  final List<BootStep> steps;

  /// Chamado quando o usuário toca em **Entrar** — nunca automaticamente.
  /// Leva à criação do cofre (primeira interação no aparelho) ou direto
  /// para o app quando o cofre já está resolvido.
  final VoidCallback onEnter;

  /// Chamado quando o usuário toca em **Demo (não salva dados)** — nunca
  /// automaticamente.
  final VoidCallback onDemo;

  /// Duração total da animação 0→100% (padrão: [bootAnimationDuration]).
  final Duration animationDuration;

  /// Timeout por etapa real (padrão: [bootStepTimeout]).
  final Duration stepTimeout;

  /// Tempo entre "Tudo pronto!" aparecer e os botões Entrar/Demo serem
  /// revelados (padrão: [bootDoneHold]).
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
  bool _actionsVisible = false;
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
    // O carregamento NUNCA navega sozinho: "Tudo pronto!" aparece e, após
    // [BootLoader.doneHold], os botões Entrar/Demo são revelados na própria
    // tela. A navegação só acontece quando o usuário escolhe.
    Future<void>.delayed(widget.doneHold, () {
      if (mounted) setState(() => _actionsVisible = true);
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
                  if (_actionsVisible) ...[
                    const SizedBox(height: AppSpacing.xl),
                    FilledButton.icon(
                      onPressed: widget.onEnter,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                      icon: const Icon(Icons.lock_open_rounded),
                      label: const Text(
                        'Entrar',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: widget.onDemo,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                      icon: const Icon(Icons.play_arrow_outlined),
                      label: const Text(
                        'Demo (não salva dados)',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'O app é offline-first: seus dados ficam só neste '
                      'dispositivo. Nada vai para a nuvem sem você pedir.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
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

/// Marca visual do carregamento — mesma identidade visual do app
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
