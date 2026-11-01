import 'package:flutter/material.dart';

/// Tokens de design do RxKit — a fundação "V4 companheiro calmo".
///
/// Números de espaçamento, raio, duração e curva vivem aqui. Componentes e
/// telas consomem os tokens em vez de literais soltos, garantindo ritmo
/// visual consistente (a escala de raio acaba com os 10 valores dispersos
/// — 4, 8, 10, 12, 16, 18, 20, 22, 24 — mapeando para 5 graus + pill).
abstract final class AppSpacing {
  /// 4 — micro ajuste (ícone↔texto).
  static const double xs = 4;

  /// 8 — respiro interno pequeno.
  static const double sm = 8;

  /// 12 — separação entre cards de lista.
  static const double md = 12;

  /// 16 — padding padrão de card.
  static const double lg = 16;

  /// 20 — padding lateral de tela.
  static const double xl = 20;

  /// 24 — bloco entre seções.
  static const double xxl = 24;

  /// 32 — estado vazio / herói.
  static const double huge = 32;
}

abstract final class AppRadius {
  /// 8 — listas de sugestão, notas.
  static const double sm = 8;

  /// 12 — badges e chips retangulares.
  static const double md = 12;

  /// 16 — inputs (padrão do tema).
  static const double lg = 16;

  /// 18 — caixas de ícone e FAB.
  static const double iconBox = 18;

  /// 24 — cards e heróis (padrão do tema).
  static const double xl = 24;

  /// Pílula completa (chips, estádios).
  static const StadiumBorder pill = StadiumBorder();
}

abstract final class AppDurations {
  /// 150ms — feedback imediato (press, check).
  static const Duration fast = Duration(milliseconds: 150);

  /// 250ms — transições de UI (aba, chip).
  static const Duration medium = Duration(milliseconds: 250);

  /// 400ms — entrada de conteúdo, confete.
  static const Duration slow = Duration(milliseconds: 400);
}

abstract final class AppCurves {
  /// Saída suave — o padrão "calmo" do app.
  static final Cubic emphasized = Curves.easeOutCubic;

  /// Entrada invertida para animações que saem da tela.
  static final Cubic emphasizedFlipped = Curves.easeInCubic;
}
