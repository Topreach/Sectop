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
import '../widgets/terrorist_location_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const _DashboardHome(),
    const _MapView(),
    const _InboxView(),
    const _ProfileView(),
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
        items: const [
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
  const _DashboardHome();

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
        SnackBar(content: Text('Language changed to ${_languages[languageCode]}')),
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
        title: const Text('Sectop'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Language selector
          PopupMenuButton<String>(
            icon: const Icon(Icons.translate, color: Colors.white, size: 22),
            tooltip: 'Change Language',
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
                  Navigator.of(context).pushNamed(AppRoutes.sos);
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
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 64, color: Colors.white),
                        SizedBox(height: 8),
                        Text(
                          'SEND SOS',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 6,
                          ),
                        ),
                        Text(
                          'Tap for emergency alert',
                          style: TextStyle(
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
              const Text(
                'Quick Actions',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
              const Text(
                'Emergency Tools',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                      label: 'Tip-Off',
                      color: Colors.indigo,
                      onTap: () => Navigator.of(context).pushNamed(AppRoutes.tipOff),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.radio_outlined,
                      label: 'Radio',
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
                      label: 'Walkie-Talkie',
                      color: const Color(0xFFE65100),
                      onTap: () => Navigator.of(context).pushNamed(AppRoutes.walkieTalkieMonitor),
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
              const SizedBox(height: 24),

              // Status Cards
              const Text(
                'System Status',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                subtitle: '$peerCount peers connected',
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
                    : '$pendingCount pending items',
                color: pendingCount > 0 ? Colors.orange : Colors.green,
              ),
              const SizedBox(height: 24),

              // Terrorist / Danger Location Finder
              const TerroristLocationCard(),

              // Recent Alerts
              const Text(
                'Recent Alerts',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text(
                    'No recent alerts',
                    style: TextStyle(color: Colors.grey),
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
  const _MapView();

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
        title: const Text('Map'),
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
                    '${_nearbyZones.length} zone(s) nearby',
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
  const _InboxView();

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
        title: const Text('Inbox'),
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
                  const Text(
                    'Recent Messages',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),

                  if (_recentMessages.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Text(
                          'No recent messages',
                          style: TextStyle(color: Colors.grey),
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
                    label: const Text('Open Inbox'),
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
  const _ProfileView();

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
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
        const Text(
          'A specialized emergency system designed for high-risk security environments.',
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () {
            // In a real app, use url_launcher
            debugPrint('Opening Privacy Policy...');
          },
          child: const Text('Read Privacy Policy'),
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
              title: const Text('Privacy & Security'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: const Text('Stealth Mode SOS'),
                    subtitle: const Text('Silent panic trigger via hardware buttons'),
                    value: triggerService.isStealthModeEnabled,
                    onChanged: (value) {
                      triggerService.setStealthMode(value);
                      setDialogState(() {});
                    },
                    activeColor: AppTheme.primaryColor,
                  ),
                  const Divider(),
                  const Text(
                    'When enabled, hardware triggers (Volume Up + Down) will send a silent SOS without showing any UI or making sound.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CLOSE'),
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
          title: const Text('Edit Profile'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Phone',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  keyboardType: TextInputType.phone,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
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
                    const SnackBar(content: Text('Profile updated')),
                  );
                }
              },
              child: const Text('SAVE'),
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
              title: const Text('Medical Info'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: bloodType.isEmpty ? null : bloodType,
                      decoration: const InputDecoration(
                        labelText: 'Blood Type',
                        prefixIcon: Icon(Icons.bloodtype),
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
                      decoration: const InputDecoration(
                        labelText: 'Allergies',
                        prefixIcon: Icon(Icons.warning_amber_outlined),
                        hintText: 'e.g., Penicillin, Peanuts',
                      ),
                      onChanged: (value) => allergies = value,
                      controller: TextEditingController.fromValue(
                        TextEditingValue(text: allergies),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Medications',
                        prefixIcon: Icon(Icons.medication_outlined),
                        hintText: 'e.g., Metformin 500mg',
                      ),
                      onChanged: (value) => medications = value,
                      controller: TextEditingController.fromValue(
                        TextEditingValue(text: medications),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Medical Conditions',
                        prefixIcon: Icon(Icons.health_and_safety_outlined),
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
                  child: const Text('CANCEL'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final data = '$bloodType||$allergies||$medications||$conditions';
                    await storage.saveSetting('medical_info', data);
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Medical info saved')),
                      );
                    }
                  },
                  child: const Text('SAVE'),
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
              title: const Text('Emergency Contacts'),
              content: SizedBox(
                width: double.maxFinite,
                child: contacts.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No emergency contacts added yet.',
                          style: TextStyle(color: Colors.grey),
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
                  child: const Text('CLOSE'),
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
                  label: const Text('Add Contact'),
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
          title: Text(initialData != null ? 'Edit Contact' : 'Add Contact'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () {
                onSave({
                  'name': nameController.text.trim(),
                  'phone': phoneController.text.trim(),
                });
                Navigator.pop(context);
              },
              child: const Text('SAVE'),
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
