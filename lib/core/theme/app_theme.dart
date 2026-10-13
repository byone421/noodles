import 'package:flutter/material.dart';

abstract final class AppColors {
  static const background = Color(0xFFF4F5F0);
  static const text = Color(0xFF17231F);
  static const muted = Color(0xFF68756E);
  static const primary = Color(0xFF286B58);
  static const deep = Color(0xFF174C3E);
  static const soft = Color(0xFFEAF1EC);
  static const accent = Color(0xFFD98B45);
  static const border = Color(0xFFDCE4DD);
}

abstract final class AppTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      surface: Colors.white,
      onSurface: AppColors.text,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: 'sans',
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        hintStyle: const TextStyle(color: AppColors.muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
    );
  }
}
