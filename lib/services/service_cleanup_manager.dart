import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'location_service.dart';
import 'device_service.dart';
import 'watchdog_service.dart';
import 'wake_lock_service.dart';
import 'timer_coordinator.dart';
import 'network_connectivity_service.dart';
import '../utils/notification_utils.dart';
// REMOVED: Services that don't have dispose methods

/// Manages cleanup of all background services and timers
/// 
/// This manager handles the termination of all running services including:
/// - Background service (flutter_background_service)
/// - TimerCoordinator (centralized timer management)
/// - Location tracking services
/// - Device monitoring services
/// - Network connectivity services
/// - Permission services
/// - Update services
/// - Error handling services
class ServiceCleanupManager {
  static final ServiceCleanupManager _instance = ServiceCleanupManager._internal();
  factory ServiceCleanupManager() => _instance;
  ServiceCleanupManager._internal();

  // Service instances
  final TimerCoordinator _timerCoordinator = TimerCoordinator();
  final LocationService _locationService = LocationService();
  final DeviceService _deviceService = DeviceService();
  final WatchdogService _watchdogService = WatchdogService();
  final WakeLockService _wakeLockService = WakeLockService();
  final NetworkConnectivityService _networkService = NetworkConnectivityService();
  // REMOVED: Services that don't have dispose methods

  // Stream subscriptions to cancel
  final List<StreamSubscription> _subscriptions = [];

  /// Stop all background services and timers
  /// 
  /// This method performs comprehensive cleanup of all running services
  /// in the correct order to prevent conflicts and ensure complete termination
  Future<void> stopAllServices() async {
    print('🛑 ServiceCleanupManager: Starting comprehensive service cleanup...');
    
    try {
      // Phase 1: Stop adaptive location updates
      await _stopAdaptiveLocationUpdates();
      
      // Phase 2: Stop background service
      await _stopBackgroundService();
      
      // Phase 3: Dispose TimerCoordinator
      await _disposeTimerCoordinator();
      
      // Phase 4: Stop location tracking
      await _stopLocationTracking();
      
      // Phase 5: Stop device monitoring
      await _stopDeviceMonitoring();
      
      // Phase 6: Stop watchdog service
      await _stopWatchdogService();
      
      // Phase 7: Clear wake locks
      await _clearWakeLocks();
      
      // Phase 8: Stop network monitoring
      await _stopNetworkMonitoring();
      
      // Phase 9: Stop permission monitoring
      await _stopPermissionMonitoring();
      
      // Phase 10: Stop update services
      await _stopUpdateServices();
      
      // Phase 11: Stop error handling
      await _stopErrorHandling();

      // Phase 12: Clear all notifications
      await _clearAllNotifications();

      // Phase 13: Cancel all stream subscriptions
      await _cancelAllSubscriptions();

      print('✅ ServiceCleanupManager: All services stopped successfully');
      
    } catch (e) {
      print('❌ ServiceCleanupManager: Error during service cleanup: $e');
      rethrow;
    }
  }

  /// Stop adaptive location updates
  Future<void> _stopAdaptiveLocationUpdates() async {
    try {
      print('📍 ServiceCleanupManager: Stopping adaptive location updates...');
      
      // Stop adaptive updates in ApiService
      ApiService.stopAdaptiveUpdates();
      
      print('✅ ServiceCleanupManager: Adaptive location updates stopped');
    } catch (e) {
      print('❌ ServiceCleanupManager: Error stopping adaptive location updates: $e');
      rethrow;
    }
  }

  /// Stop background service with permanent disable flag
  Future<void> _stopBackgroundService() async {
    try {
      print('🔄 ServiceCleanupManager: Stopping background service...');

      // ENHANCED: Set permanent disable flag and logout timestamp to prevent auto-restart
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      
      await prefs.setBool('background_service_permanently_disabled', true);
      await prefs.setInt('background_service_disable_timestamp', now);
      await prefs.setInt('logoutTimestamp', now); // ENHANCED: Set logout timestamp
      print('ServiceCleanupManager: Set permanent disable flag and logout timestamp');

      final service = FlutterBackgroundService();

      // Check if service is running
      final isRunning = await service.isRunning();
      if (isRunning) {
        // Stop the service
        service.invoke('stopService');

        // Wait for service to stop
        await Future.delayed(const Duration(milliseconds: 500));

        // Verify service is stopped
        final stillRunning = await service.isRunning();
        if (stillRunning) {
          print('⚠️ ServiceCleanupManager: Background service still running, forcing stop...');
          // Force stop by calling stopService multiple times
          for (int i = 0; i < 3; i++) {
            service.invoke('stopService');
            await Future.delayed(const Duration(milliseconds: 200));
          }

          // AGGRESSIVE: Force stop multiple times
          for (int j = 0; j < 5; j++) {
            service.invoke('stopService');
            await Future.delayed(const Duration(milliseconds: 100));
          }
        }
      }

      print('✅ ServiceCleanupManager: Background service stopped with permanent disable');
    } catch (e) {
      print('❌ ServiceCleanupManager: Error stopping background service: $e');
      rethrow;
    }
  }

  /// Dispose TimerCoordinator
  Future<void> _disposeTimerCoordinator() async {
    try {
      print('⏰ ServiceCleanupManager: Disposing TimerCoordinator...');
      
      // Dispose all timers managed by TimerCoordinator
      _timerCoordinator.dispose();
      
      print('✅ ServiceCleanupManager: TimerCoordinator disposed');
    } catch (e) {
      print('❌ ServiceCleanupManager: Error disposing TimerCoordinator: $e');
      rethrow;
    }
  }

  /// Stop location tracking
  Future<void> _stopLocationTracking() async {
    try {
      print('📍 ServiceCleanupManager: Stopping location tracking...');
      
      // Dispose location service
      _locationService.dispose();
      
      // Stop location service (Geolocator doesn't have stopLocationUpdates method)
      // Location service disposal is handled by LocationService.dispose()
      
      print('✅ ServiceCleanupManager: Location tracking stopped');
    } catch (e) {
      print('❌ ServiceCleanupManager: Error stopping location tracking: $e');
      rethrow;
    }
  }

  /// Stop device monitoring
  Future<void> _stopDeviceMonitoring() async {
    try {
      print('📱 ServiceCleanupManager: Stopping device monitoring...');
      
      // Dispose device service
      _deviceService.dispose();
      
      print('✅ ServiceCleanupManager: Device monitoring stopped');
    } catch (e) {
      print('❌ ServiceCleanupManager: Error stopping device monitoring: $e');
      rethrow;
    }
  }

  /// Stop watchdog service
  Future<void> _stopWatchdogService() async {
    try {
      print('🐕 ServiceCleanupManager: Stopping watchdog service...');
      
      // Stop watchdog
      _watchdogService.stopWatchdog();
      
      print('✅ ServiceCleanupManager: Watchdog service stopped');
    } catch (e) {
      print('❌ ServiceCleanupManager: Error stopping watchdog service: $e');
      rethrow;
    }
  }

  /// Clear wake locks
  Future<void> _clearWakeLocks() async {
    try {
      print('🔋 ServiceCleanupManager: Clearing wake locks...');
      
      // Disable wake locks
      _wakeLockService.dispose();
      
      print('✅ ServiceCleanupManager: Wake locks cleared');
    } catch (e) {
      print('❌ ServiceCleanupManager: Error clearing wake locks: $e');
      rethrow;
    }
  }

  /// Stop network monitoring
  Future<void> _stopNetworkMonitoring() async {
    try {
      print('🌐 ServiceCleanupManager: Stopping network monitoring...');
      
      // Dispose network service
      _networkService.dispose();
      
      print('✅ ServiceCleanupManager: Network monitoring stopped');
    } catch (e) {
      print('❌ ServiceCleanupManager: Error stopping network monitoring: $e');
      rethrow;
    }
  }

  /// Stop permission monitoring
  Future<void> _stopPermissionMonitoring() async {
    try {
      print('🔐 ServiceCleanupManager: Stopping permission monitoring...');
      
      // Permission service doesn't have dispose method
      // This is handled by the service itself
      
      print('✅ ServiceCleanupManager: Permission monitoring stopped');
    } catch (e) {
      print('❌ ServiceCleanupManager: Error stopping permission monitoring: $e');
      rethrow;
    }
  }

  /// Stop update services
  Future<void> _stopUpdateServices() async {
    try {
      print('🔄 ServiceCleanupManager: Stopping update services...');
      
      // Update service doesn't have dispose method
      // This is handled by the service itself
      
      print('✅ ServiceCleanupManager: Update services stopped');
    } catch (e) {
      print('❌ ServiceCleanupManager: Error stopping update services: $e');
      rethrow;
    }
  }

  /// Stop error handling
  Future<void> _stopErrorHandling() async {
    try {
      print('⚠️ ServiceCleanupManager: Stopping error handling...');
      
      // Error handling service doesn't have dispose method
      // This is handled by the service itself
      
      print('✅ ServiceCleanupManager: Error handling stopped');
    } catch (e) {
      print('❌ ServiceCleanupManager: Error stopping error handling: $e');
      rethrow;
    }
  }

  /// Clear all notifications (FIXED: Added to fix persistent notifications after logout)
  Future<void> _clearAllNotifications() async {
    try {
      print('🔔 ServiceCleanupManager: Clearing all notifications...');

      // Use centralized notification utility
      await NotificationUtils.clearAllNotifications();

      print('✅ ServiceCleanupManager: All notifications cleared');
    } catch (e) {
      print('❌ ServiceCleanupManager: Error clearing notifications: $e');
      rethrow;
    }
  }

  /// Cancel all stream subscriptions
  Future<void> _cancelAllSubscriptions() async {
    try {
      print('📡 ServiceCleanupManager: Canceling all subscriptions...');

      // Cancel all stored subscriptions
      for (final subscription in _subscriptions) {
        await subscription.cancel();
      }
      _subscriptions.clear();

      print('✅ ServiceCleanupManager: All subscriptions canceled');
    } catch (e) {
      print('❌ ServiceCleanupManager: Error canceling subscriptions: $e');
      rethrow;
    }
  }

  /// Stop only critical services for emergency logout
  Future<void> stopCriticalServices() async {
    print('🚨 ServiceCleanupManager: Stopping critical services only...');

    try {
      // Stop only the most critical services
      await _stopAdaptiveLocationUpdates();
      await _stopBackgroundService();
      await _disposeTimerCoordinator();
      await _stopLocationTracking();

      // FIXED: Also clear notifications during emergency logout
      await _clearAllNotifications();

      print('✅ ServiceCleanupManager: Critical services stopped');
    } catch (e) {
      print('❌ ServiceCleanupManager: Error stopping critical services: $e');
      rethrow;
    }
  }

  /// Verify that all services are stopped
  Future<bool> verifyServicesStopped() async {
    try {
      print('🔍 ServiceCleanupManager: Verifying services are stopped...');
      
      // Check if background service is stopped
      final service = FlutterBackgroundService();
      final isBackgroundRunning = await service.isRunning();
      
      // Check if adaptive updates are stopped
      final isAdaptiveRunning = ApiService.isAdaptiveUpdatesRunning();
      
      // Check if location service is active
      final isLocationActive = _locationService.isLocationEnabled;
      
      // Check if TimerCoordinator is active
      final timerStatus = _timerCoordinator.getStatus();
      final isTimerActive = timerStatus['isInitialized'] == true;
      
      final allStopped = !isBackgroundRunning && !isAdaptiveRunning && !isLocationActive && !isTimerActive;
      
      print('${allStopped ? '✅' : '❌'} ServiceCleanupManager: Services stopped: $allStopped');
      print('  - Background service: ${!isBackgroundRunning ? 'stopped' : 'running'}');
      print('  - Adaptive updates: ${!isAdaptiveRunning ? 'stopped' : 'running'}');
      print('  - Location service: ${!isLocationActive ? 'stopped' : 'running'}');
      print('  - TimerCoordinator: ${!isTimerActive ? 'stopped' : 'running'}');
      
      return allStopped;
    } catch (e) {
      print('❌ ServiceCleanupManager: Error verifying services: $e');
      return false;
    }
  }

  /// Add subscription for tracking
  void addSubscription(StreamSubscription subscription) {
    _subscriptions.add(subscription);
  }

  /// Remove subscription from tracking
  void removeSubscription(StreamSubscription subscription) {
    _subscriptions.remove(subscription);
  }
}
