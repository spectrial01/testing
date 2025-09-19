import 'package:flutter/material.dart';

class AppConstants {
  static const String baseUrl = 'https://asia-southeast1-nexuspolice-13560.cloudfunctions.net/';
  static const String appTitle = 'Philippine National Police';
  static const String appMotto = 'SERVICE • HONOR • JUSTICE';
  static const String developerCredit = 'DEVELOPED BY RCC4A AND RICTMD4A';
  static const int locationWarningNotificationId = 99;
  
  // Movement-based adaptive intervals - SINGLE SOURCE OF TRUTH
  static const Duration fastMovingInterval = Duration(seconds: 5);     // >10 km/h
  static const Duration movingInterval = Duration(seconds: 15);        // >7 km/h
  static const Duration stationaryInterval = Duration(seconds: 30);    // Stationary (FIXED: 30s not 2min)
  
  // Session monitoring (reduced from 5s to save data)
  static const Duration sessionCheckInterval = Duration(seconds: 10);  // 30s → 10s (3x faster)
  
  // Signal status monitoring intervals
  static const Duration signalUpdateInterval = Duration(seconds: 30);
  
  // Background service intervals - OPTIMIZED for faster session detection
  static const Duration heartbeatInterval = Duration(minutes: 1);  // 5min → 1min (5x faster)
}

// Signal status constants based on API specification
class SignalStatus {
  static const String strong = 'strong';  // Combined strong and moderate (API compatible)
  static const String weak = 'weak';
  static const String poor = 'poor';
  
  // Helper method to get all valid signal statuses
  static List<String> get allValues => [strong, weak, poor];
  
  // Helper method to get color for signal status
  static Color getColor(String status) {
    switch (status) {
      case strong:
        return Colors.green;
      case weak:
        return Colors.orange;
      case poor:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}

// Movement detection thresholds
class AppSettings {
  static const double stationarySpeedThreshold = 1.0;    // m/s (~3.6 km/h)
  static const double movingSpeedThreshold = 2.0;        // m/s (~7.2 km/h)  
  static const double fastMovingSpeedThreshold = 2.78;   // m/s (~10.0 km/h)
  static const double movementDistanceThreshold = 10.0;  // meters
  
  // Battery optimization thresholds
  static const int lowBatteryThreshold = 20;             // %
  static const int criticalBatteryThreshold = 10;       // %
  
  // Data optimization settings
  static const int coordinatePrecision = 5;              // decimal places (~1m accuracy)
  static const int speedPrecision = 1;                   // decimal places
  static const int batteryChangeThreshold = 5;           // % change to trigger update
}