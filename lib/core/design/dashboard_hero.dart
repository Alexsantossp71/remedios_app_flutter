import 'package:flutter/material.dart';

import 'brand_colors.dart';

/// Herói do painel — gradiente teal de 115° com anéis decorativos no canto
/// superior direito e sombra projetada, equivalente direto do
/// `.dashboard-hero` do PWA (incluindo o `::after` com círculos concêntricos).
///
/// O conteúdo em cima do herói deve usar texto branco (o gradiente é
/// idêntico nos modos claro e escuro, como no CSS do app irmão).
class DashboardHero extends StatelessWidget {
  const DashboardHero({super.key, required this.child});

  final Widget child;

  /// `border-radius: 1.6rem` (1.2rem no mobile) — um raio único cobre os
  /// dois casos com folga visual.
  static const double radius = 26;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(radius)),
        boxShadow: [
          // 0 18px 42px rgba(15, 118, 110, .16)
          BoxShadow(
            color: Color(0x290F766E),
            offset: Offset(0, 18),
            blurRadius: 42,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(radius)),
        child: DecoratedBox(
          // linear-gradient(115deg, #115e59 0%, #0f766e 48%, #0d9488 100%)
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-0.92, -0.42),
              end: Alignment(0.92, 0.42),
              colors: [
                BrandColors.heroDeep,
                BrandColors.teal700,
                BrandColors.teal600,
              ],
              stops: [0, 0.48, 1],
            ),
          ),
          child: Stack(
            // hardEdge (padrão): o anel posicionado além das bordas é
            // recortado pelo próprio Stack — o mesmo papel do
            // `overflow: hidden` do CSS — e o ClipRRect externo arredonda.
            // O conteúdo é filho NÃO posicionado para que o Stack herde
            // a altura dele (slivers têm altura não limitada; um Stack só
            // com filhos posicionados quebraria ali). Como no CSS, os anéis
            // (::after) pintam POR CIMA do conteúdo — último filho.
            children: [
              child,
              Positioned(
                right: -112,
                top: -144,
                child: _DecorativeRing(size: 288),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DecorativeRing extends StatelessWidget {
  const _DecorativeRing({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: .14)),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: .035),
            spreadRadius: 32,
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: .025),
            spreadRadius: 64,
          ),
        ],
      ),
    );
  }
}
