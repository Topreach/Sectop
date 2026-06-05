/// Utility functions for location calculations.

class LocationUtils {
  /// Earth's radius in meters.
  static const double earthRadius = 6371000;

  /// Calculate distance between two coordinates using the Haversine formula.
  /// Returns distance in meters.
  static double calculateDistance(
    double lat1, double lon1,
    double lat2, double lon2,
  ) {
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = _sinSquared(dLat / 2) +
        _cos(lat1) * _cos(lat2) * _sinSquared(dLon / 2);
    final c = 2 * _atan2(_sqrt(a), _sqrt(1 - a));
    return earthRadius * c;
  }

  /// Calculate bounding box coordinates given a center point and radius.
  /// Returns [minLat, minLon, maxLat, maxLon].
  static List<double> calculateBoundingBox(
    double latitude,
    double longitude,
    double radiusMeters,
  ) {
    final latDelta = _toDegrees(radiusMeters / earthRadius);
    final lonDelta = _toDegrees(
      radiusMeters / (earthRadius * _cos(latitude)),
    );

    return [
      latitude - latDelta,
      longitude - lonDelta,
      latitude + latDelta,
      longitude + lonDelta,
    ];
  }

  /// Check if a point is within a circular zone.
  static bool isInZone(
    double pointLat, double pointLon,
    double zoneLat, double zoneLon,
    double zoneRadiusMeters,
  ) {
    final distance = calculateDistance(pointLat, pointLon, zoneLat, zoneLon);
    return distance <= zoneRadiusMeters;
  }

  /// Format coordinates for display.
  static String formatCoordinate(double coordinate, {bool isLatitude = true}) {
    final direction = isLatitude
        ? (coordinate >= 0 ? 'N' : 'S')
        : (coordinate >= 0 ? 'E' : 'W');
    final absolute = coordinate.abs();
    final degrees = absolute.floor();
    final minutes = (absolute - degrees) * 60;
    final minutesInt = minutes.floor();
    final seconds = (minutes - minutesInt) * 60;
    return '$degrees°$minutesInt\'${seconds.toStringAsFixed(1)}"$direction';
  }

  static double _toRadians(double degrees) => degrees * (3.141592653589793 / 180);
  static double _toDegrees(double radians) => radians * (180 / 3.141592653589793);
  static double _sinSquared(double x) {
    final s = x.sin;
    return s * s;
  }
  static double _cos(double degrees) => _toRadians(degrees).cos;
  static double _atan2(double y, double x) => y.atan2(x);
  static double _sqrt(double x) => x.sqrt();
}
