import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Ilustrações de linha dos estados vazios — traço fino na cor de ação do
/// tema, preenchimentos suaves no contêiner e um toque de verde-saúde.
/// Desenhadas com [CustomPainter] (zero dependências, escalam sem perda e
/// herdam as cores do tema claro/escuro automaticamente).
enum EmptyIllustrationKind {
  freeDay,
  pillBottle,
  calendarHeart,
  shieldPlus,
  stethoscope,
}

class EmptyIllustration extends StatelessWidget {
  const EmptyIllustration({
    super.key,
    required this.kind,
    this.width = 170,
    this.height = 128,
  });

  final EmptyIllustrationKind kind;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _EmptyIllustrationPainter(
          kind: kind,
          stroke: theme.colorScheme.primary,
          fill: theme.colorScheme.primaryContainer,
          accent: AppSemanticColors.of(context).success,
          surface: theme.colorScheme.surface,
        ),
      ),
    );
  }
}

class _EmptyIllustrationPainter extends CustomPainter {
  _EmptyIllustrationPainter({
    required this.kind,
    required this.stroke,
    required this.fill,
    required this.accent,
    required this.surface,
  });

  final EmptyIllustrationKind kind;
  final Color stroke;
  final Color fill;
  final Color accent;
  final Color surface;

  static const _strokeWidth = 2.6;

  Paint get _strokePaint =>
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = stroke;

  Paint get _fillPaint =>
      Paint()
        ..style = PaintingStyle.fill
        ..color = fill;

  Paint get _surfacePaint =>
      Paint()
        ..style = PaintingStyle.fill
        ..color = surface;

  Paint get _accentPaint =>
      Paint()
        ..style = PaintingStyle.fill
        ..color = accent;

  @override
  void paint(Canvas canvas, Size size) {
    switch (kind) {
      case EmptyIllustrationKind.freeDay:
        _paintSunClock(canvas, size);
      case EmptyIllustrationKind.pillBottle:
        _paintPillBottle(canvas, size);
      case EmptyIllustrationKind.calendarHeart:
        _paintCalendarHeart(canvas, size);
      case EmptyIllustrationKind.shieldPlus:
        _paintShieldPlus(canvas, size);
      case EmptyIllustrationKind.stethoscope:
        _paintStethoscope(canvas, size);
    }
  }

  /// Sol com raios + relógio: o dia livre de doses.
  void _paintSunClock(Canvas canvas, Size size) {
    final sun = Offset(size.width * 0.36, size.height * 0.36);
    final clock = Offset(size.width * 0.68, size.height * 0.66);

    // Sol: disco suave + contorno + raios curtos.
    canvas.drawCircle(sun, 19, _fillPaint);
    canvas.drawCircle(sun, 19, _strokePaint);
    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4;
      final from = sun + Offset(math.cos(angle), math.sin(angle)) * 25;
      final to = sun + Offset(math.cos(angle), math.sin(angle)) * 32;
      canvas.drawLine(from, to, _strokePaint);
    }

    // Relógio: círculo branco com contorno, ponteiros em destaque.
    canvas.drawCircle(clock, 24, _surfacePaint);
    canvas.drawCircle(clock, 24, _strokePaint);
    canvas.drawLine(
      clock,
      clock + const Offset(0, -13),
      _strokePaint..strokeWidth = 3,
    );
    canvas.drawLine(
      clock,
      clock + const Offset(9, 2),
      _strokePaint..strokeWidth = 3,
    );

    // Faísca: pequena estrela de quatro pontas no alto à direita.
    final spark = Offset(size.width * 0.86, size.height * 0.18);
    final star =
        Path()
          ..moveTo(spark.dx, spark.dy - 7)
          ..quadraticBezierTo(spark.dx, spark.dy, spark.dx + 7, spark.dy)
          ..quadraticBezierTo(spark.dx, spark.dy, spark.dx, spark.dy + 7)
          ..quadraticBezierTo(spark.dx, spark.dy, spark.dx - 7, spark.dy)
          ..quadraticBezierTo(spark.dx, spark.dy, spark.dx, spark.dy - 7);
    canvas.drawPath(star, _accentPaint);
  }

  /// Frasco de remédio + cápsula + comprimido: comece seu tratamento.
  void _paintPillBottle(Canvas canvas, Size size) {
    final left = size.width * 0.28;
    final top = size.height * 0.34;

    // Tampa e gargalo.
    final cap = RRect.fromRectAndRadius(
      Rect.fromLTWH(left + 2, top - 16, 52, 14),
      const Radius.circular(5),
    );
    canvas.drawRRect(cap, _fillPaint);
    canvas.drawRRect(cap, _strokePaint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left + 9, top - 2, 38, 10),
        const Radius.circular(3),
      ),
      _surfacePaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left + 9, top - 2, 38, 10),
        const Radius.circular(3),
      ),
      _strokePaint,
    );

    // Corpo do frasco.
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(left - 4, top + 8, 66, 62),
      const Radius.circular(12),
    );
    canvas.drawRRect(body, _surfacePaint);
    canvas.drawRRect(body, _strokePaint);

    // Rótulo com cruz de saúde.
    final label = RRect.fromRectAndRadius(
      Rect.fromLTWH(left + 4, top + 30, 50, 26),
      const Radius.circular(6),
    );
    canvas.drawRRect(label, _fillPaint);
    final cx = left + 29;
    final cy = top + 43;
    canvas.drawLine(Offset(cx - 6, cy), Offset(cx + 6, cy), _strokePaint);
    canvas.drawLine(Offset(cx, cy - 6), Offset(cx, cy + 6), _strokePaint);

    // Cápsula inclinada (metade verde) ao lado do frasco.
    canvas.save();
    canvas.translate(size.width * 0.76, size.height * 0.80);
    canvas.rotate(-0.6);
    final capsule = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: 34, height: 15),
      const Radius.circular(7.5),
    );
    canvas.drawRRect(capsule, _surfacePaint);
    canvas.save();
    canvas.clipRRect(capsule);
    canvas.drawRect(Rect.fromLTWH(-17, -8, 17, 16), _accentPaint);
    canvas.restore();
    canvas.drawRRect(capsule, _strokePaint);
    canvas.restore();

    // Comprimido redondo com vinco.
    final tablet = Offset(size.width * 0.14, size.height * 0.84);
    canvas.drawCircle(tablet, 9, _surfacePaint);
    canvas.drawCircle(tablet, 9, _strokePaint);
    canvas.drawLine(
      tablet + const Offset(-6, 0),
      tablet + const Offset(6, 0),
      _strokePaint,
    );
  }

  /// Calendário com coração: nenhuma consulta agendada.
  void _paintCalendarHeart(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      size.width * 0.24,
      size.height * 0.22,
      size.width * 0.52,
      size.height * 0.66,
    );
    final frame = RRect.fromRectAndRadius(rect, const Radius.circular(14));

    canvas.drawRRect(frame, _surfacePaint);
    // Faixa do cabeçalho.
    canvas.save();
    canvas.clipRRect(frame);
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.top, rect.width, 20),
      _fillPaint,
    );
    canvas.restore();
    canvas.drawRRect(frame, _strokePaint);

    // Argolas.
    for (final x in [
      rect.left + rect.width * 0.28,
      rect.left + rect.width * 0.72,
    ]) {
      canvas.drawLine(
        Offset(x, rect.top - 8),
        Offset(x, rect.top + 8),
        _strokePaint..strokeWidth = 3,
      );
    }

    // Coração dentro do calendário.
    final center = Offset(
      rect.left + rect.width / 2,
      rect.top + rect.height * 0.62,
    );
    final r = 13.0;
    final heart =
        Path()
          ..moveTo(center.dx, center.dy + r * 0.85)
          ..cubicTo(
            center.dx - r * 1.3,
            center.dy - r * 0.2,
            center.dx - r * 0.6,
            center.dy - r * 1.1,
            center.dx,
            center.dy - r * 0.35,
          )
          ..cubicTo(
            center.dx + r * 0.6,
            center.dy - r * 1.1,
            center.dx + r * 1.3,
            center.dy - r * 0.2,
            center.dx,
            center.dy + r * 0.85,
          );
    canvas.drawPath(heart, _accentPaint);

    // Pontinhos de agenda no cabeçalho.
    canvas.drawCircle(
      Offset(rect.left + rect.width * 0.15, rect.top + 10),
      2,
      _surfacePaint,
    );
  }

  /// Escudo com cruz: nenhum plano de saúde cadastrado.
  void _paintShieldPlus(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    final top = size.height * 0.18;
    final halfWidth = size.width * 0.26;
    final bottom = size.height * 0.92;

    final shield =
        Path()
          ..moveTo(cx, top)
          ..lineTo(cx + halfWidth, top + 14)
          ..lineTo(cx + halfWidth, size.height * 0.52)
          ..quadraticBezierTo(cx + halfWidth, size.height * 0.80, cx, bottom)
          ..quadraticBezierTo(
            cx - halfWidth,
            size.height * 0.80,
            cx - halfWidth,
            size.height * 0.52,
          )
          ..lineTo(cx - halfWidth, top + 14)
          ..close();

    canvas.drawPath(shield, _fillPaint);
    canvas.drawPath(shield, _strokePaint);

    // Cruz de saúde no centro, em destaque.
    final cross =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..color = accent;
    canvas.drawLine(Offset(cx, top + 34), Offset(cx, top + 62), cross);
    canvas.drawLine(
      Offset(cx - 14, top + 48),
      Offset(cx + 14, top + 48),
      cross,
    );
  }

  /// Estetoscópio com prontuário: seu catálogo de médicos começa aqui.
  void _paintStethoscope(Canvas canvas, Size size) {
    // Prontuário/cartão clínico ao fundo.
    final card = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.52,
        size.height * 0.16,
        size.width * 0.34,
        size.height * 0.52,
      ),
      const Radius.circular(10),
    );
    canvas.drawRRect(card, _surfacePaint);
    canvas.drawRRect(card, _strokePaint);
    final line =
        Paint()
          ..color = stroke.withValues(alpha: .4)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(card.left + 12, card.top + 18),
      Offset(card.right - 12, card.top + 18),
      line,
    );
    canvas.drawLine(
      Offset(card.left + 12, card.top + 30),
      Offset(card.right - 22, card.top + 30),
      line,
    );

    // Tubo em U do estetoscópio.
    final tube =
        Path()
          ..moveTo(size.width * 0.20, size.height * 0.10)
          ..cubicTo(
            size.width * 0.16,
            size.height * 0.46,
            size.width * 0.34,
            size.height * 0.52,
            size.width * 0.44,
            size.height * 0.62,
          )
          ..cubicTo(
            size.width * 0.56,
            size.height * 0.74,
            size.width * 0.62,
            size.height * 0.78,
            size.width * 0.60,
            size.height * 0.88,
          );
    canvas.drawPath(tube, _strokePaint);

    // Arautos metálicos (olivas) no topo.
    canvas.drawLine(
      Offset(size.width * 0.20, size.height * 0.10),
      Offset(size.width * 0.30, size.height * 0.06),
      _strokePaint,
    );

    // Campânula (disco) na ponta.
    final bell = Offset(size.width * 0.60, size.height * 0.90);
    canvas.drawCircle(bell, 11, _accentPaint);
    canvas.drawCircle(bell, 11, _strokePaint);
  }

  @override
  bool shouldRepaint(covariant _EmptyIllustrationPainter oldDelegate) {
    return oldDelegate.kind != kind ||
        oldDelegate.stroke != stroke ||
        oldDelegate.fill != fill ||
        oldDelegate.accent != accent ||
        oldDelegate.surface != surface;
  }
}
