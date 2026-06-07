import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../core/constants.dart';
import 'offline_storage.dart';

/// Centralized HTTP client for all backend API communication.
///
/// All frontend services use this class instead of making raw HTTP calls.
/// Provides automatic auth headers, timeout handling, and error normalization.
class BackendApi {
  static final BackendApi _instance = BackendApi._();
  factory BackendApi() => _instance;
  BackendApi._();

  final OfflineStorageService _storage = OfflineStorageService();
  final String _baseUrl = '${AppConstants.apiBaseUrl}/${AppConstants.apiVersion}';
  final Duration _timeout = Duration(seconds: AppConstants.apiTimeout);

  // ---------------------------------------------------------------------------
  // Auth headers
  // ---------------------------------------------------------------------------

  Future<Map<String, String>> _headers() async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    try {
      final token = await _storage.getSensitiveSetting(AppConstants.keyAuthToken);
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    } catch (_) {}
    return headers;
  }

  // ---------------------------------------------------------------------------
  // Generic HTTP methods
  // ---------------------------------------------------------------------------

  /// Perform a GET request and parse the JSON response.
  Future<Map<String, dynamic>> get(String path) async {
    final uri = Uri.parse('$_baseUrl$path');
    final response = await http
        .get(uri, headers: await _headers())
        .timeout(_timeout);
    return _handleResponse(response);
  }

  /// Perform a POST request with an optional JSON body.
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    final response = await http
        .post(
          uri,
          headers: await _headers(),
          body: body != null ? json.encode(body) : null,
        )
        .timeout(_timeout);
    return _handleResponse(response);
  }

  /// Perform a PUT request with an optional JSON body.
  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    final response = await http
        .put(
          uri,
          headers: await _headers(),
          body: body != null ? json.encode(body) : null,
        )
        .timeout(_timeout);
    return _handleResponse(response);
  }

  /// Perform a DELETE request.
  Future<void> delete(String path) async {
    final uri = Uri.parse('$_baseUrl$path');
    await http
        .delete(uri, headers: await _headers())
        .timeout(_timeout);
  }

  Map<String, dynamic> _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return {};
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw ApiException(response.statusCode, response.body);
  }

  // ---------------------------------------------------------------------------
  // AI / ML
  // ---------------------------------------------------------------------------

  /// Analyze a text message for distress signals.
  Future<Map<String, dynamic>> analyzeMessage(String text, {String userId = 'anonymous'}) async {
    return post('/ai/analyze-message', body: {
      'text': text,
      'userId': userId,
    });
  }

  /// Prioritize a message (returns priority level and confidence).
  Future<Map<String, dynamic>> prioritize(String text) async {
    return post('/ai/prioritize', body: {'text': text});
  }

  /// Batch prioritize multiple messages.
  Future<Map<String, dynamic>> prioritizeBatch(List<String> texts) async {
    return post('/ai/prioritize-batch', body: {'texts': texts});
  }

  /// Analyze audio data for distress signals.
  Future<Map<String, dynamic>> analyzeAudio(String base64Audio) async {
    return post('/ai/analyze-audio', body: {'audio': base64Audio});
  }

  // ---------------------------------------------------------------------------
  // Predictive Analytics
  // ---------------------------------------------------------------------------

  /// Get danger zone forecasts.
  Future<Map<String, dynamic>> forecastDangerZones(
    List<String> zoneIds, {
    int historyHours = 72,
    int forecastHours = 6,
  }) async {
    return post('/predictive/forecast', body: {
      'zoneIds': zoneIds,
      'historyHours': historyHours,
      'forecastHours': forecastHours,
    });
  }

  /// Detect anomalies in a time series of values.
  Future<Map<String, dynamic>> detectAnomaly(List<double> values) async {
    return post('/predictive/anomaly', body: {'values': values});
  }

  /// Optimize resource deployment across zones and responders.
  Future<Map<String, dynamic>> optimizeResources(
    List<Map<String, dynamic>> zones,
    List<Map<String, dynamic>> responders,
  ) async {
    return post('/predictive/optimize-resources', body: {
      'zones': zones,
      'responders': responders,
    });
  }

  // ---------------------------------------------------------------------------
  // Digital Twin
  // ---------------------------------------------------------------------------

  /// Get city tileset configuration.
  Future<Map<String, dynamic>> getCityTileset(String cityId) async {
    return get('/digital-twin/cities/$cityId/tileset');
  }

  /// Get building metadata for a city.
  Future<Map<String, dynamic>> getCityBuildings(String cityId) async {
    return get('/digital-twin/cities/$cityId/buildings');
  }

  /// Run hazard propagation simulation.
  Future<Map<String, dynamic>> predictPropagation(Map<String, dynamic> params) async {
    return post('/digital-twin/predict-propagation', body: params);
  }

  /// Get evacuation plan for a location.
  Future<Map<String, dynamic>> getEvacuationPlan(double latitude, double longitude) async {
    return post('/digital-twin/evacuation-plan', body: {
      'latitude': latitude,
      'longitude': longitude,
    });
  }

  // ---------------------------------------------------------------------------
  // Drones
  // ---------------------------------------------------------------------------

  /// Get available drones near a location.
  Future<Map<String, dynamic>> getAvailableDrones({
    double latitude = 0,
    double longitude = 0,
  }) async {
    return get('/drones/available?latitude=$latitude&longitude=$longitude');
  }

  /// Deploy a LoRa relay drone.
  Future<Map<String, dynamic>> deployRelayDrone(
    String droneId,
    double latitude,
    double longitude,
  ) async {
    return post('/drones/deploy-relay', body: {
      'droneId': droneId,
      'latitude': latitude,
      'longitude': longitude,
    });
  }

  /// Run damage assessment for a zone.
  Future<Map<String, dynamic>> assessDamage(
    String zoneId,
    double centerLat,
    double centerLng,
    double radiusKm,
  ) async {
    return post('/drones/assess-damage', body: {
      'zoneId': zoneId,
      'centerLat': centerLat,
      'centerLng': centerLng,
      'radiusKm': radiusKm,
    });
  }

  /// Deploy a swarm mesh around a zone.
  Future<Map<String, dynamic>> deploySwarmMesh(
    String zoneId,
    double centerLat,
    double centerLng,
    double radiusKm,
  ) async {
    return post('/drones/deploy-swarm', body: {
      'zoneId': zoneId,
      'centerLat': centerLat,
      'centerLng': centerLng,
      'radiusKm': radiusKm,
    });
  }

  // ---------------------------------------------------------------------------
  // Mesh Network
  // ---------------------------------------------------------------------------

  /// Find optimal route between two mesh devices.
  Future<Map<String, dynamic>> findRoute(
    String sourceDeviceId,
    String targetDeviceId, {
    List<Map<String, dynamic>> neighborMetrics = const [],
  }) async {
    return post('/mesh/route', body: {
      'sourceDeviceId': sourceDeviceId,
      'targetDeviceId': targetDeviceId,
      'neighborMetrics': neighborMetrics,
    });
  }

  /// Broadcast a message through the mesh network.
  Future<Map<String, dynamic>> broadcastMeshMessage(
    String sourceDeviceId,
    String messageType,
    int priority,
    Map<String, dynamic> payload,
  ) async {
    return post('/mesh/broadcast', body: {
      'sourceDeviceId': sourceDeviceId,
      'messageType': messageType,
      'priority': priority,
      'payload': payload,
    });
  }

  /// Get known mesh peers.
  Future<Map<String, dynamic>> getMeshPeers() async {
    return get('/mesh/peers');
  }

  /// Report mesh statistics.
  Future<Map<String, dynamic>> reportMeshStats(Map<String, dynamic> stats) async {
    return post('/mesh/stats', body: stats);
  }

  // ---------------------------------------------------------------------------
  // Observability
  // ---------------------------------------------------------------------------

  /// Send trace spans to the backend.
  Future<void> sendTraces(List<Map<String, dynamic>> spans) async {
    try {
      await post('/observability/traces', body: {'spans': spans});
    } catch (e) {
      debugPrint('BackendApi: Failed to send traces: $e');
    }
  }

  /// Send metrics to the backend.
  Future<void> sendMetrics(List<Map<String, dynamic>> metrics) async {
    try {
      await post('/observability/metrics', body: {'metrics': metrics});
    } catch (e) {
      debugPrint('BackendApi: Failed to send metrics: $e');
    }
  }

  /// Send logs to the backend.
  Future<void> sendLogs(List<Map<String, dynamic>> logs) async {
    try {
      await post('/observability/logs', body: {'logs': logs});
    } catch (e) {
      debugPrint('BackendApi: Failed to send logs: $e');
    }
  }

  /// Send a crash report to the backend.
  Future<void> sendCrashReport(Map<String, dynamic> report) async {
    try {
      await post('/observability/crash-report', body: report);
    } catch (e) {
      debugPrint('BackendApi: Failed to send crash report: $e');
    }
  }
}

/// Exception thrown when the API returns a non-2xx status code.
class ApiException implements Exception {
  final int statusCode;
  final String body;

  ApiException(this.statusCode, this.body);

  @override
  String toString() => 'ApiException($statusCode): $body';
}
