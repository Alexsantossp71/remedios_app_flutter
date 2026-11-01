import 'package:flutter/material.dart';

/// Cores semânticas do app (sucesso, perigo, alerta) que não existem no
/// [ColorScheme] do Material 3. Acessível via
/// `Theme.of(context).extension<AppSemanticColors>()!`.
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.danger,
    required this.warning,
  });

  /// Dose tomada / progresso concluído.
  final Color success;
  final Color onSuccess;
  final Color successContainer;

  /// Atraso / ação destrutiva.
  final Color danger;

  /// Dose atrasada há pouco tempo.
  final Color warning;

  /// Acesso tolerante: se o tema em uso não registrou a extensão (ex.: um
  /// teste com MaterialApp simples), devolve o par claro padrão em vez de
  /// quebrar — a extensão é sempre registrada pelos temas do app.
  static AppSemanticColors of(BuildContext context) {
    return Theme.of(context).extension<AppSemanticColors>() ??
        const AppSemanticColors(
          success: Color(0xFF2E9E6B),
          onSuccess: Colors.white,
          successContainer: Color(0xFFDDF3E7),
          danger: Color(0xFFD64545),
          warning: Color(0xFFB97A0A),
        );
  }

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? danger,
    Color? warning,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      danger: danger ?? this.danger,
      warning: warning ?? this.warning,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer:
          Color.lerp(successContainer, other.successContainer, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }
}

class AppTheme {
  /// V3 — "Clínico calmo": azul de confiança profundo + verde-saúde,
  /// tipografia Nunito. Tema claro.
  static ThemeData v3() {
    return _buildTheme(
      seedColor: const Color(0xFF1E5BA8),
      canvasColor: const Color(0xFFF4F8FD),
      inputFill: const Color(0xFFEAF1FB),
      titleColor: const Color(0xFF0F2A52),
      cardColor: Colors.white,
      navColor: Colors.white,
      semantic: const AppSemanticColors(
        success: Color(0xFF2E9E6B),
        onSuccess: Colors.white,
        successContainer: Color(0xFFDDF3E7),
        danger: Color(0xFFD64545),
        warning: Color(0xFFB97A0A),
      ),
      accentLabel: 'V3 - Clínico calmo (claro)',
    );
  }

  /// V3 escuro: segue o sistema pelo [ThemeMode.system] no MaterialApp.
  /// Superfícies azul-petróleo escuro em vez de cinza puro para manter a
  /// identidade clínica.
  static ThemeData v3Dark() {
    return _buildTheme(
      seedColor: const Color(0xFF7FB0EC),
      canvasColor: const Color(0xFF101826),
      inputFill: const Color(0xFF1B2A40),
      titleColor: const Color(0xFFE7F0FB),
      cardColor: const Color(0xFF17233A),
      navColor: const Color(0xFF142032),
      semantic: const AppSemanticColors(
        success: Color(0xFF63C894),
        onSuccess: Color(0xFF0C2A1C),
        successContainer: Color(0xFF1E4634),
        danger: Color(0xFFF08C8C),
        warning: Color(0xFFE9B45C),
      ),
      accentLabel: 'V3 - Clínico calmo (escuro)',
    );
  }

  static ThemeData light() => v3();

  static ThemeData dark() => v3Dark();

  static ThemeData _buildTheme({
    required Color seedColor,
    required Color canvasColor,
    required Color inputFill,
    required Color titleColor,
    required Color cardColor,
    required Color navColor,
    required AppSemanticColors semantic,
    required String accentLabel,
  }) {
    final isDark = cardColor != Colors.white;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: isDark ? Brightness.dark : Brightness.light,
      surface: cardColor,
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Nunito',
      colorScheme: colorScheme,
      scaffoldBackgroundColor: canvasColor,
      dialogTheme: DialogThemeData(backgroundColor: cardColor),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: cardColor),
      appBarTheme: AppBarTheme(
        backgroundColor: canvasColor,
        foregroundColor: titleColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Nunito',
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: titleColor,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFill,
        labelStyle: TextStyle(color: titleColor.withValues(alpha: .75)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: inputFill,
        // Seleção óbvia: chip escolhido fica PREENCHIDO com o azul de ação
        // (não um contêiner pálido) + check branco. É o estado que o usuário
        // apontou como pouco visível.
        selectedColor: colorScheme.primary,
        checkmarkColor: colorScheme.onPrimary,
        secondarySelectedColor: colorScheme.primary,
        labelStyle: TextStyle(
          fontFamily: 'Nunito',
          fontWeight: FontWeight.w600,
          color: titleColor.withValues(alpha: .85),
        ),
        secondaryLabelStyle: TextStyle(
          fontFamily: 'Nunito',
          fontWeight: FontWeight.w700,
          color: colorScheme.onPrimary,
        ),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: .5),
        ),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: isDark ? navColor : Colors.white,
        indicatorColor: colorScheme.primaryContainer,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontFamily: 'Nunito',
            // Fonte de rótulo menor e em linha única: com 6 destinos em
            // telas de ~412px, o tamanho padrão quebrava "Tratamentos"
            // em duas linhas.
            fontSize: 11.5,
            height: 1.15,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      extensions: <ThemeExtension<dynamic>>[
        semantic,
        _AppBrandExtension(accentLabel: accentLabel),
      ],
    );
  }
}

class _AppBrandExtension extends ThemeExtension<_AppBrandExtension> {
  const _AppBrandExtension({required this.accentLabel});

  final String accentLabel;

  @override
  _AppBrandExtension copyWith({String? accentLabel}) {
    return _AppBrandExtension(accentLabel: accentLabel ?? this.accentLabel);
  }

  @override
  _AppBrandExtension lerp(ThemeExtension<_AppBrandExtension>? other, double t) {
    if (other is! _AppBrandExtension) {
      return this;
    }

    return _AppBrandExtension(
      accentLabel: t < 0.5 ? accentLabel : other.accentLabel,
    );
  }
}
