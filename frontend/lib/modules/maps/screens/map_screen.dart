import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../../core/constants.dart';
import '../../../core/themes.dart';
import '../../../shared/services/backend_api.dart';
import '../../auth/services/auth_service.dart';
import '../services/map_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({Key? key}) : super(key: key);

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  List<Map<String, dynamic>> _allZones = [];
  List<Map<String, dynamic>> _allAlerts = [];
  Map<String, dynamic>? _selectedMarker;
  String _filterMode = 'all'; // 'all', 'safe', 'danger'
  bool _isLoading = true;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final api = context.read<BackendApi>();
      final results = await Future.wait([
        api.getDangerZones(),
        api.getActiveZones(),
        api.getActiveAlerts(),
      ], eagerError: false);

      final dangerZones = results[0];
      final activeZones = results[1];
      final activeAlerts = results[2];

      final List<Map<String, dynamic>> zones = [];
      if (dangerZones['zones'] is List) {
        zones.addAll(List<Map<String, dynamic>>.from(dangerZones['zones']));
      }
      if (activeZones['zones'] is List) {
        // Merge active zones, avoiding duplicates
        for (final z in activeZones['zones'] as List) {
          final zMap = z as Map<String, dynamic>;
          final exists = zones.any((e) => e['id'] == zMap['id']);
          if (!exists) zones.add(zMap);
        }
      }

      final List<Map<String, dynamic>> alerts = [];
      if (activeAlerts['alerts'] is List) {
        alerts.addAll(List<Map<String, dynamic>>.from(activeAlerts['alerts']));
      }

      setState(() {
        _allZones = zones;
        _allAlerts = alerts;
        _isLoading = false;
        _isOffline = false;
      });
    } catch (e) {
      debugPrint('MapScreen: Failed to load data: $e');
      setState(() {
        _isLoading = false;
        _isOffline = true;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredZones {
    if (_filterMode == 'all') return _allZones;
    return _allZones.where((z) => z['type'] == _filterMode).toList();
  }

  void _showCreateZoneDialog(BuildContext context) {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    String selectedType = 'danger';
    String selectedSeverity = 'medium';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report Zone'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Zone Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
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
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedSeverity,
                decoration: const InputDecoration(
                  labelText: 'Severity',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'low', child: Text('Low')),
                  DropdownMenuItem(value: 'medium', child: Text('Medium')),
                  DropdownMenuItem(value: 'high', child: Text('High')),
                  DropdownMenuItem(value: 'critical', child: Text('Critical')),
                ],
                onChanged: (value) => selectedSeverity = value!,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final mapService = context.read<MapService>();
              final pos = mapService.currentPosition;
              if (pos == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Location not available')),
                );
                return;
              }
              try {
                await context.read<BackendApi>().createZone({
                  'name': nameController.text,
                  'type': selectedType,
                  'description': descriptionController.text,
                  'latitude': pos.latitude,
                  'longitude': pos.longitude,
                  'radius': AppConstants.geofenceDefaultRadius,
                  'severity': selectedSeverity,
                  'status': 'active',
                });
                if (context.mounted) Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Zone reported successfully')),
                );
                _loadData();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to report zone: $e')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Report'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mapService = context.watch<MapService>();
    final currentPos = mapService.currentPosition;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Map'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        actions: [
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
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: currentPos != null
                        ? LatLng(currentPos.latitude, currentPos.longitude)
                        : const LatLng(0, 0),
                    initialZoom: AppConstants.defaultMapZoom,
                    onTap: (_, __) => setState(() => _selectedMarker = null),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: AppConstants.packageName,
                    ),
                    // Current location marker
                    if (currentPos != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(
                                currentPos.latitude, currentPos.longitude),
                            width: 30,
                            height: 30,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Colors.white, width: 3),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.blue.withOpacity(0.4),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    // Zone markers
                    MarkerLayer(
                      markers: _buildZoneMarkers(),
                    ),
                    // Alert markers
                    MarkerLayer(
                      markers: _buildAlertMarkers(),
                    ),
                    // Offline banner
                    if (_isOffline)
                      const Align(
                        alignment: Alignment.topCenter,
                        child: Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Card(
                            color: Colors.orange,
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.cloud_off,
                                      color: Colors.white, size: 18),
                                  SizedBox(width: 8),
                                  Text('Offline - showing cached data',
                                      style: TextStyle(color: Colors.white)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
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
                        color: _filterMode == 'safe'
                            ? Colors.green
                            : Colors.grey[700],
                        onTap: () {
                          setState(() {
                            _filterMode =
                                _filterMode == 'safe' ? 'all' : 'safe';
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(_filterMode == 'safe'
                                    ? 'Showing safe zones'
                                    : 'Showing all zones')),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      _MapControlButton(
                        icon: Icons.warning_outlined,
                        label: 'Danger Zones',
                        color: _filterMode == 'danger'
                            ? Colors.red
                            : Colors.grey[700],
                        onTap: () {
                          setState(() {
                            _filterMode =
                                _filterMode == 'danger' ? 'all' : 'danger';
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(_filterMode == 'danger'
                                    ? 'Showing danger zones'
                                    : 'Showing all zones')),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                // Bottom info card
                if (_selectedMarker != null)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: _buildMarkerInfoCard(),
                  )
                else
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
                                    color: AppTheme.primaryColor, size: 20),
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

  List<Marker> _buildZoneMarkers() {
    final markers = <Marker>[];
    for (final zone in _filteredZones) {
      final lat = (zone['latitude'] as num).toDouble();
      final lng = (zone['longitude'] as num).toDouble();
      final type = zone['type'] as String? ?? 'unknown';
      final name = zone['name'] as String? ?? 'Zone';

      Color markerColor;
      if (type == 'danger') {
        markerColor = Colors.red;
      } else if (type == 'safe') {
        markerColor = Colors.green;
      } else {
        markerColor = Colors.orange;
      }

      markers.add(
        Marker(
          point: LatLng(lat, lng),
          width: 40,
          height: 40,
          child: GestureDetector(
            onTap: () => setState(() => _selectedMarker = {
              ...zone,
              '_type': 'zone',
            }),
            child: Container(
              decoration: BoxDecoration(
                color: markerColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: markerColor.withOpacity(0.4),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'Z',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return markers;
  }

  List<Marker> _buildAlertMarkers() {
    final markers = <Marker>[];
    for (final alert in _allAlerts) {
      final lat = (alert['latitude'] as num?)?.toDouble();
      final lng = (alert['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;

      markers.add(
        Marker(
          point: LatLng(lat, lng),
          width: 36,
          height: 36,
          child: GestureDetector(
            onTap: () => setState(() => _selectedMarker = {
              ...alert,
              '_type': 'alert',
            }),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.6),
                    blurRadius: 10,
                    spreadRadius: 3,
                  ),
                ],
              ),
              child: const Center(
                child: Icon(Icons.warning, color: Colors.white, size: 18),
              ),
            ),
          ),
        ),
      );
    }
    return markers;
  }

  Widget _buildMarkerInfoCard() {
    final marker = _selectedMarker!;
    final isAlert = marker['_type'] == 'alert';
    final title = isAlert
        ? (marker['type'] as String? ?? 'Alert')
        : (marker['name'] as String? ?? 'Zone');
    final status = marker['status'] as String? ?? 'active';
    final severity = marker['severity'] as String?;
    final description = marker['description'] as String?;

    Color statusColor;
    if (status == 'active') {
      statusColor = Colors.red;
    } else if (status == 'resolved') {
      statusColor = Colors.green;
    } else {
      statusColor = Colors.orange;
    }

    return Card(
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
                Icon(
                  isAlert ? Icons.warning_amber : Icons.place,
                  color: isAlert ? Colors.red : AppTheme.primaryColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            if (severity != null) ...[
              const SizedBox(height: 4),
              Text(
                'Severity: $severity',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ],
            if (description != null && description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ],
            if (!isAlert) ...[
              const SizedBox(height: 4),
              Text(
                'Type: ${marker['type'] ?? 'unknown'}',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ],
          ],
        ),
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
          backgroundColor: color ?? AppTheme.primaryColor,
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
