import 'package:flutter/material.dart';
import '../../../core/constants.dart';
import '../../../core/themes.dart';

class OfflineResourcesScreen extends StatelessWidget {
  const OfflineResourcesScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline Resources'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // First Aid Section
          _ResourceSection(
            title: 'First Aid',
            icon: Icons.medical_services_outlined,
            color: Colors.red,
            items: [
              _ResourceItem(
                title: 'CPR Guide',
                subtitle: 'Step-by-step CPR instructions',
                icon: Icons.favorite_outline,
              ),
              _ResourceItem(
                title: 'Wound Care',
                subtitle: 'Treating cuts, burns, and fractures',
                icon: Icons.healing_outlined,
              ),
              _ResourceItem(
                title: 'Emergency Kit',
                subtitle: 'Essential items checklist',
                icon: Icons.inventory_2_outlined,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Survival Guide
          _ResourceSection(
            title: 'Survival Guide',
            icon: Icons.lightbulb_outline,
            color: Colors.orange,
            items: [
              _ResourceItem(
                title: 'Shelter Building',
                subtitle: 'Emergency shelter construction',
                icon: Icons.roofing_outlined,
              ),
              _ResourceItem(
                title: 'Water Purification',
                subtitle: 'Safe drinking water methods',
                icon: Icons.water_drop_outlined,
              ),
              _ResourceItem(
                title: 'Fire Starting',
                subtitle: 'Fire-making techniques',
                icon: Icons.local_fire_department_outlined,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Communication
          _ResourceSection(
            title: 'Communication',
            icon: Icons.wifi_tethering,
            color: Colors.blue,
            items: [
              _ResourceItem(
                title: 'Mesh Network Guide',
                subtitle: 'How to use peer-to-peer mesh',
                icon: Icons.wifi_tethering,
              ),
              _ResourceItem(
                title: 'Emergency Signals',
                subtitle: 'Visual and audio distress signals',
                icon: Icons.signal_wifi_4_bar,
              ),
              _ResourceItem(
                title: 'Radio Frequencies',
                subtitle: 'Emergency broadcast channels',
                icon: Icons.radio_outlined,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Emergency Contacts
          _ResourceSection(
            title: 'Emergency Contacts',
            icon: Icons.contacts_outlined,
            color: Colors.green,
            items: [
              _ResourceItem(
                title: 'Local Emergency Services',
                subtitle: 'Police, Fire, Ambulance',
                icon: Icons.local_police_outlined,
              ),
              _ResourceItem(
                title: 'Disaster Hotlines',
                subtitle: 'National disaster response',
                icon: Icons.phone_outlined,
              ),
              _ResourceItem(
                title: 'Nearby Shelters',
                subtitle: 'Pre-loaded shelter locations',
                icon: Icons.location_city_outlined,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Offline Data
          _ResourceSection(
            title: 'Offline Data',
            icon: Icons.storage_outlined,
            color: Colors.purple,
            items: [
              _ResourceItem(
                title: 'Cached Maps',
                subtitle: 'Downloaded map regions',
                icon: Icons.map_outlined,
              ),
              _ResourceItem(
                title: 'Emergency Protocols',
                subtitle: 'Pre-loaded response plans',
                icon: Icons.description_outlined,
              ),
              _ResourceItem(
                title: 'Medical Records',
                subtitle: 'Your stored medical information',
                icon: Icons.folder_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResourceSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<_ResourceItem> items;

  const _ResourceSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          ...items.map((item) => ListTile(
                leading: Icon(item.icon, color: color.withOpacity(0.7)),
                title: Text(item.title),
                subtitle: Text(item.subtitle),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Opening ${item.title}...'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              )),
        ],
      ),
    );
  }
}

class _ResourceItem {
  final String title;
  final String subtitle;
  final IconData icon;

  const _ResourceItem({
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}
