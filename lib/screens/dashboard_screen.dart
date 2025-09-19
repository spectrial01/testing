import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../ui/widgets/logout_confirmation_dialog.dart';
import '../services/location_service.dart';
import '../services/device_service.dart';
import '../services/api_service.dart';
import '../services/background_service.dart';
import '../services/watchdog_service.dart';
import '../services/wake_lock_service.dart';
import '../services/network_connectivity_service.dart';
import '../services/timer_coordinator.dart';
import '../services/secure_storage_service.dart';
import '../ui/services/theme_provider.dart';
import '../ui/services/responsive_ui_service.dart';
import '../services/update_service.dart';
import '../services/logout_service.dart'; // NEW: Import logout service
import '../ui/widgets/auto_size_text.dart';
import '../ui/widgets/update_dialog.dart';
import '../ui/widgets/hero_header.dart';
import '../ui/widgets/status_card.dart';
import '../utils/constants.dart';
import 'login_screen.dart';

class DashboardScreen extends StatefulWidget {
  final String token;
  final String deploymentCode;

  const DashboardScreen({
    super.key,
    required this.token,
    required this.deploymentCode,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with ResponsiveStateMixin, WidgetsBindingObserver {
  final _locationService = LocationService();
  final _deviceService = DeviceService();
  final _watchdogService = WatchdogService();
  final _wakeLockService = WakeLockService();
  final _networkService = NetworkConnectivityService();
  final _timerCoordinator = TimerCoordinator();
  final _logoutService = LogoutService(); // NEW: Add logout service
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  // TimerCoordinator callbacks
  VoidCallback? _sessionCheckCallback;
  VoidCallback? _heartbeatCallback;
  VoidCallback? _locationMonitoringCallback;

  bool _isLoading = true;
  bool _isLocationLoading = true;
  bool _isLoggingOut = false; // NEW: Track logout state
  
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  int _locationUpdatesSent = 0;
  DateTime? _lastSuccessfulUpdate;
  bool _isOnline = true;

  bool _isCheckingSession = false;
  bool _sessionActive = true;
  DateTime? _lastSessionCheck;
  int _consecutiveSessionFailures = 0;
  static const int _maxSessionFailures = 3;
  static const Duration _sessionCheckTimeout = Duration(seconds: 8);
  static const Duration _sessionRetryDelay = Duration(seconds: 2);

  StreamSubscription<ServiceStatus>? _locationServiceStatusSubscription;
  bool _isLocationServiceEnabled = true;

  // Realtime console state
  final List<String> _consoleLines = [];
  static const int _consoleMaxLines = 150;
  
  void _pushConsole(String message) {
    final now = DateTime.now();
    final time = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
    final line = "$time  $message";
    
    if (mounted) {
      setState(() {
        _consoleLines.add(line);
        if (_consoleLines.length > _consoleMaxLines) {
          _consoleLines.removeRange(0, _consoleLines.length - _consoleMaxLines);
        }
      });
    } else {
      _consoleLines.add(line);
      if (_consoleLines.length > _consoleMaxLines) {
        _consoleLines.removeRange(0, _consoleLines.length - _consoleMaxLines);
      }
    }
  }

  void _seedConsole() {
    if (_consoleLines.isNotEmpty) return;
    _consoleLines.add(_isOnline ? 'Network: ONLINE' : 'Network: OFFLINE');
    _consoleLines.add('Session: ' + (_sessionActive ? 'ACTIVE' : 'LOST'));
    _consoleLines.add('Battery: ${_deviceService.batteryLevel}%');
    _consoleLines.add('Signal: ${_deviceService.signalStatus.toUpperCase()}');
    if (_lastSuccessfulUpdate != null) {
      _consoleLines.add('Last update: ${_lastSuccessfulUpdate!.toString().substring(11, 19)} (sent: $_locationUpdatesSent)');
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeServices();
    _initializeNotifications();
    _listenForConnectivityChanges();
    _startSessionMonitoring();
    _listenToLocationServiceStatus();
  }

  @override
  void dispose() {
    // NEW: Enhanced dispose with logout service cleanup
    if (!_isLoggingOut) {
      // Only clean up if not in logout process
      _cleanupAllTimers();
      _locationService.dispose();
      _deviceService.dispose();
      _watchdogService.stopWatchdog();
      _networkService.dispose();
      _timerCoordinator.dispose();
      _connectivitySubscription?.cancel();
      _locationServiceStatusSubscription?.cancel();
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.resumed:
        print('Dashboard: App resumed - re-enabling wake lock...');
        _wakeLockService.setBackgroundMode(false);
        _watchdogService.markAppAsAlive();
        // Re-enable wake lock when app comes to foreground
        _wakeLockService.forceEnableForCriticalOperation();
        break;
      case AppLifecycleState.paused:
        print('Dashboard: App paused - setting background mode...');
        _wakeLockService.setBackgroundMode(true);
        break;
      case AppLifecycleState.detached:
        print('Dashboard: App detached - disabling wake lock...');
        _wakeLockService.disableWakeLock();
        break;
      default:
        break;
    }
  }

  // NEW: Enhanced logout implementation
  Future<void> _performLogout() async {
    // Check network connectivity first
    var connectivityResult = await (Connectivity().checkConnectivity());
    if (!connectivityResult.contains(ConnectivityResult.mobile) &&
        !connectivityResult.contains(ConnectivityResult.wifi)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AutoSizeText(
              'No network connection. Please connect to log out properly.',
              maxFontSize: getResponsiveFont(14.0),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Show confirmation dialog
    final confirmed = await LogoutConfirmationDialog.show(context: context);
    if (confirmed != true) return;

    // Set logout state to prevent double logout
    if (_isLoggingOut) {
      print('Dashboard: Logout already in progress, ignoring...');
      return;
    }

    setState(() {
      _isLoggingOut = true;
    });

    // Show logout progress dialog
    _showLogoutProgressDialog();

    try {
      print('Dashboard: Starting enhanced logout process...');
      _pushConsole('🚪 LOGOUT INITIATED - Starting cleanup...');

      // Use the new LogoutService for complete cleanup
      final logoutResult = await _logoutService.performCompleteLogout(
        token: widget.token,
        deploymentCode: widget.deploymentCode,
      );

      if (logoutResult.success) {
        print('Dashboard: Logout completed successfully');
        _pushConsole('✅ LOGOUT COMPLETED - All systems stopped');
        
        // Navigate to login screen
        if (mounted) {
          Navigator.of(context).pop(); // Close progress dialog
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const LoginScreen()),
            (route) => false,
          );
        }
      } else {
        // Handle logout failure
        print('Dashboard: Logout failed: ${logoutResult.error ?? logoutResult.message}');
        _pushConsole('❌ LOGOUT FAILED - ${logoutResult.error ?? logoutResult.message}');
        
        if (mounted) {
          Navigator.of(context).pop(); // Close progress dialog
          _showLogoutErrorDialog(logoutResult.error ?? 'Unknown error');
        }
      }
    } catch (e) {
      print('Dashboard: Logout error: $e');
      _pushConsole('💥 LOGOUT ERROR - $e');
      
      if (mounted) {
        Navigator.of(context).pop(); // Close progress dialog
        _showLogoutErrorDialog(e.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoggingOut = false;
        });
      }
    }
  }


  // NEW: Logout progress dialog
  void _showLogoutProgressDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false, // Prevent back button during logout
        child: AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 50,
                height: 50,
                child: CircularProgressIndicator(
                  strokeWidth: 4,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              SizedBox(height: 20),
              Text(
                'Logging Out...',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Stopping all services and clearing data',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Please wait, do not close the app...',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue[700],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // NEW: Logout error dialog
  void _showLogoutErrorDialog(String errorMessage) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Expanded(child: Text('Logout Error')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The logout process encountered an error:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Text(
                errorMessage,
                style: TextStyle(
                  color: Colors.red[700],
                  fontSize: 14,
                ),
              ),
            ),
            SizedBox(height: 16),
            Text(
              'What would you like to do?',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Stay Logged In'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(context).pop();
              _performLogout(); // Retry logout
            },
            child: Text('Try Again'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(context).pop();
              _forceLogout(); // Force logout
            },
            child: Text('Force Logout'),
          ),
        ],
      ),
    );
  }

  // NEW: Force logout (fallback method)
  Future<void> _forceLogout() async {
    print('Dashboard: Force logout initiated...');
    _pushConsole('🔥 FORCE LOGOUT - Emergency cleanup');
    
    try {
      // Force clear credentials immediately
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      
      final secureStorage = SecureStorageService();
      await secureStorage.clearAllData();
      
      // Force stop background service
      try {
        await stopBackgroundServiceSafely();
      } catch (e) {
        print('Force logout: Background service stop failed: $e');
      }
      
      print('Dashboard: Force logout completed');
      _pushConsole('✅ FORCE LOGOUT COMPLETED');
      
      // Navigate to login
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      print('Dashboard: Force logout error: $e');
      // Last resort - just navigate
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  // ... [Keep all existing methods unchanged] ...
  // [All other methods remain exactly the same as the original code]
  
  void _listenToLocationServiceStatus() {
    _locationServiceStatusSubscription = Geolocator.getServiceStatusStream().listen((ServiceStatus status) {
      if (mounted) {
        final isEnabled = (status == ServiceStatus.enabled);
        if (_isLocationServiceEnabled != isEnabled) {
          setState(() {
            _isLocationServiceEnabled = isEnabled;
          });
          if (!isEnabled) {
            _startLocationAlarm();
          } else {
            _stopLocationAlarm();
          }
        }
      }
    });
  }

  void _checkLocationStatusAndNotify() async {
    try {
      final isEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isEnabled) {
        _showLocationOffNotification();
      } else {
        _notifications.cancel(AppConstants.locationWarningNotificationId);
      }
    } catch (e) {
      print('Dashboard: Error checking location status: $e');
    }
  }

  void _startLocationAlarm() {
    _checkLocationStatusAndNotify();
    print('Dashboard: Location monitoring started via TimerCoordinator.');
  }

  void _stopLocationAlarm() {
    _notifications.cancel(AppConstants.locationWarningNotificationId);
    print('Dashboard: Location monitoring stopped and notification cleared.');
  }

  Future<void> _showLocationOffNotification() async {
    const String title = 'Location Service Disabled';
    const String body = 'Location is required for the app to function correctly. Please turn it back on.';
    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'location_alarm_channel',
      'Location Status',
      channelDescription: 'Alarm for when location service is disabled',
      importance: Importance.max,
      priority: Priority.high,
      sound: RawResourceAndroidNotificationSound('alarm_sound'),
      playSound: true,
      ongoing: true,
      visibility: NotificationVisibility.public,
      styleInformation: const BigTextStyleInformation(
        body,
        contentTitle: title,
      ),
    );
    final NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await _notifications.show(
      AppConstants.locationWarningNotificationId,
      title,
      body,
      platformChannelSpecifics,
    );
  }

  void _cleanupAllTimers() {
    print('Dashboard: Cleaning up timer callbacks...');
    
    if (_sessionCheckCallback != null) {
      _timerCoordinator.removeSessionCheckCallback(_sessionCheckCallback!);
      _sessionCheckCallback = null;
    }
    if (_heartbeatCallback != null) {
      _timerCoordinator.removeHeartbeatCallback(_heartbeatCallback!);
      _heartbeatCallback = null;
    }
    if (_locationMonitoringCallback != null) {
      _timerCoordinator.removeLocationMonitoringCallback(_locationMonitoringCallback!);
      _locationMonitoringCallback = null;
    }

    print('Dashboard: All timer callbacks cleaned up successfully');
  }

  void _startSessionMonitoring() {
    print('Dashboard: Starting session monitoring via TimerCoordinator...');

    if (_sessionCheckCallback != null) {
      _timerCoordinator.removeSessionCheckCallback(_sessionCheckCallback!);
    }

    _sessionCheckCallback = () => _verifySessionWithTimeout();
    _timerCoordinator.onSessionCheck(_sessionCheckCallback!);

    Future.delayed(Duration(seconds: 2), () {
      _verifySessionWithTimeout();
    });

    print('Dashboard: Session monitoring started via TimerCoordinator');
  }

  Future<void> _verifySessionWithTimeout() async {
    if (_isCheckingSession || _isLoggingOut) { // NEW: Skip if logging out
      print('Dashboard: Session check skipped (${_isLoggingOut ? "logging out" : "already checking"})');
      return;
    }

    _isCheckingSession = true;
    
    if (mounted) {
      setState(() {
        _lastSessionCheck = DateTime.now();
      });
    } else {
      _lastSessionCheck = DateTime.now();
    }

    try {
      print('Dashboard: Starting session verification with timeout... (${_lastSessionCheck!.toString().substring(11, 19)})');
      _pushConsole('Session check started');

      final isOnline = await _networkService.checkConnectivity();
      if (!isOnline) {
        print('Dashboard: Device is offline, skipping session verification');
        _pushConsole('Session: OFFLINE MODE (skipping server check)');
        _consecutiveSessionFailures = 0;
        return;
      }

      final sessionCheckFuture = ApiService.checkStatus(
        widget.token,
        widget.deploymentCode
      );

      final statusResponse = await sessionCheckFuture.timeout(
        _sessionCheckTimeout,
        onTimeout: () {
          print('Dashboard: Session check timed out after ${_sessionCheckTimeout.inSeconds}s');
          throw TimeoutException('Session check timed out', _sessionCheckTimeout);
        },
      );

      if (statusResponse.success && statusResponse.data != null) {
        final isStillLoggedIn = statusResponse.data!['isLoggedIn'] ?? false;
        _consecutiveSessionFailures = 0;

        if (!isStillLoggedIn && _sessionActive && mounted && !_isLoggingOut) {
          print('Dashboard: SESSION TERMINATED BY ANOTHER DEVICE - auto-logging out');
          _sessionActive = false;
          _pushConsole('Session: LOST (another device)');
          await _handleAutomaticLogout();
        } else if (isStillLoggedIn && mounted) {
          if (!_sessionActive) {
            setState(() => _sessionActive = true);
            print('Dashboard: Session restored');
            _pushConsole('Session: RESTORED');
          } else {
            print('Dashboard: Session still active');
            _pushConsole('Session: ACTIVE');
          }
        }
      } else {
        print('Dashboard: Session check failed: ${statusResponse.message}');
        await _handleSessionCheckFailure('API error: ${statusResponse.message}');
        _pushConsole('Session check error: ${statusResponse.message}');
      }

    } on TimeoutException catch (e) {
      print('Dashboard: Session check timeout: $e');
      await _handleSessionCheckFailure('Timeout: ${e.message}');
      _pushConsole('Session check timeout');

    } catch (e) {
      print('Dashboard: Session verification failed: $e');
      await _handleSessionCheckFailure('Network error: $e');
      _pushConsole('Session check failed: $e');

    } finally {
      _isCheckingSession = false;
      
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _handleSessionCheckFailure(String reason) async {
    if (reason.contains('Timeout') || reason.contains('Network error')) {
      print('Dashboard: Network issue detected, staying in offline mode');
      _pushConsole('Session: NETWORK ISSUE (offline mode)');
      return;
    }
    
    _consecutiveSessionFailures++;
    print('Dashboard: Session check failure #$_consecutiveSessionFailures: $reason');

    if (_consecutiveSessionFailures >= _maxSessionFailures) {
      print('Dashboard: Too many consecutive session failures ($_consecutiveSessionFailures/$_maxSessionFailures)');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.warning, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: AutoSizeText(
                    'Session verification issues detected. Check your connection.',
                    style: TextStyle(fontSize: 14),
                    maxLines: 2,
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.orange[700],
            duration: Duration(seconds: 5),
          ),
        );
      }

      _consecutiveSessionFailures = 0;
      await Future.delayed(_sessionRetryDelay);
    }
  }

  Future<void> _handleAutomaticLogout() async {
    if (_isLoggingOut) {
      print('Dashboard: Automatic logout already in progress');
      return;
    }
    
    print('Dashboard: HANDLING AUTOMATIC LOGOUT WITH PROPER CLEANUP');
    _pushConsole('🚨 AUTO-LOGOUT: Session terminated by another device');

    setState(() {
      _isLoggingOut = true;
    });

    try {
      // Use LogoutService for automatic logout
      final logoutResult = await _logoutService.performCompleteLogout(
        token: widget.token,
        deploymentCode: widget.deploymentCode,
      );

      if (logoutResult.success && mounted) {
        _showAutomaticLogoutDialog();
      }
    } catch (e) {
      print('Dashboard: Error during automatic logout: $e');
      if (mounted) {
        _forceNavigateToLogin();
      }
    }
  }

  Future<void> _showAutomaticLogoutDialog() async {
    if (!mounted) return;

    final Completer<void> dialogCompleter = Completer<void>();
    
    Timer(const Duration(seconds: 10), () {
      if (!dialogCompleter.isCompleted) {
        print('Dashboard: Auto-dismissing logout dialog after timeout');
        dialogCompleter.complete();
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
          _forceNavigateToLogin();
        }
      }
    });

    try {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: Row(
              children: [
                Icon(Icons.logout, color: Colors.orange, size: 24),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Session Terminated',
                    style: TextStyle(
                      color: Colors.orange[700],
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Your deployment code "${widget.deploymentCode}" was logged in from another device.',
                          style: TextStyle(
                            color: Colors.orange[700],
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  'You have been automatically logged out for security. Please login again to continue.',
                  style: TextStyle(fontSize: 14),
                ),
                SizedBox(height: 12),
                Text(
                  'Time: ${DateTime.now().toString().substring(0, 19)}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                    fontSize: 12,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Auto-redirect in 10 seconds...',
                  style: TextStyle(
                    color: Colors.blue[600],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () {
                    print('Dashboard: User clicked Login Again button');
                    if (!dialogCompleter.isCompleted) {
                      dialogCompleter.complete();
                    }
                    _forceNavigateToLogin();
                  },
                  icon: Icon(Icons.login, size: 20),
                  label: Text(
                    'Login Again',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      print('Dashboard: Error showing logout dialog: $e');
      if (!dialogCompleter.isCompleted) {
        dialogCompleter.complete();
      }
      if (mounted) {
        _forceNavigateToLogin();
      }
    }
  }

  void _forceNavigateToLogin() {
    if (!mounted) return;
    
    print('Dashboard: Force navigating to login screen...');
    
    try {
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      print('Dashboard: Error in force navigation: $e');
      try {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      } catch (e2) {
        print('Dashboard: Basic navigation also failed: $e2');
      }
    }
  }

  // ... [Keep all other existing methods unchanged] ...
  
  // ... [Keep all remaining existing methods unchanged] ...
  
  List<Widget> _buildStatusCards(BuildContext context) {
    final widgets = <Widget>[
      StatusCard(
        title: 'Connection',
        value: _isOnline ? 'Online' : 'Offline',
        subtitle: _deviceService.getConnectivityDescription(),
        icon: _isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
        status: _isOnline ? 'connected' : 'disconnected',
      ),
      SizedBox(height: context.responsiveFont(12.0)),
      StatusCard(
        title: 'Battery',
        value: '${_deviceService.batteryLevel}%',
        subtitle: _deviceService.getBatteryHealthStatus(),
        icon: _getBatteryIcon(),
        status: _deviceService.batteryLevel > 20 ? 'active' : 'warning',
      ),
      SizedBox(height: context.responsiveFont(12.0)),
      StatusCard(
        title: 'Signal Status',
        value: _deviceService.signalStatus.toUpperCase(),
        subtitle: 'Network strength indicator',
        icon: Icons.signal_cellular_alt_rounded,
        status: _deviceService.signalStatus == 'strong' ? 'active' : (_deviceService.signalStatus == 'weak' ? 'warning' : 'error'),
      ),
      SizedBox(height: context.responsiveFont(12.0)),
      StatusCard(
        title: 'Last Update',
        value: _lastSuccessfulUpdate?.toString().substring(11, 19) ?? 'Never',
        subtitle: 'Most recent data sync',
        icon: Icons.update_rounded,
        status: _lastSuccessfulUpdate != null ? 'active' : 'warning',
      ),
      SizedBox(height: context.responsiveFont(12.0)),
    ];

    final position = _locationService.currentPosition;
    if (_isLocationLoading) {
      widgets.add(StatusCard(
        title: 'Location',
        value: 'Loading...',
        subtitle: 'Retrieving high-precision GPS',
        icon: Icons.gps_fixed_rounded,
        status: 'warning',
      ));
    } else if (position == null) {
      widgets.add(StatusCard(
        title: 'Location',
        value: 'Unavailable',
        subtitle: 'Tap to refresh',
        icon: Icons.location_off,
        status: 'error',
      ));
    } else {
      widgets.add(StatusCard(
        title: 'Location',
        value: 'Lat: ${position.latitude.toStringAsFixed(4)}  Lng: ${position.longitude.toStringAsFixed(4)}',
        subtitle: 'Acc: ±${position.accuracy.toStringAsFixed(1)}m',
        icon: Icons.gps_fixed_rounded,
        status: 'active',
      ));
    }

    widgets.add(SizedBox(height: context.responsiveFont(12.0)));
    widgets.add(StatusCard(
      title: 'Session',
      value: _sessionActive ? 'Active' : 'Lost',
      subtitle: 'Last Check: ${_lastSessionCheck != null ? _lastSessionCheck!.toString().substring(11, 19) : 'Never'}',
      icon: _sessionActive ? Icons.verified_user_rounded : Icons.error_rounded,
      status: _sessionActive ? 'active' : 'error',
    ));

    return widgets;
  }

  Widget _buildSessionStatusIndicator() {
    Color color;
    String tooltip;
    
    if (!_isOnline) {
      color = Colors.orange;
      tooltip = 'Offline Mode - App will sync when connection is restored';
    } else if (_sessionActive) {
      color = Colors.green;
      tooltip = 'Session Active - Online';
    } else {
      color = Colors.red;
      tooltip = 'Session Lost';
    }

    return Tooltip(
      message: tooltip,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: context.responsiveFont(8.0),
          vertical: context.responsiveFont(4.0),
        ),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(context.responsiveFont(12.0)),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Container(
          width: context.responsiveFont(10.0),
          height: context.responsiveFont(10.0),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.3)),
          ),
        ),
      ),
    );
  }

  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await _notifications.initialize(initializationSettings);
    
    const AndroidNotificationChannel locationAlarmChannel = AndroidNotificationChannel(
      'location_alarm_channel',
      'Location Status',
      description: 'Alarm for when location service is disabled',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
    );
    
    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(locationAlarmChannel);
  }

  void _listenForConnectivityChanges() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> result) {
      final wasOnline = _isOnline;
      _isOnline = !result.contains(ConnectivityResult.none) && result.isNotEmpty;

      if (mounted) {
        setState(() {});
      }

      if (!_isOnline && wasOnline) {
        _showConnectionLostNotification();
        _pushConsole('Network changed: OFFLINE');
      } else if (_isOnline && !wasOnline) {
        _handleConnectionRestored();
        _pushConsole('Network changed: ONLINE');
      }
    });
  }

  Future<void> _handleConnectionRestored() async {
    print('Dashboard: Connection restored, attempting to reconnect...');
    await _notifications.cancel(0);
    _showConnectionRestoredNotification();
    _startAdaptivePeriodicUpdates();
    await _sendLocationUpdateSafely();
    print('Dashboard: Automatic reconnection completed');
  }

  Future<void> _showConnectionLostNotification() async {
    const String title = 'Network Connection Lost';
    const String body = 'Device is offline. Location tracking continues but data cannot be sent. Will auto-reconnect when network is available.';
    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'connectivity_channel',
      'Connectivity',
      channelDescription: 'Channel for connectivity notifications',
      importance: Importance.max,
      priority: Priority.high,
      sound: RawResourceAndroidNotificationSound('alarm_sound'),
      enableVibration: true,
      visibility: NotificationVisibility.public,
      ongoing: true,
      fullScreenIntent: true,
      styleInformation: const BigTextStyleInformation(
        body,
        contentTitle: title,
      ),
    );
    final NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    await _notifications.show(
      0,
      title,
      body,
      platformChannelSpecifics,
    );
  }

  Future<void> _showConnectionRestoredNotification() async {
    const String title = 'Connection Restored';
    const String body = 'Network connection restored. Location tracking resumed successfully.';
    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'connectivity_channel',
      'Connectivity',
      channelDescription: 'Channel for connectivity notifications',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: false,
      visibility: NotificationVisibility.public,
      autoCancel: true,
      styleInformation: const BigTextStyleInformation(
        body,
        contentTitle: title,
      ),
    );
    final NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    await _notifications.show(
      1,
      title,
      body,
      platformChannelSpecifics,
    );

    Timer(const Duration(seconds: 3), () {
      _notifications.cancel(1);
    });
  }

  Future<void> _initializeServices() async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      _seedConsole();
      await Future.wait([
        _initializeTimerCoordinator(),
        _initializeNetworkService(),
        _initializeDeviceService(),
        _initializeLocationTracking(),
        _initializeWatchdog(),
        _initializePermanentWakeLock(),
      ], eagerError: false);

      _startAdaptivePeriodicUpdates();

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AutoSizeText(
              'Initialization error: ${e.toString()}',
              maxFontSize: getResponsiveFont(14.0),
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _initializeTimerCoordinator() async {
    await _timerCoordinator.initialize();
    print('Dashboard: TimerCoordinator initialized');
  }

  Future<void> _initializeNetworkService() async {
    await _networkService.initialize();
    print('Dashboard: Network service initialized');
  }

  Future<void> _initializeDeviceService() async {
    await _deviceService.initialize();
    if (mounted) {
      setState(() {});
      if (_deviceService.isOnline) {
        print('Dashboard: Device is online, sending immediate status update to webapp');
        _sendLocationUpdateSafely();
      }
    }
  }

  Future<void> _initializeWatchdog() async {
    try {
      await _watchdogService.initialize(
        onAppDead: () {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('App monitoring was interrupted. Restarting services...'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 5),
              ),
            );
            _initializeServices();
          }
        },
      );
      _watchdogService.startWatchdog();
    } catch (e) {
      print('Dashboard: Error initializing watchdog: $e');
    }
  }

  Future<void> _initializePermanentWakeLock() async {
    try {
      await _wakeLockService.initialize();
      _wakeLockService.setBackgroundMode(false); // Set to foreground mode
      await _wakeLockService.forceEnableForCriticalOperation();
      if (mounted) {
        setState(() {});
      }
      print('Dashboard: Wake lock initialized and enabled for foreground');
    } catch (e) {
      print('Dashboard: Wake lock initialization failed: $e');
      Timer(const Duration(seconds: 5), () {
        _initializePermanentWakeLock();
      });
    }
  }

  Future<void> _initializeLocationTracking() async {
    if (!mounted) return;

    setState(() => _isLocationLoading = true);

    try {
      final hasAccess = await _locationService.checkLocationRequirements();
      if (hasAccess) {
        await _wakeLockService.forceEnableForCriticalOperation();

        final position = await _locationService.getCurrentPosition(
          accuracy: LocationAccuracy.bestForNavigation,
          timeout: const Duration(seconds: 15),
        );

        if (position != null && mounted) {
          setState(() => _isLocationLoading = false);
        }

        _locationService.startLocationTracking(
          (position) {
            if (mounted) {
              setState(() => _isLocationLoading = false);
            }
          },
        );

        Timer(const Duration(seconds: 20), () {
          if (mounted && _isLocationLoading) {
            setState(() => _isLocationLoading = false);
          }
        });

      } else {
        if (mounted) {
          setState(() => _isLocationLoading = false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLocationLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AutoSizeText(
              'Failed to initialize high-precision location: $e',
              maxFontSize: getResponsiveFont(14.0),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _startAdaptivePeriodicUpdates() {
    _registerTimerCallbacks();
    _scheduleNextAdaptiveUpdate();
    _sendLocationUpdateSafely();
  }

  void _registerTimerCallbacks() {
    if (_heartbeatCallback != null) {
      _timerCoordinator.removeHeartbeatCallback(_heartbeatCallback!);
    }
    _heartbeatCallback = () {
      _watchdogService.ping();
      _maintainWakeLock();
      if (mounted) {
        setState(() {});
      }
      print('Dashboard: Heartbeat sent to watchdog via TimerCoordinator');
    };
    _timerCoordinator.onHeartbeat(_heartbeatCallback!);

    if (_locationMonitoringCallback != null) {
      _timerCoordinator.removeLocationMonitoringCallback(_locationMonitoringCallback!);
    }
    _locationMonitoringCallback = () {
      _checkLocationStatusAndNotify();
      _sendLocationUpdateSafely(); // Send location update to server and console
    };
    _timerCoordinator.onLocationMonitoring(_locationMonitoringCallback!);
  }

  void _scheduleNextAdaptiveUpdate() {
    print('Dashboard: Adaptive location updates now handled by TimerCoordinator');
  }

  Future<void> _maintainWakeLock() async {
    final isEnabled = await _wakeLockService.checkWakeLockStatus();
    if (!isEnabled) {
      await _wakeLockService.forceEnableForCriticalOperation();
    }
  }

  Future<void> _sendLocationUpdateSafely() async {
    if (!_isOnline) {
      print('Dashboard: Offline, skipping location update');
      return;
    }

    try {
      await _sendLocationUpdate();
    } catch (e) {
      print('Dashboard: Error sending location update: $e');
    }
  }

  Future<void> _sendLocationUpdate() async {
    final position = _locationService.currentPosition;
    if (position == null) return;

    try {
      _pushConsole('Sending location update...');
      final result = await ApiService.updateLocation(
        token: widget.token,
        deploymentCode: widget.deploymentCode,
        position: position,
        batteryLevel: _deviceService.batteryLevel,
        signal: _deviceService.signalStatus,
        includeSessionCheck: true,
        forceUpdate: false,
      );

      if (result.success) {
        if (result.message == 'Skipped - no significant change') {
          final movementStatus = _getMovementStatus(position);
          final nextInterval = ApiService.getCurrentInterval();
          
          print('Dashboard: Location update skipped - no significant change');
          _pushConsole('⏭️ Skipped - no significant change • Next: ${nextInterval.inSeconds}s ($movementStatus)');
        } else {
          _locationUpdatesSent++;
          _lastSuccessfulUpdate = DateTime.now();
          
          final speed = position.speed * 3.6;
          final movementStatus = _getMovementStatus(position);
          final nextInterval = ApiService.getCurrentInterval();
          
          print('Dashboard: Location update #$_locationUpdatesSent sent successfully');
          _pushConsole('Location sent (${speed.toInt()} km/h) • Next: ${nextInterval.inSeconds}s ($movementStatus) • Total: $_locationUpdatesSent');
        }
      } else {
        print('Dashboard: Location update failed: ${result.message}');
        _pushConsole('Location failed: ${result.message}');

        if (result.message.contains('Session expired') || result.message.contains('logged in')) {
          _handleSessionExpired();
        }
      }
    } catch (e) {
      print('Dashboard: Error sending location update: $e');
      _pushConsole('Location error: $e');
    }
  }

  void _handleSessionExpired() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: AutoSizeText(
          'Session Expired',
          maxFontSize: getResponsiveFont(18.0),
        ),
        content: AutoSizeText(
          'Your session has expired or you have been logged out from another device. Please login again.',
          maxFontSize: getResponsiveFont(14.0),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _performLogout();
            },
            child: AutoSizeText(
              'OK',
              maxFontSize: getResponsiveFont(14.0),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getBatteryIcon() {
    final level = _deviceService.batteryLevel;
    final state = _deviceService.batteryState;
    if (state.toString().contains('charging')) return Icons.battery_charging_full_rounded;
    if (level > 80) return Icons.battery_full_rounded;
    if (level > 60) return Icons.battery_6_bar_rounded;
    if (level > 40) return Icons.battery_4_bar_rounded;
    if (level > 20) return Icons.battery_2_bar_rounded;
    return Icons.battery_1_bar_rounded;
  }

  Future<void> _refreshLocation() async {
    setState(() => _isLocationLoading = true);
    try {
      final position = await _locationService.getCurrentPosition();
      if (position != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AutoSizeText(
              'Location refreshed (±${position.accuracy.toStringAsFixed(1)}m)',
              maxFontSize: getResponsiveFont(14.0),
            ),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AutoSizeText(
              'Failed to get location.',
              maxFontSize: getResponsiveFont(14.0),
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AutoSizeText(
              'Failed to refresh location: $e',
              maxFontSize: getResponsiveFont(14.0),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLocationLoading = false);
      }
    }
  }

  Future<void> _refreshDashboard() async {
    print('Dashboard: Starting pull-to-refresh...');

    try {
      await Future.wait([
        _deviceService.refreshDeviceInfo(),
        _refreshLocation(),
        _sendLocationUpdateSafely(),
      ], eagerError: false);

      if (mounted) {
        setState(() {});
      }

      print('Dashboard: Pull-to-refresh completed successfully');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AutoSizeText(
              'Dashboard refreshed successfully',
              maxFontSize: getResponsiveFont(14.0),
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Dashboard: Error during pull-to-refresh: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AutoSizeText(
              'Refresh failed: ${e.toString()}',
              maxFontSize: getResponsiveFont(14.0),
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _checkForUpdates() async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 12),
              Text('Checking for updates...'),
            ],
          ),
          backgroundColor: Colors.blue[800],
          duration: Duration(seconds: 2),
        ),
      );

      final updateService = UpdateService();
      final result = await updateService.checkForUpdates();

      ScaffoldMessenger.of(context).clearSnackBars();

      if (result.hasUpdate && result.updateInfo != null) {
        showDialog(
          context: context,
          builder: (context) => UpdateDialog(
            updateInfo: result.updateInfo!,
            currentVersion: result.currentVersion,
          ),
        );
      } else if (result.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Update check failed: ${result.error}',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red[800],
            duration: Duration(seconds: 5),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text(
                  'You are using the latest version.',
                  style: TextStyle(fontSize: 14),
                ),
              ],
            ),
            backgroundColor: Colors.green[800],
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Update check failed: $e',
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.red[800],
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  String _getMovementStatus(Position position) {
    final speed = position.speed;
    final kmh = speed * 3.6;
    
    if (speed >= 2.78) return 'FAST (${kmh.toInt()} km/h)';
    if (speed >= 2.0) return 'MOVING (${kmh.toInt()} km/h)';
    return 'STATIONARY (${kmh.toInt()} km/h)';
  }

  List<String> _buildRealtimeConsoleLines() {
    if (_consoleLines.isEmpty) {
      _seedConsole();
    }
    return _consoleLines;
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Stack(
          children: [
            Scaffold(
              appBar: AppBar(
                title: AutoSizeText(
                  'Project Nexus',
                  maxFontSize: getResponsiveFont(20.0),
                ),
                actions: [
                  _buildSessionStatusIndicator(),
                  SizedBox(width: context.responsiveFont(8.0)),
                  IconButton(
                    icon: Icon(
                      Icons.system_update_rounded,
                      size: ResponsiveUIService.getResponsiveIconSize(
                        context: context,
                        baseIconSize: 24.0,
                      ),
                    ),
                    onPressed: _checkForUpdates,
                    tooltip: 'Check for Updates',
                  ),
                  SizedBox(width: context.responsiveFont(8.0)),
                  IconButton(
                    icon: Icon(
                      themeProvider.themeMode == ThemeMode.dark
                          ? Icons.light_mode_rounded
                          : Icons.dark_mode_rounded,
                      size: ResponsiveUIService.getResponsiveIconSize(
                        context: context,
                        baseIconSize: 24.0,
                      ),
                    ),
                    onPressed: () {
                      themeProvider.toggleTheme();
                    },
                    tooltip: 'Toggle Theme',
                  ),
                ],
              ),
              body: _isLoading
                  ? Center(
                      child: SizedBox(
                        width: context.responsiveFont(48.0),
                        height: context.responsiveFont(48.0),
                        child: CircularProgressIndicator(
                          strokeWidth: context.responsiveFont(3.0),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _refreshDashboard,
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          // Console terminal (HeroHeader) - now scrollable
                          HeroHeader(
                            title: 'Device Monitor',
                            subtitle: 'Deployment: ${widget.deploymentCode}',
                            leadingIcon: Icons.shield_rounded,
                            consoleLines: _buildRealtimeConsoleLines(),
                          ),
                          SizedBox(height: context.responsiveFont(8.0)),
                          // Device information section
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: context.responsiveFont(16.0),
                              vertical: context.responsiveFont(8.0),
                            ),
                            child: Column(
                              children: _buildStatusCards(context),
                            ),
                          ),
                          // Logout button - now part of scrollable content
                          Padding(
                            padding: EdgeInsets.all(context.responsiveFont(16.0)),
                            child: SizedBox(
                              width: double.infinity,
                              height: ResponsiveUIService.getResponsiveButtonHeight(
                                context: context,
                                baseHeight: 48.0,
                              ),
                              child: ElevatedButton.icon(
                                onPressed: _isLoggingOut ? null : _performLogout,
                                icon: _isLoggingOut 
                                  ? SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    )
                                  : Icon(Icons.logout),
                                label: AutoSizeText(
                                  _isLoggingOut ? 'Logging Out...' : 'Logout',
                                  maxFontSize: getResponsiveFont(16.0),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _isLoggingOut ? Colors.grey : Colors.red,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          // Add some bottom padding for better scrolling experience
                          SizedBox(height: context.responsiveFont(20.0)),
                        ],
                      ),
                    ),
            ),
            if (!_isLocationServiceEnabled)
              Container(
                color: Colors.black.withOpacity(0.85),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.location_off,
                        color: Colors.white,
                        size: 80,
                      ),
                      SizedBox(height: 20),
                      Text(
                        'Location is required to continue',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}