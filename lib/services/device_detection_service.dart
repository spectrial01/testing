import 'package:device_info_plus/device_info_plus.dart';

/// Service for detecting device characteristics and rendering capabilities
class DeviceDetectionService {
  static final DeviceInfoPlugin _deviceInfoPlugin = DeviceInfoPlugin();


  /// Checks if the device might have dialog rendering issues
  /// Uses multiple criteria to detect potential problems across all devices
  static Future<bool> hasDialogRenderingIssues() async {
    try {
      final deviceInfo = await _deviceInfoPlugin.androidInfo;
      final model = deviceInfo.model.toLowerCase();
      final brand = deviceInfo.brand.toLowerCase();
      final androidVersion = deviceInfo.version.sdkInt;
      
      // Check Android version first (most reliable indicator)
      if (androidVersion < 28) { // Android 9 and below
        return true;
      }
      
      // Check for problematic device patterns
      final problematicPatterns = [
        // Specific model numbers
        'm2102j20sg', 'm2101k9g', 'm2101k9r', 'sm-a125f', 'sm-a225f',
        // Brand patterns
        'poco x3', 'redmi note', 'xiaomi mi', 'samsung galaxy a', 'samsung galaxy m', 'samsung galaxy f',
        'oppo a', 'oppo f', 'vivo y', 'vivo v', 'realme c', 'realme narzo',
        'oneplus nord', 'huawei nova', 'huawei p', 'huawei mate',
        // Low-end patterns
        'galaxy a0', 'galaxy a1', 'galaxy a2', 'galaxy a3', 'galaxy a4',
        'redmi 8', 'redmi 9', 'redmi 10', 'redmi 11', 'redmi 12',
        'oppo a1', 'oppo a2', 'oppo a3', 'oppo a4', 'oppo a5',
        'vivo y1', 'vivo y2', 'vivo y3', 'vivo y4', 'vivo y5',
        'realme c1', 'realme c2', 'realme c3', 'realme c4', 'realme c5',
        'huawei y', 'huawei p lite', 'huawei nova lite',
        'infinix', 'tecno', 'itel',
        // Suspicious patterns
        'lite', 'go', 'play', 'prime', 'max', 'pro max', 'ultra', 'neo', 'ace', 'gt', 'se'
      ];
      
      // Check if device matches any problematic pattern
      for (final pattern in problematicPatterns) {
        if (model.contains(pattern) || brand.contains(pattern)) {
          return true;
        }
      }
      
      // Check for problematic manufacturers
      final problematicManufacturers = [
        'xiaomi', 'redmi', 'poco', 'oppo', 'vivo', 'realme',
        'huawei', 'honor', 'infinix', 'tecno', 'itel'
      ];
      
      for (final manufacturer in problematicManufacturers) {
        if (brand.contains(manufacturer)) {
          return true;
        }
      }
      
      return false;
    } catch (e) {
      print('DeviceDetectionService: Error checking dialog rendering issues: $e');
      // If we can't determine, assume it might have issues and use simple dialog
      return true;
    }
  }


  /// Gets comprehensive device analysis for debugging
  static Future<Map<String, dynamic>> getDeviceAnalysis() async {
    try {
      final deviceInfo = await _deviceInfoPlugin.androidInfo;
      final hasRenderingIssues = await hasDialogRenderingIssues();
      
      return {
        'deviceInfo': {
          'brand': deviceInfo.brand,
          'model': deviceInfo.model,
          'manufacturer': deviceInfo.manufacturer,
          'androidVersion': deviceInfo.version.release,
          'sdkInt': deviceInfo.version.sdkInt,
          'isPhysicalDevice': deviceInfo.isPhysicalDevice,
          'product': deviceInfo.product,
          'device': deviceInfo.device,
          'board': deviceInfo.board,
          'hardware': deviceInfo.hardware,
        },
        'analysis': {
          'hasRenderingIssues': hasRenderingIssues,
          'recommendedDialogType': hasRenderingIssues ? 'Simple' : 'Enhanced',
          'reasons': _getRenderingIssueReasons(deviceInfo),
        },
      };
    } catch (e) {
      return {
        'error': e.toString(),
        'hasRenderingIssues': true,
        'recommendedDialogType': 'Basic',
      };
    }
  }

  /// Gets reasons why a device might have rendering issues
  static List<String> _getRenderingIssueReasons(dynamic deviceInfo) {
    final reasons = <String>[];
    final model = deviceInfo.model.toLowerCase();
    final brand = deviceInfo.brand.toLowerCase();
    final androidVersion = deviceInfo.version.sdkInt;
    
    // Check each criteria and add reasons
    if (androidVersion < 24) {
      reasons.add('Very old Android version (API $androidVersion)');
    } else if (androidVersion < 28) {
      reasons.add('Older Android version (API $androidVersion)');
    }
    
    if (brand.contains('xiaomi') || brand.contains('redmi') || brand.contains('poco')) {
      reasons.add('Xiaomi group device (known UI issues)');
    }
    
    if (brand.contains('oppo') || brand.contains('vivo') || brand.contains('realme')) {
      reasons.add('BBK group device (Oppo/Vivo/Realme)');
    }
    
    if (model.contains('galaxy a') || model.contains('galaxy m') || model.contains('galaxy f')) {
      reasons.add('Samsung budget/mid-range device');
    }
    
    if (model.contains('lite') || model.contains('go') || model.contains('play')) {
      reasons.add('Budget device variant');
    }
    
    return reasons;
  }

  /// Checks if device is running on Android 12 or higher
  /// Some devices have different rendering behavior on newer Android versions
  static Future<bool> isAndroid12OrHigher() async {
    try {
      final deviceInfo = await _deviceInfoPlugin.androidInfo;
      return deviceInfo.version.sdkInt >= 31; // Android 12 is API level 31
    } catch (e) {
      print('DeviceDetectionService: Error checking Android version: $e');
      return false;
    }
  }
}
