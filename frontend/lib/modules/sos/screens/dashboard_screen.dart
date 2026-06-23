import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants.dart';
import '../../../core/routes.dart';
import '../../../core/themes.dart';
import '../../../shared/services/sync_manager.dart';
import '../../../shared/services/backend_api.dart';
import '../../../shared/services/offline_storage.dart';
import '../../auth/services/auth_service.dart';
import '../../mesh/services/mesh_manager.dart';
import '../../maps/services/map_service.dart';
import '../../../shared/services/global_location_service.dart';
import '../../../shared/services/hardware_trigger_service.dart';
import '../services/sos_service.dart';
import '../widgets/terrorist_location_card.dart';
import '../../ai/widgets/threat_awareness_card.dart';
import '../../ai/services/threat_awareness_service.dart';
import '../../monetization/widgets/points_balance_widget.dart';
import '../../monetization/services/monetization_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    _DashboardHome(),
    _MapView(),
    _InboxView(),
    _ProfileView(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppTheme.primaryColor,
        unselectedItemColor: Colors.grey,
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            activeIcon: Icon(Icons.map),
            label: 'Map',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.inbox_outlined),
            activeIcon: Icon(Icons.inbox),
            label: 'Inbox',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _DashboardHome extends StatefulWidget {
  _DashboardHome();

  @override
  State<_DashboardHome> createState() => _DashboardHomeState();
}

class _DashboardHomeState extends State<_DashboardHome> {
  int _unreadMessageCount = 0;

  @override
  void initState() {
    super.initState();
    // Register popup callback for critical threat alerts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final threatService = context.read<ThreatAwarenessService>();
      threatService.onCriticalAlert = (alert) {
        if (!mounted) return;
        _showThreatPopup(context, alert);
      };
      _loadUnreadCount();
    });
  }

  Future<void> _loadUnreadCount() async {
    try {
      final authService = context.read<AuthService>();
      final userId = authService.currentUser?.id;
      if (userId == null) return;
      final api = context.read<BackendApi>();
      final data = await api.getUnreadCount(userId);
      if (mounted) {
        setState(() {
          _unreadMessageCount = data['count'] as int? ?? 0;
        });
      }
    } catch (e) {
      debugPrint('_DashboardHomeState: Failed to load unread count: $e');
    }
  }

  @override
  void dispose() {
    // Unregister callback to avoid memory leaks
    try {
      ThreatAwarenessService().onCriticalAlert = null;
    } catch (_) {}
    super.dispose();
  }
/// Show a popup dialog for critical/high threat alerts.
/// Resolves the threat location name via internet reverse geocoding
/// and shows distance/direction from the user's current position.
void _showThreatPopup(BuildContext context, ThreatAlert alert) {
  // Resolve location name from coordinates using internet geocoding
  _resolveThreatLocation(alert).then((locationInfo) {
    if (!mounted) return;
    _showThreatDialog(context, alert, locationInfo);
  });
}

/// Resolve threat coordinates to a human-readable address via internet.
Future<Map<String, dynamic>?> _resolveThreatLocation(ThreatAlert alert) async {
  if (alert.latitude == null || alert.longitude == null) return null;
  try {
    return await GlobalLocationService.reverseGeocode(
      alert.latitude!,
      alert.longitude!,
    );
  } catch (e) {
    debugPrint('_showThreatPopup: Reverse geocode failed: $e');
    return null;
  }
}

/// Calculate distance in km between two coordinates using Haversine formula.
double _calculateDistance(double lat1, double lng1, double lat2, double lng2) {
  const R = 6371.0; // Earth radius in km
  final dLat = _toRadians(lat2 - lat1);
  final dLng = _toRadians(lng2 - lng1);
  final a = _sinSquared(dLat / 2) +
      _cos(lat1) * _cos(lat2) * _sinSquared(dLng / 2);
  final c = 2 * _asin(_sqrt(a));
  return R * c;
}

double _toRadians(double deg) => deg * 3.141592653589793 / 180.0;
double _sinSquared(double x) {
  final s = _sin(x);
  return s * s;
}
double _sin(double x) => x - (x * x * x) / 6 + (x * x * x * x * x) / 120;
double _cos(double x) => 1 - (x * x) / 2 + (x * x * x * x) / 24;
double _sqrt(double x) {
  if (x <= 0) return 0;
  double z = x / 2;
  for (int i = 0; i < 10; i++) {
    z = (z + x / z) / 2;
  }
  return z;
}
double _asin(double x) {
  if (x < -1 || x > 1) return x < 0 ? -1.57079632679 : 1.57079632679;
  return 1.57079632679 - _sqrt(1 - x * x) * (1 + (x * x) / 6);
}

/// Calculate compass bearing from user to threat.
String _calculateDirection(double userLat, double userLng, double threatLat, double threatLng) {
  final dLng = _toRadians(threatLng - userLng);
  final y = _sin(dLng) * _cos(threatLat);
  final x = _cos(userLat) * _sin(threatLat) -
      _sin(userLat) * _cos(threatLat) * _cos(dLng);
  final bearing = _toDegrees(_atan2(y, x));
  final normalized = (bearing + 360) % 360;
  if (normalized >= 337.5 || normalized < 22.5) return 'N';
  if (normalized >= 22.5 && normalized < 67.5) return 'NE';
  if (normalized >= 67.5 && normalized < 112.5) return 'E';
  if (normalized >= 112.5 && normalized < 157.5) return 'SE';
  if (normalized >= 157.5 && normalized < 202.5) return 'S';
  if (normalized >= 202.5 && normalized < 247.5) return 'SW';
  if (normalized >= 247.5 && normalized < 292.5) return 'W';
  return 'NW';
}

double _toDegrees(double rad) => rad * 180.0 / 3.141592653589793;
double _atan2(double y, double x) {
  if (x > 0) return _atan(y / x);
  if (x < 0) return y >= 0 ? _atan(y / x) + 3.141592653589793 : _atan(y / x) - 3.141592653589793;
  return y > 0 ? 3.141592653589793 / 2 : -3.141592653589793 / 2;
}
double _atan(double x) {
  return x - (x * x * x) / 3 + (x * x * x * x * x) / 5 - (x * x * x * x * x * x * x) / 7;
}

/// Get icon for threat type.
IconData _threatTypeIcon(String type) {
  switch (type) {
    case 'incident': return Icons.warning_amber_rounded;
    case 'danger_zone': return Icons.gps_fixed;
    case 'sos_alert': return Icons.notifications_active;
    case 'message_analysis': return Icons.message;
    case 'prediction': return Icons.trending_up;
    default: return Icons.notifications;
  }
}

/// Get label for threat type.
String _threatTypeLabel(String type) {
  switch (type) {
    case 'incident': return 'Reported Incident';
    case 'danger_zone': return 'Danger Zone';
    case 'sos_alert': return 'SOS Alert';
    case 'message_analysis': return 'Message Analysis';
    case 'prediction': return 'AI Prediction';
    default: return 'Threat Alert';
  }
}

/// Show the actual dialog after location resolution.
void _showThreatDialog(BuildContext context, ThreatAlert alert, Map<String, dynamic>? locationInfo) {
  // Get user's current position for distance/direction calculation
  double? distanceKm;
  String? direction;
  try {
    final mapService = MapService();
    final pos = mapService.currentPosition;
    if (pos != null && alert.latitude != null && alert.longitude != null) {
      distanceKm = _calculateDistance(
        pos.latitude, pos.longitude,
        alert.latitude!, alert.longitude!,
      );
      direction = _calculateDirection(
        pos.latitude, pos.longitude,
        alert.latitude!, alert.longitude!,
      );
    }
  } catch (_) {}

  final locationName = locationInfo?['displayName'] as String?;
  final city = locationInfo?['city'] as String?;
  final state = locationInfo?['state'] as String?;
  final country = locationInfo?['country'] as String?;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          Icon(
            alert.severity == 'critical'
                ? Icons.dangerous
                : Icons.warning_amber_rounded,
            color: alert.severity == 'critical'
                ? Colors.red
                : Colors.orange,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              alert.severity == 'critical'
                  ? '🚨 CRITICAL ALERT'
                  : '⚠️ HIGH ALERT',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: alert.severity == 'critical'
                    ? Colors.red
                    : Colors.orange,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Threat type badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: alert.severity == 'critical'
                  ? Colors.red.withOpacity(0.1)
                  : Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _threatTypeIcon(alert.type),
                  size: 14,
                  color: alert.severity == 'critical' ? Colors.red : Colors.orange,
                ),
                const SizedBox(width: 4),
                Text(
                  _threatTypeLabel(alert.type),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: alert.severity == 'critical' ? Colors.red : Colors.orange,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Title
          Text(
            alert.title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          // Description
          Text(
            alert.description,
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
          ),
          const SizedBox(height: 12),
          // Location info (resolved via internet reverse geocoding)
          if (locationName != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withOpacity(0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.location_on, size: 16, color: Colors.blue[700]),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          locationName,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[800],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (city != null || state != null || country != null) ...[
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(left: 22),
                      child: Text(
                        [
                          if (city != null) city,
                          if (state != null) state,
                          if (country != null) country,
                        ].join(', '),
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ] else if (alert.latitude != null && alert.longitude != null) ...[
            // Fallback: show raw coordinates if geocoding failed
            Row(
              children: [
                Icon(Icons.location_on, size: 16, color: Colors.grey[500]),
                const SizedBox(width: 6),
                Text(
                  '${alert.latitude!.toStringAsFixed(4)}, ${alert.longitude!.toStringAsFixed(4)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
          // Distance and direction from user
          if (distanceKm != null && direction != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.navigation, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Text(
                  '${distanceKm < 1 ? '${(distanceKm * 1000).toInt()}m' : '${distanceKm.toStringAsFixed(1)}km'} $direction of you',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          // Confidence
          Row(
            children: [
              Icon(Icons.analytics, size: 16, color: Colors.grey[500]),
              const SizedBox(width: 6),
              Text(
                'Confidence: ${(alert.confidence * 100).toInt()}%',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
          // Timestamp
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.access_time, size: 16, color: Colors.grey[500]),
              const SizedBox(width: 6),
              Text(
                _formatAlertTime(alert.timestamp),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            // Mark as read
            ThreatAwarenessService().markAsRead(alert.id);
          },
          child: const Text('ACKNOWLEDGE'),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            ThreatAwarenessService().markAsRead(alert.id);
            // Navigate to map centered on the threat location
            if (alert.latitude != null && alert.longitude != null) {
              Navigator.of(context).pushNamed(
                AppRoutes.map,
                arguments: {
                  'centerLat': alert.latitude,
                  'centerLng': alert.longitude,
                  'zoom': 16.0,
                },
              );
            } else {
              Navigator.of(context).pushNamed(AppRoutes.map);
            }
          },
          child: const Text('VIEW ON MAP'),
        ),
      ],
    ),
  );
}

String _formatAlertTime(DateTime time) {
  final now = DateTime.now();
  final diff = now.difference(time);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${time.day}/${time.month}/${time.year}';
}
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = context.select<SyncManager, bool>((s) => s.isOnline);
    final isSyncing = context.select<SyncManager, bool>((s) => s.isSyncing);
    final pendingCount = context.select<SyncManager, int>((s) => s.pendingCount);
    final peerCount = context.select<MeshManager, int>((m) => m.discoveredPeers.length);
    final isTracking = context.select<MapService, bool>((m) => m.isTracking);

    return Scaffold(
      appBar: AppBar(
        title: Text('Sectop'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Points balance badge
          PointsBalanceWidget(
            compact: true,
            onTap: () => Navigator.pushNamed(context, AppRoutes.monetization),
          ),
          const SizedBox(width: 4),
          // Sync status indicator
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(
              isOnline ? Icons.cloud_done : Icons.cloud_off,
              color: isOnline ? Colors.green[300] : Colors.orange[300],
              size: 20,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => context.read<SyncManager>().triggerSync(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // SOS Button - Large and prominent
              GestureDetector(
                onTap: () {
                  // If stealth mode is ON, send silent SOS directly without navigation
                  final hardwareService = HardwareTriggerService();
                  if (hardwareService.isStealthModeEnabled) {
                    _sendSilentSOS();
                  } else {
                    Navigator.of(context).pushNamed(AppRoutes.sos);
                  }
                },
                child: Container(
                  height: 180,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFFE53935),
                        Color(0xFFD32F2F),
                        Color(0xFFC62828),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryColor.withOpacity(0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.warning_amber_rounded, size: 64, color: Colors.white),
                        const SizedBox(height: 8),
                        Text(
                          'SEND SOS',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 6,
                          ),
                        ),
                        Text(
                          'Tap for emergency alert',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Quick Actions Grid
              Text(
                'Quick Actions',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              // Row 1: Existing quick actions
              Row(
                children: [
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.map_outlined,
                      label: 'Safe Zones',
                      color: Colors.green,
                      onTap: () => Navigator.of(context).pushNamed(AppRoutes.map),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.wifi_tethering,
                      label: 'Mesh Network',
                      color: Colors.blue,
                      onTap: () => Navigator.of(context).pushNamed(AppRoutes.meshStatus),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.inbox_outlined,
                      label: 'Messages',
                      color: Colors.purple,
                      count: _unreadMessageCount,
                      onTap: () => Navigator.of(context).pushNamed(AppRoutes.inbox),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.medical_services_outlined,
                      label: 'First Aid',
                      color: Colors.orange,
                      onTap: () => Navigator.of(context).pushNamed(AppRoutes.firstAid),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Row 2: NEW - 4 Feature Quick Actions
              Text(
                'Emergency Tools',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.campaign_outlined,
                      label: 'Broadcasts',
                      color: Colors.red,
                      onTap: () => Navigator.of(context).pushNamed(AppRoutes.broadcasts),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.route_outlined,
                      label: 'Safe Route',
                      color: Colors.teal,
                      onTap: () => Navigator.of(context).pushNamed(AppRoutes.safeRoute),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.visibility_outlined,
                      label: 'Tip Off',
                      color: Colors.indigo,
                      onTap: () => Navigator.of(context).pushNamed(AppRoutes.tipOff),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.security_outlined,
                      label: 'Danger Zones',
                      color: const Color(0xFFB71C1C),
                      onTap: () => Navigator.of(context).pushNamed(AppRoutes.map),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Community section
              Text(
                'Community',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.groups_outlined,
                      label: 'Community Feed',
                      color: const Color(0xFF7B1FA2),
                      onTap: () => Navigator.of(context).pushNamed(AppRoutes.communityFeed),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.add_a_photo_outlined,
                      label: 'Create Post',
                      color: const Color(0xFF00897B),
                      onTap: () => Navigator.of(context).pushNamed(AppRoutes.communityCreatePost),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // My Posts - view and manage your own posts
              Row(
                children: [
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.person_outline,
                      label: 'My Posts',
                      color: const Color(0xFF6A1B9A),
                      onTap: () => Navigator.of(context).pushNamed(AppRoutes.communityMyPosts),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.favorite_outline,
                      label: 'My Favorites',
                      color: const Color(0xFFC62828),
                      onTap: () => Navigator.of(context).pushNamed(AppRoutes.communityFavorites),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Status Cards
              Text(
                'System Status',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              // Connection status
              _StatusCard(
                icon: isOnline ? Icons.cloud_done : Icons.cloud_off,
                title: 'Cloud Connection',
                subtitle: isOnline ? 'Connected' : 'Offline',
                color: isOnline ? Colors.green : Colors.orange,
              ),
              const SizedBox(height: 8),

              // Mesh status
              _StatusCard(
                icon: Icons.wifi_tethering,
                title: 'Mesh Network',
                subtitle: '${'peers connected'}: $peerCount',
                color: peerCount > 0 ? Colors.blue : Colors.grey,
              ),
              const SizedBox(height: 8),

              // Location status
              _StatusCard(
                icon: Icons.my_location,
                title: 'Location Tracking',
                subtitle: isTracking ? 'Active' : 'Inactive',
                color: isTracking ? Colors.green : Colors.grey,
              ),
              const SizedBox(height: 8),

              // Sync status
              _StatusCard(
                icon: Icons.sync,
                title: 'Data Sync',
                subtitle: isSyncing
                    ? 'Syncing...'
                    : '${'pending items'}: $pendingCount',
                color: pendingCount > 0 ? Colors.orange : Colors.green,
              ),
              const SizedBox(height: 24),

              // Threat Awareness Card — Real-time intelligence monitoring
              ThreatAwarenessCard(
                onAlertTap: (alert) => _showThreatPopup(context, alert),
              ),

              // Terrorist / Danger Location Finder
              const TerroristLocationCard(),
            ],
          ),
        ),
      ),
    );
  }

  /// Send a silent SOS directly without showing any UI (Stealth Mode).
  Future<void> _sendSilentSOS() async {
    debugPrint('DashboardScreen: Sending silent SOS (stealth mode ON)');
    try {
      final sosService = SOSService();
      await sosService.sendSOS(
        alertType: 'silent_panic',
        description: 'Stealth mode SOS triggered from dashboard',
        isSilent: true,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('SOS sent silently'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('DashboardScreen: Silent SOS failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('SOS failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final int? count;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Stack(
                children: [
                  Icon(icon, size: 32, color: color),
                  if (count != null && count! > 0)
                    Positioned(
                      right: -8,
                      top: -8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        child: Text(
                          count! > 99 ? '99+' : '$count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[800],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const _StatusCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MapView extends StatefulWidget {
  _MapView();

  @override
  State<_MapView> createState() => _MapViewState();
}

class _MapViewState extends State<_MapView> {
  List<Map<String, dynamic>> _nearbyZones = [];
  List<Map<String, dynamic>> _activeAlerts = [];
  List<Map<String, dynamic>> _nearbyIncidents = [];
  Map<String, dynamic>? _dangerScore;
  bool _isLoadingZones = true;
  bool _isLoadingDangerScore = false;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _loadMapData();
  }

  Future<void> _loadMapData() async {
    setState(() => _isLoadingZones = true);
    try {
      final mapService = context.read<MapService>();
      final position = mapService.currentPosition ??
          await mapService.getCurrentLocation();
      if (position != null) {
        final api = context.read<BackendApi>();
        // Load zones, alerts, and incidents in parallel from the internet
        final results = await Future.wait([
          api.getZonesNearby(position.latitude, position.longitude),
          api.getActiveAlerts(),
        ], eagerError: false);

        final zones = results[0]['zones'] is List
            ? List<Map<String, dynamic>>.from(results[0]['zones'])
            : <Map<String, dynamic>>[];
        final alerts = results[1]['alerts'] is List
            ? List<Map<String, dynamic>>.from(results[1]['alerts'])
            : <Map<String, dynamic>>[];

        // Cache zones locally for offline use
        try {
          final storage = OfflineStorageService();
          for (final zone in zones) {
            await storage.saveZone(zone);
          }
        } catch (_) {}

        // Load nearby incidents via internet
        List<Map<String, dynamic>> incidents = [];
        try {
          final incidentResult = await api.getNearbyIncidents(
            latitude: position.latitude,
            longitude: position.longitude,
            radiusKm: 50,
          );
          if (incidentResult['incidents'] is List) {
            incidents = List<Map<String, dynamic>>.from(incidentResult['incidents']);
          }
        } catch (e) {
          debugPrint('_MapView: Failed to load incidents: $e');
        }

        setState(() {
          _nearbyZones = zones;
          _activeAlerts = alerts;
          _nearbyIncidents = incidents;
          _isLoadingZones = false;
          _isOffline = false;
        });

        // Load danger score after map data
        _loadDangerScore(position.latitude, position.longitude);
      } else {
        setState(() => _isLoadingZones = false);
      }
    } catch (e) {
      debugPrint('_MapView: Server unreachable, loading cached data: $e');
      // Offline fallback: load nearby zones from local storage
      try {
        final mapService = context.read<MapService>();
        final position = mapService.currentPosition ??
            await mapService.getCurrentLocation();
        if (position != null) {
          final storage = OfflineStorageService();
          final cachedZones = await storage.getZonesNearLocation(
            position.latitude,
            position.longitude,
            radiusKm: 5.0,
          );
          setState(() {
            _nearbyZones = cachedZones;
            _isLoadingZones = false;
            _isOffline = true;
          });
          debugPrint('_MapView: Loaded ${cachedZones.length} cached zones');
        } else {
          setState(() => _isLoadingZones = false);
        }
      } catch (cacheError) {
        debugPrint('_MapView: Cache load also failed: $cacheError');
        setState(() => _isLoadingZones = false);
      }
    }
  }

  Future<void> _loadDangerScore(double latitude, double longitude) async {
    setState(() => _isLoadingDangerScore = true);
    try {
      final api = context.read<BackendApi>();
      final score = await api.getDangerScore(
        latitude: latitude,
        longitude: longitude,
        radiusKm: 5,
      );
      if (mounted) {
        setState(() {
          _dangerScore = score;
          _isLoadingDangerScore = false;
        });
      }
    } catch (e) {
      debugPrint('_MapView: Failed to load danger score: $e');
      if (mounted) setState(() => _isLoadingDangerScore = false);
    }
  }

  Color _dangerLevelColor(String level) {
    switch (level.toLowerCase()) {
      case 'safe':
        return Colors.green;
      case 'low':
        return Colors.yellow.shade700;
      case 'medium':
        return Colors.orange;
      case 'high':
        return Colors.deepOrange;
      case 'critical':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mapService = context.watch<MapService>();
    final position = mapService.currentPosition;
    final center = position != null
        ? LatLng(position.latitude, position.longitude)
        : const LatLng(9.0820, 8.6753); // Default: Nigeria center

    return Scaffold(
      appBar: AppBar(
        title: Text('Map'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.fullscreen),
            tooltip: 'Open Full Map',
            onPressed: () => Navigator.of(context).pushNamed(AppRoutes.map),
          ),
        ],
      ),
      body: Column(
        children: [
          // Offline banner
          if (_isOffline)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: Colors.orange[100],
              child: Row(
                children: [
                  Icon(Icons.cloud_off, size: 16, color: Colors.orange[800]),
                  const SizedBox(width: 8),
                  Text(
                    'Offline — showing cached data',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange[900],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: 14.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.dangeremergence.app',
                    ),
                    // Current location marker with user avatar
                    MarkerLayer(
                      markers: [
                        if (position != null)
                          Marker(
                            point: center,
                            width: 44,
                            height: 44,
                            child: _UserLocationMarker(
                              authService: context.read<AuthService>(),
                            ),
                          ),
                        // Zone markers
                        ..._nearbyZones.map((zone) {
                          final lat = (zone['latitude'] as num?)?.toDouble() ?? 0;
                          final lng = (zone['longitude'] as num?)?.toDouble() ?? 0;
                          final type = zone['type'] as String? ?? 'unknown';
                          final zoneColor = AppTheme.getZoneColor(type);
                          return Marker(
                            point: LatLng(lat, lng),
                            width: 24,
                            height: 24,
                            child: Container(
                              decoration: BoxDecoration(
                                color: zoneColor,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Icon(
                                Icons.warning,
                                color: Colors.white,
                                size: 14,
                              ),
                            ),
                          );
                        }),
                        // Alert markers (active SOS alerts from internet)
                        ..._activeAlerts.map((alert) {
                          final lat = (alert['latitude'] as num?)?.toDouble() ?? 0;
                          final lng = (alert['longitude'] as num?)?.toDouble() ?? 0;
                          final title = alert['title'] as String? ?? 'Active Alert';
                          return Marker(
                            point: LatLng(lat, lng),
                            width: 28,
                            height: 28,
                            child: Tooltip(
                              message: title,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.red.withOpacity(0.5),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.sos,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                          );
                        }),
                        // Incident markers (from internet API)
                        ..._nearbyIncidents.map((inc) {
                          final lat = (inc['latitude'] as num?)?.toDouble() ?? 0;
                          final lng = (inc['longitude'] as num?)?.toDouble() ?? 0;
                          final type = inc['type'] as String? ?? 'unknown';
                          final desc = inc['description'] as String? ?? type;
                          Color incColor;
                          switch (type.toLowerCase()) {
                            case 'kidnapping':
                              incColor = Colors.deepPurple;
                              break;
                            case 'terrorism':
                            case 'terrorist':
                              incColor = Colors.red.shade900;
                              break;
                            case 'robbery':
                            case 'armed_robbery':
                              incColor = Colors.orange.shade800;
                              break;
                            case 'assault':
                              incColor = Colors.pink.shade700;
                              break;
                            case 'vandalism':
                              incColor = Colors.brown;
                              break;
                            default:
                              incColor = Colors.grey.shade700;
                          }
                          return Marker(
                            point: LatLng(lat, lng),
                            width: 24,
                            height: 24,
                            child: Tooltip(
                              message: desc,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: incColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                                child: const Icon(
                                  Icons.report_problem,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ],
                ),
                // Danger score card (top-left overlay)
                if (_dangerScore != null || _isLoadingDangerScore)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _buildDangerScoreCard(),
                  ),
              ],
            ),
          ),
          // Summary bar showing zones, alerts, and incidents
          if (_isLoadingZones)
            const Padding(
              padding: EdgeInsets.all(8),
              child: LinearProgressIndicator(),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Colors.grey[100],
              child: Row(
                children: [
                  // Zones count
                  Icon(Icons.warning_amber, size: 16, color: Colors.orange[700]),
                  const SizedBox(width: 4),
                  Text(
                    '${_nearbyZones.length} zones',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (_activeAlerts.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Container(width: 1, height: 14, color: Colors.grey[300]),
                    const SizedBox(width: 12),
                    Icon(Icons.sos, size: 16, color: Colors.red[700]),
                    const SizedBox(width: 4),
                    Text(
                      '${_activeAlerts.length} alerts',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  if (_nearbyIncidents.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Container(width: 1, height: 14, color: Colors.grey[300]),
                    const SizedBox(width: 12),
                    Icon(Icons.report_problem, size: 16, color: Colors.deepPurple),
                    const SizedBox(width: 4),
                    Text(
                      '${_nearbyIncidents.length} incidents',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.deepPurple,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDangerScoreCard() {
    final score = _dangerScore;
    final level = (score?['level'] as String?) ?? 'unknown';
    final scoreValue = (score?['score'] as num?)?.toDouble();
    final color = _dangerLevelColor(level);

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        constraints: const BoxConstraints(maxWidth: 160),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield, size: 14, color: color),
                const SizedBox(width: 4),
                Text(
                  'Danger Score',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            if (_isLoadingDangerScore)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else ...[
              Text(
                scoreValue != null ? scoreValue.toStringAsFixed(0) : '--',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                  height: 1.1,
                ),
              ),
              Text(
                level[0].toUpperCase() + level.substring(1),
                style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A marker widget that shows the current user's location on the map.
/// Displays the user's initials in a colored circle, or a person icon
/// as fallback. Includes a pulsing outer ring for visibility.
class _UserLocationMarker extends StatelessWidget {
  final AuthService authService;

  const _UserLocationMarker({required this.authService});

  @override
  Widget build(BuildContext context) {
    final user = authService.currentUser;
    final name = user?.name ?? 'U';
    final initials = name.isNotEmpty ? name[0].toUpperCase() : 'U';

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.4),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
      child: CircleAvatar(
        radius: 20,
        backgroundColor: Colors.blue,
        child: Text(
          initials,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _InboxView extends StatefulWidget {
  _InboxView();

  @override
  State<_InboxView> createState() => _InboxViewState();
}

class _InboxViewState extends State<_InboxView> {
  int _unreadCount = 0;
  int _alertCount = 0;
  List<Map<String, dynamic>> _recentMessages = [];
  List<Map<String, dynamic>> _tips = [];
  bool _isLoading = true;
  bool _isLoadingTips = true;

  @override
  void initState() {
    super.initState();
    _loadInboxSummary();
  }

  Future<void> _loadInboxSummary() async {
    setState(() => _isLoading = true);
    try {
      final authService = context.read<AuthService>();
      final userId = authService.currentUser?.id;
      if (userId == null) {
        setState(() => _isLoading = false);
        return;
      }
      final api = context.read<BackendApi>();

      final results = await Future.wait([
        api.getUnreadCount(userId),
        api.getAlertCount(),
        api.getMessages(userId),
      ]);

      final unreadData = results[0];
      final alertData = results[1];
      final messagesData = results[2];

      setState(() {
        _unreadCount = unreadData['count'] as int? ?? 0;
        _alertCount = alertData['count'] as int? ?? 0;
        final allMessages = messagesData['messages'] is List
            ? List<Map<String, dynamic>>.from(messagesData['messages'])
            : <Map<String, dynamic>>[];
        _recentMessages = allMessages.take(3).toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('_InboxView: Failed to load summary: $e');
      setState(() => _isLoading = false);
    }
    // Load tips for Updates section
    await _loadTips();
  }

  Future<void> _loadTips() async {
    setState(() => _isLoadingTips = true);
    try {
      final api = context.read<BackendApi>();
      final result = await api.getRecentTips();
      final rawTips = result['data'];
      final List<Map<String, dynamic>> tipsList;
      if (rawTips is List) {
        tipsList = rawTips.cast<Map<String, dynamic>>().toList();
      } else {
        tipsList = [];
      }
      if (mounted) {
        setState(() {
          _tips = tipsList.take(3).toList();
          _isLoadingTips = false;
        });
      }
    } catch (e) {
      debugPrint('_InboxView: Failed to load tips: $e');
      if (mounted) {
        setState(() => _isLoadingTips = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Inbox'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: 'Open Inbox',
            onPressed: () => Navigator.of(context).pushNamed(AppRoutes.inbox),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadInboxSummary,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Summary cards row
                  Row(
                    children: [
                      Expanded(
                        child: _SummaryCard(
                          icon: Icons.message_outlined,
                          label: 'Unread Messages',
                          count: _unreadCount,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SummaryCard(
                          icon: Icons.warning_amber_outlined,
                          label: 'Active Alerts',
                          count: _alertCount,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Recent messages section
                  Text(
                    'Recent Messages',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),

                  if (_recentMessages.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          'No recent messages',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    ..._recentMessages.map((msg) {
                      final content = msg['content'] as String? ?? '';
                      final senderId = msg['sender_id'] as String? ?? 'Unknown';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppTheme.primaryColor,
                            child: const Icon(Icons.person, color: Colors.white, size: 20),
                          ),
                          title: Text(
                            senderId,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            content,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.grey[600], fontSize: 13),
                          ),
                        ),
                      );
                    }),
const SizedBox(height: 16),
ElevatedButton.icon(
  onPressed: () => Navigator.of(context).pushNamed(AppRoutes.inbox),
  icon: const Icon(Icons.open_in_new, size: 18),
  label: Text('Open Inbox'),
),

const SizedBox(height: 24),

// Updates section
Text(
  'Updates',
  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
),
const SizedBox(height: 12),

if (_isLoadingTips)
  const Center(
    child: Padding(
      padding: EdgeInsets.all(16),
      child: CircularProgressIndicator(),
    ),
  )
else if (_tips.isNotEmpty)
  ..._tips.map((tip) {
    final tipType = tip['tipType'] ?? 'other';
    final description = tip['description'] as String? ?? 'No description';
    final threatScore = tip['threatScore'] as int? ?? 0;
    final status = tip['status'] as String? ?? 'pending';
    final createdAt = tip['createdAt'];

    IconData typeIcon;
    Color typeColor;
    switch (tipType.toString()) {
      case 'planned_attack':
        typeIcon = Icons.groups;
        typeColor = Colors.red;
        break;
      case 'suspicious_person':
        typeIcon = Icons.person_search;
        typeColor = Colors.orange;
        break;
      case 'suspicious_vehicle':
        typeIcon = Icons.directions_car;
        typeColor = Colors.amber;
        break;
      case 'hidden_weapons':
        typeIcon = Icons.gavel;
        typeColor = Colors.deepOrange;
        break;
      case 'kidnapping_plot':
        typeIcon = Icons.people_outline;
        typeColor = Colors.red;
        break;
      case 'bombing_plot':
        typeIcon = Icons.warning;
        typeColor = Colors.deepPurple;
        break;
      default:
        typeIcon = Icons.tips_and_updates;
        typeColor = Colors.blue;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: typeColor.withOpacity(0.2),
          child: Icon(typeIcon, color: typeColor, size: 20),
        ),
        title: Text(
          description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        subtitle: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: typeColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                tipType.toString().replaceAll('_', ' '),
                style: TextStyle(fontSize: 11, color: typeColor),
              ),
            ),
            const SizedBox(width: 8),
            if (threatScore > 0)
              Text(
                'Threat: $threatScore%',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
          ],
        ),
      ),
    );
  })
else
  Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.grey[100],
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Center(
      child: Column(
        children: [
          Icon(Icons.update_outlined, size: 40, color: Colors.grey),
          SizedBox(height: 8),
          Text(
            'No updates available',
            style: TextStyle(color: Colors.grey),
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
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color color;

  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileView extends StatelessWidget {
  _ProfileView();

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();

    return Scaffold(
      appBar: AppBar(
        title: Text('Profile'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await authService.logout();
              if (context.mounted) {
                Navigator.of(context).pushReplacementNamed(AppRoutes.login);
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const CircleAvatar(
              radius: 48,
              backgroundColor: AppTheme.primaryColor,
              child: Icon(Icons.person, size: 48, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Text(
              authService.currentUser?.name ?? 'Emergency User',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              authService.currentUser?.email ?? 'Offline Mode',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            // Profile options
            _ProfileOption(Icons.person_outline, 'Edit Profile', () {
              _showEditProfileDialog(context, authService);
            }),
            _ProfileOption(Icons.medical_services_outlined, 'Medical Info', () {
              _showMedicalInfoDialog(context);
            }),
            _ProfileOption(Icons.contacts_outlined, 'Emergency Contacts', () {
              _showEmergencyContactsDialog(context);
            }),
            _ProfileOption(Icons.settings_outlined, 'Settings', () {
              Navigator.of(context).pushNamed(AppRoutes.settings);
            }),
            _ProfileOption(Icons.shield_outlined, 'Privacy & Security', () {
              _showPrivacySecurityDialog(context);
            }),
            _ProfileOption(Icons.info_outline, 'About', () {
              _showAboutDialog(context);
            }),
          ],
        ),
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Sectop',
      applicationVersion: '1.0.0 (Nigeria Edition)',
      applicationIcon: const Icon(Icons.security, color: AppTheme.primaryColor, size: 48),
      children: [
        const SizedBox(height: 16),
        Text(
          'A specialized emergency system designed for high-risk security environments.',
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () {
            // In a real app, use url_launcher
            debugPrint('Opening Privacy Policy...');
          },
          child: Text('Read Privacy Policy'),
        ),
      ],
    );
  }

  void _showPrivacySecurityDialog(BuildContext context) {
    final triggerService = Provider.of<HardwareTriggerService>(context, listen: false);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Privacy & Security'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: Text('Stealth Mode SOS'),
                    subtitle: Text('Silent panic trigger via hardware buttons'),
                    value: triggerService.isStealthModeEnabled,
                    onChanged: (value) {
                      triggerService.setStealthMode(value);
                      setDialogState(() {});
                    },
                    activeColor: AppTheme.primaryColor,
                  ),
                  const Divider(),
                  Text(
                    'When enabled, hardware triggers (Volume Up + Down) will send a silent SOS without showing any UI or making sound.',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('CLOSE'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditProfileDialog(BuildContext context, AuthService authService) {
    final user = authService.currentUser;
    final nameController = TextEditingController(text: user?.name ?? '');
    final emailController = TextEditingController(text: user?.email ?? '');
    final phoneController = TextEditingController(text: user?.phone ?? '');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Edit Profile'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailController,
                  decoration: InputDecoration(
                    labelText: 'Email Address',
                    prefixIcon: const Icon(Icons.email_outlined),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  decoration: InputDecoration(
                    labelText: 'Phone Number',
                    prefixIcon: const Icon(Icons.phone_outlined),
                  ),
                  keyboardType: TextInputType.phone,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () async {
                final updated = UserProfile(
                  id: user?.id ?? '',
                  name: nameController.text.trim(),
                  email: emailController.text.trim(),
                  phone: phoneController.text.trim(),
                  role: user?.role ?? AppConstants.roleCitizen,
                  emergencyContacts: user?.emergencyContacts ?? [],
                  medicalInfo: user?.medicalInfo,
                  createdAt: user?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
                );
                await authService.updateProfile(updated);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Profile updated')),
                  );
                }
              },
              child: Text('SAVE'),
            ),
          ],
        );
      },
    );
  }

  void _showMedicalInfoDialog(BuildContext context) {
    final storage = OfflineStorageService();
    String bloodType = '';
    String allergies = '';
    String medications = '';
    String conditions = '';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Load existing data
            storage.getSetting('medical_info').then((value) {
              if (value != null && value is String) {
                final data = value.split('||');
                if (data.length >= 4) {
                  bloodType = data[0];
                  allergies = data[1];
                  medications = data[2];
                  conditions = data[3];
                }
              }
            });

            return AlertDialog(
              title: Text('Medical Info'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: bloodType.isEmpty ? null : bloodType,
                      decoration: InputDecoration(
                        labelText: 'Blood Type',
                        prefixIcon: const Icon(Icons.bloodtype),
                      ),
                      items: ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']
                          .map((type) => DropdownMenuItem(
                                value: type,
                                child: Text(type),
                              ))
                          .toList(),
                      onChanged: (value) => bloodType = value ?? '',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: InputDecoration(
                        labelText: 'Allergies',
                        prefixIcon: const Icon(Icons.warning_amber_outlined),
                        hintText: 'e.g., Penicillin, Peanuts',
                      ),
                      onChanged: (value) => allergies = value,
                      controller: TextEditingController.fromValue(
                        TextEditingValue(text: allergies),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: InputDecoration(
                        labelText: 'Medications',
                        prefixIcon: const Icon(Icons.medication_outlined),
                        hintText: 'e.g., Metformin 500mg',
                      ),
                      onChanged: (value) => medications = value,
                      controller: TextEditingController.fromValue(
                        TextEditingValue(text: medications),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: InputDecoration(
                        labelText: 'Medical Conditions',
                        prefixIcon: const Icon(Icons.health_and_safety_outlined),
                        hintText: 'e.g., Diabetes, Asthma',
                      ),
                      onChanged: (value) => conditions = value,
                      controller: TextEditingController.fromValue(
                        TextEditingValue(text: conditions),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('CANCEL'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final data = '$bloodType||$allergies||$medications||$conditions';
                    await storage.saveSetting('medical_info', data);
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Medical info saved')),
                      );
                    }
                  },
                  child: Text('SAVE'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEmergencyContactsDialog(BuildContext context) {
    // Navigate to the full Emergency Contacts screen which has the enhanced
    // device contact picker, in-app user detection, and app sharing features.
    Navigator.of(context).pushNamed(AppRoutes.emergencyContacts);
  }
}

class _ProfileOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _ProfileOption(this.icon, this.title, this.onTap);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.primaryColor),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
