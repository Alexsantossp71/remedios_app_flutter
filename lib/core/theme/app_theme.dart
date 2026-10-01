import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData v1() {
    return _buildTheme(
      seedColor: const Color(0xFF1E9D6A),
      canvasColor: const Color(0xFFF4FBF7),
      inputFill: const Color(0xFFEAF7F1),
      titleColor: const Color(0xFF173225),
      accentLabel: 'V1 - Verde',
    );
  }

  static ThemeData v2() {
    return _buildTheme(
      seedColor: const Color(0xFF1E63E8),
      canvasColor: const Color(0xFFF3F8FF),
      inputFill: const Color(0xFFE8F0FF),
      titleColor: const Color(0xFF102A56),
      accentLabel: 'V2 - Azul',
    );
  }

  static ThemeData light() => v2();

  static ThemeData _buildTheme({
    required Color seedColor,
    required Color canvasColor,
    required Color inputFill,
    required Color titleColor,
    required String accentLabel,
  }) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
      surface: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: canvasColor,
      appBarTheme: AppBarTheme(
        backgroundColor: canvasColor,
        foregroundColor: titleColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFill,
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
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: Colors.white,
        indicatorColor: colorScheme.primaryContainer,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w700, color: colorScheme.onSurface),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      extensions: <ThemeExtension<dynamic>>[
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
