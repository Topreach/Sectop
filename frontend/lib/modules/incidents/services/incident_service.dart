import 'package:flutter/foundation.dart';
import '../../../shared/services/backend_api.dart';

/// Service for crowdsourced incident reporting and danger location detection.
///
/// Supports:
/// - Reporting kidnappings, terrorism, banditry, suspicious activity
/// - Anonymous reporting for safety
/// - Heatmap visualization of danger zones
/// - Nearby incident queries
/// - Community validation (upvoting)
class IncidentService extends ChangeNotifier {
  static final IncidentService _instance = IncidentService._internal();
  factory IncidentService() => _instance;
  IncidentService._internal();

  final BackendApi _api = BackendApi();

  bool _isLoading = false;
  String? _lastError;

  bool get isLoading => _isLoading;
  String? get lastError => _lastError;

  /// Report a new incident (kidnapping, terrorism, suspicious activity, etc.)
  Future<Map<String, dynamic>?> reportIncident({
    String? reporterId,
    required String incidentType,
    String? description,
    required double latitude,
    required double longitude,
    double? accuracy,
    String? occurredAt,
    String severity = 'medium',
    bool isAnonymous = false,
  }) async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();

    try {
      final result = await _api.reportIncident(
        reporterId: reporterId,
        incidentType: incidentType,
        description: description,
        latitude: latitude,
        longitude: longitude,
        accuracy: accuracy,
        occurredAt: occurredAt,
        severity: severity,
        isAnonymous: isAnonymous,
      );
      _isLoading = false;
      notifyListeners();
      return result;
    } catch (e) {
      _lastError = e.toString();
      _isLoading = false;
      notifyListeners();
      debugPrint('IncidentService: Failed to report incident: $e');
      return null;
    }
  }

  /// Get verified incidents near a location.
  Future<List<Map<String, dynamic>>> getNearbyIncidents({
    required double latitude,
    required double longitude,
    double radiusKm = 10,
    List<String>? types,
  }) async {
    try {
      final result = await _api.getNearbyIncidents(
        latitude: latitude,
        longitude: longitude,
        radiusKm: radiusKm,
        types: types,
      );
      final incidents = result['incidents'];
      if (incidents is List) {
        return incidents.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      debugPrint('IncidentService: Failed to get nearby incidents: $e');
      return [];
    }
  }

  /// Get heatmap data for danger zone visualization.
  Future<List<Map<String, dynamic>>> getHeatmapData({
    required double latitude,
    required double longitude,
    double radiusKm = 20,
    String? since,
  }) async {
    try {
      final result = await _api.getIncidentHeatmap(
        latitude: latitude,
        longitude: longitude,
        radiusKm: radiusKm,
        since: since,
      );
      final heatmap = result['heatmap'];
      if (heatmap is List) {
        return heatmap.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      debugPrint('IncidentService: Failed to get heatmap data: $e');
      return [];
    }
  }

  /// Upvote an incident (community validation).
  Future<bool> upvoteIncident(String incidentId) async {
    try {
      await _api.upvoteIncident(incidentId);
      return true;
    } catch (e) {
      debugPrint('IncidentService: Failed to upvote incident: $e');
      return false;
    }
  }

  /// Get incident statistics for dashboard.
  Future<Map<String, dynamic>> getStatistics() async {
    try {
      return await _api.getIncidentStats();
    } catch (e) {
      debugPrint('IncidentService: Failed to get statistics: $e');
      return {};
    }
  }

  /// Get a human-readable label for an incident type.
  static String getIncidentTypeLabel(String type) {
    switch (type) {
      case 'kidnapping':
        return 'Kidnapping';
      case 'terrorism':
        return 'Terrorism';
      case 'banditry':
        return 'Banditry';
      case 'armed_robbery':
        return 'Armed Robbery';
      case 'suspicious_activity':
        return 'Suspicious Activity';
      case 'herdsmen_attack':
        return 'Herdsmen Attack';
      case 'cult_violence':
        return 'Cult Violence';
      case 'ritual_killings':
        return 'Ritual Killings';
      case 'political_violence':
        return 'Political Violence';
      case 'communal_clash':
        return 'Communal Clash';
      case 'other':
        return 'Other';
      default:
        return type;
    }
  }

  /// Get an icon for an incident type.
  static String getIncidentTypeIcon(String type) {
    switch (type) {
      case 'kidnapping':
        return '🔗';
      case 'terrorism':
        return '💣';
      case 'banditry':
        return '🔫';
      case 'armed_robbery':
        return '💰';
      case 'suspicious_activity':
        return '👁️';
      case 'herdsmen_attack':
        return '🐄';
      case 'cult_violence':
        return '⚔️';
      case 'ritual_killings':
        return '🕯️';
      case 'political_violence':
        return '🏛️';
      case 'communal_clash':
        return '🔥';
      default:
        return '⚠️';
    }
  }

  /// Get severity color.
  static int getSeverityColor(String severity) {
    switch (severity) {
      case 'critical':
        return 0xFFD32F2F; // Red
      case 'high':
        return 0xFFFF5722; // Deep Orange
      case 'medium':
        return 0xFFFFC107; // Amber
      case 'low':
        return 0xFF4CAF50; // Green
      default:
        return 0xFF9E9E9E; // Grey
    }
  }
}
