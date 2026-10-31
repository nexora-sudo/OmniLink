import 'dart:ui';
import 'package:flutter/material.dart';

class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
  });
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: (dark ? const Color(0xff17283b) : Colors.white).withValues(
              alpha: .72,
            ),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: Colors.white.withValues(alpha: dark ? .12 : .8),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

ThemeData omniTheme(Brightness brightness) {
  final colors = ColorScheme.fromSeed(
    seedColor: const Color(0xff087f86),
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    brightness: brightness,
    scaffoldBackgroundColor: Colors.transparent,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
