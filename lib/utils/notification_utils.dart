import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Centralized notification utility for consistent notification management
/// 
/// This utility provides a single source of truth for all notification operations
/// to prevent code duplication and ensure consistency across the app.
class NotificationUtils {
  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  
  // Centralized notification IDs - single source of truth
  static const List<int> backgroundServiceNotificationIds = [
    888, // Main notification ID
    999, // Heartbeat notification ID
    997, // Offline notification ID
    996, // Reconnection notification ID
    995, // Aggressive disconnection ID
    994, // Emergency alert ID
    893, // Session terminated ID
    1003, // Critical location alert notification ID
  ];
  
  static const List<int> deviceServiceNotificationIds = [
    102, // Device service notification
    100, // Device service notification
  ];
  
  static const List<int> allNotificationIds = [
    ...backgroundServiceNotificationIds,
    ...deviceServiceNotificationIds,
  ];

  /// Clear all background service notifications
  /// 
  /// This method clears all notifications related to background services
  /// including tracking, heartbeat, and alert notifications.
  static Future<void> clearBackgroundServiceNotifications() async {
    try {
      print('🔔 NotificationUtils: Clearing background service notifications...');
      
      // Cancel specific notification IDs
      for (final id in backgroundServiceNotificationIds) {
        await _notifications.cancel(id);
      }
      
      print('✅ NotificationUtils: Background service notifications cleared');
    } catch (e) {
      print('❌ NotificationUtils: Error clearing background service notifications: $e');
      rethrow;
    }
  }

  /// Clear all device service notifications
  /// 
  /// This method clears all notifications related to device services.
  static Future<void> clearDeviceServiceNotifications() async {
    try {
      print('🔔 NotificationUtils: Clearing device service notifications...');
      
      // Cancel specific notification IDs
      for (final id in deviceServiceNotificationIds) {
        await _notifications.cancel(id);
      }
      
      print('✅ NotificationUtils: Device service notifications cleared');
    } catch (e) {
      print('❌ NotificationUtils: Error clearing device service notifications: $e');
      rethrow;
    }
  }

  /// Clear all app notifications
  /// 
  /// This method clears all notifications from the app, including both
  /// background service and device service notifications.
  static Future<void> clearAllNotifications() async {
    try {
      print('🔔 NotificationUtils: Clearing all notifications...');
      
      // Cancel specific notification IDs
      for (final id in allNotificationIds) {
        await _notifications.cancel(id);
      }
      
      // Also cancel any generic ones
      await _notifications.cancelAll();
      
      print('✅ NotificationUtils: All notifications cleared');
    } catch (e) {
      print('❌ NotificationUtils: Error clearing all notifications: $e');
      rethrow;
    }
  }

  /// Clear all notifications safely (non-throwing)
  /// 
  /// This method clears all notifications but doesn't throw errors,
  /// making it safe to use in cleanup scenarios where errors should not
  /// interrupt the main flow.
  static Future<void> clearAllNotificationsSafely() async {
    try {
      await clearAllNotifications();
    } catch (e) {
      print('⚠️ NotificationUtils: Error in safe notification clearing: $e');
      // Don't rethrow - this is safe cleanup
    }
  }

  /// Get the notification plugin instance
  /// 
  /// This method provides access to the notification plugin for
  /// advanced operations that require direct plugin access.
  static FlutterLocalNotificationsPlugin get plugin => _notifications;
}
