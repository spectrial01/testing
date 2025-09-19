import 'dart:async';
import 'api_service.dart';
import 'service_cleanup_manager.dart';
import 'data_purge_manager.dart';
import 'memory_reset_manager.dart';
import 'logout_result.dart';

/// Comprehensive logout service that completely resets the app to fresh state
/// 
/// This service orchestrates the complete cleanup of all app state, services,
/// data, and memory to ensure a clean logout similar to fresh app install.
/// 
/// Features:
/// - Complete service termination (background, timers, location tracking)
/// - Data purging (secure storage, preferences, cache, files)
/// - Memory cleanup (singletons, providers, controllers, streams)
/// - Server notification (logout with forceOffline)
/// - Fresh navigation to login screen
class LogoutService {
  static final LogoutService _instance = LogoutService._internal();
  factory LogoutService() => _instance;
  LogoutService._internal();

  // Cleanup managers
  final ServiceCleanupManager _serviceCleanup = ServiceCleanupManager();
  final DataPurgeManager _dataPurge = DataPurgeManager();
  final MemoryResetManager _memoryReset = MemoryResetManager();

  // Progress tracking
  int _totalSteps = 0;
  Function(LogoutProgress)? _onProgress;

  /// Perform complete logout with progress tracking
  /// 
  /// This is the main method that orchestrates the entire logout process:
  /// 1. Notify server of logout
  /// 2. Stop all background services and timers
  /// 3. Clear all stored data and cache
  /// 4. Reset memory and state
  /// 5. Navigate to login screen
  /// 
  /// Returns [LogoutResult] with success status and any errors encountered
  Future<LogoutResult> performCompleteLogout({
    required String? token,
    required String? deploymentCode,
    bool forceOffline = false,
    Function(LogoutProgress)? onProgress,
  }) async {
    _onProgress = onProgress;
    _totalSteps = 5; // Total cleanup phases

    final result = LogoutResult();
    final stopwatch = Stopwatch()..start();

    try {
      print('🚪 LogoutService: Starting complete logout process...');
      _updateProgress('Initializing logout...', 0);

      // Phase 1: Notify server of logout
      await _notifyServerLogout(token, deploymentCode, forceOffline, result);
      _updateProgress('Server notified', 1);

      // Phase 2: Stop all services and timers
      await _stopAllServices(result);
      _updateProgress('Services stopped', 2);

      // Phase 3: Clear all data and storage
      await _clearAllData(result);
      _updateProgress('Data cleared', 3);

      // Phase 4: Reset memory and state
      await _resetMemoryAndState(result);
      _updateProgress('Memory reset', 4);

      // Phase 5: Navigate to login
      await _navigateToLogin(result);
      _updateProgress('Logout complete', 5);

      stopwatch.stop();
      result.success = true;
      result.duration = stopwatch.elapsed;
      result.message = 'Logout completed successfully in ${stopwatch.elapsedMilliseconds}ms';

      print('✅ LogoutService: Logout completed successfully in ${stopwatch.elapsedMilliseconds}ms');
      return result;

    } catch (e, stackTrace) {
      stopwatch.stop();
      result.success = false;
      result.duration = stopwatch.elapsed;
      result.message = 'Logout failed: $e';
      result.error = e.toString();
      result.stackTrace = stackTrace.toString();

      print('❌ LogoutService: Logout failed: $e');
      print('❌ LogoutService: Stack trace: $stackTrace');
      return result;
    }
  }

  /// Phase 1: Notify server of logout
  Future<void> _notifyServerLogout(
    String? token,
    String? deploymentCode,
    bool forceOffline,
    LogoutResult result,
  ) async {
    try {
      if (token != null && deploymentCode != null) {
        print('🌐 LogoutService: Notifying server of logout...');
        
      // Try server logout with timeout
      try {
        final logoutResult = await ApiService.logout(
          token,
          deploymentCode,
          forceOffline: forceOffline,
        ).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            print('⚠️ LogoutService: Server logout timeout, continuing with local cleanup');
            result.warnings.add('Server logout timeout - continuing with local cleanup');
            return ApiResponse(success: false, message: 'Server logout timeout');
          },
        );
        
        if (!logoutResult.success) {
          result.warnings.add('Server logout failed: ${logoutResult.message}');
        }
      } catch (e) {
        print('⚠️ LogoutService: Server logout failed: $e');
        result.warnings.add('Server logout failed: $e');
      }
        
        print('✅ LogoutService: Server logout completed');
      } else {
        print('⚠️ LogoutService: No credentials available for server logout');
        result.warnings.add('No credentials available for server logout');
      }
    } catch (e) {
      print('⚠️ LogoutService: Server logout failed: $e');
      result.warnings.add('Server logout failed: $e');
      // Continue with local cleanup even if server logout fails
    }
  }

  /// Phase 2: Stop all background services and timers
  Future<void> _stopAllServices(LogoutResult result) async {
    try {
      print('🛑 LogoutService: Stopping all services...');
      
      // Use ServiceCleanupManager for comprehensive service termination
      await _serviceCleanup.stopAllServices();
      
      print('✅ LogoutService: All services stopped successfully');
    } catch (e) {
      print('❌ LogoutService: Error stopping services: $e');
      result.errors.add('Service cleanup failed: $e');
      rethrow;
    }
  }

  /// Phase 3: Clear all stored data and cache
  Future<void> _clearAllData(LogoutResult result) async {
    try {
      print('🗑️ LogoutService: Clearing all data...');
      
      // Use DataPurgeManager for comprehensive data clearing
      await _dataPurge.clearAllData();
      
      print('✅ LogoutService: All data cleared successfully');
    } catch (e) {
      print('❌ LogoutService: Error clearing data: $e');
      result.errors.add('Data clearing failed: $e');
      rethrow;
    }
  }

  /// Phase 4: Reset memory and state
  Future<void> _resetMemoryAndState(LogoutResult result) async {
    try {
      print('🧹 LogoutService: Resetting memory and state...');
      
      // Use MemoryResetManager for comprehensive memory cleanup
      await _memoryReset.resetAllMemoryAndState();
      
      print('✅ LogoutService: Memory and state reset successfully');
    } catch (e) {
      print('❌ LogoutService: Error resetting memory: $e');
      result.errors.add('Memory reset failed: $e');
      rethrow;
    }
  }

  /// Phase 5: Navigate to login screen
  Future<void> _navigateToLogin(LogoutResult result) async {
    try {
      print('🚀 LogoutService: Navigating to login screen...');
      
      // This will be handled by the calling widget
      // The navigation logic should be implemented in the UI layer
      print('✅ LogoutService: Navigation prepared');
    } catch (e) {
      print('❌ LogoutService: Error preparing navigation: $e');
      result.errors.add('Navigation preparation failed: $e');
      rethrow;
    }
  }

  /// Update progress callback
  void _updateProgress(String message, int step) {
    final progress = _totalSteps > 0 ? (step / _totalSteps) : 0.0;
    
    if (_onProgress != null) {
      _onProgress!(LogoutProgress(
        message: message,
        progress: progress,
        step: step,
        totalSteps: _totalSteps,
      ));
    }
    
    print('📊 LogoutService: $message (${(progress * 100).toInt()}%)');
  }

  /// Quick logout for emergency situations
  /// 
  /// This method performs a fast logout without server notification
  /// and with minimal cleanup for emergency situations
  Future<LogoutResult> performEmergencyLogout() async {
    print('🚨 LogoutService: Performing emergency logout...');
    
    final result = LogoutResult();
    result.isEmergency = true;
    
    try {
      // Stop critical services only
      await _serviceCleanup.stopCriticalServices();
      
      // Clear sensitive data only
      await _dataPurge.clearSensitiveData();
      
      result.success = true;
      result.message = 'Emergency logout completed';
      
      print('✅ LogoutService: Emergency logout completed');
      return result;
      
    } catch (e) {
      result.success = false;
      result.message = 'Emergency logout failed: $e';
      result.error = e.toString();
      
      print('❌ LogoutService: Emergency logout failed: $e');
      return result;
    }
  }

  /// Verify logout completeness
  /// 
  /// This method checks if the logout was successful by verifying
  /// that all services are stopped and data is cleared
  Future<bool> verifyLogoutCompleteness() async {
    try {
      print('🔍 LogoutService: Verifying logout completeness...');
      
      // Check if services are stopped
      final servicesStopped = await _serviceCleanup.verifyServicesStopped();
      
      // Check if data is cleared
      final dataCleared = await _dataPurge.verifyDataCleared();
      
      // Check if memory is reset
      final memoryReset = await _memoryReset.verifyMemoryReset();
      
      final isComplete = servicesStopped && dataCleared && memoryReset;
      
      print('${isComplete ? '✅' : '❌'} LogoutService: Logout completeness: $isComplete');
      return isComplete;
      
    } catch (e) {
      print('❌ LogoutService: Error verifying logout completeness: $e');
      return false;
    }
  }
}
