import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../core/constants.dart';
import '../../../shared/services/offline_storage.dart';
import '../../maps/services/map_service.dart';
import '../../predictive/services/predictive_engine.dart';
import '../models/twin_models.dart';
import 'simulation_engine.dart';
import 'ar_overlay.dart';

/// Digital Twin Service - 3D city model visualization, hazard propagation
/// simulation, and AR overlay for emergency responders.
///
/// Integrates:
/// - Cesium 3D Tiles for city-scale rendering
/// - GPU-accelerated fluid dynamics for hazard prediction
/// - ARKit/ARCore for real-world overlay
/// - Building-level metadata for evacuation planning
class DigitalTwinService extends ChangeNotifier {
  static final DigitalTwinService _instance = DigitalTwinService._();
  factory DigitalTwinService() => _instance;
  DigitalTwinService._();

  // Dependencies — factory constructors return singletons, same as Provider-managed instances
  final OfflineStorageService _storage = OfflineStorageService();
  final MapService _mapService = MapService();
  final PredictiveEngine _predictiveEngine = PredictiveEngine();

  // Sub-services
  late final SimulationEngine _simEngine;
  late final AROverlayService _arOverlay;

  // State
  TwinConnectionStatus _connectionStatus = TwinConnectionStatus.disconnected;
  String? _activeCityId;
  CityTilesetConfig? _tilesetConfig;
  Map<String, BuildingData> _buildings = {};
  List<SimulationResult> _simulationHistory = [];
  SimulationResult? _latestSimulation;
  bool _isSimulating = false;
  double _tilesLoadProgress = 0.0;

  // 3D tileset state (simulated - in production uses Cesium3DTileset)
  bool _tilesetLoaded = false;
  int _tilesLoaded = 0;
  int _tilesTotal = 0;

  // Callbacks
  void Function(SimulationResult result)? onSimulationComplete;
  void Function(String alert)? onHazardAlert;
  void Function(double progress)? onTilesLoadProgress;

  // Getters
  TwinConnectionStatus get connectionStatus => _connectionStatus;
  String? get activeCityId => _activeCityId;
  CityTilesetConfig? get tilesetConfig => _tilesetConfig;
  Map<String, BuildingData> get buildings => Map.unmodifiable(_buildings);
  List<SimulationResult> get simulationHistory =>
      List.unmodifiable(_simulationHistory);
  SimulationResult? get latestSimulation => _latestSimulation;
  bool get isSimulating => _isSimulating;
  double get tilesLoadProgress => _tilesLoadProgress;
  bool get tilesetLoaded => _tilesetLoaded;
  SimulationEngine get simulationEngine => _simEngine;
  AROverlayService get arOverlay => _arOverlay;

  /// Initialize the digital twin service.
  Future<void> initialize() async {
    _connectionStatus = TwinConnectionStatus.connecting;
    notifyListeners();

    try {
      // Initialize simulation engine with default parameters
      _simEngine = SimulationEngine(
        resolution: 0.5, // 0.5m grid cells
        timestep: 0.1, // 100ms simulation steps
      );

      // Initialize AR overlay
      _arOverlay = AROverlayService();

      // Listen for simulation progress
      _simEngine.addListener(_onSimulationProgress);

      _connectionStatus = TwinConnectionStatus.connected;
      debugPrint('Digital Twin Service initialized');
    } catch (e) {
      _connectionStatus = TwinConnectionStatus.error;
      debugPrint('Digital Twin initialization error: $e');
    }

    notifyListeners();
  }

  /// Load a city's 3D tileset and building metadata.
  Future<void> loadCity(String cityId) async {
    _activeCityId = cityId;
    _connectionStatus = TwinConnectionStatus.syncing;
    notifyListeners();

    try {
      // Load tileset configuration
      _tilesetConfig = await _fetchTilesetConfig(cityId);

      // Load building metadata
      final buildingsData = await _fetchBuildingMetadata(cityId);
      _buildings = {
        for (final b in buildingsData) b.id: b,
      };

      // Initialize simulation engine with terrain data
      final terrainData = await _fetchTerrainData(cityId);
      final fuelLoad = await _fetchFuelLoadData(cityId);
      final buildingMask = _generateBuildingMask(terrainData.length,
          terrainData[0].length, _buildings.values.toList());

      await _simEngine.initialize(
        terrainHeight: terrainData,
        fuelLoad: fuelLoad,
        buildingMask: buildingMask,
      );

      // Simulate tileset loading progress
      _tilesTotal = 100;
      for (int i = 0; i <= _tilesTotal; i++) {
        _tilesLoaded = i;
        _tilesLoadProgress = i / _tilesTotal;
        onTilesLoadProgress?.call(_tilesLoadProgress);
        await Future.delayed(const Duration(milliseconds: 50));
      }

      _tilesetLoaded = true;
      _connectionStatus = TwinConnectionStatus.connected;

      debugPrint('City $cityId loaded: ${_buildings.length} buildings');
    } catch (e) {
      _connectionStatus = TwinConnectionStatus.error;
      debugPrint('City load error: $e');
    }

    notifyListeners();
  }

  /// Predict hazard propagation using GPU-accelerated simulation.
  Future<SimulationResult> predictPropagation({
    required HazardType hazard,
    required Vector3 origin,
    required WeatherData weather,
    Duration duration = const Duration(hours: 6),
  }) async {
    if (_connectionStatus != TwinConnectionStatus.connected) {
      throw StateError('Digital twin not connected. Call loadCity() first.');
    }

    _isSimulating = true;
    notifyListeners();

    try {
      final timesteps = (duration.inSeconds / _simEngine.timestep).round();

      final output = await _simEngine.run(
        hazard: hazard,
        origin: origin,
        weather: weather,
        timesteps: timesteps,
      );

      // SimulationResult is returned directly from the engine
      final result = output;

      _latestSimulation = result;
      _simulationHistory.add(result);

      // Keep only last 100 simulations
      if (_simulationHistory.length > 100) {
        _simulationHistory.removeAt(0);
      }

      // Cache simulation result
      await _cacheSimulationResult(result);

      // Trigger callbacks
      onSimulationComplete?.call(result);
// Check for critical hazards based on estimated arrival times
final affectedBuildings = result.estimatedArrivalTimes.length;
if (affectedBuildings > 10) {
  onHazardAlert?.call(
    '⚠️ $affectedBuildings buildings at risk '
    'from ${hazard.name}',
  );
}
      }

      // Update AR overlay with simulation results
      await _updateAROverlay(result);

      return result;
    } catch (e) {
      debugPrint('Simulation error: $e');
      rethrow;
    } finally {
      _isSimulating = false;
      notifyListeners();
    }
  }

  /// Update AR overlay with simulation results.
  Future<void> _updateAROverlay(SimulationResult result) async {
    if (!_arOverlay.isActive) return;

    _arOverlay.clearAnnotations();

    // Add hazard annotations
    for (final point in result.propagationPath.take(50)) {
      _arOverlay.addAnnotation(ARAnnotation(
        id: 'hazard_${point.latitude}_${point.longitude}',
        worldPosition: Vector3(point.latitude, point.longitude, 0),
        label: '${point.hazardType.name}: ${point.intensity.toStringAsFixed(1)}',
        color: Colors.red.withOpacity(point.intensity),
        type: ARAnnotationType.hazard,
        metadata: {
          'arrivalTime': point.arrivalTimeMinutes,
          'intensity': point.intensity,
        },
      ));
    }

    // Add safe corridor annotations
    for (final corridor in result.safeCorridors) {
      _arOverlay.addAnnotation(ARAnnotation(
        id: 'safe_${corridor.id}',
        worldPosition: Vector3(
          corridor.polygon.isNotEmpty ? corridor.polygon.first.x : 0,
          corridor.polygon.isNotEmpty ? corridor.polygon.first.y : 0,
          0,
        ),
        label: 'Safe Corridor (${corridor.estimatedCapacity.toInt()} people)',
        color: Colors.green,
        type: ARAnnotationType.safePoint,
      ));
    }

    // Set evacuation path
    if (result.safeCorridors.isNotEmpty) {
      final path = result.safeCorridors.first.polygon
          .map((p) => Vector3(p.x, p.y, 0))
          .toList();
      _arOverlay.setEvacuationPath(path);
    }
  }

  /// Get buildings at risk from the latest simulation.
  List<BuildingData> getBuildingsAtRisk({double minIntensity = 0.3}) {
    if (_latestSimulation == null) return [];

    final atRisk = <BuildingData>[];
    for (final building in _buildings.values) {
      final arrivalTime = _latestSimulation!.estimatedArrivalTimes[building.id];
      if (arrivalTime != null) {
        atRisk.add(building);
      }
    }

    // Sort by arrival time (most urgent first)
    atRisk.sort((a, b) {
      final aTime = _latestSimulation!.estimatedArrivalTimes[a.id] ?? double.infinity;
      final bTime = _latestSimulation!.estimatedArrivalTimes[b.id] ?? double.infinity;
      return aTime.compareTo(bTime);
    });

    return atRisk;
  }

  /// Get evacuation recommendations for a specific building.
  EvacuationPlan? getEvacuationPlan(String buildingId) {
    final building = _buildings[buildingId];
    if (building == null) return null;

    final arrivalTime = _latestSimulation?.estimatedArrivalTimes[buildingId];
    if (arrivalTime == null) return null;

    // Find nearest safe corridor
    SafeCorridor? nearestCorridor;
    double minDistance = double.infinity;

    if (_latestSimulation != null) {
      for (final corridor in _latestSimulation!.safeCorridors) {
        if (corridor.polygon.isEmpty) continue;
        final center = corridor.polygon.first;
        final dx = center.x - building.latitude;
        final dy = center.y - building.longitude;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist < minDistance) {
          minDistance = dist;
          nearestCorridor = corridor;
        }
      }
    }

    return EvacuationPlan(
      buildingId: buildingId,
      buildingName: building.name,
      timeUntilHazard: Duration(minutes: arrivalTime.toInt()),
      nearestSafeCorridor: nearestCorridor,
      evacuationTimeEstimate: Duration(minutes: (building.occupancy * 0.5).toInt()),
      occupantCount: building.occupancy,
      hasBasement: building.hasBasement,
      hasEmergencyExits: building.hasEmergencyExits,
    );
  }

  /// Fetch tileset configuration from the API.
  Future<CityTilesetConfig> _fetchTilesetConfig(String cityId) async {
    // In production, fetches from:
    // GET /api/v1/digital-twin/cities/{cityId}/tileset
    try {
      final response = await http.get(
        Uri.parse(
          '${AppConstants.apiBaseUrl}/${AppConstants.apiVersion}/'
          'digital-twin/cities/$cityId/tileset',
        ),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return CityTilesetConfig(
          cityId: cityId,
          tilesetUrl: data['tileset_url'] as String,
          initialLatitude: (data['initial_latitude'] as num).toDouble(),
          initialLongitude: (data['initial_longitude'] as num).toDouble(),
          initialZoom: (data['initial_zoom'] as num?)?.toDouble() ?? 14.0,
        );
      }
    } catch (e) {
      debugPrint('Failed to fetch tileset config: $e');
    }

    // Fallback to default config
    return CityTilesetConfig(
      cityId: cityId,
      tilesetUrl: 'https://tiles.dangeremergence.com/cities/$cityId/tileset.json',
      initialLatitude: 0.0,
      initialLongitude: 0.0,
    );
  }

  /// Fetch building metadata from the API.
  Future<List<BuildingData>> _fetchBuildingMetadata(String cityId) async {
    // In production, fetches from:
    // GET /api/v1/digital-twin/cities/{cityId}/buildings
    try {
      final response = await http.get(
        Uri.parse(
          '${AppConstants.apiBaseUrl}/${AppConstants.apiVersion}/'
          'digital-twin/cities/$cityId/buildings',
        ),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List<dynamic>;
        return data
            .map((b) => BuildingData.fromMap(b as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('Failed to fetch building metadata: $e');
    }

    // Check offline cache
    final cached = await _storage.query('buildings',
        where: 'city_id = ?', whereArgs: [cityId]);
    if (cached.isNotEmpty) {
      return cached.map((b) => BuildingData.fromMap(b)).toList();
    }

    return [];
  }

  /// Fetch terrain height data.
  Future<List<List<double>>> _fetchTerrainData(String cityId) async {
    // In production, fetches a GeoTIFF or heightmap from:
    // GET /api/v1/digital-twin/cities/{cityId}/terrain
    //
    // Returns a 2D grid of elevation values in meters.
    // For now, return a flat terrain grid.
    const gridSize = 200; // 200x200 grid = 100m x 100m at 0.5m resolution
    return List.generate(
      gridSize,
      (_) => List.filled(gridSize, 0.0),
    );
  }

  /// Fetch fuel load data (for wildfire simulation).
  Future<List<List<double>>> _fetchFuelLoadData(String cityId) async {
    // In production, fetches vegetation/fuel data from satellite imagery.
    const gridSize = 200;
    return List.generate(
      gridSize,
      (_) => List.filled(gridSize, 1.0), // Default fuel load
    );
  }

  /// Generate building mask from building data.
  List<List<bool>> _generateBuildingMask(
    int rows,
    int cols,
    List<BuildingData> buildings,
  ) {
    final mask = List.generate(rows, (_) => List.filled(cols, false));

    for (final building in buildings) {
      // Convert lat/lon to grid coordinates (simplified)
      final gx = (building.latitude * 100).round().clamp(0, rows - 1);
      final gy = (building.longitude * 100).round().clamp(0, cols - 1);

      // Mark building footprint (simplified as rectangle)
      const footprint = 2; // 2 cells in each direction
      for (int dx = -footprint; dx <= footprint; dx++) {
        for (int dy = -footprint; dy <= footprint; dy++) {
          final nx = gx + dx;
          final ny = gy + dy;
          if (nx >= 0 && nx < rows && ny >= 0 && ny < cols) {
            mask[nx][ny] = true;
          }
        }
      }
    }

    return mask;
  }

  /// Cache simulation result for offline access.
  Future<void> _cacheSimulationResult(SimulationResult result) async {
    try {
      await _storage.insert('simulation_results', {
        'timestamp': result.timestamp.toIso8601String(),
        'confidence': result.confidence,
        'affected_buildings': result.estimatedArrivalTimes.length,
        'safe_corridors': result.safeCorridors.length,
        'propagation_points': result.propagationPath.length,
      });
    } catch (e) {
      debugPrint('Failed to cache simulation: $e');
    }
  }

  /// Handle simulation engine progress updates.
  void _onSimulationProgress() {
    notifyListeners();
  }

  /// Get cached simulation results.
  Future<List<Map<String, dynamic>>> getCachedSimulations() async {
    return await _storage.query('simulation_results',
        orderBy: 'timestamp DESC', limit: 20);
  }

  /// Clear all cached data for a city.
  Future<void> clearCityCache(String cityId) async {
    _buildings.clear();
    _simulationHistory.clear();
    _latestSimulation = null;
    _tilesetLoaded = false;
    _tilesLoadProgress = 0.0;
    notifyListeners();
  }

  @override
  void dispose() {
    _simEngine.removeListener(_onSimulationProgress);
    _simEngine.dispose();
    _arOverlay.dispose();
    super.dispose();
  }
}

/// Evacuation plan for a specific building.
class EvacuationPlan {
  final String buildingId;
  final String buildingName;
  final Duration timeUntilHazard;
  final SafeCorridor? nearestSafeCorridor;
  final Duration evacuationTimeEstimate;
  final int occupantCount;
  final bool hasBasement;
  final bool hasEmergencyExits;

  const EvacuationPlan({
    required this.buildingId,
    required this.buildingName,
    required this.timeUntilHazard,
    this.nearestSafeCorridor,
    required this.evacuationTimeEstimate,
    required this.occupantCount,
    required this.hasBasement,
    required this.hasEmergencyExits,
  });

  /// Whether evacuation is feasible given remaining time.
  bool get isEvacuationFeasible =>
      timeUntilHazard.inMinutes > evacuationTimeEstimate.inMinutes;

  /// Priority score (lower = more urgent).
  double get priorityScore =>
      timeUntilHazard.inMinutes / (occupantCount + 1);
}
