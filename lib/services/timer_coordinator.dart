import 'dart:async';
import 'package:flutter/foundation.dart';
import '../utils/constants.dart';

/// Centralized timer management service to prevent conflicts and improve performance
/// 
/// This service manages all app timers in one place, eliminating duplicate timers
/// and reducing battery drain. All services should use this coordinator instead
/// of creating their own timers.
class TimerCoordinator {
  static final TimerCoordinator _instance = TimerCoordinator._internal();
  factory TimerCoordinator() => _instance;
  TimerCoordinator._internal();

  // Timer references
  Timer? _sessionVerificationTimer;
  // REMOVED: _locationUpdateTimer - conflicts with adaptive location system
  Timer? _heartbeatTimer;
  Timer? _watchdogTimer;
  Timer? _connectivityTimer;
  Timer? _locationMonitoringTimer;

  // Event callbacks
  final List<VoidCallback> _sessionCheckCallbacks = [];
  // REMOVED: _locationUpdateCallbacks - conflicts with adaptive location system
  final List<VoidCallback> _heartbeatCallbacks = [];
  final List<VoidCallback> _watchdogCallbacks = [];
  final List<VoidCallback> _connectivityCallbacks = [];
  final List<VoidCallback> _locationMonitoringCallbacks = [];


  static const Duration watchdogInterval = Duration(minutes: 1);
  static const Duration connectivityInterval = Duration(seconds: 10);
  static const Duration locationMonitoringInterval = Duration(seconds: 5);

  bool _isInitialized = false;

  /// Initialize the timer coordinator
  Future<void> initialize() async {
    if (_isInitialized) {
      print('TimerCoordinator: Already initialized');
      return;
    }

    print('TimerCoordinator: Initializing centralized timer management...');
    
    // Start all timers (location updates handled by adaptive system)
    _startSessionVerificationTimer();
    // REMOVED: _startLocationUpdateTimer() - conflicts with adaptive location
    _startHeartbeatTimer();
    _startWatchdogTimer();
    _startConnectivityTimer();
    _startLocationMonitoringTimer();

    _isInitialized = true;
    print('TimerCoordinator: Initialized successfully');
  }

  /// Start session verification timer
  void _startSessionVerificationTimer() {
    _sessionVerificationTimer?.cancel();
    _sessionVerificationTimer = Timer.periodic(AppConstants.sessionCheckInterval, (timer) {
      print('TimerCoordinator: Session verification timer triggered');
      _notifySessionCheckCallbacks();
    });
    print('TimerCoordinator: Session verification timer started (${AppConstants.sessionCheckInterval.inSeconds}s)');
  }

  /// Start heartbeat timer
  void _startHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(AppConstants.heartbeatInterval, (timer) {
      print('TimerCoordinator: Heartbeat timer triggered');
      _notifyHeartbeatCallbacks();
    });
    print('TimerCoordinator: Heartbeat timer started (${AppConstants.heartbeatInterval.inMinutes}min)');
  }

  /// Start watchdog timer
  void _startWatchdogTimer() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(watchdogInterval, (timer) {
      print('TimerCoordinator: Watchdog timer triggered');
      _notifyWatchdogCallbacks();
    });
    print('TimerCoordinator: Watchdog timer started (${watchdogInterval.inMinutes}min)');
  }

  /// Start connectivity timer
  void _startConnectivityTimer() {
    _connectivityTimer?.cancel();
    _connectivityTimer = Timer.periodic(connectivityInterval, (timer) {
      print('TimerCoordinator: Connectivity timer triggered');
      _notifyConnectivityCallbacks();
    });
    print('TimerCoordinator: Connectivity timer started (${connectivityInterval.inSeconds}s)');
  }

  /// Start location monitoring timer
  void _startLocationMonitoringTimer() {
    _locationMonitoringTimer?.cancel();
    _locationMonitoringTimer = Timer.periodic(locationMonitoringInterval, (timer) {
      print('TimerCoordinator: Location monitoring timer triggered');
      _notifyLocationMonitoringCallbacks();
    });
    print('TimerCoordinator: Location monitoring timer started (${locationMonitoringInterval.inSeconds}s)');
  }

  /// Subscribe to session check events
  void onSessionCheck(VoidCallback callback) {
    _sessionCheckCallbacks.add(callback);
    print('TimerCoordinator: Session check callback registered');
  }

  /// Subscribe to heartbeat events
  void onHeartbeat(VoidCallback callback) {
    _heartbeatCallbacks.add(callback);
    print('TimerCoordinator: Heartbeat callback registered');
  }

  /// Subscribe to watchdog events
  void onWatchdog(VoidCallback callback) {
    _watchdogCallbacks.add(callback);
    print('TimerCoordinator: Watchdog callback registered');
  }

  /// Subscribe to connectivity events
  void onConnectivity(VoidCallback callback) {
    _connectivityCallbacks.add(callback);
    print('TimerCoordinator: Connectivity callback registered');
  }

  /// Subscribe to location monitoring events
  void onLocationMonitoring(VoidCallback callback) {
    _locationMonitoringCallbacks.add(callback);
    print('TimerCoordinator: Location monitoring callback registered');
  }

  /// Unsubscribe from session check events
  void removeSessionCheckCallback(VoidCallback callback) {
    _sessionCheckCallbacks.remove(callback);
    print('TimerCoordinator: Session check callback removed');
  }

  /// Unsubscribe from heartbeat events
  void removeHeartbeatCallback(VoidCallback callback) {
    _heartbeatCallbacks.remove(callback);
    print('TimerCoordinator: Heartbeat callback removed');
  }

  /// Unsubscribe from watchdog events
  void removeWatchdogCallback(VoidCallback callback) {
    _watchdogCallbacks.remove(callback);
    print('TimerCoordinator: Watchdog callback removed');
  }

  /// Unsubscribe from connectivity events
  void removeConnectivityCallback(VoidCallback callback) {
    _connectivityCallbacks.remove(callback);
    print('TimerCoordinator: Connectivity callback removed');
  }

  /// Unsubscribe from location monitoring events
  void removeLocationMonitoringCallback(VoidCallback callback) {
    _locationMonitoringCallbacks.remove(callback);
    print('TimerCoordinator: Location monitoring callback removed');
  }

  /// Notify all session check callbacks
  void _notifySessionCheckCallbacks() {
    for (final callback in _sessionCheckCallbacks) {
      try {
        callback();
      } catch (e) {
        print('TimerCoordinator: Error in session check callback: $e');
      }
    }
  }

  /// Notify all heartbeat callbacks
  void _notifyHeartbeatCallbacks() {
    for (final callback in _heartbeatCallbacks) {
      try {
        callback();
      } catch (e) {
        print('TimerCoordinator: Error in heartbeat callback: $e');
      }
    }
  }

  /// Notify all watchdog callbacks
  void _notifyWatchdogCallbacks() {
    for (final callback in _watchdogCallbacks) {
      try {
        callback();
      } catch (e) {
        print('TimerCoordinator: Error in watchdog callback: $e');
      }
    }
  }

  /// Notify all connectivity callbacks
  void _notifyConnectivityCallbacks() {
    for (final callback in _connectivityCallbacks) {
      try {
        callback();
      } catch (e) {
        print('TimerCoordinator: Error in connectivity callback: $e');
      }
    }
  }

  /// Notify all location monitoring callbacks
  void _notifyLocationMonitoringCallbacks() {
    for (final callback in _locationMonitoringCallbacks) {
      try {
        callback();
      } catch (e) {
        print('TimerCoordinator: Error in location monitoring callback: $e');
      }
    }
  }

  /// Get timer status for debugging
  Map<String, dynamic> getStatus() {
    return {
      'isInitialized': _isInitialized,
      'sessionVerificationActive': _sessionVerificationTimer?.isActive ?? false,
      'heartbeatActive': _heartbeatTimer?.isActive ?? false,
      'watchdogActive': _watchdogTimer?.isActive ?? false,
      'connectivityActive': _connectivityTimer?.isActive ?? false,
      'locationMonitoringActive': _locationMonitoringTimer?.isActive ?? false,
      'sessionCheckCallbacks': _sessionCheckCallbacks.length,
      'heartbeatCallbacks': _heartbeatCallbacks.length,
      'watchdogCallbacks': _watchdogCallbacks.length,
      'connectivityCallbacks': _connectivityCallbacks.length,
      'locationMonitoringCallbacks': _locationMonitoringCallbacks.length,
    };
  }

  /// Stop all timers and clean up
  void dispose() {
    print('TimerCoordinator: Disposing all timers...');
    
    _sessionVerificationTimer?.cancel();
    _heartbeatTimer?.cancel();
    _watchdogTimer?.cancel();
    _connectivityTimer?.cancel();
    _locationMonitoringTimer?.cancel();

    _sessionVerificationTimer = null;
    _heartbeatTimer = null;
    _watchdogTimer = null;
    _connectivityTimer = null;
    _locationMonitoringTimer = null;
    _sessionCheckCallbacks.clear();
    _heartbeatCallbacks.clear();
    _watchdogCallbacks.clear();
    _connectivityCallbacks.clear();
    _locationMonitoringCallbacks.clear();

    _isInitialized = false;
    print('TimerCoordinator: All timers disposed successfully');
  }
}
