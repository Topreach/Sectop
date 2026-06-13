import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../shared/services/backend_api.dart';
import '../../../shared/services/offline_storage.dart';
import '../../incidents/services/incident_service.dart';
import '../../maps/services/map_service.dart';
import 'distress_detector.dart';
import 'ambient_audio_monitor.dart';

/// Result of a threat analysis.
class ThreatAlert {
  final String id;
  final String type; // 'incident', 'danger_zone', 'sos_alert', 'message_analysis'
  final String title;
  final String description;
  final double? latitude;
  final double? longitude;
  final String severity; // 'low', 'medium', 'high', 'critical'
  final double confidence;
  final DateTime timestamp;
  final bool isRead;
  final Map<String, dynamic>? sourceData;

  ThreatAlert({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    this.latitude,
    this.longitude,
    required this.severity,
    required this.confidence,
    required this.timestamp,
    this.isRead = false,
    this.sourceData,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'title': title,
    'description': description,
    'latitude': latitude,
    'longitude': longitude,
    'severity': severity,
    'confidence': confidence,
    'timestamp': timestamp.toIso8601String(),
    'isRead': isRead,
    'sourceData': sourceData,
  };

  factory ThreatAlert.fromJson(Map<String, dynamic> json) => ThreatAlert(
    id: json['id'] as String,
    type: json['type'] as String,
    title: json['title'] as String,
    description: json['description'] as String,
    latitude: json['latitude'] as double?,
    longitude: json['longitude'] as double?,
    severity: json['severity'] as String,
    confidence: (json['confidence'] as num).toDouble(),
    timestamp: DateTime.parse(json['timestamp'] as String),
    isRead: json['isRead'] as bool? ?? false,
    sourceData: json['sourceData'] as Map<String, dynamic>?,
  );
}

/// Proactive threat awareness service that continuously monitors the
/// environment for terrorist activity, kidnappings, and other dangers.
///
/// Features:
/// - Periodic polling of nearby incidents and danger zones
/// - Automatic message analysis via ML service
/// - Threat level calculation for current location
/// - Push-style alert generation for the dashboard
/// - Local caching of threat alerts for offline access
class ThreatAwarenessService extends ChangeNotifier {
  static final ThreatAwarenessService _instance =
      ThreatAwarenessService._internal();
  factory ThreatAwarenessService() => _instance;
  ThreatAwarenessService._internal();

  final BackendApi _api = BackendApi();
  final IncidentService _incidentService = IncidentService();
  final DistressDetector _distressDetector = DistressDetector();
  final OfflineStorageService _storage = OfflineStorageService();
  final AmbientAudioMonitor _ambientAudioMonitor = AmbientAudioMonitor();

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  List<ThreatAlert> _alerts = [];
  bool _isMonitoring = false;
  bool _isLoading = false;
  String? _lastError;
  double _currentThreatLevel = 0.0; // 0.0 - 1.0
  int _nearbyIncidentCount = 0;
  int _nearbyDangerZoneCount = 0;
  Timer? _pollTimer;
  Timer? _analysisTimer;

  // Configuration
  static const int _pollIntervalSeconds = 60; // Poll incidents every 60s
  static const int _analysisIntervalSeconds = 300; // Analyze messages every 5min
  static const double _threatRadiusKm = 20.0; // Radius for nearby threats
  static const int _maxAlerts = 50;
  static const String _alertsStorageKey = 'threat_alerts';

  // Getters
  List<ThreatAlert> get alerts => List.unmodifiable(_alerts);
  bool get isMonitoring => _isMonitoring;
  bool get isLoading => _isLoading;
  String? get lastError => _lastError;
  double get currentThreatLevel => _currentThreatLevel;
  int get nearbyIncidentCount => _nearbyIncidentCount;
  int get nearbyDangerZoneCount => _nearbyDangerZoneCount;

  /// Get unread alert count.
  int get unreadCount => _alerts.where((a) => !a.isRead).length;

  /// Get critical/high severity alerts.
  List<ThreatAlert> get criticalAlerts =>
      _alerts.where((a) => a.severity == 'critical' || a.severity == 'high').toList();

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Start proactive threat monitoring.
  /// Start proactive threat monitoring.
  Future<void> startMonitoring() async {
    if (_isMonitoring) return;
    _isMonitoring = true;
    notifyListeners();

    // Load cached alerts first
    await _loadCachedAlerts();

    // Immediate first poll
    await pollThreats();

    // Start periodic polling
    _pollTimer = Timer.periodic(
      Duration(seconds: _pollIntervalSeconds),
      (_) => pollThreats(),
    );

    // Start periodic message analysis
    _analysisTimer = Timer.periodic(
      Duration(seconds: _analysisIntervalSeconds),
      (_) => analyzeRecentMessages(),
    );

    // Start ambient audio monitoring
    await _ambientAudioMonitor.startMonitoring();

    debugPrint('ThreatAwarenessService: Monitoring started');
  }

  /// Stop proactive threat monitoring.
  Future<void> stopMonitoring() async {
    _isMonitoring = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _analysisTimer?.cancel();
    _analysisTimer = null;
    await _ambientAudioMonitor.stopMonitoring();
    notifyListeners();
    debugPrint('ThreatAwarenessService: Monitoring stopped');
  }
  @override
  void dispose() {
    stopMonitoring();
    _ambientAudioMonitor.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Threat Polling
  // ---------------------------------------------------------------------------

  /// Poll all threat sources and update state.
  Future<void> pollThreats() async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();

    try {
      final mapService = MapService();
      final position = mapService.currentPosition;

      if (position == null) {
        debugPrint('ThreatAwarenessService: No position available, skipping poll');
        _isLoading = false;
        return;
      }

      // Fetch nearby incidents
      final incidents = await _incidentService.getNearbyIncidents(
        latitude: position.latitude,
        longitude: position.longitude,
        radiusKm: _threatRadiusKm,
      );

      // Fetch nearby danger zones
      final zonesResponse = await _api.getZonesNearby(
        position.latitude,
        position.longitude,
        radiusDegrees: _threatRadiusKm / 111.0,
      );
      final zones = zonesResponse['zones'] as List? ?? [];

      // Fetch active alerts
      final alertsResponse = await _api.getActiveAlerts();
      final activeAlerts = alertsResponse['alerts'] as List? ?? [];

      // Update counts
      _nearbyIncidentCount = incidents.length;
      _nearbyDangerZoneCount = zones.length;

      // Calculate overall threat level (0.0 - 1.0)
      _calculateThreatLevel(incidents, zones, activeAlerts);

      // Generate alerts for new threats
      _processIncidents(incidents);
      _processDangerZones(zones);
      _processActiveAlerts(activeAlerts);

      // Trim to max
      if (_alerts.length > _maxAlerts) {
        _alerts = _alerts.sublist(0, _maxAlerts);
      }

      // Cache alerts
      await _cacheAlerts();

      _lastError = null;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _lastError = e.toString();
      _isLoading = false;
      debugPrint('ThreatAwarenessService: Poll failed: $e');
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Message Analysis
  // ---------------------------------------------------------------------------

  /// Analyze recent messages from the inbox for threat content.
  Future<void> analyzeRecentMessages() async {
    try {
      // Get recent messages from offline storage
      final recentMessages = await _storage.query('messages',
          orderBy: 'created_at DESC',
          limit: 20);

      for (final msg in recentMessages) {
        final text = msg['content'] as String?;
        if (text == null || text.length < 10) continue;

        // Skip already analyzed messages
        final msgId = msg['id'] as String?;
        if (msgId != null && _alerts.any((a) =>
            a.sourceData?['messageId'] == msgId)) {
          continue;
        }

        // Analyze via ML service
        final result = await _distressDetector.analyzeMessage(text);

        if (result.priority == 'high' || result.priority == 'critical') {
          _addAlert(ThreatAlert(
            id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
            type: 'message_analysis',
            title: 'Threat Detected in Message',
            description: result.reasons.isNotEmpty
                ? result.reasons.join(', ')
                : 'Message content flagged as ${result.priority} priority',
            latitude: (msg['latitude'] as num?)?.toDouble(),
            longitude: (msg['longitude'] as num?)?.toDouble(),
            severity: result.priority,
            confidence: result.confidence,
            timestamp: DateTime.now(),
            sourceData: {
              'messageId': msgId,
              'text': text,
              'label': result.label,
            },
          ));
        }
      }
    } catch (e) {
      debugPrint('ThreatAwarenessService: Message analysis failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Manual Threat Check
  // ---------------------------------------------------------------------------

  /// Get the ambient audio monitor instance.
  AmbientAudioMonitor get ambientAudioMonitor => _ambientAudioMonitor;

  /// Manually analyze a piece of text for threat content.
  Future<ThreatAlert?> analyzeText(String text) async {
    try {
      final result = await _distressDetector.analyzeMessage(text);

      if (result.priority == 'high' || result.priority == 'critical') {
        final alert = ThreatAlert(
          id: 'manual_${DateTime.now().millisecondsSinceEpoch}',
          type: 'message_analysis',
          title: 'Threat Detected in Text',
          description: result.reasons.isNotEmpty
              ? result.reasons.join(', ')
              : 'Text flagged as ${result.priority} priority',
          severity: result.priority,
          confidence: result.confidence,
          timestamp: DateTime.now(),
          sourceData: {
            'text': text,
            'label': result.label,
          },
        );
        _addAlert(alert);
        return alert;
      }
    } catch (e) {
      debugPrint('ThreatAwarenessService: Text analysis failed: $e');
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Alert Management
  // ---------------------------------------------------------------------------

  /// Mark an alert as read.
  void markAsRead(String alertId) {
    final index = _alerts.indexWhere((a) => a.id == alertId);
    if (index >= 0) {
      final alert = _alerts[index];
      _alerts[index] = ThreatAlert(
        id: alert.id,
        type: alert.type,
        title: alert.title,
        description: alert.description,
        latitude: alert.latitude,
        longitude: alert.longitude,
        severity: alert.severity,
        confidence: alert.confidence,
        timestamp: alert.timestamp,
        isRead: true,
        sourceData: alert.sourceData,
      );
      notifyListeners();
      _cacheAlerts();
    }
  }

  /// Mark all alerts as read.
  void markAllAsRead() {
    _alerts = _alerts.map((a) => ThreatAlert(
      id: a.id,
      type: a.type,
      title: a.title,
      description: a.description,
      latitude: a.latitude,
      longitude: a.longitude,
      severity: a.severity,
      confidence: a.confidence,
      timestamp: a.timestamp,
      isRead: true,
      sourceData: a.sourceData,
    )).toList();
    notifyListeners();
    _cacheAlerts();
  }

  /// Clear all alerts.
  Future<void> clearAlerts() async {
    _alerts.clear();
    _currentThreatLevel = 0.0;
    _nearbyIncidentCount = 0;
    _nearbyDangerZoneCount = 0;
    await _storage.remove(_alertsStorageKey);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Internal Helpers
  // ---------------------------------------------------------------------------

  void _addAlert(ThreatAlert alert) {
    // Avoid duplicates by checking if similar alert already exists
    final exists = _alerts.any((a) =>
        a.type == alert.type &&
        a.title == alert.title &&
        a.timestamp.difference(alert.timestamp).inMinutes < 5);

    if (!exists) {
      _alerts.insert(0, alert);
      notifyListeners();
    }
  }

  void _processIncidents(List<Map<String, dynamic>> incidents) {
    for (final incident in incidents) {
      final id = incident['id'] as String?;
      final type = incident['incidentType'] as String? ?? 'unknown';
      final severity = incident['severity'] as String? ?? 'medium';
      final description = incident['description'] as String? ?? '';
      final lat = (incident['latitude'] as num?)?.toDouble();
      final lng = (incident['longitude'] as num?)?.toDouble();

      // Skip if already alerted
      if (id != null && _alerts.any((a) => a.sourceData?['incidentId'] == id)) {
        continue;
      }

      // Only alert for high/critical severity
      if (severity == 'high' || severity == 'critical') {
        final typeLabel = _getIncidentTypeLabel(type);
        _addAlert(ThreatAlert(
          id: 'inc_${id ?? DateTime.now().millisecondsSinceEpoch}',
          type: 'incident',
          title: '$typeLabel Reported Nearby',
          description: description.isNotEmpty ? description : 'A $typeLabel incident has been reported in your area',
          latitude: lat,
          longitude: lng,
          severity: severity,
          confidence: 0.85,
          timestamp: DateTime.now(),
          sourceData: {
            'incidentId': id,
            'incidentType': type,
          },
        ));
      }
    }
  }

  void _processDangerZones(List<dynamic> zones) {
    for (final z in zones) {
      final zone = z as Map<String, dynamic>;
      final id = zone['id'] as String?;
      final name = zone['name'] as String? ?? 'Unknown Zone';
      final severity = zone['severity'] as String? ?? 'medium';
      final lat = (zone['latitude'] as num?)?.toDouble();
      final lng = (zone['longitude'] as num?)?.toDouble();

      if (id != null && _alerts.any((a) => a.sourceData?['zoneId'] == id)) {
        continue;
      }

      if (severity == 'high' || severity == 'critical') {
        _addAlert(ThreatAlert(
          id: 'zone_${id ?? DateTime.now().millisecondsSinceEpoch}',
          type: 'danger_zone',
          title: 'Danger Zone: $name',
          description: 'A ${severity}-severity danger zone is active in your area',
          latitude: lat,
          longitude: lng,
          severity: severity,
          confidence: 0.9,
          timestamp: DateTime.now(),
          sourceData: {
            'zoneId': id,
            'zoneName': name,
          },
        ));
      }
    }
  }

  void _processActiveAlerts(List<dynamic> alerts) {
    for (final a in alerts) {
      final alert = a as Map<String, dynamic>;
      final id = alert['id'] as String?;
      final type = alert['type'] as String? ?? 'alert';
      final lat = (alert['latitude'] as num?)?.toDouble();
      final lng = (alert['longitude'] as num?)?.toDouble();

      if (id != null && _alerts.any((a) => a.sourceData?['alertId'] == id)) {
        continue;
      }

      _addAlert(ThreatAlert(
        id: 'alert_${id ?? DateTime.now().millisecondsSinceEpoch}',
        type: 'sos_alert',
        title: type == 'sos' ? 'SOS Alert in Your Area' : 'Alert Nearby',
        description: alert['message'] as String? ?? 'An emergency alert has been issued nearby',
        latitude: lat,
        longitude: lng,
        severity: 'high',
        confidence: 0.95,
        timestamp: DateTime.now(),
        sourceData: {
          'alertId': id,
          'alertType': type,
        },
      ));
    }
  }

  void _calculateThreatLevel(
    List<Map<String, dynamic>> incidents,
    List<dynamic> zones,
    List<dynamic> alerts,
  ) {
    double level = 0.0;

    // Base level from incident count
    if (incidents.length > 10) level += 0.4;
    else if (incidents.length > 5) level += 0.3;
    else if (incidents.length > 2) level += 0.2;
    else if (incidents.length > 0) level += 0.1;

    // Boost from danger zones
    if (zones.length > 5) level += 0.3;
    else if (zones.length > 2) level += 0.2;
    else if (zones.length > 0) level += 0.1;

    // Boost from active alerts
    if (alerts.length > 3) level += 0.3;
    else if (alerts.length > 0) level += 0.15;

    // Check for critical severity items
    final hasCritical = incidents.any((i) =>
        (i['severity'] as String? ?? '') == 'critical') ||
        zones.any((z) => (z is Map && z['severity'] == 'critical'));
    if (hasCritical) level += 0.2;

    _currentThreatLevel = level.clamp(0.0, 1.0);
  }

  String _getIncidentTypeLabel(String type) {
    switch (type) {
      case 'kidnapping': return 'Kidnapping';
      case 'terrorism': return 'Terrorism';
      case 'banditry': return 'Banditry';
      case 'armed_robbery': return 'Armed Robbery';
      case 'suspicious_activity': return 'Suspicious Activity';
      case 'herdsmen_attack': return 'Herdsmen Attack';
      case 'cult_violence': return 'Cult Violence';
      case 'ritual_killings': return 'Ritual Killings';
      case 'political_violence': return 'Political Violence';
      case 'communal_clash': return 'Communal Clash';
      default: return type[0].toUpperCase() + type.substring(1);
    }
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  Future<void> _loadCachedAlerts() async {
    try {
      final cached = await _storage.getSetting(_alertsStorageKey);
      if (cached != null && cached.isNotEmpty) {
        final List<dynamic> decoded = json.decode(cached);
        _alerts = decoded
            .map((e) => ThreatAlert.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('ThreatAwarenessService: Failed to load cached alerts: $e');
    }
  }

  Future<void> _cacheAlerts() async {
    try {
      final json = json.encode(_alerts.map((a) => a.toJson()).toList());
      await _storage.setSetting(_alertsStorageKey, json);
    } catch (e) {
      debugPrint('ThreatAwarenessService: Failed to cache alerts: $e');
    }
  }
}
