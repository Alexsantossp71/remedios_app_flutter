/// Confete V4: cápsulas e comprimidos caindo de verdade (CustomPainter)
/// nas cores verde-saúde do tema, disparado quando a última dose do dia
/// é concluída.
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../core/design/app_tokens.dart';
import '../../../core/theme/app_theme.dart';

/// Confete V4: cápsulas e comprimidos caindo de verdade (CustomPainter),
/// nas cores verde-saúde do tema — comemora sem virar carnaval.
void showCapsuleConfetti(BuildContext context) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => CapsuleConfetti(onDone: () => entry.remove()),
  );
  overlay.insert(entry);
}

class CapsuleConfetti extends StatefulWidget {
  const CapsuleConfetti({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<CapsuleConfetti> createState() => _CapsuleConfettiState();
}

class _CapsuleConfettiState extends State<CapsuleConfetti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_ConfettiParticle> _particles;
  static final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppDurations.slow * 4,
    );
    _controller.forward().whenComplete(widget.onDone);
    _particles = List.generate(26, (_) => _ConfettiParticle.random(_random));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _ConfettiPainter(
            progress: _controller.value,
            particles: _particles,
            baseColor: semantic.success,
          ),
          size: MediaQuery.sizeOf(context),
        ),
      ),
    );
  }
}

class _ConfettiParticle {
  _ConfettiParticle({
    required this.startX,
    required this.delay,
    required this.fallSpeed,
    required this.drift,
    required this.rotation,
    required this.spin,
    required this.size,
    required this.isCapsule,
    required this.shade,
  });

  factory _ConfettiParticle.random(math.Random random) {
    return _ConfettiParticle(
      startX: random.nextDouble(),
      delay: random.nextDouble() * .35,
      fallSpeed: .55 + random.nextDouble() * .45,
      drift: (random.nextDouble() - .5) * .18,
      rotation: random.nextDouble() * math.pi * 2,
      spin: (random.nextDouble() - .5) * 5,
      size: 7 + random.nextDouble() * 7,
      isCapsule: random.nextBool(),
      shade: random.nextDouble(),
    );
  }

  final double startX;
  final double delay;
  final double fallSpeed;
  final double drift;
  final double rotation;
  final double spin;
  final double size;
  final bool isCapsule;
  final double shade;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({
    required this.progress,
    required this.particles,
    required this.baseColor,
  });

  final double progress;
  final List<_ConfettiParticle> particles;
  final Color baseColor;

  @override
  void paint(Canvas canvas, Size size) {
    for (final particle in particles) {
      final local = (progress - particle.delay) / (1 - particle.delay);
      if (local <= 0 || local >= 1) continue;
      final y = -30 + local * particle.fallSpeed * (size.height + 60);
      final x =
          particle.startX * size.width + particle.drift * local * size.width;
      final angle = particle.rotation + particle.spin * local * math.pi;
      final opacity = local > .8 ? (1 - local) / .2 : 1.0;
      final color = Color.lerp(
        baseColor,
        baseColor.withValues(alpha: .55),
        particle.shade,
      )!.withValues(alpha: opacity);

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle);
      final paint = Paint()..color = color;
      if (particle.isCapsule) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: particle.size * 1.8,
              height: particle.size * .8,
            ),
            Radius.circular(particle.size * .4),
          ),
          paint,
        );
      } else {
        canvas.drawCircle(Offset.zero, particle.size * .45, paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
