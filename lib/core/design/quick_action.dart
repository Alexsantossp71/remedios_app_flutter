import 'package:material_ui/material_ui.dart';

import 'brand_colors.dart';

/// Ação rápida em contorno — equivalente do `.quick-action` do PWA:
/// botão retangular arredondado com borda fina que acende em teal no hover
/// (desktop/web). No toque, o ripple do [InkWell] cumpre o mesmo papel.
class QuickAction extends StatefulWidget {
  const QuickAction({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  State<QuickAction> createState() => _QuickActionState();
}

class _QuickActionState extends State<QuickAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final borderColor = _hovered
        ? (isDark ? BrandColors.teal700 : const Color(0xFF99F6E4))
        : (isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1));
    final fillColor = _hovered
        ? (isDark
              ? BrandColors.teal700.withValues(alpha: .16)
              : const Color(0xFFF0FDFA))
        : (isDark ? Colors.transparent : Colors.white);
    final contentColor = _hovered
        ? (isDark ? const Color(0xFF99F6E4) : BrandColors.teal700)
        : (isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155));

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        constraints: const BoxConstraints(minHeight: 46),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: fillColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
          // Design audit: elevation sutil para affordance de botão clicável.
          // Antes: sem shadow, parecia linha de texto. Agora: card com depth.
          boxShadow: _hovered
              ? null
              : [
                  BoxShadow(
                    color: isDark
                        ? Colors.black.withValues(alpha: .08)
                        : const Color(0xFF94A3B8).withValues(alpha: .12),
                    offset: const Offset(0, 2),
                    blurRadius: 8,
                  ),
                ],
        ),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(14),
          child: Row(
            children: [
              Icon(widget.icon, size: 18, color: contentColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  // Design audit: maxLines 2 + fontSize 13 para evitar
                  // truncamento em mobile (390px). "Checar interações"
                  // e "Consultor de horários" cabem em 2 linhas.
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: contentColor,
                  ),
                ),
              ),
              // Design audit: chevron sinaliza que é clicável.
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: contentColor.withValues(alpha: .6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
