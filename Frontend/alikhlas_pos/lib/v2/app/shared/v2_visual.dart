part of '../v2_app.dart';

class _ThemeModeControl extends ConsumerWidget {
  const _ThemeModeControl({this.compact = false});
  final bool compact;
  Future<void> _change(BuildContext context, WidgetRef ref, String mode) async {
    try {
      await ref.read(appThemeModeProvider.notifier).change(mode);
    } catch (_) {
      if (context.mounted) {
        _showSnack(context, 'تعذر حفظ المظهر. أعد المحاولة.');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preference = ref.watch(appThemeModeProvider);
    if (compact) {
      final dark = Theme.of(context).brightness == Brightness.dark;
      return IconButton(
        key: const ValueKey('theme-toggle'),
        tooltip: dark ? 'التبديل للمظهر الفاتح' : 'التبديل للمظهر الداكن',
        onPressed: preference.isLoading
            ? null
            : () => _change(context, ref, dark ? 'light' : 'dark'),
        icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
      );
    }
    final mode = preference.asData?.value ?? 'light';
    return DropdownButtonFormField<String>(
      key: ValueKey('appearance-$mode'),
      initialValue: mode,
      decoration: const InputDecoration(labelText: 'مظهر التطبيق'),
      items: const [
        DropdownMenuItem(value: 'light', child: Text('فاتح')),
        DropdownMenuItem(value: 'dark', child: Text('داكن')),
        DropdownMenuItem(value: 'system', child: Text('حسب النظام')),
      ],
      onChanged: preference.isLoading
          ? null
          : (v) {
              if (v != null) _change(context, ref, v);
            },
    );
  }
}

class _Screen extends StatelessWidget {
  const _Screen({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GlassPane(
          enableBlur: true,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(child: child),
      ],
    );
  }
}

class _GlassStage extends StatelessWidget {
  const _GlassStage({required this.child, this.background});

  final Widget child;
  final UiBackgroundSnapshot? background;

  @override
  Widget build(BuildContext context) {
    final imagePath = background?.imagePath;
    final imageFile = imagePath == null ? null : File(imagePath);
    final hasImage = imageFile != null && imageFile.existsSync();
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: _backgroundGradient(
                background?.preset ?? 'aurora',
                Theme.of(context).brightness == Brightness.dark,
              ),
            ),
          ),
          if (hasImage)
            Image.file(
              imageFile,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          if (hasImage)
            DecoratedBox(
              decoration: BoxDecoration(
                color: LiquidGlassColors.of(
                  context,
                ).stage.withValues(alpha: .84),
              ),
            ),
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _LiquidBackdropPainter(
                  preset: background?.preset ?? 'aurora',
                  dark: Theme.of(context).brightness == Brightness.dark,
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _GlassPane extends StatelessWidget {
  const _GlassPane({
    required this.child,
    this.width,
    this.padding,
    this.enableBlur = false,
  });
  final Widget child;
  final double? width;
  final EdgeInsetsGeometry? padding;
  final bool enableBlur;
  @override
  Widget build(BuildContext context) => LiquidGlassSurface(
    width: width,
    padding: padding ?? const EdgeInsets.all(16),
    enableBlur: enableBlur,
    child: child,
  );
}

class _LiquidBackdropPainter extends CustomPainter {
  const _LiquidBackdropPainter({required this.preset, required this.dark});
  final String preset;
  final bool dark;
  @override
  void paint(Canvas canvas, Size size) {
    final palette = _backgroundPalette(preset);
    final rect = Offset.zero & size;
    for (final orb in [
      (const Alignment(.9, -.95), palette.$1, .64),
      (const Alignment(-.95, .65), palette.$2, .72),
      (const Alignment(.4, 1.4), palette.$3, .50),
    ]) {
      final paint = Paint()
        ..shader = RadialGradient(
          center: orb.$1,
          radius: orb.$3,
          colors: [
            orb.$2.withValues(alpha: dark ? .13 : .18),
            orb.$2.withValues(alpha: 0),
          ],
        ).createShader(rect);
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_LiquidBackdropPainter old) =>
      old.preset != preset || old.dark != dark;
}

LinearGradient _backgroundGradient(String preset, bool dark) {
  final base = LiquidGlassColors(dark: dark).stage;
  return LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [
      base,
      dark ? const Color(0xFF13262A) : const Color(0xFFE8F1F2),
      base,
    ],
  );
}

(Color, Color, Color) _backgroundPalette(String preset) {
  return switch (preset) {
    'sky' => (
      const Color(0xFF78D6F4),
      const Color(0xFF7E8EE8),
      const Color(0xFFEAF7FF),
    ),
    'blush' => (
      const Color(0xFFE9A7A0),
      const Color(0xFFB7A6F4),
      const Color(0xFFFFE8D9),
    ),
    'graphite' => (
      const Color(0xFF90A4AE),
      const Color(0xFF607D8B),
      const Color(0xFFECEFF1),
    ),
    _ => (V2DesignTokens.mint, V2DesignTokens.iris, V2DesignTokens.rose),
  };
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.metrics});
  final List<(String, int, IconData)> metrics;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: metrics.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 230,
        mainAxisExtent: 112,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemBuilder: (context, index) {
        final item = metrics[index];
        return _GlassPane(
          enableBlur: false,
          child: Row(
            children: [
              Icon(item.$3, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        Money(item.$2).format(),
                        maxLines: 1,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TextMetricsGrid extends StatelessWidget {
  const _TextMetricsGrid({required this.metrics});
  final List<(String, String, IconData)> metrics;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: metrics.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 230,
        mainAxisExtent: 112,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemBuilder: (context, index) {
        final item = metrics[index];
        return _GlassPane(
          enableBlur: false,
          child: Row(
            children: [
              Icon(item.$3, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        item.$2,
                        maxLines: 1,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
