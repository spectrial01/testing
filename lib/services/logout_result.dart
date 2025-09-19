/// Result models and enums for logout operations
/// 
/// This file contains all the data structures used to represent
/// the results and progress of logout operations.

/// Represents the result of a logout operation
class LogoutResult {
  /// Whether the logout was successful
  bool success;
  
  /// Duration of the logout operation
  Duration duration;
  
  /// Human-readable message about the result
  String message;
  
  /// Error message if logout failed
  String? error;
  
  /// Stack trace if logout failed
  String? stackTrace;
  
  /// List of warnings encountered during logout
  List<String> warnings;
  
  /// List of errors encountered during logout
  List<String> errors;
  
  /// Whether this was an emergency logout
  bool isEmergency;
  
  /// Timestamp when logout was initiated
  DateTime timestamp;
  
  /// Additional data about the logout process
  Map<String, dynamic> metadata;

  LogoutResult({
    this.success = false,
    Duration? duration,
    this.message = '',
    this.error,
    this.stackTrace,
    List<String>? warnings,
    List<String>? errors,
    this.isEmergency = false,
    DateTime? timestamp,
    Map<String, dynamic>? metadata,
  }) : duration = duration ?? Duration.zero,
       warnings = warnings ?? [],
       errors = errors ?? [],
       timestamp = timestamp ?? DateTime.now(),
       metadata = metadata ?? {};

  /// Create a successful logout result
  factory LogoutResult.success({
    required String message,
    Duration? duration,
    List<String>? warnings,
    Map<String, dynamic>? metadata,
  }) {
    return LogoutResult(
      success: true,
      message: message,
      duration: duration,
      warnings: warnings,
      metadata: metadata,
    );
  }

  /// Create a failed logout result
  factory LogoutResult.failure({
    required String message,
    required String error,
    String? stackTrace,
    Duration? duration,
    List<String>? warnings,
    List<String>? errors,
    Map<String, dynamic>? metadata,
  }) {
    return LogoutResult(
      success: false,
      message: message,
      error: error,
      stackTrace: stackTrace,
      duration: duration,
      warnings: warnings,
      errors: errors,
      metadata: metadata,
    );
  }

  /// Create an emergency logout result
  factory LogoutResult.emergency({
    required String message,
    Duration? duration,
    List<String>? warnings,
    Map<String, dynamic>? metadata,
  }) {
    return LogoutResult(
      success: true,
      message: message,
      duration: duration,
      warnings: warnings,
      isEmergency: true,
      metadata: metadata,
    );
  }

  /// Add a warning to the result
  void addWarning(String warning) {
    warnings.add(warning);
  }

  /// Add an error to the result
  void addError(String error) {
    errors.add(error);
  }

  /// Add metadata to the result
  void addMetadata(String key, dynamic value) {
    metadata[key] = value;
  }

  /// Get metadata value
  T? getMetadata<T>(String key) {
    return metadata[key] as T?;
  }

  /// Check if there are any warnings
  bool get hasWarnings => warnings.isNotEmpty;

  /// Check if there are any errors
  bool get hasErrors => errors.isNotEmpty;

  /// Get total number of issues (warnings + errors)
  int get totalIssues => warnings.length + errors.length;

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'duration': duration.inMilliseconds,
      'message': message,
      'error': error,
      'stackTrace': stackTrace,
      'warnings': warnings,
      'errors': errors,
      'isEmergency': isEmergency,
      'timestamp': timestamp.toIso8601String(),
      'metadata': metadata,
    };
  }

  /// Create from JSON
  factory LogoutResult.fromJson(Map<String, dynamic> json) {
    return LogoutResult(
      success: json['success'] ?? false,
      duration: Duration(milliseconds: json['duration'] ?? 0),
      message: json['message'] ?? '',
      error: json['error'],
      stackTrace: json['stackTrace'],
      warnings: List<String>.from(json['warnings'] ?? []),
      errors: List<String>.from(json['errors'] ?? []),
      isEmergency: json['isEmergency'] ?? false,
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
      metadata: Map<String, dynamic>.from(json['metadata'] ?? {}),
    );
  }

  @override
  String toString() {
    return 'LogoutResult(success: $success, duration: $duration, message: $message, '
           'warnings: ${warnings.length}, errors: ${errors.length}, '
           'isEmergency: $isEmergency)';
  }
}

/// Represents the progress of a logout operation
class LogoutProgress {
  /// Current progress message
  final String message;
  
  /// Progress value between 0.0 and 1.0
  final double progress;
  
  /// Current step number
  final int step;
  
  /// Total number of steps
  final int totalSteps;
  
  /// Timestamp when this progress was created
  final DateTime timestamp;

  LogoutProgress({
    required this.message,
    required this.progress,
    required this.step,
    required this.totalSteps,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Create progress from step information
  factory LogoutProgress.fromStep({
    required String message,
    required int step,
    required int totalSteps,
  }) {
    return LogoutProgress(
      message: message,
      progress: totalSteps > 0 ? step / totalSteps : 0.0,
      step: step,
      totalSteps: totalSteps,
    );
  }

  /// Get progress percentage
  int get percentage => (progress * 100).round();

  /// Check if progress is complete
  bool get isComplete => progress >= 1.0;

  /// Get remaining steps
  int get remainingSteps => totalSteps - step;

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'message': message,
      'progress': progress,
      'step': step,
      'totalSteps': totalSteps,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  /// Create from JSON
  factory LogoutProgress.fromJson(Map<String, dynamic> json) {
    return LogoutProgress(
      message: json['message'] ?? '',
      progress: (json['progress'] ?? 0.0).toDouble(),
      step: json['step'] ?? 0,
      totalSteps: json['totalSteps'] ?? 0,
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
    );
  }

  @override
  String toString() {
    return 'LogoutProgress(message: $message, progress: ${percentage}%, '
           'step: $step/$totalSteps)';
  }
}

/// Represents the status of a logout operation
enum LogoutStatus {
  /// Logout has not been initiated
  notStarted,
  
  /// Logout is in progress
  inProgress,
  
  /// Logout completed successfully
  completed,
  
  /// Logout failed
  failed,
  
  /// Logout was cancelled
  cancelled,
  
  /// Emergency logout in progress
  emergency,
}

/// Extension methods for LogoutStatus
extension LogoutStatusExtension on LogoutStatus {
  /// Check if logout is active (in progress or emergency)
  bool get isActive => this == LogoutStatus.inProgress || this == LogoutStatus.emergency;
  
  /// Check if logout is finished (completed, failed, or cancelled)
  bool get isFinished => this == LogoutStatus.completed || 
                        this == LogoutStatus.failed || 
                        this == LogoutStatus.cancelled;
  
  /// Get human-readable status message
  String get message {
    switch (this) {
      case LogoutStatus.notStarted:
        return 'Logout not started';
      case LogoutStatus.inProgress:
        return 'Logout in progress...';
      case LogoutStatus.completed:
        return 'Logout completed successfully';
      case LogoutStatus.failed:
        return 'Logout failed';
      case LogoutStatus.cancelled:
        return 'Logout cancelled';
      case LogoutStatus.emergency:
        return 'Emergency logout in progress...';
    }
  }
}

/// Represents the phase of a logout operation
enum LogoutPhase {
  /// Notifying server of logout
  serverNotification,
  
  /// Stopping all services
  serviceCleanup,
  
  /// Clearing all data
  dataClearing,
  
  /// Resetting memory and state
  memoryReset,
  
  /// Navigating to login screen
  navigation,
}

/// Extension methods for LogoutPhase
extension LogoutPhaseExtension on LogoutPhase {
  /// Get human-readable phase name
  String get name {
    switch (this) {
      case LogoutPhase.serverNotification:
        return 'Server Notification';
      case LogoutPhase.serviceCleanup:
        return 'Service Cleanup';
      case LogoutPhase.dataClearing:
        return 'Data Clearing';
      case LogoutPhase.memoryReset:
        return 'Memory Reset';
      case LogoutPhase.navigation:
        return 'Navigation';
    }
  }
  
  /// Get phase description
  String get description {
    switch (this) {
      case LogoutPhase.serverNotification:
        return 'Notifying server of logout and terminating session';
      case LogoutPhase.serviceCleanup:
        return 'Stopping all background services and timers';
      case LogoutPhase.dataClearing:
        return 'Clearing all stored data and cache';
      case LogoutPhase.memoryReset:
        return 'Resetting memory and application state';
      case LogoutPhase.navigation:
        return 'Navigating to login screen';
    }
  }
  
  /// Get phase order (0-based index)
  int get order {
    switch (this) {
      case LogoutPhase.serverNotification:
        return 0;
      case LogoutPhase.serviceCleanup:
        return 1;
      case LogoutPhase.dataClearing:
        return 2;
      case LogoutPhase.memoryReset:
        return 3;
      case LogoutPhase.navigation:
        return 4;
    }
  }
}
