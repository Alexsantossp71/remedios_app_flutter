import 'package:flutter/material.dart';

import 'brand_colors.dart';

/// Cartão de estatística do painel — equivalente do `.app-stat-card` do
/// PWA: superfície com gradiente sutil, borda fina, sombra suave e o
/// `.stat-icon` em caixa arredondada com anel interno.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.iconColor,
  });

  final IconData icon;
  final String value;
  final String label;

  /// Cor do acento do ícone; o padrão é o teal de ação da marca.
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = iconColor ?? BrandColors.teal700;
    final valueColor = isDark ? BrandColors.darkInk : BrandColors.ink;
    final labelColor = isDark ? BrandColors.darkMuted : BrandColors.muted;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        // linear-gradient(145deg, #fff, #fbfefe) — e no escuro #1e293b → #192a32.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors:
              isDark
                  ? const [BrandColors.darkSurface, Color(0xFF192A32)]
                  : const [Colors.white, Color(0xFFFBFEFE)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? BrandColors.darkLine : BrandColors.line,
        ),
        boxShadow: [
          BoxShadow(
            color:
                isDark
                    ? Colors.black.withValues(alpha: .14)
                    : BrandColors.shadowSoft.withValues(alpha: .35),
            offset: const Offset(0, 8),
            blurRadius: 28,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDark ? .18 : .10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accent.withValues(alpha: .07)),
            ),
            child: Icon(icon, size: 22, color: accent),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 20,
              height: 1.2,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.2,
              color: labelColor,
            ),
          ),
        ],
      ),
    );
  }
}
