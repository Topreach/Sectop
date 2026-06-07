import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants.dart';
import '../../../core/routes.dart';
import '../../../core/themes.dart';
import '../../../shared/services/sync_manager.dart';
import '../../auth/services/auth_service.dart';
import '../../mesh/services/mesh_manager.dart';
import '../../maps/services/map_service.dart';
import '../../../shared/services/hardware_trigger_service.dart';

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

class _DashboardHome extends StatelessWidget {
  const _DashboardHome();

  @override
  Widget build(BuildContext context) {
    final syncManager = context.watch<SyncManager>();
    final meshManager = context.watch<MeshManager>();
    final mapService = context.watch<MapService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Danger Emergence'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Sync status indicator
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(
              syncManager.isOnline ? Icons.cloud_done : Icons.cloud_off,
              color: syncManager.isOnline ? Colors.green[300] : Colors.orange[300],
              size: 20,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => syncManager.triggerSync(),
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
                      onTap: () {
                        // Switch to inbox tab
                        final dashboard = context.findAncestorStateOfType<State>();
                        dashboard?.setState(() {});
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.medical_services_outlined,
                      label: 'First Aid',
                      color: Colors.orange,
                      onTap: () => Navigator.of(context).pushNamed(AppRoutes.offlineResources),
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
                icon: syncManager.isOnline ? Icons.cloud_done : Icons.cloud_off,
                title: 'Cloud Connection',
                subtitle: syncManager.isOnline ? 'Connected' : 'Offline',
                color: syncManager.isOnline ? Colors.green : Colors.orange,
              ),
              const SizedBox(height: 8),

              // Mesh status
              _StatusCard(
                icon: Icons.wifi_tethering,
                title: 'Mesh Network',
                subtitle: '${meshManager.discoveredPeers.length} peers connected',
                color: meshManager.discoveredPeers.isNotEmpty ? Colors.blue : Colors.grey,
              ),
              const SizedBox(height: 8),

              // Location status
              _StatusCard(
                icon: Icons.my_location,
                title: 'Location Tracking',
                subtitle: mapService.isTracking ? 'Active' : 'Inactive',
                color: mapService.isTracking ? Colors.green : Colors.grey,
              ),
              const SizedBox(height: 8),

              // Sync status
              _StatusCard(
                icon: Icons.sync,
                title: 'Data Sync',
                subtitle: syncManager.isSyncing
                    ? 'Syncing...'
                    : '${syncManager.pendingCount} pending items',
                color: syncManager.pendingCount > 0 ? Colors.orange : Colors.green,
              ),
              const SizedBox(height: 24),

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

class _MapView extends StatelessWidget {
  const _MapView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Map'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: const Center(
        child: Text('Map View - Implement with flutter_map'),
      ),
    );
  }
}

class _InboxView extends StatelessWidget {
  const _InboxView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inbox'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: const Center(
        child: Text('Inbox - Messages and alerts'),
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
            _ProfileOption(Icons.person_outline, 'Edit Profile', () {}),
            _ProfileOption(Icons.medical_services_outlined, 'Medical Info', () {}),
            _ProfileOption(Icons.contacts_outlined, 'Emergency Contacts', () {}),
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
      applicationName: 'Danger Emergence',
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
