import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design/app_tokens.dart';
import '../core/design/brand_colors.dart';
import '../providers/user_profile_provider.dart';
import '../widgets/privacy_notice.dart';
import '../widgets/skeleton.dart';
import '../widgets/stepped_form_sheet.dart';

/// Diálogo de consentimento específico das ferramentas de IA: nomes de
/// medicamentos (e resumo de adesão) saem do dispositivo até o proxy de
/// IA para produzir as análises. Grava `aiConsentAt` no perfil; uma vez
/// concedido, as ferramentas abrem direto.
Future<bool> ensureAiConsent(BuildContext context) async {
  final provider = context.read<UserProfileProvider>();
  if (provider.profile?.aiConsentAt != null) return true;

  final accepted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Autorização para usar a IA'),
      content: const SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'As ferramentas de IA enviam os NOMES e DOSAGENS dos seus '
              'medicamentos (e um resumo de adesão, na preparação de '
              'consultas) a um serviço de inteligência artificial, que '
              'devolve análises educativas. Nada é salvo nesse serviço e '
              'nenhum resultado altera seus dados sem sua confirmação.\n\n'
              'Se preferir, não use estas ferramentas — todo o resto do '
              'app funciona igual.',
            ),
            SizedBox(height: 12),
            PrivacyNoticeCard(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Agora não'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Aceito e autorizo'),
        ),
      ],
    ),
  );

  if (accepted != true) return false;
  await provider.grantAiConsent();
  return true;
}

/// Rodapé obrigatório das ferramentas de IA — o equivalente do disclaimer
/// do PWA: informação educativa, nunca prescrição.
class AiDisclaimer extends StatelessWidget {
  const AiDisclaimer({super.key, this.text});

  final String? text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:
            isDark
                ? BrandColors.yellow.withValues(alpha: .10)
                : BrandColors.yellow.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: BrandColors.yellow.withValues(alpha: .45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: isDark ? BrandColors.yellow : const Color(0xFFA16E0F),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text ??
                  'Análise educativa gerada por IA — não substitui médico, '
                  'farmacêutico ou a bula do fabricante. Antes de mudar '
                  'qualquer tratamento, confirme com um profissional.',
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.35,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Casca das ferramentas de IA: gerencia carregando/erro/resultado com
/// retry, cabeçalho com ícone e rodapé com [AiDisclaimer]. A chamada ao
/// serviço acontece aqui — as telas só abrem a sheet com o carregador.
class AiSheetScaffold<T> extends StatefulWidget {
  const AiSheetScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.loadingMessage,
    required this.load,
    required this.buildResult,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String loadingMessage;

  /// Consulta ao serviço de IA (deve lançar [AiException] em falha).
  final Future<T> Function() load;

  /// Constrói o conteúdo quando a análise conclui.
  final Widget Function(BuildContext context, T result) buildResult;

  @override
  State<AiSheetScaffold<T>> createState() => _AiSheetScaffoldState<T>();
}

class _AiSheetScaffoldState<T> extends State<AiSheetScaffold<T>> {
  AiSheetState<T> _state = const AiSheetState.loading();

  @override
  void initState() {
    super.initState();
    _runLoad();
  }

  Future<void> _runLoad() async {
    setState(() => _state = const AiSheetState.loading());
    try {
      final result = await widget.load();
      if (!mounted) return;
      setState(() => _state = AiSheetState.done(result));
    } catch (error) {
      if (!mounted) return;
      final message =
          error is Exception ? error.toString() : 'Falha inesperada na análise.';
      setState(
        () => _state = AiSheetState.error(
          _friendlyMessage(message),
        ),
      );
    }
  }

  /// Serviços lançam exceções com `toString()` no formato
  /// `ClassName: mensagem` — exibe só a parte legível.
  static String _friendlyMessage(String raw) {
    final colon = raw.indexOf(': ');
    return (colon > 0 && colon < raw.length - 2)
        ? raw.substring(colon + 2)
        : raw;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.94,
        builder: (context, scrollController) => Column(
          children: [
            // Cabeçalho fixo com a identidade do app.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: BrandColors.accentSoft,
                      borderRadius: BorderRadius.circular(AppRadius.iconBox),
                      border: Border.all(
                        color: BrandColors.teal700.withValues(alpha: .07),
                      ),
                    ),
                    child: Icon(
                      widget.icon,
                      color: BrandColors.teal700,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          widget.subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 20),
            Expanded(
              child: _state.when(
                loading: () => Center(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: 8),
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: SkeletonList(),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.loadingMessage,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                error: (message) => ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  controller: scrollController,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color:
                            theme.brightness == Brightness.dark
                                ? BrandColors.red.withValues(alpha: .12)
                                : BrandColors.red.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color: BrandColors.red.withValues(alpha: .35),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: BrandColors.red,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              message,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _runLoad,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Tentar novamente'),
                    ),
                    const SizedBox(height: 16),
                    const AiDisclaimer(),
                  ],
                ),
                done: (result) => ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  controller: scrollController,
                  children: [
                    widget.buildResult(context, result),
                    const SizedBox(height: 14),
                    const AiDisclaimer(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Estado interno da casca — visível aos testes para verificar transições.
sealed class AiSheetState<T> {
  const AiSheetState();

  const factory AiSheetState.loading() = AiSheetLoading<T>;
  const factory AiSheetState.error(String message) = AiSheetError<T>;
  const factory AiSheetState.done(T result) = AiSheetDone<T>;

  R when<R>({
    required R Function() loading,
    required R Function(String message) error,
    required R Function(T result) done,
  }) {
    final self = this;
    if (self is AiSheetLoading<T>) return loading();
    if (self is AiSheetError<T>) return error(self.message);
    if (self is AiSheetDone<T>) return done(self.result);
    throw StateError('Estado desconhecido: $self');
  }
}

class AiSheetLoading<T> extends AiSheetState<T> {
  const AiSheetLoading();
}

class AiSheetError<T> extends AiSheetState<T> {
  const AiSheetError(this.message);
  final String message;
}

class AiSheetDone<T> extends AiSheetState<T> {
  const AiSheetDone(this.result);
  final T result;
}

/// Abre a sheet padronizada depois da verificação de consentimento.
/// Retorna `false`/null quando o usuário não autorizou.
Future<T?> showAiSheet<T>({
  required BuildContext context,
  required String title,
  required String subtitle,
  required IconData icon,
  required String loadingMessage,
  required Future<T> Function() load,
  required Widget Function(BuildContext context, T result) buildResult,
}) async {
  final consented = await ensureAiConsent(context);
  if (!consented || !context.mounted) return null;
  return showSteppedFormSheet<T>(
    context: context,
    builder: (_) => AiSheetScaffold<T>(
      title: title,
      subtitle: subtitle,
      icon: icon,
      loadingMessage: loadingMessage,
      load: load,
      buildResult: buildResult,
    ),
  );
}
