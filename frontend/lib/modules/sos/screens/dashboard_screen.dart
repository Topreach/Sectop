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
import '../../../shared/services/locale_provider.dart';
import '../../auth/services/auth_service.dart';
import '../../mesh/services/mesh_manager.dart';
import '../../maps/services/map_service.dart';
import '../../../shared/services/hardware_trigger_service.dart';
import '../services/sos_service.dart';
import '../widgets/terrorist_location_card.dart';
import '../../ai/widgets/threat_awareness_card.dart';
import '../../../core/localization.dart';

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
            label: context.tr('home'),
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            activeIcon: Icon(Icons.map),
            label: context.tr('map'),
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.inbox_outlined),
            activeIcon: Icon(Icons.inbox),
            label: context.tr('inbox'),
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: context.tr('profile'),
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
  String _selectedLanguage = 'en';

  static const Map<String, String> _languages = {
    'en': 'English',
    'yo': 'Yorùbá',
    'ig': 'Igbo',
    'ha': 'Hausa',
  };

  @override
  void initState() {
    super.initState();
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedLanguage = prefs.getString('app_language') ?? 'en';
    });
  }

  Future<void> _changeLanguage(String languageCode) async {
    if (!mounted) return;
    final localeProvider = context.read<LocaleProvider>();
    await localeProvider.setLocale(
      Locale(languageCode, languageCode == 'en' ? 'US' : 'NG'),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${context.tr('language_changed_to')} ${_languages[languageCode]}')),
      );
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
        title: Text(context.tr('app_name')),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Language selector
          PopupMenuButton<String>(
            icon: const Icon(Icons.translate, color: Colors.white, size: 22),
            tooltip: context.tr('change_language'),
            onSelected: _changeLanguage,
            itemBuilder: (context) => _languages.entries.map((entry) {
              return PopupMenuItem<String>(
                value: entry.key,
                child: Row(
                  children: [
                    if (entry.key == _selectedLanguage)
                      const Icon(Icons.check, size: 18, color: AppTheme.primaryColor)
                    else
                      const SizedBox(width: 18),
                    const SizedBox(width: 8),
                    Text(entry.value),
                  ],
                ),
              );
            }).toList(),
          ),
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
                          context.tr('send_sos'),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 6,
                          ),
                        ),
                        Text(
                          context.tr('tap_emergency'),
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                          ),
                        ],
                      ),
                    ),
                  ),
              ),
              const SizedBox(height: 20),

              // Quick Actions Grid
              Text(
                context.tr('quick_actions'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              // Row 1: Existing quick actions
              Row(
                children: [
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.map_outlined,
                      label: context.tr('safe_zones'),
                      color: Colors.green,
                      onTap: () => Navigator.of(context).pushNamed(AppRoutes.map),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.wifi_tethering,
                      label: context.tr('mesh_network'),
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
                      label: context.tr('messages'),
                      color: Colors.purple,
                      onTap: () => Navigator.of(context).pushNamed(AppRoutes.inbox),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.medical_services_outlined,
                      label: context.tr('first_aid'),
                      color: Colors.orange,
                      onTap: () => Navigator.of(context).pushNamed(AppRoutes.firstAid),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Row 2: NEW - 4 Feature Quick Actions
              Text(
                context.tr('emergency_tools'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.campaign_outlined,
                      label: context.tr('broadcasts'),
                      color: Colors.red,
                      onTap: () => Navigator.of(context).pushNamed(AppRoutes.broadcasts),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.route_outlined,
                      label: context.tr('safe_route'),
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
                      label: context.tr('tip_off'),
                      color: Colors.indigo,
                      onTap: () => Navigator.of(context).pushNamed(AppRoutes.tipOff),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.radio_outlined,
                      label: context.tr('radio'),
                      color: Colors.brown,
                      onTap: () => Navigator.of(context).pushNamed(AppRoutes.radioBroadcast),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.radio,
                      label: context.tr('walkie_talkie'),
                      color: const Color(0xFFE65100),
                      onTap: () => Navigator.of(context).pushNamed(AppRoutes.walkieTalkieMonitor),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.security_outlined,
                      label: context.tr('danger_zones'),
                      color: const Color(0xFFB71C1C),
                      onTap: () => Navigator.of(context).pushNamed(AppRoutes.map),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Status Cards
              Text(
                context.tr('system_status'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              // Connection status
              _StatusCard(
                icon: isOnline ? Icons.cloud_done : Icons.cloud_off,
                title: context.tr('cloud_connection'),
                subtitle: isOnline ? context.tr('connected') : context.tr('offline'),
                color: isOnline ? Colors.green : Colors.orange,
              ),
              const SizedBox(height: 8),

              // Mesh status
              _StatusCard(
                icon: Icons.wifi_tethering,
                title: context.tr('mesh_network'),
                subtitle: '${context.tr('peers_connected')}: $peerCount',
                color: peerCount > 0 ? Colors.blue : Colors.grey,
              ),
              const SizedBox(height: 8),

              // Location status
              _StatusCard(
                icon: Icons.my_location,
                title: context.tr('location_tracking'),
                subtitle: isTracking ? context.tr('active') : context.tr('inactive'),
                color: isTracking ? Colors.green : Colors.grey,
              ),
              const SizedBox(height: 8),

              // Sync status
              _StatusCard(
                icon: Icons.sync,
                title: context.tr('data_sync'),
                subtitle: isSyncing
                    ? context.tr('syncing')
                    : '${context.tr('pending_items')}: $pendingCount',
                color: pendingCount > 0 ? Colors.orange : Colors.green,
              ),
              const SizedBox(height: 24),

              // Threat Awareness Card — Real-time intelligence monitoring
              const ThreatAwarenessCard(),

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
          SnackBar(content: Text(context.tr('sos_sent_silently')),
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

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
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
              Icon(icon, size: 32, color: color),
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
  bool _isLoadingZones = true;

  @override
  void initState() {
    super.initState();
    _loadNearbyZones();
  }

  Future<void> _loadNearbyZones() async {
    setState(() => _isLoadingZones = true);
    try {
      final mapService = context.read<MapService>();
      final position = mapService.currentPosition ??
          await mapService.getCurrentLocation();
      if (position != null) {
        final api = context.read<BackendApi>();
        final result = await api.getZonesNearby(
          position.latitude,
          position.longitude,
        );
        setState(() {
          _nearbyZones = result['zones'] is List
              ? List<Map<String, dynamic>>.from(result['zones'])
              : [];
          _isLoadingZones = false;
        });
      } else {
        setState(() => _isLoadingZones = false);
      }
    } catch (e) {
      debugPrint('_MapView: Failed to load zones: $e');
      setState(() => _isLoadingZones = false);
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
        title: Text(context.tr('map')),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.fullscreen),
            tooltip: context.tr('open_full_map'),
            onPressed: () => Navigator.of(context).pushNamed(AppRoutes.map),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: 14.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.dangeremergence.app',
                ),
                // Current location marker
                MarkerLayer(
                  markers: [
                    if (position != null)
                      Marker(
                        point: center,
                        width: 30,
                        height: 30,
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.my_location,
                            color: Colors.white,
                            size: 18,
                          ),
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
                  ],
                ),
              ],
            ),
          ),
          // Zone summary bar
          if (_isLoadingZones)
            const Padding(
              padding: EdgeInsets.all(8),
              child: LinearProgressIndicator(),
            )
          else if (_nearbyZones.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.grey[100],
              child: Row(
                children: [
                  Icon(Icons.warning_amber, size: 16, color: Colors.orange[700]),
                  const SizedBox(width: 8),
                  Text(
                    '${context.tr('zones_nearby')}: ${_nearbyZones.length}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
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

class _InboxView extends StatefulWidget {
  _InboxView();

  @override
  State<_InboxView> createState() => _InboxViewState();
}

class _InboxViewState extends State<_InboxView> {
  int _unreadCount = 0;
  int _alertCount = 0;
  List<Map<String, dynamic>> _recentMessages = [];
  bool _isLoading = true;

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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('inbox')),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: context.tr('open_inbox'),
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
                          label: context.tr('unread_messages'),
                          count: _unreadCount,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SummaryCard(
                          icon: Icons.warning_amber_outlined,
                          label: context.tr('active_alerts'),
                          count: _alertCount,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Recent messages section
                  Text(
                    context.tr('recent_messages'),
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
                          context.tr('no_recent_messages'),
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
                    label: Text(context.tr('open_inbox')),
                  ),
                ],
              ),
            ),
    );
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
        title: Text(context.tr('profile')),
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
              authService.currentUser?.name ?? context.tr('emergency_user'),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              authService.currentUser?.email ?? context.tr('offline_mode'),
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            // Profile options
            _ProfileOption(Icons.person_outline, context.tr('edit_profile'), () {
              _showEditProfileDialog(context, authService);
            }),
            _ProfileOption(Icons.medical_services_outlined, context.tr('medical_info'), () {
              _showMedicalInfoDialog(context);
            }),
            _ProfileOption(Icons.contacts_outlined, context.tr('emergency_contacts'), () {
              _showEmergencyContactsDialog(context);
            }),
            _ProfileOption(Icons.settings_outlined, context.tr('settings'), () {
              Navigator.of(context).pushNamed(AppRoutes.settings);
            }),
            _ProfileOption(Icons.shield_outlined, context.tr('privacy_security'), () {
              _showPrivacySecurityDialog(context);
            }),
            _ProfileOption(Icons.info_outline, context.tr('about'), () {
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
          context.tr('app_description'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () {
            // In a real app, use url_launcher
            debugPrint('Opening Privacy Policy...');
          },
          child: Text(context.tr('read_privacy_policy')),
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
              title: Text(context.tr('privacy_security_title')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: Text(context.tr('stealth_mode_sos')),
                    subtitle: Text(context.tr('silent_panic_trigger')),
                    value: triggerService.isStealthModeEnabled,
                    onChanged: (value) {
                      triggerService.setStealthMode(value);
                      setDialogState(() {});
                    },
                    activeColor: AppTheme.primaryColor,
                  ),
                  const Divider(),
                  Text(
                    context.tr('stealth_mode_description'),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.tr('close_action')),
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
          title: Text(context.tr('edit_profile_title')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: context.tr('full_name'),
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailController,
                  decoration: InputDecoration(
                    labelText: context.tr('email_address'),
                    prefixIcon: const Icon(Icons.email_outlined),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  decoration: InputDecoration(
                    labelText: context.tr('phone_number'),
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
              child: Text(context.tr('cancel_action')),
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
                    SnackBar(content: Text(context.tr('profile_updated'))),
                  );
                }
              },
              child: Text(context.tr('save_action')),
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
              title: Text(context.tr('medical_info_title')),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: bloodType.isEmpty ? null : bloodType,
                      decoration: InputDecoration(
                        labelText: context.tr('blood_type'),
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
                        labelText: context.tr('allergies'),
                        prefixIcon: const Icon(Icons.warning_amber_outlined),
                        hintText: context.tr('allergies_hint'),
                      ),
                      onChanged: (value) => allergies = value,
                      controller: TextEditingController.fromValue(
                        TextEditingValue(text: allergies),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: InputDecoration(
                        labelText: context.tr('medications'),
                        prefixIcon: const Icon(Icons.medication_outlined),
                        hintText: context.tr('medications_hint'),
                      ),
                      onChanged: (value) => medications = value,
                      controller: TextEditingController.fromValue(
                        TextEditingValue(text: medications),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: InputDecoration(
                        labelText: context.tr('medical_conditions'),
                        prefixIcon: const Icon(Icons.health_and_safety_outlined),
                        hintText: context.tr('conditions_hint'),
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
                  child: Text(context.tr('cancel_action')),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final data = '$bloodType||$allergies||$medications||$conditions';
                    await storage.saveSetting('medical_info', data);
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(context.tr('medical_info_saved'))),
                      );
                    }
                  },
                  child: Text(context.tr('save_action')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEmergencyContactsDialog(BuildContext context) {
    final storage = OfflineStorageService();
    List<Map<String, String>> contacts = [];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Load existing contacts
            storage.getSetting('emergency_contacts').then((value) {
              if (value != null && value is String) {
                final decoded = json.decode(value) as List;
                contacts = decoded.map((e) => Map<String, String>.from(e)).toList();
              }
            });

            return AlertDialog(
              title: Text(context.tr('emergency_contacts_title')),
              content: SizedBox(
                width: double.maxFinite,
                child: contacts.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          context.tr('no_emergency_contacts'),
                          style: const TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: contacts.length,
                        itemBuilder: (context, index) {
                          final contact = contacts[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppTheme.primaryColor,
                              child: const Icon(Icons.person, color: Colors.white, size: 20),
                            ),
                            title: Text(contact['name'] ?? ''),
                            subtitle: Text(contact['phone'] ?? ''),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 18),
                                  onPressed: () {
                                    _showAddEditContactDialog(
                                      context,
                                      (updatedContact) {
                                        contacts[index] = updatedContact;
                                        _saveContacts(storage, contacts);
                                        setDialogState(() {});
                                      },
                                      initialData: contact,
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                                  onPressed: () {
                                    contacts.removeAt(index);
                                    _saveContacts(storage, contacts);
                                    setDialogState(() {});
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.tr('close_action')),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    _showAddEditContactDialog(
                      context,
                      (newContact) {
                        contacts.add(newContact);
                        _saveContacts(storage, contacts);
                        setDialogState(() {});
                      },
                    );
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(context.tr('add_contact_title')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAddEditContactDialog(
    BuildContext context,
    void Function(Map<String, String>) onSave, {
    Map<String, String>? initialData,
  }) {
    final nameController = TextEditingController(text: initialData?['name'] ?? '');
    final phoneController = TextEditingController(text: initialData?['phone'] ?? '');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(initialData != null ? context.tr('edit_contact') : context.tr('add_contact_title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: context.tr('full_name'),
                  prefixIcon: const Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                decoration: InputDecoration(
                  labelText: context.tr('phone_number'),
                  prefixIcon: const Icon(Icons.phone_outlined),
                ),
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr('cancel_action')),
            ),
            ElevatedButton(
              onPressed: () {
                onSave({
                  'name': nameController.text.trim(),
                  'phone': phoneController.text.trim(),
                });
                Navigator.pop(context);
              },
              child: Text(context.tr('save_action')),
            ),
          ],
        );
      },
    );
  }

  void _saveContacts(OfflineStorageService storage, List<Map<String, String>> contacts) {
    storage.saveSetting('emergency_contacts', json.encode(contacts));
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
