import 'package:flutter/material.dart';

class V2DesignTokens {
  const V2DesignTokens._();

  static const ink = Color(0xFF13201F);
  static const inkMuted = Color(0xFF465C5A);
  static const peacock = Color(0xFF0D6C68);
  static const peacockDeep = Color(0xFF084C4A);
  static const mint = Color(0xFF3DD6B4);
  static const copper = Color(0xFFC27846);
  static const iris = Color(0xFF7E8EE8);
  static const rose = Color(0xFFE9A7A0);
  static const pearl = Color(0xFFF7FAF8);
  static const glassWhite = Color(0x8FFFFFFF);
  static const glassStroke = Color(0xF2FFFFFF);

  static const space8 = 8.0;
  static const space16 = 16.0;

  static const radiusMd = 16.0;
  static const radiusXl = 28.0;

  static BorderRadius get radiusXlBorder => BorderRadius.circular(radiusXl);

  static final softPaneShadow = BoxShadow(
    color: Colors.black.withValues(alpha: 0.11),
    blurRadius: 38,
    offset: const Offset(0, 20),
  );

  static final softControlShadow = BoxShadow(
    color: Colors.black.withValues(alpha: 0.04),
    blurRadius: 14,
    offset: const Offset(0, 6),
  );

  static LinearGradient get stageGradient => const LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [
      Color(0xFFD5ECE7),
      Color(0xFFF4ECE3),
      Color(0xFFD7E0F4),
      Color(0xFFF8FBFA),
    ],
    stops: [0, 0.36, 0.72, 1],
  );

  static LinearGradient get paneSurface => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Colors.white.withValues(alpha: 0.72),
      Colors.white.withValues(alpha: 0.34),
      mint.withValues(alpha: 0.08),
      iris.withValues(alpha: 0.10),
    ],
    stops: const [0, 0.42, 0.74, 1],
  );

  static LinearGradient get paneHighlight => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Colors.white.withValues(alpha: 0.95),
      Colors.white.withValues(alpha: 0.24),
      Colors.white.withValues(alpha: 0.04),
    ],
    stops: const [0, 0.34, 1],
  );
}

/// Semantic colors shared by controls, glass chrome and dense business data.
/// Document/PDF colors deliberately do not depend on this palette.
class LiquidGlassColors {
  const LiquidGlassColors({required this.dark, this.highContrast = false});
  factory LiquidGlassColors.of(BuildContext context) => LiquidGlassColors(
    dark: Theme.of(context).brightness == Brightness.dark,
    highContrast: MediaQuery.highContrastOf(context),
  );
  final bool dark;
  final bool highContrast;
  Color get ink => dark ? const Color(0xFFF1F8F7) : V2DesignTokens.ink;
  Color get muted => dark ? const Color(0xFFB7CAC7) : V2DesignTokens.inkMuted;
  Color get stage => dark ? const Color(0xFF101A20) : const Color(0xFFF0F5F5);
  Color get surface => dark ? const Color(0xFF1C2B32) : const Color(0xFFF8FBFB);
  Color get control => dark ? const Color(0xFF253840) : const Color(0xFFF9FCFC);
  Color get primary => dark ? const Color(0xFF82E1CE) : const Color(0xFF075E58);
  Color get onPrimary => dark ? const Color(0xFF063C36) : Colors.white;
  Color get stroke => highContrast
      ? muted
      : (dark
            ? Colors.white.withValues(alpha: .22)
            : const Color(0xFF8DA9A8).withValues(alpha: .4));
  Color get selected =>
      dark ? const Color(0xFF2E514F) : const Color(0xFFD8ECE7);
  Color get row => dark ? const Color(0xFF22363E) : const Color(0xFFF4FAF8);
  Color get error => dark ? const Color(0xFFFFB4AB) : const Color(0xFFA82525);
  Color get warning => dark ? const Color(0xFFFFDBA3) : const Color(0xFF815016);
  Color get success => dark ? const Color(0xFF97DFC0) : const Color(0xFF166246);
  LinearGradient surfaceGradient({required bool chrome}) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: highContrast
        ? [surface, surface]
        : dark
        ? [
            surface.withValues(alpha: chrome ? .82 : .97),
            const Color(0xFF263A43).withValues(alpha: chrome ? .65 : .93),
          ]
        : [
            Colors.white.withValues(alpha: chrome ? .80 : .96),
            const Color(0xFFEAF4F3).withValues(alpha: chrome ? .54 : .90),
          ],
  );
}
