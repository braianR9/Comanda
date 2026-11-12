import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'brand_colors.dart';

/// Paleta cálida de la landing: papel, tinta y bordes tostados.
class AppColors {
  // Primarios
  static const primary = Color(0xFF1F1B16); // tinta
  static const primaryLight = Color(0xFF2B261F);
  static const accent = Color(0xFFB4502B); // terracota
  static const accentLight = Color(0xFFD7714A);

  // Secundarios
  static const surface = Color(0xFFFBF8F2); // tarjetas y diálogos
  static const background = Color(0xFFF5EFE4); // papel
  static const cardBg = Color(0xFFFBF8F2);
  static const line = Color(0xFFD9CDB8);

  // Texto
  static const textDark = Color(0xFF1F1B16);
  static const textMedium = Color(0xFF6A6157);
  static const textLight = Color(0xFFFFFFFF);

  // Estado
  static const success = Color(0xFF10B981);
  static const error = Color(0xFFEF4444);
  static const warning = Color(0xFFF59E0B);
}

class AppTheme {
  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Brand.primary,
        primary: Brand.primary,
        onPrimary: Brand.onPrimary,
        surface: AppColors.surface,
        background: AppColors.background,
      ),
      scaffoldBackgroundColor: AppColors.background,
      // Texto en Work Sans y títulos en Fraunces, como la landing.
      fontFamily: GoogleFonts.workSans().fontFamily,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textDark,
        titleTextStyle: GoogleFonts.fraunces(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: AppColors.textDark),
      ),
      cardTheme: CardThemeData(
        color: AppColors.cardBg,
        surfaceTintColor: Colors.transparent,
      ),
      dividerColor: AppColors.line,
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.fraunces(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: AppColors.textDark),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFFFDF9),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Brand.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        labelStyle: const TextStyle(color: AppColors.textMedium),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Brand.primary,
          foregroundColor: Brand.onPrimary,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
          textStyle: GoogleFonts.workSans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
