import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Helper class for permission status UI elements
/// Centralizes permission status logic to reduce code duplication
class PermissionStatusHelper {
  /// Get color for permission status
  static Color getStatusColor(PermissionStatus status) {
    switch (status) {
      case PermissionStatus.granted:
        return Colors.green;
      case PermissionStatus.denied:
        return Colors.orange;
      case PermissionStatus.permanentlyDenied:
        return Colors.red;
      case PermissionStatus.restricted:
        return Colors.purple;
      case PermissionStatus.limited:
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }

  /// Get icon for permission status
  static IconData getStatusIcon(PermissionStatus status) {
    switch (status) {
      case PermissionStatus.granted:
        return Icons.check_circle;
      case PermissionStatus.denied:
        return Icons.warning;
      case PermissionStatus.permanentlyDenied:
        return Icons.block;
      case PermissionStatus.restricted:
        return Icons.lock;
      case PermissionStatus.limited:
        return Icons.info;
      default:
        return Icons.help;
    }
  }

  /// Get text for permission status
  static String getStatusText(PermissionStatus status) {
    switch (status) {
      case PermissionStatus.granted:
        return 'GRANTED';
      case PermissionStatus.denied:
        return 'DENIED';
      case PermissionStatus.permanentlyDenied:
        return 'PERMANENTLY DENIED';
      case PermissionStatus.restricted:
        return 'RESTRICTED';
      case PermissionStatus.limited:
        return 'LIMITED';
      default:
        return 'UNKNOWN';
    }
  }

  /// Check if permission is critical for app functionality
  static bool isCritical(String title) {
    final lowerTitle = title.toLowerCase();
    return lowerTitle.contains('background') || 
           lowerTitle.contains('location') ||
           lowerTitle.contains('battery') ||
           lowerTitle.contains('notification');
  }

  /// Get Android 12+ specific instructions for background location
  static String getBackgroundLocationInstructions() {
    return '1. First grant basic location permission\n'
           '2. Then select "Allow all the time" for background\n'
           '3. If settings open, navigate to Location permissions\n'
           '4. Change from "While using app" to "Allow all the time"';
  }

  /// Get appropriate description based on status and permission type
  static String getStatusDescription(PermissionStatus status, String title) {
    if (status == PermissionStatus.permanentlyDenied) {
      return 'Go to Settings > Apps > This App > Permissions to enable manually.';
    }
    
    if (isCritical(title)) {
      return 'This permission is required for the app to function properly.';
    }
    
    return 'This permission helps improve app functionality.';
  }
}
