import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color backgroundPrimary = Color(0xFFFAFBFC);
  static const Color backgroundSecondary = Color(0xFFFFFFFF);
  static const Color backgroundTertiary = Color(0xFFF8F9FA);
  static const Color backgroundQuaternary = Color(0xFFF1F3F4);

  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF4A4A4A);
  static const Color textTertiary = Color(0xFF6B7280);
  static const Color textDisabled = Color(0xFF9CA3AF);

  static const Color accent = Color(0xFF6366F1);
  static const Color accentSecondary = Color(0xFF8B5CF6);
  static const Color accentLight = Color(0xFFA5B4FC);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);

  static const Color hover = Color(0xFFF3F4F6);
  static const Color pressed = Color(0xFFE5E7EB);
  static const Color selected = Color(0xFF6366F1);
  static const Color disabled = Color(0xFFF9FAFB);

  static const Color border = Color(0xFFE5E7EB);
  static const Color borderLight = Color(0xFFF3F4F6);
  static const Color divider = Color(0xFFF3F4F6);

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFFFFF), Color(0xFFFAFBFC)],
  );

  static const Color overlay = Color(0x80000000);
  static const Color overlayLight = Color(0x40000000);
  static const Color overlayHeavy = Color(0xB3000000);
}
