import 'package:flutter/material.dart';

import 'brand_colors.dart';

/// Cartão de registro — equivalente do `.app-record-card` do PWA: superfície
/// com gradiente sutil a 145°, borda fina e, no hover (desktop/web), o
/// levantamento de 2px com borda acendendo em teal. No escuro, gradiente
/// próprio #1e293b → #1a2a34.
///
/// O [accentColor] acende a borda e dá um véu sutil na superfície para
/// cartões que precisam chamar atenção (consulta nos próximos dias,
/// cartão de emergência) — o mesmo papel do `border-color` colorido que o
/// CSS do app irmão aplica a variações de destaque.
class RecordCard extends StatefulWidget {
  const RecordCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.accentColor,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  /// Cor de destaque opcional (alerta, perigo). `null` mantém o cartão
  /// neutro com hover teal.
  final Color? accentColor;

  @override
  State<RecordCard> createState() => _RecordCardState();
}

class _RecordCardState extends State<RecordCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = widget.accentColor;

    final Color borderColor;
    if (accent != null) {
      borderColor = accent.withValues(alpha: _hovered ? .70 : .45);
    } else if (_hovered) {
      borderColor = BrandColors.teal600.withValues(alpha: .30);
    } else {
      borderColor =
          isDark
              ? const Color(0xFF3A5153)
              : const Color(0xFFD2E1DF).withValues(alpha: .9);
    }

    // Com acento, a superfície é chapada (véu de ~8% sobre a base) —
    // o mesmo papel do `background-color` com alpha nas variações de
    // destaque do CSS. Sem acento, mantém o gradiente 145° de assinatura.
    final Color? flatSurface =
        accent == null
            ? null
            : Color.alphaBlend(
              accent.withValues(alpha: .08),
              isDark ? BrandColors.darkSurface : Colors.white,
            );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor:
          widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
        decoration: BoxDecoration(
          // linear-gradient(145deg, ...) — claro #fff → #fbfefe,
          // escuro #1e293b → #1a2a34.
          color: flatSurface,
          gradient:
              flatSurface == null
                  ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors:
                        isDark
                            ? const [BrandColors.darkSurface, Color(0xFF1A2A34)]
                            : const [Colors.white, Color(0xFFFBFEFE)],
                  )
                  : null,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color:
                  isDark
                      ? Colors.black.withValues(alpha: .14)
                      : const Color(0xFF0F3234).withValues(alpha: .05),
              offset: Offset(0, isDark ? 6 : 5),
              blurRadius: isDark ? 20 : 18,
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(18),
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      ),
    );
  }
}
