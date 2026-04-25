import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ─── Palette principale : Vert & Blanc ─────────────────────
  static const Color primary = Color(0xFF1B7F4A);       // Vert profond CAP
  static const Color primaryLight = Color(0xFF2EA05E);  // Vert clair
  static const Color primaryDark = Color(0xFF0F5232);   // Vert foncé
  static const Color primarySurface = Color(0xFFE8F5EE); // Vert très pâle
  static const Color primaryMid = Color(0xFFB2DFCB);    // Vert moyen

  static const Color white = Color(0xFFFFFFFF);
  static const Color offWhite = Color(0xFFF7FBF9);
  static const Color background = Color(0xFFF4FAF7);

  // ─── Neutres ───────────────────────────────────────────────
  static const Color grey100 = Color(0xFFF2F4F3);
  static const Color grey200 = Color(0xFFE2E8E5);
  static const Color grey300 = Color(0xFFC6D2CC);
  static const Color grey400 = Color(0xFF9EB0A7);
  static const Color grey500 = Color(0xFF6B8279);
  static const Color grey600 = Color(0xFF4A5E57);
  static const Color grey700 = Color(0xFF2E3D38);
  static const Color grey800 = Color(0xFF1C2622);

  // ─── Sémantiques ───────────────────────────────────────────
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // ─── Chat bubbles ──────────────────────────────────────────
  static const Color bubbleSent = Color(0xFF1B7F4A);
  static const Color bubbleReceived = Color(0xFFFFFFFF);
  static const Color bubbleSentText = Color(0xFFFFFFFF);
  static const Color bubbleReceivedText = Color(0xFF1C2622);

  // ─── Online indicator ──────────────────────────────────────
  static const Color online = Color(0xFF22C55E);
  static const Color offline = Color(0xFF9EB0A7);
}

class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Nunito',
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        onPrimary: AppColors.white,
        primaryContainer: AppColors.primarySurface,
        onPrimaryContainer: AppColors.primaryDark,
        secondary: AppColors.primaryLight,
        onSecondary: AppColors.white,
        surface: AppColors.white,
        onSurface: AppColors.grey800,
        background: AppColors.background,
        onBackground: AppColors.grey800,
        error: AppColors.error,
      ),
      scaffoldBackgroundColor: AppColors.background,

      // ─── AppBar ──────────────────────────────────────────
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.grey800,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: Color(0x1A1B7F4A),
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.grey700),
        titleTextStyle: TextStyle(
          fontFamily: 'Nunito',
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.grey800,
        ),
      ),

      // ─── Card ────────────────────────────────────────────
      cardTheme: CardThemeData(
        color: AppColors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.grey200, width: 1),
        ),
      ),

      // ─── Input ───────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.grey100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.grey200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        hintStyle: const TextStyle(color: AppColors.grey400, fontSize: 15),
        labelStyle: const TextStyle(color: AppColors.grey500, fontSize: 15),
      ),

      // ─── ElevatedButton ──────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Nunito',
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      // ─── TextButton ──────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(
            fontFamily: 'Nunito',
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ─── ListTile ────────────────────────────────────────
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),

      // ─── Divider ─────────────────────────────────────────
      dividerTheme: const DividerThemeData(
        color: AppColors.grey200,
        thickness: 1,
        space: 1,
      ),

      // ─── Text ────────────────────────────────────────────
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.grey800),
        displayMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.grey800),
        headlineLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.grey800),
        headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.grey800),
        headlineSmall: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.grey800),
        titleLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.grey800),
        titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.grey700),
        titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.grey600),
        bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: AppColors.grey700),
        bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.grey600),
        bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.grey500),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.grey700),
        labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.grey600),
        labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.grey500),
      ),

      // ─── BottomNavigationBar ─────────────────────────────
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.white,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.grey400,
        selectedLabelStyle: TextStyle(fontFamily: 'Nunito', fontSize: 12, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(fontFamily: 'Nunito', fontSize: 12, fontWeight: FontWeight.w500),
        elevation: 8,
        type: BottomNavigationBarType.fixed,
      ),

      // ─── NavigationBar (Material 3) ───────────────────────
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.white,
        indicatorColor: AppColors.primarySurface,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.primary);
          }
          return const IconThemeData(color: AppColors.grey400);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            );
          }
          return const TextStyle(
            fontFamily: 'Nunito',
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.grey400,
          );
        }),
      ),

      // ─── Chip ────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.grey100,
        selectedColor: AppColors.primarySurface,
        labelStyle: const TextStyle(fontFamily: 'Nunito', fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),

      // ─── FAB ─────────────────────────────────────────────
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.white,
        elevation: 4,
      ),

      // ─── SnackBar ────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.grey800,
        contentTextStyle: const TextStyle(fontFamily: 'Nunito', color: AppColors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}