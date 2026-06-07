import 'package:flutter/foundation.dart';
import '../../../shared/services/backend_api.dart';
import '../models/twin_models.dart';

/// Thin API wrapper for digital twin services.
///
/// All GPU-accelerated fluid dynamics, hazard propagation simulation, and
/// evacuation planning have been moved to the backend.
class DigitalTwinService extends ChangeNotifier {
  static final DigitalTwinService _instance = DigitalTwinService._internal();
  factory DigitalTwinService() => _instance;
  DigitalTwinService._internal();

  final BackendApi _api = BackendApi();

  CityTilesetConfig? _currentCity;
  List<BuildingData> _buildings = [];
  bool _isLoading = false;

  /// The currently loaded city tileset configuration.
  CityTilesetConfig? get currentCity => _currentCity;

  /// Buildings in the currently loaded city.
  List<BuildingData> get buildings => _buildings;

  /// Whether data is currently being loaded.
  bool get isLoading => _isLoading;

  /// Initialize — no-op in thin client mode.
  Future<void> initialize() async {
    debugPrint('DigitalTwinService: Thin client mode — simulation is server-side');
  }

  /// Load city data from backend API.
  Future<void> loadCity(String cityId) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Fetch tileset config
      final tilesetResult = await _api.getCityTileset(cityId);
      _currentCity = CityTilesetConfig(
        cityId: tilesetResult['cityId'] as String? ?? cityId,
        tilesetUrl: tilesetResult['tilesetUrl'] as String? ?? '',
        centerLat: ((tilesetResult['center'] as Map?)?['lat'] as num?)?.toDouble() ?? 0.0,
        centerLng: ((tilesetResult['center'] as Map?)?['lng'] as num?)?.toDouble() ?? 0.0,
        zoom: (tilesetResult['zoom'] as num?)?.toInt() ?? 14,
      );

      // Fetch buildings
      final buildingsResult = await _api.getCityBuildings(cityId);
      if (buildingsResult['buildings'] is List) {
        _buildings = (buildingsResult['buildings'] as List).map((b) {
          final bMap = b as Map<String, dynamic>;
          return BuildingData(
            id: bMap['id'] as String? ?? '',
            name: bMap['name'] as String? ?? '',
            latitude: (bMap['latitude'] as num?)?.toDouble() ?? 0.0,
            longitude: (bMap['longitude'] as num?)?.toDouble() ?? 0.0,
            floors: (bMap['floors'] as num?)?.toInt() ?? 1,
            type: bMap['type'] as String? ?? 'unknown',
            occupancy: (bMap['occupancy'] as num?)?.toInt() ?? 0,
          );
        }).toList();
      }
    } catch (e) {
      debugPrint('DigitalTwinService: loadCity failed: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Predict hazard propagation via backend API.
  Future<PropagationResult> predictPropagation({
    required String cityId,
    required String hazardType,
    required double originLat,
    required double originLng,
    double windSpeed = 0,
    double windDirection = 0,
  }) async {
    try {
      final result = await _api.predictPropagation({
        'cityId': cityId,
        'hazardType': hazardType,
        'originLat': originLat,
        'originLng': originLng,
        'windSpeed': windSpeed,
        'windDirection': windDirection,
      });

      final cells = <PropagationCell>[];
      if (result['propagationCells'] is List) {
        for (final c in result['propagationCells'] as List) {
          final cMap = c as Map<String, dynamic>;
          cells.add(PropagationCell(
            lat: (cMap['lat'] as num).toDouble(),
            lng: (cMap['lng'] as num).toDouble(),
            arrivalTime: (cMap['arrivalTime'] as num).toInt(),
            intensity: (cMap['intensity'] as num).toDouble(),
          ));
        }
      }

      final buildingsAtRisk = <BuildingData>[];
      if (result['buildingsAtRisk'] is List) {
        for (final b in result['buildingsAtRisk'] as List) {
          final bMap = b as Map<String, dynamic>;
          buildingsAtRisk.add(BuildingData(
            id: bMap['id'] as String? ?? '',
            name: bMap['name'] as String? ?? '',
            latitude: (bMap['latitude'] as num?)?.toDouble() ?? 0.0,
            longitude: (bMap['longitude'] as num?)?.toDouble() ?? 0.0,
            floors: (bMap['floors'] as num?)?.toInt() ?? 1,
            type: bMap['type'] as String? ?? 'unknown',
            occupancy: (bMap['occupancy'] as num?)?.toInt() ?? 0,
          ));
        }
      }

      return PropagationResult(
        cells: cells,
        buildingsAtRisk: buildingsAtRisk,
        hazardType: hazardType,
      );
    } catch (e) {
      debugPrint('DigitalTwinService: predictPropagation failed: $e');
      return PropagationResult(cells: [], buildingsAtRisk: []);
    }
  }

  /// Get evacuation plan via backend API.
  Future<EvacuationPlan> getEvacuationPlan(double latitude, double longitude) async {
    try {
      final result = await _api.getEvacuationPlan(latitude, longitude);

      final safeZones = <SafeZone>[];
      if (result['safeZones'] is List) {
        for (final z in result['safeZones'] as List) {
          final zMap = z as Map<String, dynamic>;
          safeZones.add(SafeZone(
            name: zMap['name'] as String? ?? '',
            latitude: (zMap['latitude'] as num).toDouble(),
            longitude: (zMap['longitude'] as num).toDouble(),
            capacity: (zMap['capacity'] as num?)?.toInt() ?? 0,
            distanceKm: (zMap['distanceKm'] as num?)?.toDouble() ?? 0.0,
          ));
        }
      }

      return EvacuationPlan(
        originLat: latitude,
        originLng: longitude,
        safeZones: safeZones,
        evacuationFeasible: result['evacuationFeasible'] as bool? ?? false,
      );
    } catch (e) {
      debugPrint('DigitalTwinService: getEvacuationPlan failed: $e');
      return EvacuationPlan(
        originLat: latitude,
        originLng: longitude,
        safeZones: [],
        evacuationFeasible: false,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Data classes (preserved for UI compatibility)
// ---------------------------------------------------------------------------

class CityTilesetConfig {
  final String cityId;
  final String tilesetUrl;
  final double centerLat;
  final double centerLng;
  final int zoom;

  CityTilesetConfig({
    required this.cityId,
    required this.tilesetUrl,
    required this.centerLat,
    required this.centerLng,
    required this.zoom,
  });
}

class BuildingData {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final int floors;
  final String type;
  final int occupancy;

  BuildingData({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.floors,
    required this.type,
    required this.occupancy,
  });
}

class PropagationResult {
  final List<PropagationCell> cells;
  final List<BuildingData> buildingsAtRisk;
  final String? hazardType;

  PropagationResult({
    required this.cells,
    required this.buildingsAtRisk,
    this.hazardType,
  });
}

class PropagationCell {
  final double lat;
  final double lng;
  final int arrivalTime;
  final double intensity;

  PropagationCell({
    required this.lat,
    required this.lng,
    required this.arrivalTime,
    required this.intensity,
  });
}

class SafeZone {
  final String name;
  final double latitude;
  final double longitude;
  final int capacity;
  final double distanceKm;

  SafeZone({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.capacity,
    required this.distanceKm,
  });
}

class EvacuationPlan {
  final double originLat;
  final double originLng;
  final List<SafeZone> safeZones;
  final bool evacuationFeasible;

  EvacuationPlan({
    required this.originLat,
    required this.originLng,
    required this.safeZones,
    required this.evacuationFeasible,
  });
}
