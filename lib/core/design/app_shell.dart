import 'package:flutter/material.dart';

import 'brand_colors.dart';

/// Fundo do app com o brilho radial teal no canto superior esquerdo —
/// equivalente direto do `.app-shell` do PWA
/// (`radial-gradient(ellipse at 10% 0%, teal, transparent 32rem)`).
///
/// Envolve o conteúdo do shell para que todas as abas compartilhem o mesmo
/// palco, como no app irmão.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glow =
        isDark
            ? BrandColors.teal600.withValues(alpha: .12)
            : const Color(0xFF14B8A6).withValues(alpha: .07);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-0.8, -1.05),
          radius: 1.7,
          colors: [glow, glow.withValues(alpha: 0)],
          stops: const [0, 1],
        ),
      ),
      child: child,
    );
  }
}
