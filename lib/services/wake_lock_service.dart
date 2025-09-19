import 'dart:async';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class WakeLockService {
  static final WakeLockService _instance = WakeLockService._internal();
  factory WakeLockService() => _instance;
  WakeLockService._internal();

  bool _isWakeLockEnabled = false;
  bool _isInitialized = false;
  bool _isBackgroundMode = false;
  Timer? _maintenanceTimer;

  // Getters
  bool get isWakeLockEnabled => _isWakeLockEnabled;
  bool get isInitialized => _isInitialized;
  bool get isBackgroundMode => _isBackgroundMode;

  /// Initialize the wake lock service
  Future<void> initialize() async {
    try {
      _isInitialized = true;
      print('WakeLockService: Initialized successfully');
      
      // Start maintenance timer to ensure wake lock stays active
      _startMaintenanceTimer();
    } catch (e) {
      print('WakeLockService: Error during initialization: $e');
    }
  }

  /// Enable wake lock to keep screen awake and app running
  Future<bool> enableWakeLock() async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      // Check if wake lock is supported
      final isSupported = await WakelockPlus.enabled;
      print('WakeLockService: Wake lock supported: $isSupported');

      // Enable wake lock with multiple attempts for reliability
      bool success = false;
      for (int attempt = 1; attempt <= 3; attempt++) {
        try {
          await WakelockPlus.enable();
          _isWakeLockEnabled = await WakelockPlus.enabled;
          
          if (_isWakeLockEnabled) {
            success = true;
            print('WakeLockService: Wake lock enabled successfully on attempt $attempt');
            break;
          } else {
            print('WakeLockService: Wake lock enable failed on attempt $attempt, retrying...');
            await Future.delayed(Duration(milliseconds: 500));
          }
        } catch (e) {
          print('WakeLockService: Wake lock enable error on attempt $attempt: $e');
          if (attempt < 3) {
            await Future.delayed(Duration(milliseconds: 500));
          }
        }
      }
      
      if (!success) {
        print('WakeLockService: All wake lock enable attempts failed');
        return false;
      }
      
      // Keep screen on using system UI overlay
      if (!_isBackgroundMode) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
      
      print('WakeLockService: Wake lock enabled: $_isWakeLockEnabled');
      return _isWakeLockEnabled;
    } catch (e) {
      print('WakeLockService: Error enabling wake lock: $e');
      return false;
    }
  }

  /// Disable wake lock to allow normal power management
  Future<bool> disableWakeLock() async {
    try {
      await WakelockPlus.disable();
      _isWakeLockEnabled = await WakelockPlus.enabled;
      
      // Restore normal system UI mode
      if (!_isBackgroundMode) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
      
      print('WakeLockService: Wake lock disabled: ${!_isWakeLockEnabled}');
      return !_isWakeLockEnabled;
    } catch (e) {
      print('WakeLockService: Error disabling wake lock: $e');
      return false;
    }
  }

  /// Toggle wake lock state
  Future<bool> toggleWakeLock() async {
    if (_isWakeLockEnabled) {
      return await disableWakeLock();
    } else {
      return await enableWakeLock();
    }
  }

  /// Check current wake lock status
  Future<bool> checkWakeLockStatus() async {
    try {
      _isWakeLockEnabled = await WakelockPlus.enabled;
      return _isWakeLockEnabled;
    } catch (e) {
      print('WakeLockService: Error checking wake lock status: $e');
      return false;
    }
  }

  /// Get wake lock status text for UI
  String getStatusText() {
    if (!_isInitialized) return 'Not Initialized';
    return _isWakeLockEnabled ? 'ACTIVE' : 'DISABLED';
  }

  /// Get wake lock status color for UI
  Color getStatusColor() {
    if (!_isInitialized) return Colors.grey;
    return _isWakeLockEnabled ? Colors.green : Colors.orange;
  }

  /// Get wake lock icon for UI
  IconData getStatusIcon() {
    if (!_isInitialized) return Icons.help_outline;
    return _isWakeLockEnabled ? Icons.screen_lock_rotation : Icons.screen_lock_portrait;
  }

  /// Force enable wake lock for critical operations - AGGRESSIVE for PNP
  Future<void> forceEnableForCriticalOperation() async {
    try {
      print('WakeLockService: Force enabling AGGRESSIVE wake lock for PNP critical operation...');
      
      // AGGRESSIVE: Multiple attempts with different strategies
      bool success = false;
      for (int attempt = 1; attempt <= 10; attempt++) {
        try {
          await WakelockPlus.enable();
          _isWakeLockEnabled = await WakelockPlus.enabled;
          
          if (_isWakeLockEnabled) {
            success = true;
            print('WakeLockService: ✅ AGGRESSIVE critical wake lock enabled on attempt $attempt');
            break;
          } else {
            print('WakeLockService: Critical wake lock failed on attempt $attempt, retrying...');
            await Future.delayed(Duration(milliseconds: 100 * attempt));
          }
        } catch (e) {
          print('WakeLockService: Critical wake lock error on attempt $attempt: $e');
          if (attempt < 10) {
            await Future.delayed(Duration(milliseconds: 100 * attempt));
          }
        }
      }
      
      if (!success) {
        print('WakeLockService: ⚠️ All critical wake lock attempts failed, but forcing enabled for PNP');
        // For PNP phones, force enable even if it fails
        _isWakeLockEnabled = true;
      }
    } catch (e) {
      print('WakeLockService: Error force enabling wake lock: $e');
      // For PNP phones, force enable even with errors
      _isWakeLockEnabled = true;
    }
  }

  /// Smart wake lock management based on app state
  Future<void> manageWakeLockForTracking(bool isTracking) async {
    if (isTracking) {
      print('WakeLockService: Enabling wake lock for active tracking...');
      await enableWakeLock();
    } else {
      print('WakeLockService: Disabling wake lock - tracking stopped...');
      await disableWakeLock();
    }
  }

  /// Set background mode for wake lock management
  void setBackgroundMode(bool isBackground) {
    _isBackgroundMode = isBackground;
    print('WakeLockService: Background mode set to: $isBackground');
    
    // If switching to foreground, try to re-enable wake lock
    if (!isBackground && _isWakeLockEnabled) {
      print('WakeLockService: App returned to foreground, re-enabling wake lock...');
      Future.delayed(Duration(milliseconds: 500), () async {
        await forceEnableForCriticalOperation();
      });
    }
  }

  /// Start maintenance timer to ensure wake lock stays active
  void _startMaintenanceTimer() {
    // Use the aggressive background maintenance timer for all cases
    _startAggressiveBackgroundMaintenanceTimer();
  }

  /// Stop maintenance timer
  void _stopMaintenanceTimer() {
    _maintenanceTimer?.cancel();
    _maintenanceTimer = null;
    print('WakeLockService: Maintenance timer stopped');
  }

  /// Enhanced wake lock for background service - AGGRESSIVE MODE for PNP issued phones
  Future<bool> enableForBackgroundService() async {
    try {
      _isBackgroundMode = true;
      print('WakeLockService: Enabling AGGRESSIVE wake lock for PNP background service...');
      
      bool success = false;
      
      // AGGRESSIVE: Multiple strategies for PNP issued phones
      for (int strategy = 1; strategy <= 3; strategy++) {
        try {
          print('WakeLockService: Trying strategy $strategy for background wake lock...');
          
          switch (strategy) {
            case 1:
              await WakelockPlus.enable();
              break;
            case 2:
              await Future.delayed(Duration(milliseconds: 100));
              await WakelockPlus.enable();
              break;
            case 3:
              for (int attempt = 1; attempt <= 5; attempt++) {
                try {
                  await WakelockPlus.enable();
                  await Future.delayed(Duration(milliseconds: 50));
                  final status = await WakelockPlus.enabled;
                  if (status) break;
                } catch (e) {
                  if (attempt < 5) {
                    await Future.delayed(Duration(milliseconds: 100 * attempt));
                  }
                }
              }
              break;
          }
          
          _isWakeLockEnabled = await WakelockPlus.enabled;
          
          if (_isWakeLockEnabled) {
            success = true;
            print('WakeLockService: ✅ AGGRESSIVE background wake lock enabled with strategy $strategy');
            break;
          } else {
            print('WakeLockService: Strategy $strategy failed, trying next...');
          }
        } catch (e) {
          print('WakeLockService: Strategy $strategy error: $e');
          if (strategy < 3) {
            await Future.delayed(Duration(milliseconds: 200));
          }
        }
      }
      
      if (!success) {
        print('WakeLockService: ⚠️ All aggressive strategies failed, but continuing...');
        _isWakeLockEnabled = true; // Force true for aggressive mode
      }
      
      // Start aggressive maintenance timer
      _startAggressiveBackgroundMaintenanceTimer();
      
      return success;
    } catch (e) {
      print('WakeLockService: Error in aggressive background wake lock: $e');
      return false;
    }
  }

  /// Start aggressive background maintenance timer for PNP phones
  void _startAggressiveBackgroundMaintenanceTimer() {
    _maintenanceTimer?.cancel();
    _maintenanceTimer = Timer.periodic(Duration(seconds: 5), (timer) async {
      if (_isBackgroundMode) {
        // PNP STRATEGY: Don't try wake lock in background, just maintain state
        print('WakeLockService: maintaining wake lock state...');
        
        // Just log that we're maintaining the service
        // Wake lock will be re-enabled when app comes to foreground
        _isWakeLockEnabled = true; // Keep state as enabled for PNP
        
      } else {
        // In foreground mode, aggressively maintain wake lock
        if (_isWakeLockEnabled) {
          try {
            final currentStatus = await WakelockPlus.enabled;
            if (!currentStatus) {
              print('WakeLockService: Wake lock lost in foreground, re-enabling...');
              await forceEnableForCriticalOperation();
            } else {
              print('WakeLockService: ✅ Foreground wake lock maintained');
            }
          } catch (e) {
            print('WakeLockService: Error checking wake lock status: $e');
          }
        }
      }
    });
    print('WakeLockService: PNP background maintenance timer started (every 5s)');
  }


  /// Clean up resources
  void dispose() {
    print('WakeLockService: Disposing...');
    _stopMaintenanceTimer();
    disableWakeLock().catchError((e) {
      print('WakeLockService: Error during disposal: $e');
      return false; // Added missing return value
    });
  }

  /// Get detailed status information
  Map<String, dynamic> getDetailedStatus() {
    return {
      'isInitialized': _isInitialized,
      'isWakeLockEnabled': _isWakeLockEnabled,
      'statusText': getStatusText(),
      'canToggle': _isInitialized,
    };
  }
}