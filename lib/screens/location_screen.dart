import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../ui/widgets/permission_status_widget.dart';

class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key});

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  PermissionStatus _permissionStatus = PermissionStatus.denied;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkPermissionStatus();
  }

  Future<void> _checkPermissionStatus() async {
    setState(() => _isLoading = true);
    
    try {
      final status = await Permission.location.status;
      if (mounted) {
        setState(() {
          _permissionStatus = status;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Location Permission'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkPermissionStatus,
            tooltip: 'Refresh Status',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Status Card
                  PermissionStatusWidget(
                    status: _permissionStatus,
                    title: 'Location Permission',
                    description: 'Grant location permission to enable precise location features and improved app functionality.',
                  ),
                  const SizedBox(height: 30),

                  // Open Settings Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: openAppSettings,
                      icon: const Icon(Icons.settings),
                      label: const Text('Open App Settings'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[700],
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),

                  // Information Card
                  Card(
                    color: Colors.blue[900],
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: Colors.lightBlueAccent),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Grant location permission to enable precise location features and improved app functionality.',
                              style: TextStyle(
                                color: Colors.lightBlueAccent[100],
                                fontSize: 14,
                              ),
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