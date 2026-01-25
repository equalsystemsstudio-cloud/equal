import 'package:flutter/material.dart';

class AppColors {
  // Primary colors
  static const Color primary = Color(0xFF2196F3);
  static const Color primaryDark = Color(0xFF1976D2);
  static const Color primaryLight = Color(0xFF64B5F6);
  
  // Background colors
  static const Color background = Color(0xFF000000);
  static const Color surface = Color(0xFF1A1A1A);
  static const Color surfaceVariant = Color(0xFF2A2A2A);
  
  // Text colors
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB0B0B0);
  static const Color textTertiary = Color(0xFF808080);
  
  // Accent colors
  static const Color accent = Color(0xFF00BCD4);
  static const Color accentLight = Color(0xFF4DD0E1);
  
  // Status colors
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color error = Color(0xFFF44336);
  static const Color info = Color(0xFF2196F3);
  
  // Border and divider colors
  static const Color border = Color(0xFF333333);
  static const Color divider = Color(0xFF2A2A2A);
  
  // Overlay colors
  static const Color overlay = Color(0x80000000);
  static const Color overlayLight = Color(0x40000000);
  
  // Gradient colors
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient accentGradient = LinearGradient(
    colors: [accent, accentLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  // Social media colors
  static const Color like = Color(0xFFE91E63);
  static const Color comment = Color(0xFF4CAF50);
  static const Color share = Color(0xFF9C27B0);
  static const Color follow = Color(0xFF2196F3);
  
  // Content type colors
  static const Color video = Color(0xFFFF5722);
  static const Color photo = Color(0xFF795548);
  static const Color text = Color(0xFF607D8B);
  static const Color audio = Color(0xFF9C27B0);
  static const Color live = Color(0xFFF44336);
  static const Color ai = Color(0xFF00BCD4);

  // Special badges
  static const Color gold = Color(0xFFFFD700);
}