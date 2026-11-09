import 'package:flutter/material.dart';

import 'design_tokens.dart';

ThemeData buildV2Theme({Brightness brightness = Brightness.light}) {
  final glass = LiquidGlassColors(dark: brightness == Brightness.dark);
  final ink = glass.ink;
  final inkMuted = glass.muted;

  final baseTextTheme = TextTheme(
    displaySmall: TextStyle(
      color: ink,
      fontWeight: FontWeight.w700,
      fontSize: 34,
      height: 1.3,
    ),
    headlineLarge: TextStyle(
      color: ink,
      fontWeight: FontWeight.w700,
      fontSize: 28,
      height: 1.3,
    ),
    headlineMedium: TextStyle(
      color: ink,
      fontWeight: FontWeight.w700,
      fontSize: 23,
      height: 1.32,
    ),
    headlineSmall: TextStyle(
      color: ink,
      fontWeight: FontWeight.w600,
      fontSize: 20,
      height: 1.35,
    ),
    titleLarge: TextStyle(
      color: ink,
      fontWeight: FontWeight.w600,
      fontSize: 18,
      height: 1.38,
    ),
    titleMedium: TextStyle(
      color: ink,
      fontWeight: FontWeight.w600,
      fontSize: 16,
      height: 1.4,
    ),
    titleSmall: TextStyle(
      color: ink,
      fontWeight: FontWeight.w600,
      fontSize: 14,
      height: 1.4,
    ),
    bodyLarge: TextStyle(
      color: ink,
      fontWeight: FontWeight.w400,
      fontSize: 15,
      height: 1.5,
    ),
    bodyMedium: TextStyle(
      color: ink,
      fontWeight: FontWeight.w400,
      fontSize: 14,
      height: 1.5,
    ),
    bodySmall: TextStyle(
      color: inkMuted,
      fontWeight: FontWeight.w400,
      fontSize: 12,
      height: 1.5,
    ),
    labelLarge: TextStyle(
      color: ink,
      fontWeight: FontWeight.w600,
      fontSize: 14,
      height: 1.22,
    ),
    labelMedium: TextStyle(
      color: ink,
      fontWeight: FontWeight.w600,
      fontSize: 12,
      height: 1.22,
    ),
    labelSmall: TextStyle(
      color: inkMuted,
      fontWeight: FontWeight.w500,
      fontSize: 11,
      height: 1.2,
    ),
  ).apply(fontFamily: 'Cairo');

  final roundedFieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(V2DesignTokens.radiusMd),
    borderSide: BorderSide(color: glass.stroke),
  );

  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Cairo',
    colorScheme: ColorScheme.fromSeed(
      seedColor: V2DesignTokens.peacock,
      brightness: brightness,
      surface: glass.surface,
      onSurface: glass.ink,
      onSurfaceVariant: glass.muted,
      onPrimary: glass.onPrimary,
      error: glass.error,
      primary: glass.primary,
      secondary: V2DesignTokens.copper,
      tertiary: V2DesignTokens.mint,
    ),
    scaffoldBackgroundColor: glass.stage,
    textTheme: baseTextTheme,
    dialogTheme: DialogThemeData(
      backgroundColor: glass.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: glass.stroke),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: glass.surface,
      surfaceTintColor: Colors.transparent,
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(glass.surface),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? glass.primary
              : glass.muted,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? glass.selected
              : Colors.transparent,
        ),
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: glass.control,
      selectedColor: glass.selected,
      side: BorderSide(color: glass.stroke),
      labelStyle: baseTextTheme.labelLarge!.copyWith(color: glass.ink),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    snackBarTheme: SnackBarThemeData(
      // Reserve space for feedback so the checkout actions remain clickable.
      behavior: SnackBarBehavior.fixed,
      backgroundColor: brightness == Brightness.dark
          ? const Color(0xFFD5EEE7)
          : const Color(0xFF173B38),
      contentTextStyle: TextStyle(
        fontFamily: 'Cairo',
        color: brightness == Brightness.dark
            ? const Color(0xFF13201F)
            : Colors.white,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: glass.control,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: roundedFieldBorder,
      enabledBorder: roundedFieldBorder,
      focusedBorder: roundedFieldBorder.copyWith(
        borderSide: BorderSide(color: glass.primary, width: 1.6),
      ),
      errorBorder: roundedFieldBorder.copyWith(
        borderSide: BorderSide(color: glass.error),
      ),
      focusedErrorBorder: roundedFieldBorder.copyWith(
        borderSide: BorderSide(color: glass.error, width: 1.6),
      ),
      labelStyle: TextStyle(color: inkMuted),
      hintStyle: TextStyle(color: inkMuted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: glass.primary,
        foregroundColor: glass.onPrimary,
        shadowColor: glass.primary.withValues(alpha: .22),
        elevation: 2,
        side: BorderSide(color: glass.onPrimary.withValues(alpha: .20)),
        minimumSize: const Size(44, 44),
        shape: const StadiumBorder(),
        textStyle: baseTextTheme.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 44),
        foregroundColor: glass.primary,
        backgroundColor: glass.control.withValues(alpha: .68),
        side: BorderSide(color: glass.stroke),
        shape: const StadiumBorder(),
        textStyle: baseTextTheme.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(textStyle: baseTextTheme.labelLarge),
    ),
    dividerTheme: DividerThemeData(
      color: glass.muted.withValues(alpha: 0.20),
      thickness: 1,
      space: 1,
    ),
  );
}
