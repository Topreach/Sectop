import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants.dart';
import '../../../shared/services/offline_storage.dart';
import '../../mesh/services/mesh_manager.dart';

/// Map Service - Handles offline maps, geofencing, and zone management.
/// Uses vector tiles (PMTiles format) for offline map rendering.
class MapService extends ChangeNotifier {
  static final MapService _instance = MapService._internal();
  factory MapService() => _instance;
  MapService._internal();

  final OfflineStorageService _storage = OfflineStorageService();
  final MeshManager _meshManager = MeshManager();
  final Uuid _uuid = const Uuid();

  List<Zone> _activeZones = [];
  List<Zone> _nearbyZones = [];
  Position? _currentPosition;
  bool _isTracking = false;
  StreamSubscription<Position>? _positionSubscription;

  List<Zone> get activeZones => _activeZones;
  List<Zone> get nearbyZones => _nearbyZones;
  Position? get currentPosition => _currentPosition;
  bool get isTracking => _isTracking;

  /// Initialize map service and load cached zones.
  Future<void> initialize() async {
    final zones = await _storage.query('zones',
        where: 'status = ?',
        whereArgs: ['active'],
        orderBy: 'created_at DESC');
    _activeZones = zones.map((z) => Zone.fromMap(z)).toList();
    notifyListeners();
  }

  /// Start tracking the user's location.
  Future<void> startLocationTracking() async {
    if (_isTracking) return;

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        _positionSubscription = Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10, // Update every 10 meters
          ),
        ).listen((Position position) {
          _currentPosition = position;
          _checkNearbyZones(position);
          notifyListeners();
        });

        _isTracking = true;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Location tracking error: $e');
    }
  }

  /// Stop location tracking.
  void stopLocationTracking() {
    _positionSubscription?.cancel();
    _isTracking = false;
    notifyListeners();
  }

  /// Check for nearby zones and trigger alerts.
  Future<void> _checkNearbyZones(Position position) async {
    final nearby = await _storage.getZonesNearLocation(
      position.latitude,
      position.longitude,
      radiusKm: 1.0,
    );

    _nearbyZones = nearby.map((z) => Zone.fromMap(z)).toList();

    // Check for zone entry/exit
    for (final zone in _nearbyZones) {
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        zone.latitude,
        zone.longitude,
      );

      if (distance <= zone.radius) {
        // User entered a zone
        _onZoneEntered(zone);
      }
    }

    notifyListeners();
  }

  /// Handle zone entry events.
  void _onZoneEntered(Zone zone) {
    debugPrint('Entered zone: ${zone.name} (${zone.type})');
    // In production, trigger local notification and mesh broadcast
  }

  /// Create a new zone (safe/danger/evacuation).
  Future<Zone> createZone({
    required String name,
    required String type,
    String? description,
    required double latitude,
    required double longitude,
    double radius = AppConstants.geofenceDefaultRadius,
    String? severity,
    String? createdBy,
    int? expiresAt,
  }) async {
    final zone = Zone(
      id: _uuid.v4(),
      name: name,
      type: type,
      description: description,
      latitude: latitude,
      longitude: longitude,
      radius: radius,
      severity: severity,
      status: ZoneStatus.active,
      createdBy: createdBy,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      expiresAt: expiresAt,
    );

    await _storage.saveZone(zone.toMap());
    _activeZones.insert(0, zone);

    // Broadcast zone update via mesh
    await _meshManager.broadcastMessage(
      type: MessageType.zoneUpdate,
      payload: zone.toMap(),
      priority: MessagePriority.high,
    );

    notifyListeners();
    return zone;
  }

  /// Update an existing zone.
  Future<void> updateZone(Zone zone) async {
    final updatedZone = zone.copyWith(
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    await _storage.update('zones', updatedZone.toMap(),
        where: 'id = ?', whereArgs: [zone.id]);

    final index = _activeZones.indexWhere((z) => z.id == zone.id);
    if (index >= 0) {
      _activeZones[index] = updatedZone;
    }

    notifyListeners();
  }

  /// Deactivate a zone.
  Future<void> deactivateZone(String zoneId) async {
    await _storage.update('zones', {
      'status': 'inactive',
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, where: 'id = ?', whereArgs: [zoneId]);

    _activeZones.removeWhere((z) => z.id == zoneId);
    notifyListeners();
  }

  /// Get zones by type.
  List<Zone> getZonesByType(String type) {
    return _activeZones.where((z) => z.type == type).toList();
  }

  /// Get danger zones (for alerting).
  List<Zone> get dangerZones =>
      getZonesByType(AppConstants.zoneTypeDanger);

  /// Get safe zones (for evacuation).
  List<Zone> get safeZones =>
      getZonesByType(AppConstants.zoneTypeSafe);

  /// Get evacuation zones.
  List<Zone> get evacuationZones =>
      getZonesByType(AppConstants.zoneTypeEvacuation);

  /// Get medical zones.
  List<Zone> get medicalZones =>
      getZonesByType(AppConstants.zoneTypeMedical);

  /// Preload offline map tiles for a region.
  Future<void> preloadMapRegion({
    required double latitude,
    required double longitude,
    required double radiusKm,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final mapDir = Directory('${dir.path}/${AppConstants.mapsDirectory}');
      if (!await mapDir.exists()) {
        await mapDir.create(recursive: true);
      }

      // In production, download PMTiles vector tiles for the region
      // and store routing graphs for offline navigation
      debugPrint('Preloading map region: $latitude, $longitude ($radiusKm km)');
    } catch (e) {
      debugPrint('Map preload error: $e');
    }
  }

  /// Calculate safe evacuation route to nearest safe zone.
  Future<List<Map<String, double>>> calculateEvacuationRoute({
    required double fromLat,
    required double fromLon,
  }) async {
    // Find nearest safe zone
    Zone? nearestSafeZone;
    double minDistance = double.infinity;

    for (final zone in safeZones) {
      final distance = Geolocator.distanceBetween(
        fromLat, fromLon,
        zone.latitude, zone.longitude,
      );
      if (distance < minDistance) {
        minDistance = distance;
        nearestSafeZone = zone;
      }
    }

    if (nearestSafeZone == null) return [];

    // In production, use offline routing engine (e.g., GraphHopper)
    // For now, return direct line path
    return [
      {'lat': fromLat, 'lon': fromLon},
      {'lat': nearestSafeZone.latitude, 'lon': nearestSafeZone.longitude},
    ];
  }

  /// Get current location as a position.
  Future<Position?> getCurrentLocation() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      debugPrint('Get location error: $e');
      return null;
    }
  }

  @override
  void dispose() {
    stopLocationTracking();
    super.dispose();
  }
}

/// Zone model for safe/danger/evacuation areas.
class Zone {
  final String id;
  final String name;
  final String type;
  final String? description;
  final double latitude;
  final double longitude;
  final double radius;
  final String? geometry; // GeoJSON polygon for complex shapes
  final String? severity;
  final ZoneStatus status;
  final String? createdBy;
  final int createdAt;
  final int? updatedAt;
  final int? expiresAt;

  Zone({
    required this.id,
    required this.name,
    required this.type,
    this.description,
    required this.latitude,
    required this.longitude,
    this.radius = AppConstants.geofenceDefaultRadius,
    this.geometry,
    this.severity,
    this.status = ZoneStatus.active,
    this.createdBy,
    required this.createdAt,
    this.updatedAt,
    this.expiresAt,
  });

  factory Zone.fromMap(Map<String, dynamic> map) {
    return Zone(
      id: map['id'] as String,
      name: map['name'] as String,
      type: map['type'] as String,
      description: map['description'] as String?,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      radius: (map['radius'] as num?)?.toDouble() ?? AppConstants.geofenceDefaultRadius,
      geometry: map['geometry'] as String?,
      severity: map['severity'] as String?,
      status: ZoneStatus.values.firstWhere(
        (s) => s.name == map['status'],
        orElse: () => ZoneStatus.active,
      ),
      createdBy: map['created_by'] as String?,
      createdAt: map['created_at'] as int,
      updatedAt: map['updated_at'] as int?,
      expiresAt: map['expires_at'] as int?,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'type': type,
    'description': description,
    'latitude': latitude,
    'longitude': longitude,
    'radius': radius,
    'geometry': geometry,
    'severity': severity,
    'status': status.name,
    'created_by': createdBy,
    'created_at': createdAt,
    'updated_at': updatedAt ?? createdAt,
    'expires_at': expiresAt,
  };

  Zone copyWith({
    String? id,
    String? name,
    String? type,
    String? description,
    double? latitude,
    double? longitude,
    double? radius,
    String? geometry,
    String? severity,
    ZoneStatus? status,
    String? createdBy,
    int? createdAt,
    int? updatedAt,
    int? expiresAt,
  }) {
    return Zone(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      description: description ?? this.description,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radius: radius ?? this.radius,
      geometry: geometry ?? this.geometry,
      severity: severity ?? this.severity,
      status: status ?? this.status,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }
}

enum ZoneStatus { active, inactive, expired }
