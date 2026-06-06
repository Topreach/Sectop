import 'dart:math' as math;
import 'dart:ui';

/// Data models for the Digital Twin module.
/// Represents 3D city models, buildings, hazards, and simulation state.

/// Hazard types that can be simulated.
enum HazardType {
  wildfire,
  flood,
  toxicCloud,
  earthquake,
  tsunami,
  hurricane,
  chemicalSpill,
  radiation,
}

/// Spectral bands for multispectral drone imagery.
enum SpectralBand {
  rgb,
  thermal,
  nir,
  lwir,
}

/// A 3D building with metadata for the digital twin.
class BuildingData {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double height; // meters
  final int floors;
  final String constructionType; // concrete, steel, wood, etc.
  final int occupancy; // estimated number of people
  final bool hasBasement;
  final bool hasEmergencyExits;
  final List<String> hazardSusceptibility; // e.g., ['flood', 'fire']
  final Map<String, dynamic>? customProperties;

  // 3D mesh data (simplified)
  final List<Vector3> vertices;
  final List<int> indices;
  final List<Vector2> textureCoordinates;

  const BuildingData({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.height,
    required this.floors,
    required this.constructionType,
    required this.occupancy,
    this.hasBasement = false,
    this.hasEmergencyExits = true,
    this.hazardSusceptibility = const [],
    this.customProperties,
    this.vertices = const [],
    this.indices = const [],
    this.textureCoordinates = const [],
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'height': height,
        'floors': floors,
        'construction_type': constructionType,
        'occupancy': occupancy,
        'has_basement': hasBasement,
        'has_emergency_exits': hasEmergencyExits,
        'hazard_susceptibility': hazardSusceptibility,
        'custom_properties': customProperties,
      };

  factory BuildingData.fromMap(Map<String, dynamic> map) => BuildingData(
        id: map['id'] as String,
        name: map['name'] as String,
        latitude: (map['latitude'] as num).toDouble(),
        longitude: (map['longitude'] as num).toDouble(),
        height: (map['height'] as num).toDouble(),
        floors: map['floors'] as int,
        constructionType: map['construction_type'] as String,
        occupancy: map['occupancy'] as int,
        hasBasement: map['has_basement'] as bool? ?? false,
        hasEmergencyExits: map['has_emergency_exits'] as bool? ?? true,
        hazardSusceptibility:
            (map['hazard_susceptibility'] as List?)?.cast<String>() ?? [],
        customProperties:
            map['custom_properties'] as Map<String, dynamic>?,
      );
}

/// Weather data affecting hazard propagation.
class WeatherData {
  final double temperature; // Celsius
  final double humidity; // percentage
  final double windSpeed; // m/s
  final double windDirection; // degrees from north
  final double precipitation; // mm/hr
  final double visibility; // meters
  final Vector3 windVector;

  const WeatherData({
    required this.temperature,
    required this.humidity,
    required this.windSpeed,
    required this.windDirection,
    this.precipitation = 0.0,
    this.visibility = 10000.0,
    this.windVector = const Vector3(0, 0, 0),
  });

  factory WeatherData.fromMap(Map<String, dynamic> map) {
    final windSpeed = (map['wind_speed'] as num?)?.toDouble() ?? 0.0;
    final windDirection =
        (map['wind_direction'] as num?)?.toDouble() ?? 0.0;
    final radians = windDirection * (3.14159 / 180.0);
    return WeatherData(
      temperature: (map['temperature'] as num?)?.toDouble() ?? 20.0,
      humidity: (map['humidity'] as num?)?.toDouble() ?? 50.0,
      windSpeed: windSpeed,
      windDirection: windDirection,
      precipitation: (map['precipitation'] as num?)?.toDouble() ?? 0.0,
      visibility: (map['visibility'] as num?)?.toDouble() ?? 10000.0,
      windVector: Vector3(
        windSpeed * -1.0 * math.sin(radians),
        windSpeed * -1.0 * math.cos(radians),
        0.0,
      ),
    );
  }
}

/// Result of a hazard propagation simulation.
class SimulationResult {
  final List<PropagationPoint> propagationPath;
  final List<SafeCorridor> safeCorridors;
  final Map<String, double> estimatedArrivalTimes; // buildingId -> minutes
  final double confidence; // 0.0 to 1.0
  final DateTime timestamp;
  final Duration simulationDuration;

  const SimulationResult({
    required this.propagationPath,
    required this.safeCorridors,
    required this.estimatedArrivalTimes,
    required this.confidence,
    required this.timestamp,
    required this.simulationDuration,
  });

  /// Get the estimated time until hazard reaches a specific location.
  double? getArrivalTime(double lat, double lon) {
    double? closestTime;
    double minDistance = double.infinity;

    for (final point in propagationPath) {
      final dx = point.latitude - lat;
      final dy = point.longitude - lon;
      final distance = (dx * dx + dy * dy);
      if (distance < minDistance) {
        minDistance = distance;
        closestTime = point.arrivalTimeMinutes;
      }
    }
    return closestTime;
  }
}

/// A point along the hazard propagation path.
class PropagationPoint {
  final double latitude;
  final double longitude;
  final double intensity; // 0.0 to 1.0
  final double arrivalTimeMinutes;
  final HazardType hazardType;

  const PropagationPoint({
    required this.latitude,
    required this.longitude,
    required this.intensity,
    required this.arrivalTimeMinutes,
    required this.hazardType,
  });
}

/// A safe corridor (area not reached by hazard within the simulation window).
class SafeCorridor {
  final String id;
  final List<Vector2> polygon; // GPS coordinates as [lat, lon] pairs
  final double estimatedCapacity; // number of people
  final double distanceToNearestHazard; // meters
  final List<String> accessibleBuildings;

  const SafeCorridor({
    required this.id,
    required this.polygon,
    required this.estimatedCapacity,
    required this.distanceToNearestHazard,
    this.accessibleBuildings = const [],
  });
}

/// An AR annotation placed on the real-world camera view.
class ARAnnotation {
  final String id;
  final Vector3 worldPosition; // GPS-relative 3D position
  final String label;
  final Color color;
  final ARAnnotationType type;
  final Map<String, dynamic>? metadata;

  const ARAnnotation({
    required this.id,
    required this.worldPosition,
    required this.label,
    required this.color,
    required this.type,
    this.metadata,
  });
}

enum ARAnnotationType {
  hazard,
  evacuationRoute,
  safePoint,
  medicalFacility,
  supplyDrop,
  casualty,
  buildingEntrance,
}

/// Camera pose for AR overlay positioning.
class CameraPose {
  final Vector3 position;
  final Quaternion orientation;
  final double fieldOfView;
  final double timestamp;

  const CameraPose({
    required this.position,
    required this.orientation,
    required this.fieldOfView,
    required this.timestamp,
  });
}

/// Simplified 3D vector for cross-platform compatibility.
class Vector3 {
  final double x;
  final double y;
  final double z;

  const Vector3(this.x, this.y, this.z);

  factory Vector3.zero() => const Vector3(0, 0, 0);

  Vector3 operator +(Vector3 other) =>
      Vector3(x + other.x, y + other.y, z + other.z);

  Vector3 operator -(Vector3 other) =>
      Vector3(x - other.x, y - other.y, z - other.z);

  Vector3 operator *(double scalar) =>
      Vector3(x * scalar, y * scalar, z * scalar);

  double get magnitude => math.sqrt(x * x + y * y + z * z);

  Vector3 normalized() {
    final mag = magnitude;
    if (mag == 0) return Vector3.zero();
    return Vector3(x / mag, y / mag, z / mag);
  }

  double dot(Vector3 other) => x * other.x + y * other.y + z * other.z;

  Vector3 cross(Vector3 other) => Vector3(
        y * other.z - z * other.y,
        z * other.x - x * other.z,
        x * other.y - y * other.x,
      );

  Map<String, double> toMap() => {'x': x, 'y': y, 'z': z};

  factory Vector3.fromMap(Map<String, dynamic> map) => Vector3(
        (map['x'] as num).toDouble(),
        (map['y'] as num).toDouble(),
        (map['z'] as num).toDouble(),
      );

  @override
  String toString() => 'Vector3($x, $y, $z)';
}

/// Simplified 2D vector.
class Vector2 {
  final double x;
  final double y;

  const Vector2(this.x, this.y);

  factory Vector2.zero() => const Vector2(0, 0);

  double get magnitude => math.sqrt(x * x + y * y);
}

/// Simplified quaternion for rotation representation.
class Quaternion {
  final double x;
  final double y;
  final double z;
  final double w;

  const Quaternion(this.x, this.y, this.z, this.w);

  factory Quaternion.identity() => const Quaternion(0, 0, 0, 1);

  /// Create from Euler angles (in radians).
  factory Quaternion.fromEuler(double roll, double pitch, double yaw) {
    final cy = math.cos(yaw * 0.5);
    final sy = math.sin(yaw * 0.5);
    final cp = math.cos(pitch * 0.5);
    final sp = math.sin(pitch * 0.5);
    final cr = math.cos(roll * 0.5);
    final sr = math.sin(roll * 0.5);

    return Quaternion(
      sr * cp * cy - cr * sp * sy,
      cr * sp * cy + sr * cp * sy,
      cr * cp * sy - sr * sp * cy,
      cr * cp * cy + sr * sp * sy,
    );
  }
}

/// Configuration for the 3D city tileset.
class CityTilesetConfig {
  final String cityId;
  final String tilesetUrl;
  final double initialLatitude;
  final double initialLongitude;
  final double initialZoom;
  final double maximumScreenSpaceError;
  final bool enableShadows;
  final bool enableFog;

  const CityTilesetConfig({
    required this.cityId,
    required this.tilesetUrl,
    required this.initialLatitude,
    required this.initialLongitude,
    this.initialZoom = 14.0,
    this.maximumScreenSpaceError = 16.0,
    this.enableShadows = true,
    this.enableFog = true,
  });
}

/// Status of the digital twin connection and data loading.
enum TwinConnectionStatus {
  disconnected,
  connecting,
  connected,
  syncing,
  error,
}

/// Simulation output from the GPU compute pipeline.
class SimulationOutput {
  final List<List<double>> heatmap; // 2D grid of intensity values
  final List<PropagationPoint> hotspots;
  final double totalAffectedArea; // square meters
  final int estimatedAffectedBuildings;
  final double confidence;

  const SimulationOutput({
    required this.heatmap,
    required this.hotspots,
    required this.totalAffectedArea,
    required this.estimatedAffectedBuildings,
    required this.confidence,
  });
}
