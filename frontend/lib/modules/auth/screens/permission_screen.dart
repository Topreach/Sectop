import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../../../core/constants.dart';
import '../../../core/routes.dart';
import '../../../core/themes.dart';
import '../services/auth_service.dart';

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({Key? key}) : super(key: key);

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> {
  bool _isRequesting = false;

  final List<PermissionItem> _permissions = [
    PermissionItem(
      permission: Permission.location,
      title: 'Location Access',
      description: 'Required to track your position during an SOS and find nearby safe zones.',
      icon: Icons.location_on_rounded,
    ),
    PermissionItem(
      permission: Permission.bluetooth,
      title: 'Bluetooth Mesh',
      description: 'Used for offline communication when cellular networks are down.',
      icon: Icons.bluetooth_audio_rounded,
      isAndroid12Only: true,
    ),
    PermissionItem(
      permission: Permission.bluetoothScan,
      title: 'Device Discovery',
      description: 'Allows finding nearby survivors and responders via mesh.',
      icon: Icons.search_rounded,
      isAndroid12Only: true,
    ),
    PermissionItem(
      permission: Permission.bluetoothConnect,
      title: 'Mesh Connection',
      description: 'Necessary to establish a data link with other mesh nodes.',
      icon: Icons.link_rounded,
      isAndroid12Only: true,
    ),
    PermissionItem(
      permission: Permission.notification,
      title: 'Emergency Alerts',
      description: 'Receive critical warnings and SOS acknowledgments in real-time.',
      icon: Icons.notifications_active_rounded,
    ),
  ];

  Future<void> _requestPermissions() async {
    setState(() => _isRequesting = true);

    try {
      // 1. Request standard permissions
      final statuses = await [
        Permission.location,
        Permission.notification,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
      ].request();

      // 2. If location is granted, request Background Location (required for SOS tracking)
      if (statuses[Permission.location]?.isGranted == true) {
        await Permission.locationAlways.request();
      }

      // Check if essential permissions are granted
      final allGranted = statuses[Permission.location]?.isGranted == true;

      if (mounted) {
        final authService = context.read<AuthService>();
        Navigator.of(context).pushReplacementNamed(
          authService.isAuthenticated ? AppRoutes.dashboard : AppRoutes.login,
        );
      }
    } catch (e) {
      debugPrint('Permission request error: $e');
    } finally {
      if (mounted) setState(() => _isRequesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),
              const Icon(
                Icons.security_rounded,
                size: 48,
                color: AppTheme.primaryColor,
              ),
              const SizedBox(height: 24),
              const Text(
                'Safety First',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sectop requires the following permissions to ensure your safety in critical scenarios.',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              Expanded(
                child: ListView.builder(
                  itemCount: _permissions.length,
                  itemBuilder: (context, index) {
                    final item = _permissions[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 24.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              item.icon,
                              color: AppTheme.primaryColor,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item.description,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isRequesting ? null : _requestPermissions,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _isRequesting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Allow Access',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () {
                    final authService = context.read<AuthService>();
                    Navigator.of(context).pushReplacementNamed(
                      authService.isAuthenticated ? AppRoutes.dashboard : AppRoutes.login,
                    );
                  },
                  child: Text(
                    'Set up later',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PermissionItem {
  final Permission permission;
  final String title;
  final String description;
  final IconData icon;
  final bool isAndroid12Only;

  PermissionItem({
    required this.permission,
    required this.title,
    required this.description,
    required this.icon,
    this.isAndroid12Only = false,
  });
}
