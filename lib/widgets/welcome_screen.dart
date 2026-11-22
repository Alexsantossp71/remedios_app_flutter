import 'package:material_ui/material_ui.dart';

import '../core/design/app_tokens.dart';

/// Primeira tela vista por um visitante casual da URL pública no Web.
///
/// Antes desta tela, o Web caía direto no [DatabaseUnlockGate] — um card
/// pedindo senha de 12 caracteres sem nome do app, sem logo, sem tagline.
/// Visitantes casuais abandonavam sem saber o que era o app.
///
/// A Welcome explica o que o app faz e oferece dois caminhos:
/// - **Começar**: leva ao [DatabaseUnlockGate] para configurar o cofre
///   criptográfico (fluxo normal, persistente).
/// - **Ver demo**: ativa o modo demo (banco em memória não persistido
///   com dados mock) — o visitante explora a UI completa sem precisar
///   criar senha. Os dados não persistem ao fechar a aba.
///
/// Esta tela só aparece em Web. Android/desktop já têm cofre do SO
/// (Keystore/Keychain) e bootstrap diretamente no app.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    required this.onStart,
    required this.onSeeDemo,
  });

  /// Chamado quando o usuário toca em "Começar". Vai para o
  /// [DatabaseUnlockGate] (fluxo persistente, criptografado).
  final VoidCallback onStart;

  /// Chamado quando o usuário toca em "Ver demo". Recebe o
  /// [BuildContext] da Welcome para que o callback possa navegar.
  /// A implementação em [AppBootstrap.runDemoMode] ativa o banco em
  /// memória com dados mock e faz bootstrapApp diretamente (sem gate).
  final void Function(BuildContext) onSeeDemo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 720;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isWide ? 48 : 28,
                    vertical: 32,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _BrandMark(isDark: isDark),
                        const SizedBox(height: 32),
                        Text(
                          'Remédio na Hora',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.onSurface,
                            letterSpacing: -0.01,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Seus medicamentos, na hora certa.',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Organize medicamentos, tratamentos, consultas, exames '
                          'e laudos em um só lugar. Receba lembretes no horário '
                          'das doses, leia receitas e carteirinhas por foto, e '
                          'acompanhe sua adesão ao longo do tempo.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.45,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        _PrivacyBlurb(theme: theme),
                        const SizedBox(height: 32),
                        FilledButton.icon(
                          onPressed: onStart,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                          ),
                          icon: const Icon(Icons.lock_outline),
                          label: const Text(
                            'Começar — criar meu cofre',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => onSeeDemo(context),
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
                            'Ver demo (não salva dados)',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
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
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Marca visual da Welcome — pílula teal com ícone de remédio.
///
/// Não usa dependência externa de SVG ou asset: é composição Material
/// com Icons.medication_rounded sobre Container com gradiente teal.
class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF15857A), Color(0xFF1A5276)],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: isDark ? const Color(0x3315857A) : const Color(0x1A15857A),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Icon(
          Icons.medication_rounded,
          size: 48,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Card compacto explicando o modelo de privacidade do app.
///
/// Três pontos curtos com ícones para que o visitante saiba o que
/// acontece com seus dados antes de tocar em qualquer botão.
class _PrivacyBlurb extends StatelessWidget {
  const _PrivacyBlurb({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String)>[
      (
        Icons.lock_rounded,
        'Criptografado em repouso neste dispositivo (Android Keystore / WebCrypto)',
      ),
      (
        Icons.cloud_off_outlined,
        'Sem nuvem, sem sincronização automática entre dispositivos',
      ),
      (
        Icons.visibility_off_outlined,
        'IA e OCR são opcionais — você ativa só quando quiser usar',
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(items[i].$1, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    items[i].$2,
                    style: theme.textTheme.bodySmall?.copyWith(
                      height: 1.4,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            if (i < items.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
