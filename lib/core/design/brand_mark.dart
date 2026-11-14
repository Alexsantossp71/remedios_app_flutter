import 'package:flutter/material.dart';

import 'brand_colors.dart';

/// Marca do app — quadrado arredondado com o gradiente do `.brand-mark`
/// do PWA (`linear-gradient(145deg, #0f766e, #0d9488 58%, #2dd4bf)`).
///
/// Usado em cabeçalhos, telas de apresentação e no ícone adaptativo quando
/// o app for publicado na loja.
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.size = 40,
    this.icon = Icons.medication_rounded,
  });

  /// Lado do quadrado em pixels lógicos.
  final double size;

  /// Glifo central (branco), dimensionado proporcionalmente ao [size].
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .32),
        gradient: const LinearGradient(
          begin: Alignment(-0.55, -0.82),
          end: Alignment(0.55, 0.82),
          colors: [
            BrandColors.teal700,
            BrandColors.teal600,
            BrandColors.teal400,
          ],
          stops: [0, .58, 1],
        ),
      ),
      child: Icon(icon, size: size * .52, color: Colors.white),
    );
  }
}
