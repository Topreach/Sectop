import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants.dart';
import '../services/map_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({Key? key}) : super(key: key);

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  @override
  Widget build(BuildContext context) {
    final mapService = context.watch<MapService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Map'),
        backgroundColor: AppConstants.emergencyRed,
        foregroundColor: Colors.white,
        actions: [
          // Location tracking toggle
          IconButton(
            icon: Icon(
              mapService.isTracking
                  ? Icons.my_location
                  : Icons.my_location_outlined,
              color: mapService.isTracking ? Colors.green[300] : null,
            ),
            onPressed: () {
              if (mapService.isTracking) {
                mapService.stopLocationTracking();
              } else {
                mapService.startLocationTracking();
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Map placeholder - replace with flutter_map or google_maps_flutter
          Container(
            color: Colors.grey[200],
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.map, size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'Map View',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Integrate with flutter_map or google_maps_flutter',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 24),
                  if (mapService.currentLocation != null) ...[
                    Text(
                      'Current Location:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${mapService.currentLocation!.latitude.toStringAsFixed(6)}, '
                      '${mapService.currentLocation!.longitude.toStringAsFixed(6)}',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Zone overlay controls
          Positioned(
            right: 16,
            top: 16,
            child: Column(
              children: [
                _MapControlButton(
                  icon: Icons.add,
                  label: 'Report Zone',
                  onTap: () => _showCreateZoneDialog(context),
                ),
                const SizedBox(height: 8),
                _MapControlButton(
                  icon: Icons.shield_outlined,
                  label: 'Safe Zones',
                  color: Colors.green,
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Showing safe zones')),
                    );
                  },
                ),
                const SizedBox(height: 8),
                _MapControlButton(
                  icon: Icons.warning_outlined,
                  label: 'Danger Zones',
                  color: Colors.red,
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Showing danger zones')),
                    );
                  },
                ),
              ],
            ),
          ),

          // Bottom info card
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: AppConstants.emergencyRed, size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'Zone Information',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap a zone on the map to view details. '
                      'Use the buttons on the right to filter zones.',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateZoneDialog(BuildContext context) {
    final nameController = TextEditingController();
    String selectedType = 'danger';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report Zone'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Zone Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: selectedType,
              decoration: const InputDecoration(
                labelText: 'Zone Type',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'danger', child: Text('Danger Zone')),
                DropdownMenuItem(value: 'safe', child: Text('Safe Zone')),
                DropdownMenuItem(value: 'restricted', child: Text('Restricted')),
              ],
              onChanged: (value) => selectedType = value!,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              // Create zone with current location
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Zone reported successfully')),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.emergencyRed,
              foregroundColor: Colors.white,
            ),
            child: const Text('Report'),
          ),
        ],
      ),
    );
  }
}

class _MapControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _MapControlButton({
    required this.icon,
    required this.label,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.small(
          heroTag: label,
          onPressed: onTap,
          backgroundColor: color ?? AppConstants.emergencyRed,
          child: Icon(icon, color: Colors.white),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[700],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
