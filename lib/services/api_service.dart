import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../utils/constants.dart';
import 'error_handling_service.dart';

class ApiService {
  // ===== BASIC API METHODS =====
  
  static Future<ApiResponse> login(String token, String deploymentCode) async {
    // FIXED: Validate token before using in HTTP headers
    if (!_isValidToken(token)) {
      return ApiResponse.error('Invalid token format - contains illegal characters for HTTP headers');
    }

    final url = Uri.parse('${AppConstants.baseUrl}setUnit');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final body = json.encode({
      'deploymentCode': deploymentCode,
      'action': 'login',
      'timestamp': DateTime.now().toIso8601String(),
      'deviceInfo': await _getDeviceInfo(),
    });

    try {
      final response = await http.post(url, headers: headers, body: body);
      return ApiResponse.fromResponse(response);
    } catch (e) {
      return ApiResponse.error(ErrorHandlingService.getUserFriendlyError(e));
    }
  }

  static Future<ApiResponse> logout(String token, String deploymentCode, {bool forceOffline = false}) async {
    // FIXED: Validate token before using in HTTP headers
    if (!_isValidToken(token)) {
      return ApiResponse.error('Invalid token format - contains illegal characters for HTTP headers');
    }

    final url = Uri.parse('${AppConstants.baseUrl}setUnit');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final body = json.encode({
      'deploymentCode': deploymentCode,
      'action': 'logout',
      'timestamp': DateTime.now().toIso8601String(),
      'forceOffline': forceOffline, // ENHANCED: Force server to immediately mark as offline
      'deviceInfo': await _getDeviceInfo(),
    });

    try {
      final response = await http.post(url, headers: headers, body: body);
      return ApiResponse.fromResponse(response);
    } catch (e) {
      return ApiResponse.error(ErrorHandlingService.getUserFriendlyError(e));
    }
  }

  static Future<ApiResponse> checkStatus(String token, String deploymentCode) async {
    // FIXED: Validate token before using in HTTP headers
    if (!_isValidToken(token)) {
      return ApiResponse.error('Invalid token format - contains illegal characters for HTTP headers');
    }

    final url = Uri.parse('${AppConstants.baseUrl}checkStatus');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final body = json.encode({
      'deploymentCode': deploymentCode,
      'timestamp': DateTime.now().toIso8601String(),
    });

    try {
      final response = await http.post(
        url, 
        headers: headers, 
        body: body,
      ).timeout(const Duration(seconds: 8));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return ApiResponse(
          success: true,
          message: 'Status checked successfully',
          data: data,
        );
      } else if (response.statusCode == 401) {
        return ApiResponse(
          success: false,
          message: 'Authentication failed - token may be invalid',
          data: {'isLoggedIn': false},
        );
      } else {
        return ApiResponse(
          success: false,
          message: 'Server error checking status',
          data: {'isLoggedIn': false},
        );
      }
    } on TimeoutException {
      return ApiResponse.error('Session check timed out');
    } catch (e) {
      return ApiResponse.error('Network error checking status: ${e.toString()}');
    }
  }

  // ===== UNIFIED LOCATION UPDATE SYSTEM =====
  
  // UNIFIED: Single method for all location updates with session check and adaptive intervals
  static Future<ApiResponse> updateLocation({
    required String token,
    required String deploymentCode,
    required Position position,
    int? batteryLevel,
    String? signal,
    bool forceUpdate = false,
    bool isAggressiveSync = false,
    bool includeSessionCheck = true,
  }) async {
    try {
      // AUTO-FETCH missing data
      final actualBatteryLevel = batteryLevel ?? await _getBatteryLevel();
      final actualSignal = signal ?? await getSignalStatus();
      
      // SESSION CHECK: Verify session before sending location
      if (includeSessionCheck) {
        final sessionResult = await _verifySessionBeforeUpdate(token, deploymentCode);
        if (!sessionResult.success) {
          return sessionResult; // Return session error immediately
        }
      }
      
      // SMART FILTERING: Skip if no significant change (unless forced)
      if (!forceUpdate && !isAggressiveSync && _shouldSkipUpdate(position, actualBatteryLevel, actualSignal)) {
        print('⏭️ Skipped - no significant change');
        return ApiResponse(success: true, message: 'Skipped - no significant change');
      }
      
      // FIXED: Validate token before using in HTTP headers
      if (!_isValidToken(token)) {
        return ApiResponse.error('Invalid token format - contains illegal characters for HTTP headers');
      }

      // BUILD OPTIMIZED PAYLOAD
      final payload = _buildOptimizedPayload(
        deploymentCode: deploymentCode,
        position: position,
        batteryLevel: actualBatteryLevel,
        signal: actualSignal,
        isAggressiveSync: isAggressiveSync,
      );

      // SEND REQUEST
      final url = Uri.parse('${AppConstants.baseUrl}updateLocation');
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
        'X-Update-Type': isAggressiveSync ? 'aggressive' : 'adaptive',
        'X-Movement-Type': _getMovementType(position),
      };
      
      final response = await http.post(
        url,
        headers: headers,
        body: json.encode(payload),
      ).timeout(Duration(seconds: isAggressiveSync ? 15 : 10));
      
      // HANDLE RESPONSE
      if (response.statusCode == 200) {
        // Update cache on successful send
        _lastSentPosition = position;
        _lastSentBattery = actualBatteryLevel;
        _lastSentSignal = actualSignal;
        _lastUpdateTime = DateTime.now();
        
        // Calculate next adaptive interval
        _currentInterval = _calculateOptimalInterval(position);
        
        final speed = position.speed * 3.6; // km/h
        final movementStatus = _getMovementStatus(position);
        print('✅ Location sent (${speed.toInt()} km/h) - Next: ${_currentInterval.inSeconds}s ($movementStatus)');
        
        return ApiResponse.fromResponse(response);
      } else if (response.statusCode == 401) {
        print('❌ Location update failed: Authentication expired (401)');
        return ApiResponse(
          success: false,
          message: 'Authentication failed - token expired',
          data: null,
        );
      } else if (response.statusCode == 403) {
        return ApiResponse.error('Session expired. Please login again.');
      } else {
        return ApiResponse.fromResponse(response);
      }
      
    } catch (e) {
      print('❌ Location update failed: $e');
      return ApiResponse.error('Network error: ${e.toString()}');
    }
  }
  
  // SESSION VERIFICATION: Check session before location update
  static Future<ApiResponse> _verifySessionBeforeUpdate(String token, String deploymentCode) async {
    try {
      final sessionResult = await checkStatus(token, deploymentCode);
      if (!sessionResult.success) {
        print('❌ Session verification failed before location update');
        return ApiResponse(
          success: false,
          message: 'Session verification failed - ${sessionResult.message}',
          data: null,
        );
      }
      return ApiResponse(success: true, message: 'Session verified');
    } catch (e) {
      print('❌ Session verification error: $e');
      return ApiResponse(
        success: false,
        message: 'Session verification error: ${e.toString()}',
        data: null,
      );
    }
  }
  
  // BUILD OPTIMIZED PAYLOAD: Single method for all payload types
  static Map<String, dynamic> _buildOptimizedPayload({
    required String deploymentCode,
    required Position position,
    required int batteryLevel,
    required String signal,
    bool isAggressiveSync = false,
  }) {
    final data = <String, dynamic>{
      'deploymentCode': deploymentCode,
      'location': {
        'latitude': _roundCoordinate(position.latitude),
        'longitude': _roundCoordinate(position.longitude),
        'accuracy': position.accuracy.round(),
        'altitude': position.altitude.round(),
        'speed': _roundSpeed(position.speed),
        'heading': position.heading.round(),
      },
      'batteryStatus': batteryLevel,
      'signal': signal,
      'timestamp': DateTime.now().toIso8601String(),
      'movementType': _getMovementType(position),
      'updateType': isAggressiveSync ? 'aggressive' : 'adaptive',
    };
    
    // Add device info for aggressive sync
    if (isAggressiveSync) {
      data['deviceInfo'] = 'Mobile Device - ${DateTime.now().toIso8601String()}';
    }
    
    return data;
  }

  // ===== ADAPTIVE LOCATION SYSTEM =====
  
  // Movement-based cache to avoid duplicate sends
  static Position? _lastSentPosition;
  static int _lastSentBattery = -1;
  static String _lastSentSignal = '';
  static DateTime? _lastUpdateTime;
  static Timer? _adaptiveTimer;
  static Duration _currentInterval = Duration(seconds: 30);
  
  // Movement thresholds for adaptive updates
  static const double stationarySpeed = 1.0; // m/s (~3.6 km/h)
  static const double movingSpeed = 2.0; // m/s (~7.2 km/h)
  static const double fastMovingSpeed = 2.78; // m/s (~10.0 km/h)
  static const double movementDistance = 10.0; // meters
  
  // Use AppConstants for all intervals - no local duplicates

  // Check if update should be skipped to save data
  static bool _shouldSkipUpdate(Position position, int batteryLevel, String signal) {
    if (_lastSentPosition == null || _lastUpdateTime == null) return false;
    
    // Calculate distance moved
    final distance = Geolocator.distanceBetween(
      _lastSentPosition!.latitude,
      _lastSentPosition!.longitude,
      position.latitude,
      position.longitude,
    );
    
    // Check time since last update
    final timeSinceUpdate = DateTime.now().difference(_lastUpdateTime!);
    
    // NEVER skip if moving significantly
    if (distance >= movementDistance) return false;
    
    // NEVER skip if speed is high (moving fast)
    if (position.speed >= movingSpeed) return false;
    
    // Skip if stationary and other data unchanged and recent update
    if (distance < 5 && // Less than 5m movement
        batteryLevel == _lastSentBattery &&
        signal == _lastSentSignal &&
        timeSinceUpdate < Duration(minutes: 1)) {
      return true;
    }
    
    return false;
  }
  
  
  // Round coordinates to reduce data size while maintaining accuracy
  static double _roundCoordinate(double coordinate) {
    return double.parse(coordinate.toStringAsFixed(5)); // ~1 meter precision
  }
  
  // Round speed to reduce data size
  static double _roundSpeed(double speed) {
    return double.parse(speed.toStringAsFixed(1)); // 0.1 m/s precision
  }
  
  // Get movement type for server context
  static String _getMovementType(Position position) {
    final speed = position.speed;
    
    if (speed >= fastMovingSpeed) return 'fast';
    if (speed >= movingSpeed) return 'moving';
    return 'stationary';
  }

  // ===== ADAPTIVE UPDATE SYSTEM =====
  
  // Start adaptive location updates with movement-based intervals
  static void startAdaptiveLocationUpdates({
    required String token,
    required String deploymentCode,
    required Function() getCurrentPosition,
    required Function() getBatteryLevel,
    required Function() getSignalStatus,
    Function(ApiResponse)? onLocationUpdate,
  }) {
    print('🚀 Starting MOVEMENT-BASED adaptive updates...');
    
    _adaptiveTimer?.cancel();
    _scheduleNextUpdate(
      token: token,
      deploymentCode: deploymentCode,
      getCurrentPosition: getCurrentPosition,
      getBatteryLevel: getBatteryLevel,
      getSignalStatus: getSignalStatus,
      onLocationUpdate: onLocationUpdate,
    );
  }
  
  static void _scheduleNextUpdate({
    required String token,
    required String deploymentCode,
    required Function() getCurrentPosition,
    required Function() getBatteryLevel,
    required Function() getSignalStatus,
    Function(ApiResponse)? onLocationUpdate,
  }) {
    _adaptiveTimer = Timer(_currentInterval, () async {
      await _processAdaptiveUpdate(
        token: token,
        deploymentCode: deploymentCode,
        getCurrentPosition: getCurrentPosition,
        getBatteryLevel: getBatteryLevel,
        getSignalStatus: getSignalStatus,
        onLocationUpdate: onLocationUpdate,
      );
      
      // Schedule next update with potentially new interval
      _scheduleNextUpdate(
        token: token,
        deploymentCode: deploymentCode,
        getCurrentPosition: getCurrentPosition,
        getBatteryLevel: getBatteryLevel,
        getSignalStatus: getSignalStatus,
        onLocationUpdate: onLocationUpdate,
      );
    });
  }
  
  static Future<void> _processAdaptiveUpdate({
    required String token,
    required String deploymentCode,
    required Function() getCurrentPosition,
    required Function() getBatteryLevel,
    required Function() getSignalStatus,
    Function(ApiResponse)? onLocationUpdate,
  }) async {
    try {
      final position = await getCurrentPosition() as Position?;
      if (position == null) {
        print('📍 No position available, keeping current interval');
        return;
      }
      
      final batteryLevel = await getBatteryLevel() as int;
      final signalStatus = await getSignalStatus() as String;
      
      // Use unified updateLocation method with session check and adaptive intervals
      final updateResult = await updateLocation(
        token: token,
        deploymentCode: deploymentCode,
        position: position,
        batteryLevel: batteryLevel,
        signal: signalStatus,
        includeSessionCheck: true, // Include session verification
        forceUpdate: false, // Use smart filtering
      );
      
      if (updateResult.success) {
        // Calculate next interval based on current movement
        _currentInterval = _calculateOptimalInterval(position);
        print('📊 Next update in: ${_currentInterval.inSeconds}s (${_getMovementStatus(position)})');
      } else {
        print('❌ Adaptive update failed: ${updateResult.message}');
      }
      
      // Notify dashboard of location update result
      if (onLocationUpdate != null) {
        onLocationUpdate(updateResult);
      }
      
    } catch (e) {
      print('❌ Adaptive update failed: $e');
    }
  }
  
  // Calculate optimal interval based on movement
  static Duration _calculateOptimalInterval(Position position) {
    final speed = position.speed; // m/s
    
    // FAST MOVEMENT: 5 seconds (when device is moving fast)
    if (speed >= fastMovingSpeed) {
      return AppConstants.fastMovingInterval;
    }
    
    // NORMAL MOVEMENT: 15 seconds
    if (speed >= movingSpeed) {
      return AppConstants.movingInterval;
    }
    
    // STATIONARY: 30 seconds
    return AppConstants.stationaryInterval;
  }
  
  // Get movement status for logging
  static String _getMovementStatus(Position position) {
    final speed = position.speed;
    final kmh = speed * 3.6;
    
    if (speed >= fastMovingSpeed) return 'FAST (${kmh.toInt()} km/h)';
    if (speed >= movingSpeed) return 'MOVING (${kmh.toInt()} km/h)';
    return 'STATIONARY (${kmh.toInt()} km/h)';
  }

  // Stop adaptive updates
  static void stopAdaptiveUpdates() {
    _adaptiveTimer?.cancel();
    _adaptiveTimer = null;
    print('🛑 Adaptive updates stopped');
  }
  
  // Get current update interval for UI display
  static Duration getCurrentInterval() => _currentInterval;
  
  // Check if adaptive updates are currently running
  static bool isAdaptiveUpdatesRunning() => _adaptiveTimer?.isActive ?? false;
  
  // Get movement statistics for debugging
  static Map<String, dynamic> getMovementStats(Position? position) {
    if (position == null) return {'status': 'No position'};
    
    final speed = position.speed;
    final kmh = speed * 3.6;
    final movementType = _getMovementType(position);
    final nextInterval = _calculateOptimalInterval(position);
    
    return {
      'speed_ms': speed.toStringAsFixed(1),
      'speed_kmh': kmh.toStringAsFixed(1),
      'movement_type': movementType,
      'current_interval': '${_currentInterval.inSeconds}s',
      'next_interval': '${nextInterval.inSeconds}s',
      'last_update': _lastUpdateTime?.toString().substring(11, 19) ?? 'Never',
    };
  }




  // ===== SIGNAL STATUS DETECTION =====
  
  // Get signal status based on API specification
  static Future<String> getSignalStatus() async {
    try {
      // Test actual API performance to determine real signal quality
      final connectivity = Connectivity();
      final results = await connectivity.checkConnectivity();
      
      // If no connectivity, return poor
      if (results.contains(ConnectivityResult.none)) {
        return SignalStatus.poor;
      }
      
      // Test actual network performance with API endpoint
      final performanceScore = await _testNetworkPerformance();
      
      // Determine signal status based on actual performance and API specification
      // API expects: "strong", "weak", "poor", etc.
      if (performanceScore >= 60) {
        return SignalStatus.strong;  // API compatible: combines strong and moderate
      } else if (performanceScore >= 30) {
        return SignalStatus.weak;    // API compatible
      } else {
        return SignalStatus.poor;    // API compatible
      }
    } catch (e) {
      print('ApiService: Error getting signal status: $e');
      return SignalStatus.poor;
    }
  }

  // Test actual network performance with API
  static Future<int> _testNetworkPerformance() async {
    try {
      final stopwatch = Stopwatch()..start();
      
      // Make a lightweight request to test API response time
      final url = Uri.parse('${AppConstants.baseUrl}checkStatus');
      final headers = {'Content-Type': 'application/json'};
      
      final response = await http.post(
        url,
        headers: headers,
        body: '{"test": "ping"}',
      ).timeout(const Duration(seconds: 3));
      
      stopwatch.stop();
      final responseTime = stopwatch.elapsedMilliseconds;
      
      // Calculate performance score based on response time and status
      int score = 0;
      
      // Response time scoring (0-50 points)
      if (responseTime <= 500) {
        score += 50; // Excellent response time
      } else if (responseTime <= 1000) {
        score += 40; // Good response time
      } else if (responseTime <= 2000) {
        score += 25; // Fair response time
      } else {
        score += 10; // Poor response time
      }
      
      // HTTP status scoring (0-50 points)
      if (response.statusCode >= 200 && response.statusCode < 300) {
        score += 50; // Success response
      } else if (response.statusCode >= 400 && response.statusCode < 500) {
        score += 25; // Client error but server reachable
      } else {
        score += 10; // Server error
      }
      
      print('ApiService: Network performance test - Response time: ${responseTime}ms, Status: ${response.statusCode}, Score: $score');
      
      return score;
    } catch (e) {
      print('ApiService: Network performance test failed: $e');
      return 0; // No connectivity or severe issues
    }
  }

  // ===== HELPER METHODS =====

  // FIXED: Validate token for HTTP header compatibility
  static bool _isValidToken(String token) {
    if (token.isEmpty) return false;

    try {
      // Check if token contains only valid ASCII characters for HTTP headers
      for (int i = 0; i < token.length; i++) {
        int charCode = token.codeUnitAt(i);
        // Allow printable ASCII characters (32-126) except DEL (127)
        if (charCode < 32 || charCode > 126) {
          print('ApiService: Invalid character in token at position $i: ${charCode}');
          return false;
        }
      }

      // Token should be reasonable length
      if (token.length < 10) {
        print('ApiService: Token too short: ${token.length} characters');
        return false;
      }

      return true;
    } catch (e) {
      print('ApiService: Error validating token: $e');
      return false;
    }
  }

  // Helper methods for device information
  static Future<String> _getDeviceInfo() async {
    try {
      return 'Mobile Device - ${DateTime.now().toIso8601String()}';
    } catch (e) {
      return 'Unknown Device';
    }
  }

  static Future<int> _getBatteryLevel() async {
    try {
      final battery = Battery();
      return await battery.batteryLevel;
    } catch (e) {
      return 100; // Default value
    }
  }
}

// Updated API Response class
class ApiResponse {
  final bool success;
  final String message;
  final Map<String, dynamic>? data;

  ApiResponse({
    required this.success,
    required this.message,
    this.data,
  });

  factory ApiResponse.fromResponse(http.Response response) {
    try {
      final body = json.decode(response.body);
      return ApiResponse(
        success: response.statusCode == 200 && (body['success'] ?? false),
        message: body['message'] ?? 'Request completed',
        data: body,
      );
    } catch (e) {
      return ApiResponse(
        success: false,
        message: 'Invalid response format from server',
      );
    }
  }

  factory ApiResponse.error(String message) {
    return ApiResponse(success: false, message: message);
  }
}