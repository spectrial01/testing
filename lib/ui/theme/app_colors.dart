import 'package:flutter/material.dart';

/// Professional PNP Law Enforcement Theme Colors
class AppColors {
  // Primary Colors - Professional Law Enforcement Theme
  static const Color primaryBlue = Color(0xFF1565C0);        // Deep Blue
  static const Color policeBlue = Color(0xFF0D47A1);         // Police Blue
  static const Color primaryDark = Color(0xFF0A3D91);        // Darker Blue for emphasis

  // Accent Colors - Status & Alert Colors
  static const Color warningOrange = Color(0xFFFF6F00);      // Warning/Alert Orange
  static const Color successGreen = Color(0xFF2E7D32);       // Success/Active Green
  static const Color errorRed = Color(0xFFD32F2F);           // Error/Critical Red
  static const Color cautionYellow = Color(0xFFF57C00);      // Caution Yellow

  // Background Colors
  static const Color backgroundLight = Color(0xFFF5F5F5);    // Light Gray Background
  static const Color backgroundWhite = Color(0xFFFFFFFF);    // Pure White
  static const Color surfaceGray = Color(0xFFEEEEEE);        // Card Surface Gray
  static const Color dividerGray = Color(0xFFE0E0E0);        // Divider Gray

  // Text Colors
  static const Color textPrimary = Color(0xFF212121);        // Primary Text
  static const Color textSecondary = Color(0xFF757575);      // Secondary Text
  static const Color textLight = Color(0xFF9E9E9E);          // Light Text
  static const Color textOnDark = Color(0xFFFFFFFF);         // White Text on Dark

  // Status Colors for Different States
  static const Color statusActive = Color(0xFF4CAF50);       // Active/Online Green
  static const Color statusWarning = Color(0xFFFF9800);      // Warning Orange
  static const Color statusError = Color(0xFFE91E63);        // Error Pink-Red
  static const Color statusOffline = Color(0xFF9E9E9E);      // Offline Gray

  // Card & Component Colors
  static const Color cardBackground = Color(0xFFFFFFFF);     // Card Background
  static const Color cardShadow = Color(0x1A000000);         // Card Shadow
  static const Color buttonPrimary = Color(0xFF1565C0);      // Primary Button
  static const Color buttonSecondary = Color(0xFFE3F2FD);    // Secondary Button

  // Notification Colors
  static const Color notificationInfo = Color(0xFF2196F3);   // Info Blue
  static const Color notificationSuccess = Color(0xFF4CAF50); // Success Green
  static const Color notificationWarning = Color(0xFFFF9800); // Warning Orange
  static const Color notificationError = Color(0xFFE91E63);  // Error Pink

  // Gradient Colors
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryBlue, policeBlue],
  );

  static const LinearGradient statusActiveGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4CAF50), Color(0xFF2E7D32)],
  );

  static const LinearGradient warningGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [warningOrange, Color(0xFFE65100)],
  );

  // Helper Methods
  static Color getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
      case 'online':
      case 'connected':
        return statusActive;
      case 'warning':
      case 'caution':
        return statusWarning;
      case 'error':
      case 'critical':
      case 'failed':
        return statusError;
      case 'offline':
      case 'disconnected':
      case 'inactive':
        return statusOffline;
      default:
        return textSecondary;
    }
  }

  static IconData getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'active':
      case 'online':
      case 'connected':
        return Icons.check_circle;
      case 'warning':
      case 'caution':
        return Icons.warning;
      case 'error':
      case 'critical':
      case 'failed':
        return Icons.error;
      case 'offline':
      case 'disconnected':
      case 'inactive':
        return Icons.radio_button_unchecked;
      default:
        return Icons.info;
    }
  }
}