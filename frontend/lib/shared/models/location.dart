/// Shared Location model used across all modules.
/// Replaces duplicate Location classes in mesh and predictive modules.
class Location {
  final double latitude;
  final double longitude;

  const Location(this.latitude, this.longitude);

  /// Calculate distance to another location using Haversine formula.
  double distanceTo(Location other) {
    const earthRadius = 6371000.0; // meters
    final dLat = _toRadians(other.latitude - latitude);
    final dLon = _toRadians(other.longitude - longitude);
    final a = _sinSquared(dLat / 2) +
        _cos(latitude) * _cos(other.latitude) * _sinSquared(dLon / 2);
    final c = 2 * _atan2(_sqrt(a), _sqrt(1 - a));
    return earthRadius * c;
  }

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
      };

  factory Location.fromJson(Map<String, dynamic> json) => Location(
        (json['latitude'] as num).toDouble(),
        (json['longitude'] as num).toDouble(),
      );

  static double _toRadians(double degrees) => degrees * (3.141592653589793 / 180);
  static double _sinSquared(double x) {
    final s = x.sin;
    return s * s;
  }

  static double _cos(double degrees) => _toRadians(degrees).cos;
  static double _atan2(double y, double x) => y.atan2(x);
  static double _sqrt(double x) => x.sqrt();

  @override
  String toString() => 'Location($latitude, $longitude)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Location &&
          latitude == other.latitude &&
          longitude == other.longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}
