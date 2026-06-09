import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../shared/services/backend_api.dart';
import '../../../shared/models/location.dart';
import '../models/drone_models.dart';

/// Thin API wrapper for drone orchestration.
///
/// All MAVLink integration, lawnmower pattern generation, LoRa relay
/// deployment, and swarm mesh networking have been moved to the backend.
class DroneService extends ChangeNotifier {
  static DroneService? _instance;
  static DroneService get instance => _instance ??= DroneService._();
  DroneService._();

  final BackendApi _api = BackendApi();

  List<DroneInfo> _availableDrones = [];
  bool _isLoading = false;
  Timer? _fleetUpdateTimer;

  /// Available drones from the backend.
  List<DroneInfo> get availableDrones => _availableDrones;

  /// Whether drone data is being loaded.
  bool get isLoading => _isLoading;

  /// Initialize — no-op in thin client mode.
  Future<void> initialize() async {
    debugPrint('DroneService: Thin client mode — orchestration is server-side');
  }

  /// Fetch available drones from backend.
  Future<List<DroneInfo>> getAvailableDrones({
    double latitude = 0,
    double longitude = 0,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _api.getAvailableDrones(
        latitude: latitude,
        longitude: longitude,
      );

      _availableDrones = [];
      if (result['drones'] is List) {
        for (final d in result['drones'] as List) {
          final dMap = d as Map<String, dynamic>;
          _availableDrones.add(DroneInfo(
            id: dMap['id'] as String? ?? '',
            name: dMap['name'] as String? ?? '',
            model: dMap['model'] as String? ?? '',
            battery: (dMap['battery'] as num?)?.toInt() ?? 0,
            status: dMap['status'] as String? ?? 'unknown',
            latitude: (dMap['latitude'] as num?)?.toDouble() ?? 0.0,
            longitude: (dMap['longitude'] as num?)?.toDouble() ?? 0.0,
            altitude: (dMap['altitude'] as num?)?.toDouble() ?? 0.0,
            maxSpeed: (dMap['maxSpeed'] as num?)?.toDouble() ?? 0.0,
            hasLoRa: dMap['hasLoRa'] as bool? ?? false,
            hasCamera: dMap['hasCamera'] as bool? ?? false,
          ));
        }
      }

      return _availableDrones;
    } catch (e) {
      debugPrint('DroneService: getAvailableDrones failed: $e');
      return [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Deploy a LoRa relay drone via backend.
  Future<Map<String, dynamic>> deployRelayDrone(
    String droneId,
    double latitude,
    double longitude,
  ) async {
    try {
      return await _api.deployRelayDrone(droneId, latitude, longitude);
    } catch (e) {
      debugPrint('DroneService: deployRelayDrone failed: $e');
      return {'error': e.toString()};
    }
  }

  /// Run damage assessment via backend.
  Future<DamageAssessment> assessDamage(
    String zoneId,
    double centerLat,
    double centerLng,
    double radiusKm,
  ) async {
    try {
      final result = await _api.assessDamage(zoneId, centerLat, centerLng, radiusKm);

      return DamageAssessment(
        damagedBuildings: _parseDamagedBuildings(result['damagedBuildings']),
        fireHotspots: _parseFireHotspots(result['fireHotspots']),
        blockedRoads: _parseBlockedRoads(result['blockedRoads']),
        casualtiesDetected: _parseCasualties(result['casualties']),
        timestamp: DateTime.now(),
      );
    } catch (e) {
      debugPrint('DroneService: assessDamage failed: $e');
      return DamageAssessment(
        damagedBuildings: [],
        fireHotspots: [],
        blockedRoads: [],
        casualtiesDetected: [],
        timestamp: DateTime.now(),
      );
    }
  }

  /// Deploy swarm mesh via backend.
  Future<SwarmMesh> deploySwarmMesh(
    String zoneId,
    double centerLat,
    double centerLng,
    double radiusKm,
  ) async {
    try {
      final result = await _api.deploySwarmMesh(zoneId, centerLat, centerLng, radiusKm);

      final deployedDrones = <DroneInfo>[];
      if (result['deployedDrones'] is List) {
        for (final d in result['deployedDrones'] as List) {
          final dMap = d as Map<String, dynamic>;
          deployedDrones.add(DroneInfo(
            id: dMap['id'] as String? ?? '',
            name: dMap['name'] as String? ?? '',
            model: dMap['model'] as String? ?? '',
            battery: (dMap['battery'] as num?)?.toInt() ?? 0,
            status: dMap['status'] as String? ?? 'deployed',
            latitude: (dMap['deployedLatitude'] as num?)?.toDouble() ?? 0.0,
            longitude: (dMap['deployedLongitude'] as num?)?.toDouble() ?? 0.0,
            altitude: (dMap['altitude'] as num?)?.toDouble() ?? 0.0,
            maxSpeed: (dMap['maxSpeed'] as num?)?.toDouble() ?? 0.0,
            hasLoRa: dMap['hasLoRa'] as bool? ?? false,
            hasCamera: dMap['hasCamera'] as bool? ?? false,
          ));
        }
      }

      return SwarmMesh(
        drones: deployedDrones.map((d) => Drone(
          id: d.id,
          name: d.name,
          location: Location(d.latitude, d.longitude),
          lastSeen: DateTime.now(),
        )).toList(),
        coverageArea: [],
        estimatedUptime: Duration(hours: 1),
        averageSignalStrength: (result['estimatedSignalStrength'] as num?)?.toDouble() ?? 0.0,
      );
    } catch (e) {
      debugPrint('DroneService: deploySwarmMesh failed: $e');
      return SwarmMesh(drones: [], coverageArea: [], estimatedUptime: Duration.zero, averageSignalStrength: 0.0);
    }
  }

  // ---------------------------------------------------------------------------
  // Parsing helpers
  // ---------------------------------------------------------------------------

  List<DamagedBuilding> _parseDamagedBuildings(dynamic data) {
    if (data is! List) return [];
    return data.map((b) {
      final bMap = b as Map<String, dynamic>;
      return DamagedBuilding(
        buildingId: bMap['id'] as String? ?? '',
        location: Location(
          (bMap['latitude'] as num).toDouble(),
          (bMap['longitude'] as num).toDouble(),
        ),
        damageLevel: DamageLevel.values.firstWhere(
          (e) => e.name == (bMap['damageLevel'] as String? ?? 'none'),
          orElse: () => DamageLevel.none,
        ),
        confidence: (bMap['confidence'] as num?)?.toDouble() ?? 0.0,
      );
    }).toList();
  }

  List<FireHotspot> _parseFireHotspots(dynamic data) {
    if (data is! List) return [];
    return data.map((h) {
      final hMap = h as Map<String, dynamic>;
      return FireHotspot(
        center: Location(
          (hMap['latitude'] as num).toDouble(),
          (hMap['longitude'] as num).toDouble(),
        ),
        radiusMeters: (hMap['area'] as num?)?.toDouble() ?? 0.0,
        intensity: (hMap['intensity'] as num).toDouble(),
        temperatureCelsius: (hMap['temperatureCelsius'] as num?)?.toDouble() ?? 100.0,
      );
    }).toList();
  }

  List<BlockedRoad> _parseBlockedRoads(dynamic data) {
    if (data is! List) return [];
    return data.map((r) {
      final rMap = r as Map<String, dynamic>;
      return BlockedRoad(
        roadId: rMap['id'] as String? ?? '',
        start: Location(
          (rMap['startLat'] as num).toDouble(),
          (rMap['startLng'] as num).toDouble(),
        ),
        end: Location(
          (rMap['endLat'] as num).toDouble(),
          (rMap['endLng'] as num).toDouble(),
        ),
        type: ObstructionType.values.firstWhere(
          (e) => e.name == (rMap['blockageType'] as String? ?? 'unknown'),
          orElse: () => ObstructionType.unknown,
        ),
      );
    }).toList();
  }

  List<Casualty> _parseCasualties(dynamic data) {
    if (data is! List) return [];
    return data.map((c) {
      final cMap = c as Map<String, dynamic>;
      return Casualty(
        location: Location(
          (cMap['latitude'] as num).toDouble(),
          (cMap['longitude'] as num).toDouble(),
        ),
        description: cMap['severity'] as String?,
        confidence: (cMap['confidence'] as num?)?.toDouble() ?? 0.5,
        detectedAt: DateTime.tryParse(cMap['detectedAt'] as String? ?? '') ?? DateTime.now(),
      );
    }).toList();
  }
}
