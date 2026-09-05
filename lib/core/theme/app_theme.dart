import 'package:flutter/material.dart';

@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  final Color fresh;
  final Color expiringSoon;
  final Color expiresToday;
  final Color expired;
  final Color used;
  final Color wasted;

  const StatusColors({
    required this.fresh,
    required this.expiringSoon,
    required this.expiresToday,
    required this.expired,
    required this.used,
    required this.wasted,
  });

  @override
  StatusColors copyWith({
    Color? fresh,
    Color? expiringSoon,
    Color? expiresToday,
    Color? expired,
    Color? used,
    Color? wasted,
  }) {
    return StatusColors(
      fresh: fresh ?? this.fresh,
      expiringSoon: expiringSoon ?? this.expiringSoon,
      expiresToday: expiresToday ?? this.expiresToday,
      expired: expired ?? this.expired,
      used: used ?? this.used,
      wasted: wasted ?? this.wasted,
    );
  }

  @override
  StatusColors lerp(ThemeExtension<StatusColors>? other, double t) {
    if (other is! StatusColors) return this;
    return StatusColors(
      fresh: Color.lerp(fresh, other.fresh, t)!,
      expiringSoon: Color.lerp(expiringSoon, other.expiringSoon, t)!,
      expiresToday: Color.lerp(expiresToday, other.expiresToday, t)!,
      expired: Color.lerp(expired, other.expired, t)!,
      used: Color.lerp(used, other.used, t)!,
      wasted: Color.lerp(wasted, other.wasted, t)!,
    );
  }
}

class AppTheme {
  AppTheme._();

  // App Palette
  static const Color _seedColor = Color(0xFF0F9D58); // Fresh green seed color

  // Light Status Colors
  static const StatusColors _lightStatusColors = StatusColors(
    fresh: Color(0xFF2E7D32), // Emerald Green
    expiringSoon: Color(0xFFEF6C00), // Amber/Orange
    expiresToday: Color(0xFFD84315), // Deep Red-Orange
    expired: Color(0xFFC62828), // Crimson Red
    used: Color(0xFF1565C0), // Business Blue
    wasted: Color(0xFF555555), // Neutral Charcoal
  );

  // Dark Status Colors
  static const StatusColors _darkStatusColors = StatusColors(
    fresh: Color(0xFF81C784),
    expiringSoon: Color(0xFFFFB74D),
    expiresToday: Color(0xFFFF8A65),
    expired: Color(0xFFE57373),
    used: Color(0xFF64B5F6),
    wasted: Color(0xFFB0BEC5),
  );

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seedColor,
        brightness: Brightness.light,
        primary: const Color(0xFF0F9D58),
        onPrimary: Colors.white,
        surface: const Color(0xFFF9FBF9),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        color: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF1F5F1),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _seedColor, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFC62828), width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _seedColor,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _seedColor,
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      extensions: const <ThemeExtension<dynamic>>[_lightStatusColors],
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seedColor,
        brightness: Brightness.dark,
        primary: const Color(0xFF12B86E),
        onPrimary: Colors.black,
        surface: const Color(0xFF121412),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade800),
        ),
        color: const Color(0xFF1E221E),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF2A2E2A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF12B86E), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE57373), width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF12B86E),
          foregroundColor: Colors.black,
          elevation: 0,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF12B86E),
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      extensions: const <ThemeExtension<dynamic>>[_darkStatusColors],
    );
  }
}
