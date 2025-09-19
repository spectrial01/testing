import 'dart:async';
import 'dart:ui';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http; // ADDED: For network keep-alive mechanism
import 'api_service.dart';
import 'timer_coordinator.dart';
import 'wake_lock_service.dart';
import '../utils/constants.dart'; // UPDATED: Added import for signal status constants
import '../utils/notification_utils.dart';

const notificationChannelId = 'pnp_location_service';
const notificationId = 888;
const heartbeatChannelId = 'pnp_heartbeat_service';
const heartbeatNotificationId = 999;
const offlineNotificationId = 997;
const reconnectionNotificationId = 996;
const aggressiveDisconnectionId = 995;
const emergencyAlertId = 994;
const sessionTerminatedId = 893;

// TimerCoordinator instance for background service
final _timerCoordinator = TimerCoordinator();

final _notifications = FlutterLocalNotificationsPlugin();
bool _isOnline = true;
bool _wasOfflineNotificationSent = false;
int _disconnectionCount = 0;
DateTime? _lastConnectionCheck;
DateTime? _serviceStartTime;
bool _sessionActive = true;
DateTime? _lastSessionCheck;
StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
Timer? _offlineNotificationTimer;
Timer? _connectivityPollingTimer;
String? _initialToken; // Guard: credentials snapshot when service starts
String? _initialDeploymentCode; // Guard: credentials snapshot when service starts
ServiceInstance? _serviceInstance; // Reference to current background service
DateTime? _lastLogoutTimestamp; // Track logout timestamps to prevent zombie services
Timer? _credentialMonitoringTimer; // Aggressive credential monitoring timer

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  // ENHANCED: Maximum priority notification channels for production stability with lockscreen visibility
  const AndroidNotificationChannel mainChannel = AndroidNotificationChannel(
    notificationChannelId,
    'PNP MOBILE TRACKING SERVICE',
    description: 'Critical system service - Maximum priority for reliable background operation',
    importance: Importance.max,
    enableVibration: false,
    playSound: false,
    showBadge: true,
    // ADDED: Enable lockscreen visibility
    enableLights: true,
    ledColor: const Color(0xFF2196F3),
  );

  const AndroidNotificationChannel heartbeatChannel = AndroidNotificationChannel(
    heartbeatChannelId,
    'PNP Heartbeat Service',
    description: 'Shows app is alive and tracking',
    importance: Importance.min,
    enableVibration: false,
    playSound: false,
    showBadge: true,
    // ADDED: Enable lockscreen visibility for heartbeat too
    enableLights: true,
    ledColor: const Color(0xFF4CAF50),
  );

  AndroidNotificationChannel sessionTerminatedChannel = AndroidNotificationChannel(
    'session_terminated_bg',
    'Session Terminated',
    description: 'Notifications when session is terminated from another device',
    importance: Importance.max,
    enableVibration: true,
    enableLights: true,
    ledColor: Color(0xFFFF6600),
    playSound: true,
    showBadge: true,
  );

  AndroidNotificationChannel criticalDisconnectionChannel = AndroidNotificationChannel(
    'critical_disconnection_bg',
    'Critical Background Disconnection',
    description: 'Critical disconnection alerts from background service',
    importance: Importance.max,
    enableVibration: true,
    enableLights: true,
    ledColor: Color(0xFFFF0000),
    playSound: true,
    sound: RawResourceAndroidNotificationSound('alarm_sound'),
    showBadge: true,
  );

  AndroidNotificationChannel emergencyChannel = AndroidNotificationChannel(
    'emergency_bg_override',
    'Emergency Background Override',
    description: 'Emergency notifications that override all restrictions',
    importance: Importance.max,
    enableVibration: true,
    enableLights: true,
    ledColor: Color(0xFFFF4500),
    playSound: true,
    sound: RawResourceAndroidNotificationSound('alarm_sound'),
    showBadge: true,
  );

  AndroidNotificationChannel reconnectionChannel = AndroidNotificationChannel(
    'reconnection_channel',
    'Auto-Reconnection',
    description: 'Notifications for automatic reconnection events',
    importance: Importance.high,
    enableVibration: false,
    playSound: false,
  );

  await _notifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(mainChannel);
      
  await _notifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(heartbeatChannel);

  await _notifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(sessionTerminatedChannel);

  await _notifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(criticalDisconnectionChannel);

  await _notifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(emergencyChannel);

  await _notifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(reconnectionChannel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: notificationChannelId,
      initialNotificationTitle: 'PNP MOBILE TRACKING SERVICE',
      initialNotificationContent: '24/7 MOBILE TRACKING ACTIVE',
      foregroundServiceNotificationId: notificationId,
      autoStartOnBoot: true,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

// Session terminated notification
Future<void> _showSessionTerminatedNotification() async {
  const String title = '🚨 Session Terminated';
  final String body = 'Your deployment code was forced logout. Background service stopped. Time: ${DateTime.now().toString().substring(11, 19)}';
  AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'session_terminated_bg',
    'SESSION TERMINATED',
    channelDescription: 'Session terminated from another device',
    importance: Importance.max,
    priority: Priority.max,
    ongoing: false,
    autoCancel: false,
    fullScreenIntent: true,
    category: AndroidNotificationCategory.alarm,
    visibility: NotificationVisibility.public,
    color: Color(0xFFFF6600),
    colorized: true,
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
    enableLights: true,
    ledColor: Color(0xFFFF6600),
    ledOnMs: 1000,
    ledOffMs: 500,
    playSound: true,
    showWhen: true,
    channelShowBadge: true,
    styleInformation: BigTextStyleInformation(
      body,
      contentTitle: title,
    ),
  );
  
  NotificationDetails details = NotificationDetails(android: androidDetails);
  
  await _notifications.show(
    sessionTerminatedId,
    title,
    body,
    details,
  );
  
  print('BackgroundService: SESSION TERMINATED notification sent');
}

// Aggressive disconnection notification
Future<void> _showAggressiveDisconnectionNotification() async {
  const String title = '🚨 BACKGROUND SERVICE: Connection Lost';
  final String body = 'ENHANCED ALERT: Device disconnected (#$_disconnectionCount). Background tracking continues. Time: ${DateTime.now().toString().substring(11, 19)}';
  AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'critical_disconnection_bg',
    'CRITICAL DISCONNECTION',
    channelDescription: 'Critical disconnection detected by background service',
    importance: Importance.max,
    priority: Priority.max,
    ongoing: true,
    autoCancel: false,
    fullScreenIntent: true,
    category: AndroidNotificationCategory.alarm,
    visibility: NotificationVisibility.public,
    color: Color(0xFFFF0000),
    colorized: true,
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000, 500, 1000]),
    enableLights: true,
    ledColor: Color(0xFFFF0000),
    ledOnMs: 1000,
    ledOffMs: 500,
    sound: RawResourceAndroidNotificationSound('alarm_sound'),
    playSound: true,
    showWhen: true,
    channelShowBadge: true,
    groupKey: 'CRITICAL_BG_ALERTS',
    setAsGroupSummary: true,
    timeoutAfter: null,
    styleInformation: BigTextStyleInformation(
      body,
      contentTitle: title,
    ),
  );
  
  NotificationDetails details = NotificationDetails(android: androidDetails);
  
  await _notifications.show(
    aggressiveDisconnectionId,
    title,
    body,
    details,
  );
  
  _wasOfflineNotificationSent = true;
  print('BackgroundService: ENHANCED disconnection notification sent');
}

// Emergency alert
Future<void> _showEmergencyBackgroundAlert() async {
  final offlineMinutes = _lastConnectionCheck != null 
      ? DateTime.now().difference(_lastConnectionCheck!).inMinutes 
      : 0;

  final String title = '🆘 EMERGENCY: Extended Offline ($offlineMinutes min)';
  final String body = 'CRITICAL: Device offline for $offlineMinutes minutes. Background service maintaining GPS tracking. Check connection immediately.';
  AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'emergency_bg_override',
    'EMERGENCY BACKGROUND ALERT',
    channelDescription: 'Emergency background alert for extended disconnection',
    importance: Importance.max,
    priority: Priority.max,
    ongoing: true,
    autoCancel: false,
    fullScreenIntent: true,
    category: AndroidNotificationCategory.alarm,
    visibility: NotificationVisibility.public,
    color: Color(0xFFFF4500),
    colorized: true,
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 1500, 1000, 1500, 1000, 1500]),
    enableLights: true,
    ledColor: Color(0xFFFF4500),
    ledOnMs: 1500,
    ledOffMs: 500,
    sound: RawResourceAndroidNotificationSound('alarm_sound'),
    playSound: true,
    showWhen: true,
    channelShowBadge: true,
    timeoutAfter: null,
    styleInformation: BigTextStyleInformation(
      body,
      contentTitle: title,
    ),
  );
  
  NotificationDetails details = NotificationDetails(android: androidDetails);
  
  await _notifications.show(
    emergencyAlertId,
    title,
    body,
    details,
  );
  
  print('BackgroundService: EMERGENCY alert sent - offline for $offlineMinutes minutes');
}

// Connection restored notification
Future<void> _showConnectionRestoredNotification() async {
  const String title = '✅ Background Service: Connection Restored';
  final String body = 'Network restored successfully. Location sync resumed. Disconnection count: $_disconnectionCount';
  AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'reconnection_channel',
    'Connection Restored',
    channelDescription: 'Network connection restored notification',
    importance: Importance.high,
    priority: Priority.high,
    enableVibration: false,
    visibility: NotificationVisibility.public,
    autoCancel: true,
    color: Color(0xFF00FF00),
    colorized: true,
    styleInformation: BigTextStyleInformation(
      body,
      contentTitle: title,
    ),
  );
  
  NotificationDetails details = NotificationDetails(android: androidDetails);
  
  await _notifications.show(
    reconnectionNotificationId,
    title,
    body,
    details,
  );
  
  // Auto-dismiss after 3 seconds
  Timer(const Duration(seconds: 3), () {
    _notifications.cancel(reconnectionNotificationId);
  });
}

// Heartbeat notification
Future<void> _showHeartbeatNotification() async {
  final uptime = _serviceStartTime != null 
      ? DateTime.now().difference(_serviceStartTime!).inMinutes 
      : 0;

  final sessionStatus = _sessionActive ? 'ACTIVE' : 'TERMINATED';

  final String title = 'PNP Enhanced Monitoring Active';
  final String body = 'Uptime: ${uptime}min • Disconnections: $_disconnectionCount • Status: ${_isOnline ? "ONLINE" : "OFFLINE"} • Session: $sessionStatus • ${DateTime.now().toString().substring(11, 16)}';
  AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    heartbeatChannelId,
    'PNP Enhanced Heartbeat',
    channelDescription: 'Shows enhanced monitoring is active',
    importance: Importance.min,
    priority: Priority.min,
    showWhen: true,
    ongoing: false,
    autoCancel: true,
    // ADDED: Make notification visible on lockscreen
    visibility: NotificationVisibility.public,
    showProgress: false,
    styleInformation: BigTextStyleInformation(
      body,
      contentTitle: title,
    ),
  );
  
  NotificationDetails details = NotificationDetails(android: androidDetails);
  
  await _notifications.show(
    heartbeatNotificationId,
    title,
    body,
    details,
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  _serviceStartTime = DateTime.now();
  _serviceInstance = service;

  // ENHANCED: Check if service was permanently disabled during logout
  try {
    final prefs = await SharedPreferences.getInstance();
    final isPermanentlyDisabled = prefs.getBool('background_service_permanently_disabled') ?? false;
    final disableTimestamp = prefs.getInt('background_service_disable_timestamp') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // ENHANCED: Also check if user is logged out
    final hasToken = prefs.getString('token') != null;
    final hasDeploymentCode = prefs.getString('deploymentCode') != null;
    final isLoggedIn = hasToken && hasDeploymentCode;

    // If service was disabled less than 10 minutes ago, don't start
    if (isPermanentlyDisabled && (now - disableTimestamp) < 600000) {
      print('BackgroundService: Service was permanently disabled, stopping immediately');

      // AGGRESSIVE: Clear notifications before stopping
      try {
        await NotificationUtils.clearAllNotificationsSafely();
        print('BackgroundService: Cleared all notifications before stop');
      } catch (e) {
        print('BackgroundService: Error clearing notifications: $e');
      }

      service.stopSelf();
      return;
    }

    // ENHANCED: If user is not logged in, don't start service
    if (!isLoggedIn) {
      print('BackgroundService: User not logged in, stopping immediately');

      // Clear notifications before stopping
      try {
        await NotificationUtils.clearAllNotificationsSafely();
        print('BackgroundService: Cleared all notifications - user not logged in');
      } catch (e) {
        print('BackgroundService: Error clearing notifications: $e');
      }

      service.stopSelf();
      return;
    }

    // Clear old disable flags (older than 10 minutes)
    if (isPermanentlyDisabled && (now - disableTimestamp) >= 600000) {
      await prefs.remove('background_service_permanently_disabled');
      await prefs.remove('background_service_disable_timestamp');
      print('BackgroundService: Cleared old disable flags');
    }
  } catch (e) {
    print('BackgroundService: Error checking disable flags: $e');
  }

  print('BackgroundService: Starting ENHANCED monitoring system with TimerCoordinator...');
  // Snapshot credentials at service start to detect account/code switches
  try {
    final prefs = await SharedPreferences.getInstance();
    _initialToken = prefs.getString('token');
    _initialDeploymentCode = prefs.getString('deploymentCode');
    _lastLogoutTimestamp = DateTime.fromMillisecondsSinceEpoch(
      prefs.getInt('logoutTimestamp') ?? 0
    );
    print('BackgroundService: Captured initial credentials (token: ' 
      + (_initialToken == null ? 'null' : 'set') + ', deploymentCode: ' 
      + (_initialDeploymentCode ?? 'null') + ')');
  } catch (e) {
    print('BackgroundService: Failed to capture initial credentials: $e');
  }

  // ENHANCED: Start aggressive credential monitoring every 5 seconds
  _startAggressiveCredentialMonitoring();
  
  // Initialize TimerCoordinator
  await _timerCoordinator.initialize();
  
  // AGGRESSIVE: PNP-optimized WakeLock implementation
  try {
    final wakeLockService = WakeLockService();
    await wakeLockService.initialize();
    final success = await wakeLockService.enableForBackgroundService();
    
      if (success) {
        print('BackgroundService: ✅ WakeLock enabled');
      } else {
        print('BackgroundService: ⚠️ WakeLock strategies applied');
        // Even if wake lock fails, we continue with aggressive maintenance
        print('BackgroundService: background service with aggressive wake lock maintenance');
      }
    } catch (e) {
      print('BackgroundService: ⚠️ WakeLock initialization failed: $e');
      print('BackgroundService: service continues with fallback strategies');
    }

  // Register TimerCoordinator callbacks
  _timerCoordinator.onSessionCheck(() async {
    await _checkSessionStatus();
  });
  print('BackgroundService: Session monitoring callback registered');

  // FIXED: Enhanced connectivity monitoring with proper cleanup
  await _initializeConnectivityMonitoring();

  // Register emergency monitoring callback
  _timerCoordinator.onWatchdog(() {
    if (!_isOnline) {
      _showEmergencyBackgroundAlert();
    }
  });
  print('BackgroundService: Emergency monitoring callback registered');

  // Register heartbeat callback
  _timerCoordinator.onHeartbeat(() {
    _showHeartbeatNotification();
    // CRITICAL FIX: Monitor adaptive interval
    final currentInterval = ApiService.getCurrentInterval();
    print('BackgroundService: Current adaptive interval: ${currentInterval.inSeconds}s');
  });
  print('BackgroundService: Heartbeat callback registered');

  // FIXED: Handle service stop requests with proper cleanup
  service.on('stopService').listen((event) async {
    print('BackgroundService: Stop ENHANCED service requested - starting cleanup...');
    
    // CRITICAL FIX: Stop adaptive location updates
    ApiService.stopAdaptiveUpdates();
    print('BackgroundService: Adaptive location updates stopped');
    
    // Clean up TimerCoordinator
    _timerCoordinator.dispose();
    
    // Clean up offline notification timer
    _offlineNotificationTimer?.cancel();
    _offlineNotificationTimer = null;
    
    // Clean up connectivity polling timer
    _connectivityPollingTimer?.cancel();
    _connectivityPollingTimer = null;
    
    // Clean up credential monitoring timer
    _credentialMonitoringTimer?.cancel();
    _credentialMonitoringTimer = null;
    
    // Clean up connectivity monitoring
    await _cleanupConnectivityMonitoring();
    
    // Disable wake lock
    try {
      await WakelockPlus.disable();
      print('BackgroundService: Wake lock disabled');
    } catch (e) {
      print('BackgroundService: Error disabling wake lock: $e');
    }
    
    print('BackgroundService: Cleanup completed, stopping service...');
    service.stopSelf();
  });

  // CRITICAL FIX: Use adaptive location updates instead of fixed timer
  print('BackgroundService: Starting adaptive location updates...');
  await _startAdaptiveLocationUpdates(service);
  print('BackgroundService: Adaptive location tracking started');

  // Register connectivity monitoring callback
  _timerCoordinator.onConnectivity(() async {
    await _checkLocationServiceStatus();
  });
  print('BackgroundService: Location service monitoring callback registered');
}

// FIXED: Initialize connectivity monitoring with proper cleanup
Future<void> _initializeConnectivityMonitoring() async {
  try {
    print('BackgroundService: Initializing connectivity monitoring...');
    
    // Clean up existing subscription first
    await _cleanupConnectivityMonitoring();
    
    // Layer 1: System connectivity listener
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        final result = results.isNotEmpty ? results.first : ConnectivityResult.none;
        _handleConnectivityChange(result, 'System Listener');
      },
      onError: (error) {
        print('BackgroundService: Connectivity subscription error: $error');
      },
      cancelOnError: false,
    );
    
    // Layer 2: Disabled aggressive polling timer to prevent false notifications
    // The system connectivity listener should be sufficient for most cases
    print('BackgroundService: Skipping aggressive polling timer to prevent false notifications');
    
    print('BackgroundService: Connectivity monitoring initialized successfully');
  } catch (e) {
    print('BackgroundService: Error initializing connectivity monitoring: $e');
  }
}

// FIXED: Cleanup connectivity monitoring
Future<void> _cleanupConnectivityMonitoring() async {
  try {
    print('BackgroundService: Cleaning up connectivity monitoring...');
    
    // Cancel connectivity subscription
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    
    // Cancel connectivity polling timer
    _connectivityPollingTimer?.cancel();
    _connectivityPollingTimer = null;
    
    // Cancel credential monitoring timer
    _credentialMonitoringTimer?.cancel();
    _credentialMonitoringTimer = null;
    
    print('BackgroundService: Connectivity monitoring cleaned up');
  } catch (e) {
    print('BackgroundService: Error cleaning up connectivity monitoring: $e');
  }
}

// ENHANCED: Network keep-alive mechanism every 45 seconds
void _startAggressiveCredentialMonitoring() {
  print('BackgroundService: Starting network keep-alive mechanism (every 45 seconds)...');
  
  _credentialMonitoringTimer?.cancel();
  _credentialMonitoringTimer = Timer.periodic(const Duration(seconds: 45), (timer) async {
    await _performNetworkKeepAlive();
    _checkCredentialsAndLogoutTimestamp();
  });
}

// ENHANCED: Network keep-alive mechanism
Future<void> _performNetworkKeepAlive() async {
  try {
    // Ultra-lightweight network ping using Google's no-content endpoint
    const keepAliveUrl = 'https://www.google.com/generate_204';
    final response = await http.get(Uri.parse(keepAliveUrl)).timeout(Duration(seconds: 5));
    
    if (response.statusCode == 204 || response.statusCode == 200) {
      print('BackgroundService: Network keep-alive successful');
    } else {
      print('BackgroundService: Network keep-alive returned: ${response.statusCode}');
    }
    
    // Maintains active network connection without heavy data usage
  } catch (e) {
    print('BackgroundService: Network keep-alive failed: $e');
    // Don't throw - this is just a keep-alive mechanism
  }
}

// ENHANCED: Check credentials and logout timestamp to prevent zombie services
Future<void> _checkCredentialsAndLogoutTimestamp() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final currentToken = prefs.getString('token');
    final currentDeploymentCode = prefs.getString('deploymentCode');
    final currentLogoutTimestamp = prefs.getInt('logoutTimestamp');
    final isPermanentlyDisabled = prefs.getBool('background_service_permanently_disabled') ?? false;
    
    // CRITICAL: Check if service was permanently disabled during logout
    if (isPermanentlyDisabled) {
      print('BackgroundService: 🚨 SERVICE PERMANENTLY DISABLED - Stopping immediately');
      await _cleanupAndStop();
      return;
    }
    
    // Check if credentials have changed
    if ((_initialToken != null && currentToken != _initialToken) ||
        (_initialDeploymentCode != null && currentDeploymentCode != _initialDeploymentCode)) {
      print('BackgroundService: 🚨 CREDENTIALS CHANGED - Stopping old background instance');
      await _cleanupAndStop();
      return;
    }
    
    // Check if logout timestamp has changed (indicating a logout occurred)
    if (currentLogoutTimestamp != null && 
        _lastLogoutTimestamp != null &&
        currentLogoutTimestamp > _lastLogoutTimestamp!.millisecondsSinceEpoch) {
      print('BackgroundService: 🚨 LOGOUT DETECTED - Stopping background instance');
      await _cleanupAndStop();
      return;
    }
    
    // Check if credentials are completely cleared (logout occurred)
    if (currentToken == null && currentDeploymentCode == null) {
      print('BackgroundService: 🚨 CREDENTIALS CLEARED - Stopping background instance');
      await _cleanupAndStop();
      return;
    }
    
    print('BackgroundService: Credential check passed - service continues');
  } catch (e) {
    print('BackgroundService: Error in credential monitoring: $e');
  }
}

// ENHANCED: Cleanup and stop service with proper notification clearing
Future<void> _cleanupAndStop() async {
  try {
    print('BackgroundService: Starting immediate cleanup...');
    
    // Stop all timers first
    _timerCoordinator.dispose();
    _offlineNotificationTimer?.cancel();
    _connectivityPollingTimer?.cancel();
    _credentialMonitoringTimer?.cancel();
    
    // Clean up connectivity monitoring
    await _cleanupConnectivityMonitoring();
    
    // Disable wake lock
    try {
      await WakelockPlus.disable();
    } catch (e) {
      print('BackgroundService: Error disabling wake lock: $e');
    }
    
    // CRITICAL: Clear all notifications immediately
    try {
      await NotificationUtils.clearAllNotificationsSafely();
      print('BackgroundService: All notifications cleared');
    } catch (e) {
      print('BackgroundService: Error clearing notifications: $e');
    }
    
    // Stop the service
    _serviceInstance?.stopSelf();
    print('BackgroundService: Service stopped after cleanup');
  } catch (e) {
    print('BackgroundService: Error during cleanup: $e');
    // Force stop even if cleanup fails
    _serviceInstance?.stopSelf();
  }
}

// FIXED: Verify if session termination is real or just network issue
Future<bool> _isRealSessionTermination(String token, String deploymentCode) async {
  print('BackgroundService: Verifying if session termination is genuine...');

  // Retry session check 2 times to distinguish between
  // genuine session termination and temporary network issues
  for (int i = 1; i <= 2; i++) {
    try {
      print('BackgroundService: Session termination verification attempt $i/2...');

      // Wait before retry (shorter delays for session checks: 3s, 6s)
      await Future.delayed(Duration(seconds: 3 * i));

      // Try to check status again
      final retryResult = await ApiService.checkStatus(token, deploymentCode)
          .timeout(const Duration(seconds: 10));

      if (retryResult.success && retryResult.data != null) {
        final isLoggedIn = retryResult.data!['isLoggedIn'] ?? false;

        if (isLoggedIn) {
          print('BackgroundService: ✅ Session termination verification failed - user is still logged in');
          return false; // Not a real session termination
        }
      } else {
        // If we get errors, it might be network related
        print('BackgroundService: ⚠️ Session verification retry $i failed: ${retryResult.message}');
      }

    } catch (e) {
      print('BackgroundService: ❌ Session verification retry $i error: $e');
      // Network error during retry - might not be real termination
    }
  }

  print('BackgroundService: 🚨 Session termination verification confirms: user logged out');
  return true; // Confirmed session termination
}

// FIXED: Verify if authentication failure is real or just network issue
Future<bool> _isRealAuthenticationFailure(String token, String deploymentCode) async {
  print('BackgroundService: Verifying if authentication failure is genuine...');

  // Retry authentication 3 times with delays to distinguish between
  // genuine auth failures and temporary network issues
  for (int i = 1; i <= 3; i++) {
    try {
      print('BackgroundService: Authentication retry attempt $i/3...');

      // Wait before retry (exponential backoff: 2s, 4s, 8s)
      await Future.delayed(Duration(seconds: 2 * i));

      // Try to check status again
      final retryResult = await ApiService.checkStatus(token, deploymentCode)
          .timeout(const Duration(seconds: 10));

      if (retryResult.success) {
        print('BackgroundService: ✅ Authentication retry succeeded - was network issue');
        return false; // Not a real auth failure
      } else if (!retryResult.message.contains('Authentication failed') &&
                 !retryResult.message.contains('401') &&
                 !retryResult.message.contains('unauthorized')) {
        // If it's not an auth error, it's likely network issue
        print('BackgroundService: ⚠️ Retry failed with non-auth error: ${retryResult.message}');
        return false; // Not a real auth failure
      }

      print('BackgroundService: ❌ Authentication retry $i failed: ${retryResult.message}');

    } catch (e) {
      print('BackgroundService: ❌ Authentication retry $i error: $e');
      // Network error during retry - continue trying
    }
  }

  print('BackgroundService: 🚨 All authentication retries failed - confirmed genuine auth failure');
  return true; // Real authentication failure
}

// Check session status with timeout handling
Future<void> _checkSessionStatus() async {
  try {
    _lastSessionCheck = DateTime.now();
    
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final deploymentCode = prefs.getString('deploymentCode');

    // Guard: stop this background instance if credentials switched
    if ((_initialToken != null && token != _initialToken) ||
        (_initialDeploymentCode != null && deploymentCode != _initialDeploymentCode)) {
      print('BackgroundService: Credentials changed (token/code). Stopping old background instance.');
      _timerCoordinator.dispose();
      _serviceInstance?.stopSelf();
      return;
    }

    if (token == null || deploymentCode == null) {
      print('BackgroundService: No credentials for session check');
      return;
    }

    // Check network connectivity before attempting server call
    if (!_isOnline) {
      print('BackgroundService: Device is offline, skipping session verification');
      return; // Skip the server call entirely when offline
    }

    print('BackgroundService: Checking session status... (${_lastSessionCheck!.toString().substring(11, 19)})');

    // Add timeout to session check
    final statusResponse = await ApiService.checkStatus(token, deploymentCode)
        .timeout(const Duration(seconds: 8));
    
    if (statusResponse.success && statusResponse.data != null) {
      final isLoggedIn = statusResponse.data!['isLoggedIn'] ?? false;

      if (!isLoggedIn && _sessionActive) {
        // FIXED: Before clearing credentials, verify it's not a network-related false negative
        if (!await _isRealSessionTermination(token, deploymentCode)) {
          print('BackgroundService: ⚠️ Session appears terminated but may be network-related, keeping credentials');
          return; // Don't clear credentials for potential false negatives
        }

        print('BackgroundService: 🚨 CONFIRMED SESSION TERMINATED BY ANOTHER DEVICE');
        _sessionActive = false;

        // Clear credentials only after confirmation
        await prefs.remove('deploymentCode');
        await prefs.setBool('isTokenLocked', false);

        // Show session terminated notification
        await _showSessionTerminatedNotification();

        print('BackgroundService: Session terminated, background service will stop');

      } else if (isLoggedIn) {
        if (!_sessionActive) {
          print('BackgroundService: Session restored');
          _sessionActive = true;
        }
        print('BackgroundService: ✅ Session still active');
      }
    } else {
      // FIXED: Handle auth failures with retry mechanism before clearing credentials
      print('BackgroundService: ❌ Session verification failed: ${statusResponse.message}');

      // If it's a 401 error, check if it's really a session termination or just network issue
      if (statusResponse.message.contains('Authentication failed') ||
          statusResponse.message.contains('401') ||
          statusResponse.message.contains('unauthorized')) {

        // FIXED: Don't immediately clear credentials - add retry mechanism
        if (!await _isRealAuthenticationFailure(token, deploymentCode)) {
          print('BackgroundService: ⚠️ Authentication issue appears to be network-related, not clearing credentials');
          return; // Don't clear credentials for temporary network issues
        }

        print('BackgroundService: 🚨 CONFIRMED AUTHENTICATION FAILED - STOPPING SERVICE');
        _sessionActive = false;

        // Clear credentials only after confirming it's a real auth failure
        await prefs.remove('deploymentCode');
        await prefs.setBool('isTokenLocked', false);

        // Show session terminated notification
        await _showSessionTerminatedNotification();

        print('BackgroundService: Service stopped due to confirmed authentication failure');
      }
    }
  } on TimeoutException catch (e) {
    print('BackgroundService: Session check timeout: $e');
  } catch (e) {
    print('BackgroundService: Session check failed: $e');
    // Don't change session status on network errors
  }
}

// Handle connectivity changes with enhanced notifications
void _handleConnectivityChange(ConnectivityResult result, String source) {
  final wasOnline = _isOnline;
  _isOnline = result != ConnectivityResult.none;
  
  print('BackgroundService: ENHANCED connectivity change via $source - $result (${_isOnline ? "online" : "offline"})');
  print('BackgroundService: Previous state: ${wasOnline ? "online" : "offline"}, New state: ${_isOnline ? "online" : "offline"}');
  
  // Only process actual connectivity changes, not polling noise
  if (_isOnline == wasOnline) {
    print('BackgroundService: No actual connectivity change detected, ignoring');
    return;
  }
  
  if (!_isOnline && wasOnline) {
    // Connection lost - ENHANCED response with transition buffer
    _disconnectionCount++;
    print('BackgroundService: ENHANCED CONNECTION LOST (#$_disconnectionCount) - Starting transition buffer');
    
    // FIXED: Transition buffer prevents false disconnections during network switches
    Future.delayed(Duration(seconds: 5), () async {
      final recheckResults = await Connectivity().checkConnectivity();
      final isStillOffline = recheckResults.contains(ConnectivityResult.none);
      
      if (isStillOffline && !_isOnline) {
        print('BackgroundService: Confirmed offline after buffer period');
        // IMMEDIATE enhanced notification
        _showAggressiveDisconnectionNotification();
        
        // FIXED: Notification frequency reduced from 10→15 seconds to reduce alarm annoyance
        _offlineNotificationTimer?.cancel(); // Cancel any existing timer
        _offlineNotificationTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
          print('BackgroundService: Periodic notification timer triggered - sending notification');
          _showAggressiveDisconnectionNotification();
        });
      } else {
        print('BackgroundService: False disconnection prevented by transition buffer');
      }
    });
    
  } else if (_isOnline && !wasOnline) {
    // Connection restored - Cancel enhanced alerts
    print('BackgroundService: ENHANCED connection restored - Cancelling notification timer');
    
    // Cancel the persistent notification timer
    _offlineNotificationTimer?.cancel();
    _offlineNotificationTimer = null;
    print('BackgroundService: Notification timer cancelled and set to null');
    
    if (_wasOfflineNotificationSent) {
      _notifications.cancel(aggressiveDisconnectionId);
      _notifications.cancel(emergencyAlertId);
      _showConnectionRestoredNotification();
      _wasOfflineNotificationSent = false;
      print('BackgroundService: All notifications cancelled and flags reset');
    }
    
    // FIXED: Immediate aggressive sync after network restoration
    Future.delayed(Duration(seconds: 2), () async {
      print('BackgroundService: Starting immediate aggressive sync after reconnection');
      await _attemptImmediateLocationSync();
    });
  }
}


// ENHANCED: Check location service status in background
Future<void> _checkLocationServiceStatus() async {
  try {
    // Check if location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    
    // Check location permissions
    LocationPermission permission = await Geolocator.checkPermission();
    bool hasPermission = permission == LocationPermission.whileInUse || 
                        permission == LocationPermission.always;
    
    // Check if location access is compromised
    if (!serviceEnabled || !hasPermission) {
      print('BackgroundService: 🚨 LOCATION SERVICE COMPROMISED - Service: $serviceEnabled, Permission: $permission');
      
      // Show critical location alert notification
      await _showCriticalLocationAlert();
    }
  } catch (e) {
    print('BackgroundService: Error checking location service status: $e');
  }
}

// Show critical location alert notification
Future<void> _showCriticalLocationAlert() async {
  const String title = '🚨 CRITICAL: Location Service Compromised';
  const String body = 'GPS/Location access lost in background! Device tracking compromised. Immediate action required.';
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'location_alert_channel',
    'Location Service Compromised',
    channelDescription: 'Critical alert for location service disconnection',
    importance: Importance.max,
    priority: Priority.max,
    enableVibration: true,
    sound: RawResourceAndroidNotificationSound('alarm_sound'),
    visibility: NotificationVisibility.public,
    ongoing: true,
    autoCancel: false,
    fullScreenIntent: true,
    color: Color(0xFFFF0000),
    colorized: true,
    styleInformation: BigTextStyleInformation(
      body,
      contentTitle: title,
    ),
  );
  
  const NotificationDetails details = NotificationDetails(android: androidDetails);
  
  await _notifications.show(
    1003, // Critical location alert notification ID
    title,
    body,
    details,
  );
}

// FIXED: Immediate location sync after network restoration  
Future<void> _attemptImmediateLocationSync() async {
  const int maxRetries = 3;
  int retryCount = 0;
  bool updateSuccessful = false;

  while (!updateSuccessful && retryCount < maxRetries) {
    try {
      print('BackgroundService: Immediate sync attempt #${retryCount + 1}');
      
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final deploymentCode = prefs.getString('deploymentCode');

      if (token == null || deploymentCode == null) {
        print('BackgroundService: No credentials for immediate sync');
        return;
      }

      final position = await _getCurrentLocationWithEnhancedRetry();
      if (position != null) {
        final battery = Battery();
        final batteryLevel = await battery.batteryLevel;

        final result = await ApiService.updateLocation(
          token: token,
          deploymentCode: deploymentCode,
          position: position,
          batteryLevel: batteryLevel,
          signal: await _getSignalStatus(),
          isAggressiveSync: retryCount > 1, // Enable aggressive mode after first retry
        );

        if (result.success) {
          updateSuccessful = true;
          print('BackgroundService: Immediate sync successful on attempt #${retryCount + 1}');
          
          // Follow-up confirmation syncs as per analysis
          Future.delayed(Duration(seconds: 10), () async {
            if (_isOnline) await _attemptFollowUpSync('10s follow-up');
          });
          Future.delayed(Duration(seconds: 30), () async {
            if (_isOnline) await _attemptFollowUpSync('30s follow-up');
          });
          Future.delayed(Duration(seconds: 60), () async {
            if (_isOnline) await _attemptFollowUpSync('60s follow-up');
          });
          
        } else {
          print('BackgroundService: Immediate sync failed on attempt #${retryCount + 1}: ${result.message}');
        }
      } else {
        print('BackgroundService: No location available for immediate sync attempt #${retryCount + 1}');
      }
    } catch (e) {
      print('BackgroundService: Error in immediate sync attempt #${retryCount + 1}: $e');
    }
    
    retryCount++;
    if (!updateSuccessful && retryCount < maxRetries) {
      await Future.delayed(Duration(seconds: 2)); // Brief delay between retries
    }
  }
}

// Follow-up sync for multi-layer reconnection reliability
Future<void> _attemptFollowUpSync(String stage) async {
  try {
    print('BackgroundService: Starting $stage sync');
    
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final deploymentCode = prefs.getString('deploymentCode');

    if (token == null || deploymentCode == null) return;

    final position = await _getCurrentLocationWithEnhancedRetry();
    if (position != null) {
      final battery = Battery();
      final batteryLevel = await battery.batteryLevel;

      final result = await ApiService.updateLocation(
        token: token,
        deploymentCode: deploymentCode,
        position: position,
        batteryLevel: batteryLevel,
        signal: await _getSignalStatus(),
        isAggressiveSync: true,
      );

      if (result.success) {
        print('BackgroundService: $stage sync successful');
      } else {
        print('BackgroundService: $stage sync failed: ${result.message}');
      }
    }
  } catch (e) {
    print('BackgroundService: Error in $stage sync: $e');
  }
}

// Helper function to get current location with enhanced retry
Future<Position?> _getCurrentLocationWithEnhancedRetry() async {
  try {
    // Check location permissions first
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        print('BackgroundService: Location permission denied');
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      print('BackgroundService: Location permission permanently denied');
      return null;
    }

    // Check if location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print('BackgroundService: Location services are disabled');
      return null;
    }

    // Get current position with high accuracy
    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 10),
    );

    return position;
  } catch (e) {
    print('BackgroundService: Error getting location: $e');
    return null;
  }
}

// Helper function to get signal status using API service
Future<String> _getSignalStatus() async {
  try {
    // Use the improved API-based signal detection
    return await ApiService.getSignalStatus();
  } catch (e) {
    print('BackgroundService: Error getting signal status: $e');
    return SignalStatus.poor;
  }
}

// Safe background service start function
Future<void> startBackgroundServiceSafely() async {
  try {
    print('BackgroundService: Starting background service safely...');
    
    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();
    
    if (!isRunning) {
      await service.startService();
      print('BackgroundService: Background service started successfully');
    } else {
      print('BackgroundService: Background service already running');
    }
  } catch (e) {
    print('BackgroundService: Error starting background service: $e');
    // Don't throw - allow app to continue without background service
  }
}

// CRITICAL FIX: Start adaptive location updates for background service
Future<void> _startAdaptiveLocationUpdates(ServiceInstance service) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final deploymentCode = prefs.getString('deploymentCode');
    
    if (token == null || deploymentCode == null) {
      print('BackgroundService: No credentials for adaptive location updates');
      return;
    }
    
    // Start adaptive location updates with proper parameters
    ApiService.startAdaptiveLocationUpdates(
      token: token,
      deploymentCode: deploymentCode,
      getCurrentPosition: () async {
        return await _getCurrentLocationWithEnhancedRetry();
      },
      getBatteryLevel: () async {
        final battery = Battery();
        return await battery.batteryLevel;
      },
      getSignalStatus: () async {
        return await _getSignalStatus();
      },
    );
    
    print('BackgroundService: Adaptive location updates started successfully');
    print('BackgroundService: Initial interval: ${ApiService.getCurrentInterval().inSeconds}s');
  } catch (e) {
    print('BackgroundService: Error starting adaptive location updates: $e');
  }
}

// Emergency update feature removed

// Safe background service stop function
Future<void> stopBackgroundServiceSafely() async {
  try {
    print('BackgroundService: Stopping background service safely...');
    
    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();
    
    if (isRunning) {
      service.invoke('stopService');
      print('BackgroundService: Background service stop requested');
    } else {
      print('BackgroundService: Background service not running');
    }
  } catch (e) {
    print('BackgroundService: Error stopping background service: $e');
    // Don't throw - allow app to continue
  }
}