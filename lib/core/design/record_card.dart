import 'package:flutter/material.dart';

import 'brand_colors.dart';

/// Cartão de registro — equivalente do `.app-record-card` do PWA: superfície
/// com gradiente sutil a 145°, borda fina e, no hover (desktop/web), o
/// levantamento de 2px com borda acendendo em teal. No escuro, gradiente
/// próprio #1e293b → #1a2a34.
class RecordCard extends StatefulWidget {
  const RecordCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  State<RecordCard> createState() => _RecordCardState();
}

class _RecordCardState extends State<RecordCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final borderColor =
        _hovered
            ? BrandColors.teal600.withValues(alpha: .30)
            : (isDark
                ? const Color(0xFF3A5153)
                : const Color(0xFFD2E1DF).withValues(alpha: .9));

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
        decoration: BoxDecoration(
          // linear-gradient(145deg, ...) — claro #fff → #fbfefe,
          // escuro #1e293b → #1a2a34.
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors:
                isDark
                    ? const [BrandColors.darkSurface, Color(0xFF1A2A34)]
                    : const [Colors.white, Color(0xFFFBFEFE)],
          ),
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
