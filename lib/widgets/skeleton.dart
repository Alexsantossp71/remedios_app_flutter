import 'package:flutter/material.dart';

import '../core/design/app_tokens.dart';

/// Skeleton de carregamento V4: blocos suaves que respiram (pulse de
/// opacidade) no lugar dos spinners de tela cheia — o conteúdo "chega"
/// em vez de "girar".
class SkeletonList extends StatefulWidget {
  const SkeletonList({super.key, this.cards = 4});

  /// Quantidade de blocos de card simulados.
  final int cards;

  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppDurations.slow,
      lowerBound: .35,
      upperBound: .8,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < widget.cards; i++) ...[
            _SkeletonCard(),
            const SizedBox(height: AppSpacing.md),
          ],
        ],
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shape = theme.colorScheme.surfaceContainerHighest.withValues(
      alpha: .8,
    );
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: .3)),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: shape, borderRadius: BorderRadius.circular(AppRadius.iconBox)),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 60, height: 12, color: shape),
                const SizedBox(height: AppSpacing.sm),
                FractionallySizedBox(
                  widthFactor: .7,
                  child: Container(height: 14, color: shape),
                ),
                const SizedBox(height: AppSpacing.sm),
                FractionallySizedBox(
                  widthFactor: .45,
                  child: Container(height: 12, color: shape),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
