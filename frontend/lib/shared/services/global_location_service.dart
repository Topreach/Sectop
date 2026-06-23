import 'package:geocoding/geocoding.dart';

/// Global location service that resolves addresses and coordinates
/// using the platform-native geocoder (Google Geocoder on Android,
/// CLGeocoder on iOS).
///
/// Works worldwide — no API key required for basic usage.
class GlobalLocationService {
  static final GlobalLocationService _instance = GlobalLocationService._();
  factory GlobalLocationService() => _instance;
  GlobalLocationService._();

  /// Search for a location by name (city, address, landmark, etc.).
  /// Returns a list of matching results with coordinates and display names.
  ///
  /// Uses [locationFromAddress] from the geocoding package.
  static Future<List<Map<String, dynamic>>> searchLocation(
      String query) async {
    if (query.trim().isEmpty) return [];

    try {
      final locations = await locationFromAddress(query);
      return locations.map((loc) {
        return {
          'name': _buildShortName(loc),
          'latitude': loc.latitude,
          'longitude': loc.longitude,
          'displayName': _buildDisplayName(loc),
          'street': loc.street ?? '',
          'city': loc.locality ?? '',
          'state': loc.administrativeArea ?? '',
          'country': loc.country ?? '',
          'postalCode': loc.postalCode ?? '',
        };
      }).toList();
    } catch (e) {
      // Geocoding may fail if no network or invalid query
      return [];
    }
  }

  /// Reverse geocode GPS coordinates to a human-readable address.
  /// Returns a map with address components, or null if resolution fails.
  static Future<Map<String, dynamic>?> reverseGeocode(
      double latitude, double longitude) async {
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isEmpty) return null;

      final placemark = placemarks.first;
      return {
        'name': _buildShortName(placemark),
        'latitude': latitude,
        'longitude': longitude,
        'displayName': _buildDisplayName(placemark),
        'street': placemark.street ?? '',
        'city': placemark.locality ?? '',
        'state': placemark.administrativeArea ?? '',
        'country': placemark.country ?? '',
        'postalCode': placemark.postalCode ?? '',
        'isoCountryCode': placemark.isoCountryCode ?? '',
      };
    } catch (e) {
      return null;
    }
  }

  /// Build a short display name (e.g., "Ikeja, Lagos, Nigeria").
  static String _buildDisplayName(Placemark p) {
    final parts = <String>[];
    if (p.street != null && p.street!.isNotEmpty) parts.add(p.street!);
    if (p.locality != null && p.locality!.isNotEmpty) parts.add(p.locality!);
    if (p.administrativeArea != null &&
        p.administrativeArea!.isNotEmpty &&
        p.administrativeArea != p.locality) {
      parts.add(p.administrativeArea!);
    }
    if (p.country != null && p.country!.isNotEmpty) parts.add(p.country!);
    return parts.isNotEmpty ? parts.join(', ') : '$latitude, $longitude';
  }

  /// Build a short name (city or town).
  static String _buildShortName(Placemark p) {
    return p.locality ??
        p.subAdministrativeArea ??
        p.administrativeArea ??
        'Unknown';
  }
}
