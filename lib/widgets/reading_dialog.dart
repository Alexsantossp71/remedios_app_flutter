import 'dart:async';

import 'package:flutter/material.dart';

import '../core/design/app_tokens.dart';
import '../core/theme/app_theme.dart';

/// Diálogo único de "lendo com OCR…" usado por receitas (tratamentos),
/// receitas de médico e cartões de plano — substitui as 3 cópias antigas.
///
/// Momento de deleite do V4: uma linha de escaneamento varre um frasco de
/// receita enquanto o texto de rodapé explica o que está acontecendo.
Future<void> showReadingDialog(
  BuildContext context, {
  String title = 'Lendo receita…',
  String subtitle = 'Pode levar alguns segundos.',
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ReadingDialog(title: title, subtitle: subtitle),
  );
}

class ReadingDialog extends StatefulWidget {
  const ReadingDialog({
    super.key,
    this.title = 'Lendo receita…',
    this.subtitle = 'Pode levar alguns segundos.',
  });

  final String title;
  final String subtitle;

  @override
  State<ReadingDialog> createState() => _ReadingDialogState();
}

class _ReadingDialogState extends State<ReadingDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scan;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppDurations.slow * 3)
      ..repeat(reverse: true);
    _scan = CurvedAnimation(parent: _controller, curve: AppCurves.emphasized);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);

    return PopScope(
      canPop: false,
      child: Dialog(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Frasco de receita com linha de escaneamento varrendo.
              SizedBox(
                width: 92,
                height: 92,
                child: AnimatedBuilder(
                  animation: _scan,
                  builder: (context, _) => CustomPaint(
                    painter: _ScanningPrescriptionPainter(
                      scanY: _scan.value,
                      stroke: theme.colorScheme.primary,
                      fill: theme.colorScheme.primaryContainer,
                      scanColor: semantic.success,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(widget.title, style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                widget.subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanningPrescriptionPainter extends CustomPainter {
  _ScanningPrescriptionPainter({
    required this.scanY,
    required this.stroke,
    required this.fill,
    required this.scanColor,
  });

  final double scanY;
  final Color stroke;
  final Color fill;
  final Color scanColor;

  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = stroke;

    // Corpo do frasco.
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(22, 26, 48, 58),
      const Radius.circular(10),
    );
    canvas.drawRRect(body, Paint()..color = fill.withValues(alpha: .35));
    canvas.drawRRect(body, strokePaint);

    // Tampa.
    final cap = RRect.fromRectAndRadius(
      Rect.fromLTWH(30, 12, 32, 12),
      const Radius.circular(4),
    );
    canvas.drawRRect(cap, Paint()..color = fill);
    canvas.drawRRect(cap, strokePaint);

    // Linhas de texto no rótulo.
    final textPaint = Paint()
      ..color = stroke.withValues(alpha: .45)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(32, 46), const Offset(60, 46), textPaint);
    canvas.drawLine(const Offset(32, 56), const Offset(52, 56), textPaint);
    canvas.drawLine(const Offset(32, 66), const Offset(58, 66), textPaint);

    // Linha de escaneamento (verde-saúde) varrendo o frasco.
    final y = 20 + scanY * 70;
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = scanColor;
    canvas.drawLine(Offset(14, y), Offset(78, y), glow);
    canvas.drawCircle(Offset(78, y), 3, Paint()..color = scanColor);
  }

  @override
  bool shouldRepaint(covariant _ScanningPrescriptionPainter oldDelegate) =>
      oldDelegate.scanY != scanY;
}
