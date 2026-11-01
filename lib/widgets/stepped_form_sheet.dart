import 'package:flutter/material.dart';

import '../core/design/app_tokens.dart';
import '../core/theme/app_theme.dart';

/// Um passo de um [SteppedFormShell]: título, conteúdo e validação própria
/// para poder avançar.
class FormStep {
  const FormStep({required this.title, required this.children, this.validate});

  final String title;
  final List<Widget> children;

  /// Mensagem de erro quando o passo não pode avançar; null = liberado.
  /// Fecha sobre os controllers do formulário-dono (sempre fresco).
  final String? Function()? validate;
}

/// Abre o formulário como bottom sheet em passos (padrão V4 "jornada").
///
/// Mesmo contrato de um `showDialog<T>`: devolve o resultado quando o
/// formulário salva, ou null quando o usuário fecha.
Future<T?> showSteppedFormSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: builder,
  );
}

/// Casca de formulário em passos com barra de progresso, validação por
/// passo e navegação Voltar/Continuar/Salvar.
///
/// O estado dos campos fica no widget-dono (que reconstrói a lista de
/// [steps] a cada build); a casca só cuida de progressão e navegação.
class SteppedFormShell extends StatefulWidget {
  const SteppedFormShell({
    super.key,
    required this.title,
    required this.intro,
    required this.steps,
    required this.onSave,
    this.saveLabel = 'Salvar',
    this.progressMessage,
  });

  final String title;

  /// Frase de abertura que explica o espírito do cadastro.
  final String intro;

  final List<FormStep> steps;

  /// Chamado no último passo. O widget-dono valida e fecha com
  /// `Navigator.pop(context, resultado)`.
  final VoidCallback onSave;

  final String saveLabel;

  /// Aviso de origem (ex.: rascunho lido por OCR).
  final String? progressMessage;

  @override
  State<SteppedFormShell> createState() => _SteppedFormShellState();
}

class _SteppedFormShellState extends State<SteppedFormShell> {
  int _current = 0;
  final _pageController = PageController();
  String? _stepError;

  bool get _isLast => _current == widget.steps.length - 1;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    setState(() {
      _current = index.clamp(0, widget.steps.length - 1);
      _stepError = null;
    });
    _pageController.animateToPage(
      _current,
      duration: AppDurations.medium,
      curve: AppCurves.emphasized,
    );
  }

  void _advance() {
    final step = widget.steps[_current];
    final error = step.validate?.call();
    if (error != null) {
      setState(() => _stepError = error);
      return;
    }
    if (_isLast) {
      widget.onSave();
      return;
    }
    _goTo(_current + 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
          // Largura confortável em desktop: a sheet nunca estica a tela toda.
          maxWidth: 560,
        ),
        // Material transparente: o shell vive em bottom sheet (que já tem
        // Material), mas também sob showDialog nos testes — TextFields e ink
        // exigem ancestral Material próprio em qualquer hospedeiro.
        child: Material(
          type: MaterialType.transparency,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              0,
              AppSpacing.xl,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  widget.intro,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(
                            begin: 0,
                            end: (_current + 1) / widget.steps.length,
                          ),
                          duration: AppDurations.medium,
                          curve: AppCurves.emphasized,
                          builder:
                              (context, value, _) => LinearProgressIndicator(
                                value: value,
                                minHeight: 6,
                                borderRadius: BorderRadius.circular(3),
                              ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Text(
                      'Passo ${_current + 1} de ${widget.steps.length}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                if (widget.progressMessage != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    widget.progressMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Flexible(
                  child: PageView(
                    controller: _pageController,
                    // Só por toque/continuar: a progressão é validada.
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      for (final step in widget.steps)
                        SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                step.title,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              ...step.children,
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                if (_stepError != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _stepError!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppSemanticColors.of(context).danger,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    if (_current > 0) ...[
                      TextButton(
                        onPressed: () => _goTo(_current - 1),
                        child: const Text('Voltar'),
                      ),
                      const Spacer(),
                    ] else
                      const Spacer(),
                    FilledButton(
                      onPressed: _advance,
                      child: Text(_isLast ? widget.saveLabel : 'Continuar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
