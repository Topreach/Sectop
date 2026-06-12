import 'dart:convert';
import 'dart:math';
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

  /// No-op initialize for compatibility with [safeInit] in main.dart.
  /// The duck-type check `dynInstance.initialize is Function` requires
  /// this getter to exist; otherwise a NoSuchMethodError is thrown.
  Future<void> initialize() async {
    // BackendApi is stateless — nothing to initialize.
  }

  final OfflineStorageService _storage = OfflineStorageService();
  final String _baseUrl = '${AppConstants.apiBaseUrl}/${AppConstants.apiVersion}';
  final Duration _timeout = Duration(seconds: AppConstants.apiTimeout);

  http.Client _client = http.Client();

  @visibleForTesting
  void setClient(http.Client client) => _client = client;

  @visibleForTesting
  void resetCircuitBreaker() {
    _circuitState = CircuitState.closed;
    _consecutiveFailures = 0;
    _lastFailureTime = null;
  }

  @visibleForTesting
  bool isCircuitOpen() => _circuitState == CircuitState.open;

  CircuitState _circuitState = CircuitState.closed;
  int _consecutiveFailures = 0;
  static const int _failureThreshold = 5;
  static const Duration _resetTimeout = Duration(seconds: 30);
  DateTime? _lastFailureTime;

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
  // Resilience: retry with exponential backoff + circuit breaker
  // ---------------------------------------------------------------------------

  Future<T> _retryWithBackoff<T>(Future<T> Function() request) async {
    int attempt = 0;
    while (true) {
      try {
        return await request();
      } catch (e) {
        attempt++;
        if (attempt >= AppConstants.apiRetryCount) rethrow;
        final delay = Duration(seconds: min(pow(2, attempt).toInt(), 10));
        debugPrint('BackendApi: Retry $attempt/${AppConstants.apiRetryCount} after $delay: $e');
        await Future.delayed(delay);
      }
    }
  }

  Future<T> _executeWithCircuitBreaker<T>(Future<T> Function() request) async {
    if (_circuitState == CircuitState.open) {
      if (DateTime.now().difference(_lastFailureTime!) > _resetTimeout) {
        _circuitState = CircuitState.halfOpen;
      } else {
        throw ApiException(503, 'Circuit breaker is open - backend unavailable');
      }
    }
    try {
      final result = await _retryWithBackoff(request);
      _consecutiveFailures = 0;
      _circuitState = CircuitState.closed;
      return result;
    } catch (e) {
      _consecutiveFailures++;
      _lastFailureTime = DateTime.now();
      if (_consecutiveFailures >= _failureThreshold) {
        _circuitState = CircuitState.open;
        debugPrint('BackendApi: Circuit breaker opened after $_consecutiveFailures failures');
      }
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Generic HTTP methods
  // ---------------------------------------------------------------------------

  /// Perform a GET request and parse the JSON response.
  Future<Map<String, dynamic>> get(String path) async {
    return _executeWithCircuitBreaker(() async {
      final uri = Uri.parse('$_baseUrl$path');
      final response = await _client
          .get(uri, headers: await _headers())
          .timeout(_timeout);
      return _handleResponse(response);
    });
  }

  /// Perform a POST request with an optional JSON body.
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    return _executeWithCircuitBreaker(() async {
      final uri = Uri.parse('$_baseUrl$path');
      final response = await _client
          .post(
            uri,
            headers: await _headers(),
            body: body != null ? json.encode(body) : null,
          )
          .timeout(_timeout);
      return _handleResponse(response);
    });
  }

  /// Perform a PUT request with an optional JSON body.
  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    return _executeWithCircuitBreaker(() async {
      final uri = Uri.parse('$_baseUrl$path');
      final response = await _client
          .put(
            uri,
            headers: await _headers(),
            body: body != null ? json.encode(body) : null,
          )
          .timeout(_timeout);
      return _handleResponse(response);
    });
  }

  /// Perform a DELETE request.
  Future<void> delete(String path) async {
    return _executeWithCircuitBreaker(() async {
      final uri = Uri.parse('$_baseUrl$path');
      await _client
          .delete(uri, headers: await _headers())
          .timeout(_timeout);
    });
  }

  Map<String, dynamic> _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return {};
      final decoded = json.decode(response.body);
      if (decoded is List) {
        return {'data': decoded};
      }
      return decoded as Map<String, dynamic>;
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
  // ---------------------------------------------------------------------------
  // Zones
  // ---------------------------------------------------------------------------

  /// Get active zones.
  Future<Map<String, dynamic>> getActiveZones() async {
    return get('/zones/active');
  }

  /// Get danger zones.
  Future<Map<String, dynamic>> getDangerZones() async {
    return get('/zones/danger');
  }

  /// Get restricted zones.
  Future<Map<String, dynamic>> getRestrictedZones() async {
    return get('/zones/restricted');
  }

  /// Get zones nearby a location.
  Future<Map<String, dynamic>> getZonesNearby(double lat, double lng, {double radiusDegrees = 0.5}) async {
    return get('/zones/nearby?latitude=$lat&longitude=$lng&radiusDegrees=$radiusDegrees');
  }

  /// Create a new zone.
  Future<Map<String, dynamic>> createZone(Map<String, dynamic> zoneData) async {
    return post('/zones', body: zoneData);
  }

  // ---------------------------------------------------------------------------
  // Messages
  // ---------------------------------------------------------------------------

  /// Get messages for a user.
  Future<Map<String, dynamic>> getMessages(String userId) async {
    return get('/messages/user/$userId');
  }

  /// Get unread message count for a user.
  Future<Map<String, dynamic>> getUnreadCount(String userId) async {
    return get('/messages/unread/$userId');
  }

  /// Mark a message as read.
  Future<void> markMessageRead(String messageId) async {
    await put('/messages/$messageId/read');
  }

  /// Send a message.
  Future<Map<String, dynamic>> sendMessage(Map<String, dynamic> messageData) async {
    return post('/messages', body: messageData);
  }

  // ---------------------------------------------------------------------------
  // Alerts
  // ---------------------------------------------------------------------------

  /// Get active alerts.
  Future<Map<String, dynamic>> getActiveAlerts() async {
    return get('/alerts/active');
  }

  /// Get alerts for a user.
  Future<Map<String, dynamic>> getUserAlerts(String userId) async {
    return get('/alerts/user/$userId');
  }

  /// Get alert count.
  Future<Map<String, dynamic>> getAlertCount() async {
    return get('/alerts/count');
  }

  // ---------------------------------------------------------------------------
  // Incidents (Kidnapper/Danger Location Detection)
  // ---------------------------------------------------------------------------

  /// Report a new incident (kidnapping, terrorism, suspicious activity, etc.)
  Future<Map<String, dynamic>> reportIncident({
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
    return post('/incidents', body: {
      'reporterId': reporterId,
      'incidentType': incidentType,
      'description': description,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'occurredAt': occurredAt ?? DateTime.now().toIso8601String(),
      'severity': severity,
      'isAnonymous': isAnonymous,
    });
  }

  /// Get verified incidents near a location.
  Future<Map<String, dynamic>> getNearbyIncidents({
    required double latitude,
    required double longitude,
    double radiusKm = 10,
    List<String>? types,
  }) async {
    String typesParam = '';
    if (types != null && types.isNotEmpty) {
      typesParam = '&types=${types.join(',')}';
    }
    return get('/incidents/nearby?latitude=$latitude&longitude=$longitude&radiusKm=$radiusKm$typesParam');
  }

  /// Get heatmap data for danger zone visualization.
  Future<Map<String, dynamic>> getIncidentHeatmap({
    required double latitude,
    required double longitude,
    double radiusKm = 20,
    String? since,
  }) async {
    String sinceParam = since != null ? '&since=$since' : '';
    return get('/incidents/heatmap?latitude=$latitude&longitude=$longitude&radiusKm=$radiusKm$sinceParam');
  }

  /// Upvote an incident (community validation).
  Future<void> upvoteIncident(String incidentId) async {
    await post('/incidents/$incidentId/upvote');
  }

  /// Get incident statistics.
  Future<Map<String, dynamic>> getIncidentStats() async {
    return get('/incidents/stats');
  }
  // ---------------------------------------------------------------------------
  // Broadcasts (Mass Alert System)
  // ---------------------------------------------------------------------------

  /// Get active broadcasts, optionally filtered by state/LGA.
  Future<Map<String, dynamic>> getActiveBroadcasts({String? state, String? lga}) async {
    String params = '';
    if (state != null) params += '?state=$state';
    if (lga != null) params += '${params.isEmpty ? '?' : '&'}lga=$lga';
    return get('/broadcasts/active$params');
  }

  /// Get broadcast by ID.
  Future<Map<String, dynamic>> getBroadcast(String id) async {
    return get('/broadcasts/$id');
  }

  /// Create a new broadcast (coordinator/admin only).
  Future<Map<String, dynamic>> createBroadcast(Map<String, dynamic> data) async {
    return post('/broadcasts', body: data);
  }

  /// Expire a broadcast (coordinator/admin only).
  Future<void> expireBroadcast(String id) async {
    await post('/broadcasts/$id/expire');
  }

  /// Get active broadcast count.
  Future<Map<String, dynamic>> getBroadcastCount() async {
    return get('/broadcasts/count');
  }

  // ---------------------------------------------------------------------------
  // Safe Route Planning
  // ---------------------------------------------------------------------------

  /// Plan a safe route between two points.
  Future<Map<String, dynamic>> planSafeRoute({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
    bool avoidHighways = false,
    bool preferLitRoads = false,
  }) async {
    return post('/routes/plan', body: {
      'fromLat': fromLat,
      'fromLng': fromLng,
      'toLat': toLat,
      'toLng': toLng,
      'avoidHighways': avoidHighways,
      'preferLitRoads': preferLitRoads,
    });
  }

  /// Get danger score for a specific location.
  Future<Map<String, dynamic>> getDangerScore({
    required double latitude,
    required double longitude,
    double radiusKm = 5,
  }) async {
    return get('/routes/danger-score?latitude=$latitude&longitude=$longitude&radiusKm=$radiusKm');
  }

  // ---------------------------------------------------------------------------
  // Tip-offs (Intelligence Channel)
  // ---------------------------------------------------------------------------

  /// Submit a new tip-off (supports anonymous reporting).
  Future<Map<String, dynamic>> submitTip(Map<String, dynamic> data) async {
    return post('/tips', body: data);
  }

  /// Get pending tips for review (coordinator/responder only).
  Future<Map<String, dynamic>> getPendingTips() async {
    return get('/tips/pending');
  }

  /// Get tip-off by ID.
  Future<Map<String, dynamic>> getTipById(String id) async {
    return get('/tips/$id');
  }

  /// Review a tip-off (coordinator/responder only).
  Future<Map<String, dynamic>> reviewTip(String id, Map<String, dynamic> data) async {
    return post('/tips/$id/review', body: data);
  }

  /// Get tip-off statistics.
  Future<Map<String, dynamic>> getTipStats() async {
    return get('/tips/stats');
  }

  // ---------------------------------------------------------------------------
  // Radio Broadcasts (Emergency Radio Integration)
  // ---------------------------------------------------------------------------

  /// Create a new radio broadcast (coordinator/admin only).
  Future<Map<String, dynamic>> createRadioBroadcast(Map<String, dynamic> data) async {
    return post('/radio/broadcast', body: data);
  }

  /// Get radio broadcast history.
  Future<Map<String, dynamic>> getRadioBroadcasts() async {
    return get('/radio/broadcasts');
  }

  /// Get radio broadcast by ID.
  Future<Map<String, dynamic>> getRadioBroadcast(String id) async {
    return get('/radio/broadcasts/$id');
  }

  /// Retry a failed radio broadcast (coordinator/admin only).
  Future<Map<String, dynamic>> retryRadioBroadcast(String id) async {
    return post('/radio/broadcasts/$id/retry');
  }

  // ---------------------------------------------------------------------------
  // Auth — Password Reset & Account Deletion (Store Compliance)
  // ---------------------------------------------------------------------------

  /// Request a password reset email.
  Future<Map<String, dynamic>> forgotPassword(String email) async {
    return post('/auth/forgot-password', body: {'email': email});
  }

  /// Reset password using the token from the email.
  Future<Map<String, dynamic>> resetPassword(String token, String newPassword) async {
    return post('/auth/reset-password', body: {
      'token': token,
      'newPassword': newPassword,
    });
  }

  /// Request account deletion (30-day grace period starts).
  Future<Map<String, dynamic>> requestAccountDeletion(String userId) async {
    final headers = await _headers();
    headers['X-User-Id'] = userId;
    return _executeWithCircuitBreaker(() async {
      final uri = Uri.parse('$_baseUrl/auth/account/deletion-request');
      final response = await _client
          .post(uri, headers: headers)
          .timeout(_timeout);
      return _handleResponse(response);
    });
  }

  /// Cancel a pending account deletion request.
  Future<Map<String, dynamic>> cancelAccountDeletion(String userId) async {
    final headers = await _headers();
    headers['X-User-Id'] = userId;
    return _executeWithCircuitBreaker(() async {
      final uri = Uri.parse('$_baseUrl/auth/account/cancel-deletion');
      final response = await _client
          .post(uri, headers: headers)
          .timeout(_timeout);
      return _handleResponse(response);
    });
  }

  /// Permanently delete the account (anonymizes PII).
  Future<void> deleteAccount(String userId) async {
    final headers = await _headers();
    headers['X-User-Id'] = userId;
    return _executeWithCircuitBreaker(() async {
      final uri = Uri.parse('$_baseUrl/auth/account');
      await _client
          .delete(uri, headers: headers)
          .timeout(_timeout);
    });
  }

  // ---------------------------------------------------------------------------
  // Evidence (Photo/Video/Audio Upload)
  // ---------------------------------------------------------------------------

  /// Upload evidence file (base64) associated with a parent entity.
  Future<Map<String, dynamic>> uploadEvidence({
    required String parentId,
    required String evidenceType,
    required String fileName,
    required String fileBytes,
    required String mimeType,
    String parentType = 'alert',
    double? latitude,
    double? longitude,
  }) async {
    return post('/evidence', body: {
      'parentId': parentId,
      'parentType': parentType,
      'evidenceType': evidenceType,
      'fileName': fileName,
      'mimeType': mimeType,
      'sizeBytes': fileBytes.length,
      'fileContent': fileBytes,
      'latitude': latitude,
      'longitude': longitude,
    });
  }

  /// Get all evidence for a parent entity.
  Future<Map<String, dynamic>> getEvidence(String parentId) async {
    return get('/evidence/parent/$parentId');
  }

  /// Get a single evidence record by ID.
  Future<Map<String, dynamic>> getEvidenceById(String id) async {
    return get('/evidence/$id');
  }

  /// Delete evidence by ID.
  Future<void> deleteEvidence(String id) async {
    await delete('/evidence/$id');
  }

  /// Delete all evidence for a parent entity.
  Future<void> deleteEvidenceForParent(String parentId) async {
    await delete('/evidence/parent/$parentId');
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

enum CircuitState { closed, open, halfOpen }
