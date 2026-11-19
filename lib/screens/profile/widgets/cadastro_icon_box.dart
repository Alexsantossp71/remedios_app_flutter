import 'package:material_ui/material_ui.dart';

import '../../../core/design/brand_colors.dart';

/// Caixa de ícone `.stat-icon` do PWA para os atalhos de cadastro do
/// Perfil: véu teal com anel fino, no claro e no escuro.
class CadastroIconBox extends StatelessWidget {
  const CadastroIconBox({super.key, required this.icon, required this.isDark});

  final IconData icon;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: isDark
            ? BrandColors.teal700.withValues(alpha: .18)
            : BrandColors.accentSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BrandColors.teal700.withValues(alpha: .07)),
      ),
      child: Icon(icon, color: BrandColors.teal700, size: 22),
    );
  }
}
