import 'package:flutter/material.dart';
import '../../../core/constants.dart';
import '../../../core/routes.dart';
import '../../../core/themes.dart';
import '../../../core/localization.dart';

class ZoneDetailsScreen extends StatelessWidget {
  const ZoneDetailsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    final Map<String, dynamic> zoneData;
    if (args is Map<String, dynamic>) {
      zoneData = args;
    } else {
      zoneData = {};
    }

    final name = zoneData['name'] as String? ?? 'Unknown Zone';
    final type = zoneData['type'] as String? ?? 'unknown';
    final severity = zoneData['severity'] as String? ?? 'N/A';
    final status = zoneData['status'] as String? ?? 'unknown';
    final description = zoneData['description'] as String? ?? 'No description available.';
    final lat = (zoneData['latitude'] as num?)?.toDouble();
    final lng = (zoneData['longitude'] as num?)?.toDouble();
    final zoneColor = AppTheme.getZoneColor(type);

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        backgroundColor: zoneColor,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Zone type badge
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: zoneColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: zoneColor.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    type == 'danger'
                        ? Icons.warning
                        : type == 'safe'
                            ? Icons.check_circle
                            : Icons.info_outline,
                    color: zoneColor,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    type.toUpperCase(),
                    style: TextStyle(
                      color: zoneColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Details card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DetailRow(label: context.tr('contact_name'), value: name),
                  const Divider(),
                  _DetailRow(label: 'Type', value: type),
                  const Divider(),
                  _DetailRow(label: 'Severity', value: severity),
                  const Divider(),
                  _DetailRow(label: 'Status', value: status),
                  if (lat != null && lng != null) ...[
                    const Divider(),
                    _DetailRow(
                      label: 'Coordinates',
                      value: '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Description
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Description',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Show on map button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pushNamed(AppRoutes.map, arguments: {
                  'latitude': lat,
                  'longitude': lng,
                });
              },
              icon: const Icon(Icons.map_outlined),
              label: const Text('Show on Map'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
