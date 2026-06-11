import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../../core/constants.dart';
import '../../../core/themes.dart';
import '../../../shared/services/backend_api.dart';
import '../../auth/services/auth_service.dart';
import '../../incidents/services/incident_service.dart';
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
  List<Map<String, dynamic>> _allIncidents = [];
  List<Map<String, dynamic>> _heatmapCells = [];
  Map<String, dynamic>? _selectedMarker;
  String _filterMode = 'all'; // 'all', 'safe', 'danger'
  bool _isLoading = true;
  bool _isOffline = false;
  bool _showIncidents = true;
  bool _showHeatmap = false;

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

      // Load incidents (kidnapping, terrorism, etc.)
      List<Map<String, dynamic>> incidents = [];
      List<Map<String, dynamic>> heatmap = [];
      try {
        final mapService = context.read<MapService>();
        final pos = mapService.currentPosition;
        if (pos != null) {
          final incidentService = IncidentService();
          incidents = await incidentService.getNearbyIncidents(
            latitude: pos.latitude,
            longitude: pos.longitude,
            radiusKm: 50,
          );
          heatmap = await incidentService.getHeatmapData(
            latitude: pos.latitude,
            longitude: pos.longitude,
            radiusKm: 50,
          );
        }
      } catch (e) {
        debugPrint('MapScreen: Failed to load incidents: $e');
      }

      setState(() {
        _allZones = zones;
        _allAlerts = alerts;
        _allIncidents = incidents;
        _heatmapCells = heatmap;
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
                    // Heatmap overlay (semi-transparent grid cells)
                    if (_showHeatmap && _heatmapCells.isNotEmpty)
                      PolygonLayer(
                        polygons: _buildHeatmapPolygons(),
                      ),
                    // Incident markers (kidnapping, terrorism, etc.)
                    if (_showIncidents)
                      MarkerLayer(
                        markers: _buildIncidentMarkers(),
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
                      const SizedBox(height: 8),
                      _MapControlButton(
                        icon: Icons.people_outline,
                        label: 'Incidents',
                        color: _showIncidents
                            ? Colors.deepPurple
                            : Colors.grey[700],
                        onTap: () {
                          setState(() => _showIncidents = !_showIncidents);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(_showIncidents
                                    ? 'Showing incident reports'
                                    : 'Hiding incident reports')),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      _MapControlButton(
                        icon: Icons.grid_on,
                        label: 'Heatmap',
                        color: _showHeatmap
                            ? Colors.red
                            : Colors.grey[700],
                        onTap: () {
                          setState(() => _showHeatmap = !_showHeatmap);
                          if (_showHeatmap) {
                            _loadHeatmapData();
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(_showHeatmap
                                    ? 'Showing danger heatmap'
                                    : 'Hiding heatmap')),
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

  /// Build markers for crowdsourced incidents (kidnapping, terrorism, etc.)
  List<Marker> _buildIncidentMarkers() {
    final markers = <Marker>[];
    for (final incident in _allIncidents) {
      final lat = (incident['latitude'] as num?)?.toDouble();
      final lng = (incident['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;

      final type = incident['incidentType'] as String? ?? 'other';
      final severity = incident['severity'] as String? ?? 'medium';
      final label = IncidentService.getIncidentTypeLabel(type);

      // Color based on severity
      Color markerColor;
      double opacity;
      switch (severity) {
        case 'critical':
          markerColor = Colors.red;
          opacity = 0.8;
          break;
        case 'high':
          markerColor = Colors.deepOrange;
          opacity = 0.7;
          break;
        case 'medium':
          markerColor = Colors.orange;
          opacity = 0.6;
          break;
        default:
          markerColor = Colors.amber;
          opacity = 0.5;
      }

      markers.add(
        Marker(
          point: LatLng(lat, lng),
          width: 32,
          height: 32,
          child: GestureDetector(
            onTap: () => setState(() => _selectedMarker = {
              ...incident,
              '_type': 'incident',
            }),
            child: Container(
              decoration: BoxDecoration(
                color: markerColor.withOpacity(opacity),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: markerColor.withOpacity(0.5),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  _getIncidentEmoji(type),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return markers;
  }

  /// Get emoji icon for incident type.
  String _getIncidentEmoji(String type) {
    switch (type) {
      case 'kidnapping': return '🔗';
      case 'terrorism': return '💣';
      case 'banditry': return '🔫';
      case 'armed_robbery': return '💰';
      case 'suspicious_activity': return '👁️';
      case 'herdsmen_attack': return '🐄';
      case 'cult_violence': return '⚔️';
      case 'ritual_killings': return '🕯️';
      case 'political_violence': return '🏛️';
      case 'communal_clash': return '🔥';
      case 'fire': return '🔥';
      case 'flood': return '🌊';
      case 'medical': return '🏥';
      case 'accident': return '🚗';
      default: return '⚠️';
    }
  }

  /// Build heatmap polygons from aggregated grid cell data.
  List<Polygon> _buildHeatmapPolygons() {
    final polygons = <Polygon>[];
    for (final cell in _heatmapCells) {
      final lat = (cell['latitude'] as num?)?.toDouble();
      final lng = (cell['longitude'] as num?)?.toDouble();
      final count = (cell['count'] as num?)?.toInt() ?? 0;
      final severity = cell['severity'] as String? ?? 'low';
      if (lat == null || lng == null || count == 0) continue;

      // Grid cell size ~0.01 degrees (~1km)
      const double cellSize = 0.01;
      final points = [
        LatLng(lat - cellSize, lng - cellSize),
        LatLng(lat - cellSize, lng + cellSize),
        LatLng(lat + cellSize, lng + cellSize),
        LatLng(lat + cellSize, lng - cellSize),
      ];

      // Color based on severity and count
      Color fillColor;
      if (severity == 'critical' || count >= 10) {
        fillColor = Colors.red.withOpacity(0.3);
      } else if (severity == 'high' || count >= 5) {
        fillColor = Colors.deepOrange.withOpacity(0.25);
      } else if (severity == 'medium' || count >= 3) {
        fillColor = Colors.orange.withOpacity(0.2);
      } else {
        fillColor = Colors.amber.withOpacity(0.15);
      }

      polygons.add(Polygon(
        points: points,
        color: fillColor,
        borderColor: fillColor.withOpacity(0.5),
        borderStrokeWidth: 0.5,
        isFilled: true,
      ));
    }
    return polygons;
  }

  /// Load heatmap data from the incident service.
  Future<void> _loadHeatmapData() async {
    try {
      final mapService = context.read<MapService>();
      final pos = mapService.currentPosition;
      if (pos != null) {
        final incidentService = IncidentService();
        final heatmap = await incidentService.getHeatmapData(
          latitude: pos.latitude,
          longitude: pos.longitude,
          radiusKm: 50,
        );
        if (mounted) {
          setState(() => _heatmapCells = heatmap);
        }
      }
    } catch (e) {
      debugPrint('MapScreen: Failed to load heatmap: $e');
    }
  }

  Widget _buildMarkerInfoCard() {
    final marker = _selectedMarker!;
    final markerType = marker['_type'] as String? ?? 'zone';
    final isAlert = markerType == 'alert';
    final isIncident = markerType == 'incident';

    String title;
    String status;
    String? severity;
    String? description;
    IconData icon;
    Color iconColor;

    if (isIncident) {
      final type = marker['incidentType'] as String? ?? 'other';
      title = IncidentService.getIncidentTypeLabel(type);
      status = marker['status'] as String? ?? 'reported';
      severity = marker['severity'] as String?;
      description = marker['description'] as String?;
      icon = Icons.person_pin_circle;
      iconColor = Colors.deepPurple;
    } else if (isAlert) {
      title = marker['type'] as String? ?? 'Alert';
      status = marker['status'] as String? ?? 'active';
      severity = marker['severity'] as String?;
      description = marker['description'] as String?;
      icon = Icons.warning_amber;
      iconColor = Colors.red;
    } else {
      title = marker['name'] as String? ?? 'Zone';
      status = marker['status'] as String? ?? 'active';
      severity = marker['severity'] as String?;
      description = marker['description'] as String?;
      icon = Icons.place;
      iconColor = AppTheme.primaryColor;
    }

    Color statusColor;
    switch (status) {
      case 'active':
      case 'reported':
        statusColor = Colors.red;
        break;
      case 'resolved':
      case 'verified':
        statusColor = Colors.green;
        break;
      case 'under_review':
        statusColor = Colors.orange;
        break;
      default:
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
                  icon,
                  color: iconColor,
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
            if (!isAlert && !isIncident) ...[
              const SizedBox(height: 4),
              Text(
                'Type: ${marker['type'] ?? 'unknown'}',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ],
            if (isIncident) ...[
              const SizedBox(height: 4),
              Text(
                'Upvotes: ${marker['upvoteCount'] ?? 0}',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
              if (marker['isAnonymous'] == true) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.visibility_off, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      'Reported anonymously',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                  ],
                ),
              ],
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
