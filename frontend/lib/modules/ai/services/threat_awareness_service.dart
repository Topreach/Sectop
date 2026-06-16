import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../core/constants.dart';
import '../../../shared/services/backend_api.dart';
import '../../../shared/services/offline_storage.dart';
import '../../incidents/services/incident_service.dart';
import '../../maps/services/map_service.dart';
import 'distress_detector.dart';
import 'ambient_audio_monitor.dart';

/// Result of a threat analysis.
class ThreatAlert {
  final String id;
  final String type; // 'incident', 'danger_zone', 'sos_alert', 'message_analysis', 'prediction'
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
/// - Real-time ML prediction updates via WebSocket
/// - Periodic polling of ML hotspot predictions (fallback)
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
  bool _isOffline = false;
  String? _lastError;
  double _currentThreatLevel = 0.0;
  int _nearbyIncidentCount = 0;
  int _nearbyDangerZoneCount = 0;
  int _predictedHotspotCount = 0;
  Timer? _pollTimer;
  Timer? _analysisTimer;
  Timer? _predictionPollTimer;

  // WebSocket for real-time prediction updates
  WebSocketChannel? _predictionWsChannel;
  StreamSubscription<dynamic>? _predictionWsSubscription;
  Timer? _predictionWsReconnectTimer;
  bool _isPredictionWsConnected = false;

  // Notification & Vibration
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  bool _notificationsInitialized = false;

  /// Callback invoked when a critical/high alert is added.
  void Function(ThreatAlert alert)? onCriticalAlert;

  // Configuration
  static const int _pollIntervalSeconds = 60;
  static const int _analysisIntervalSeconds = 300;
  static const double _threatRadiusKm = 20.0;
  static const int _maxAlerts = 50;
  static const String _alertsStorageKey = 'threat_alerts';

  // Getters
  List<ThreatAlert> get alerts => List.unmodifiable(_alerts);
  bool get isMonitoring => _isMonitoring;
  bool get isLoading => _isLoading;
  bool get isOffline => _isOffline;
  String? get lastError => _lastError;
  double get currentThreatLevel => _currentThreatLevel;
  int get nearbyIncidentCount => _nearbyIncidentCount;
  int get nearbyDangerZoneCount => _nearbyDangerZoneCount;
  int get predictedHotspotCount => _predictedHotspotCount;
  bool get isPredictionWsConnected => _isPredictionWsConnected;

  int get unreadCount => _alerts.where((a) => !a.isRead).length;

  List<ThreatAlert> get criticalAlerts =>
      _alerts.where((a) => a.severity == 'critical' || a.severity == 'high').toList();

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> initialize() async {
    debugPrint('ThreatAwarenessService: Initializing...');
    await _initNotifications();
    await startMonitoring();
    debugPrint('ThreatAwarenessService: Initialization complete');
  }

  Future<void> _initNotifications() async {
    if (_notificationsInitialized) return;
    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      await _localNotifications.initialize(initSettings);
      _notificationsInitialized = true;
    } catch (e) {
      debugPrint('ThreatAwarenessService: Failed to init notifications: $e');
    }
  }

  Future<void> startMonitoring() async {
    if (_isMonitoring) return;
    _isMonitoring = true;
    notifyListeners();

    await _loadCachedAlerts();
    await pollThreats();

    _pollTimer = Timer.periodic(
      Duration(seconds: _pollIntervalSeconds),
      (_) => pollThreats(),
    );

    _analysisTimer = Timer.periodic(
      Duration(seconds: _analysisIntervalSeconds),
      (_) => analyzeRecentMessages(),
    );

    await _ambientAudioMonitor.startMonitoring();

    // Connect to prediction WebSocket for real-time ML hotspot updates
    _connectPredictionWebSocket();

    // Start periodic prediction polling (fallback when WebSocket is unavailable)
    _startPredictionPolling();

    debugPrint('ThreatAwarenessService: Monitoring started');
  }

  Future<void> stopMonitoring() async {
    _isMonitoring = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _analysisTimer?.cancel();
    _analysisTimer = null;
    _predictionPollTimer?.cancel();
    _predictionPollTimer = null;
    _disconnectPredictionWebSocket();
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

      final incidents = await _incidentService.getNearbyIncidents(
        latitude: position.latitude,
        longitude: position.longitude,
        radiusKm: _threatRadiusKm,
      );

      final zonesResponse = await _api.getZonesNearby(
        position.latitude,
        position.longitude,
        radiusDegrees: _threatRadiusKm / 111.0,
      );
      final zones = zonesResponse['zones'] as List? ?? [];

      final alertsResponse = await _api.getActiveAlerts();
      final activeAlerts = alertsResponse['alerts'] as List? ?? [];

      _isOffline = false;
      _nearbyIncidentCount = incidents.length;
      _nearbyDangerZoneCount = zones.length;

      _calculateThreatLevel(incidents, zones, activeAlerts);

      _processIncidents(incidents);
      _processDangerZones(zones);
      _processActiveAlerts(activeAlerts);

      if (_alerts.length > _maxAlerts) {
        _alerts = _alerts.sublist(0, _maxAlerts);
      }

      await _cacheAlerts();
      await _cachePollDataToSqlite(incidents, zones, activeAlerts);

      _lastError = null;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      debugPrint('ThreatAwarenessService: Poll failed (offline fallback): $e');
      _isOffline = true;
      _lastError = 'Offline mode — showing cached threat data';

      try {
        final cachedIncidents = await _storage.query('incidents',
            orderBy: 'created_at DESC', limit: 50);
        final incidents = cachedIncidents.map((row) => {
          'id': row['id'],
          'incidentType': row['type'],
          'severity': row['severity'],
          'description': row['description'],
          'latitude': row['latitude'],
          'longitude': row['longitude'],
          'status': row['status'],
        }).toList();

        final cachedZones = await _storage.query('zones',
            where: 'status = ?', whereArgs: ['active'],
            orderBy: 'created_at DESC', limit: 50);
        final zones = cachedZones.map((row) => {
          'id': row['id'],
          'name': row['name'],
          'type': row['type'],
          'severity': row['severity'],
          'latitude': row['latitude'],
          'longitude': row['longitude'],
          'status': row['status'],
        }).toList();

        final cachedAlerts = await _storage.query('sos_alerts',
            where: 'status = ?', whereArgs: ['active'],
            orderBy: 'created_at DESC', limit: 50);
        final activeAlerts = cachedAlerts.map((row) => {
          'id': row['id'],
          'type': row['alert_type'],
          'message': row['description'],
          'latitude': row['latitude'],
          'longitude': row['longitude'],
          'status': row['status'],
        }).toList();

        _nearbyIncidentCount = incidents.length;
        _nearbyDangerZoneCount = zones.length;

        _calculateThreatLevel(incidents, zones, activeAlerts);

        _processIncidents(incidents);
        _processDangerZones(zones);
        _processActiveAlerts(activeAlerts);

        if (_alerts.length > _maxAlerts) {
          _alerts = _alerts.sublist(0, _maxAlerts);
        }
      } catch (cacheError) {
        debugPrint('ThreatAwarenessService: Offline fallback also failed: $cacheError');
      }

      _isLoading = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Message Analysis
  // ---------------------------------------------------------------------------

  Future<void> analyzeRecentMessages() async {
    try {
      final recentMessages = await _storage.query('messages',
          orderBy: 'created_at DESC',
          limit: 20);

      for (final msg in recentMessages) {
        final text = msg['content'] as String?;
        if (text == null || text.length < 10) continue;

        final msgId = msg['id'] as String?;
        if (msgId != null && _alerts.any((a) =>
            a.sourceData?['messageId'] == msgId)) {
          continue;
        }

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
        } else if (result.method == 'error') {
          final localResult = _localKeywordAnalysis(text);
          if (localResult != null) {
            _addAlert(ThreatAlert(
              id: 'msg_local_${DateTime.now().millisecondsSinceEpoch}',
              type: 'message_analysis',
              title: localResult['title'] as String,
              description: localResult['description'] as String,
              latitude: (msg['latitude'] as num?)?.toDouble(),
              longitude: (msg['longitude'] as num?)?.toDouble(),
              severity: localResult['severity'] as String,
              confidence: localResult['confidence'] as double,
              timestamp: DateTime.now(),
              sourceData: {
                'messageId': msgId,
                'text': text,
                'label': localResult['label'] as String,
                'method': 'local_keyword',
              },
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('ThreatAwarenessService: Message analysis failed: $e');
    }
  }

  Map<String, dynamic>? _localKeywordAnalysis(String text) {
    final lower = text.toLowerCase();

    final threatKeywords = <String, Map<String, dynamic>>{
      'kidnap': {'severity': 'critical', 'label': 'kidnapping', 'confidence': 0.7},
      'kidnapped': {'severity': 'critical', 'label': 'kidnapping', 'confidence': 0.8},
      'abduction': {'severity': 'critical', 'label': 'kidnapping', 'confidence': 0.7},
      'abducted': {'severity': 'critical', 'label': 'kidnapping', 'confidence': 0.8},
      'ransom': {'severity': 'critical', 'label': 'kidnapping', 'confidence': 0.6},
      'terrorist': {'severity': 'critical', 'label': 'terrorism', 'confidence': 0.7},
      'terrorism': {'severity': 'critical', 'label': 'terrorism', 'confidence': 0.8},
      'bomb': {'severity': 'critical', 'label': 'terrorism', 'confidence': 0.7},
      'bombing': {'severity': 'critical', 'label': 'terrorism', 'confidence': 0.8},
      'explosion': {'severity': 'critical', 'label': 'terrorism', 'confidence': 0.7},
      'suicide attack': {'severity': 'critical', 'label': 'terrorism', 'confidence': 0.8},
      'ied': {'severity': 'critical', 'label': 'terrorism', 'confidence': 0.7},
      'bandit': {'severity': 'high', 'label': 'banditry', 'confidence': 0.7},
      'banditry': {'severity': 'high', 'label': 'banditry', 'confidence': 0.8},
      'armed robbery': {'severity': 'high', 'label': 'armed_robbery', 'confidence': 0.7},
      'gunmen': {'severity': 'high', 'label': 'banditry', 'confidence': 0.6},
      'gunshot': {'severity': 'high', 'label': 'banditry', 'confidence': 0.7},
      'herdsmen': {'severity': 'high', 'label': 'herdsmen_attack', 'confidence': 0.6},
      'fulani herdsmen': {'severity': 'high', 'label': 'herdsmen_attack', 'confidence': 0.7},
      'cult': {'severity': 'high', 'label': 'cult_violence', 'confidence': 0.6},
      'ritual': {'severity': 'high', 'label': 'ritual_killings', 'confidence': 0.6},
      'ritual killing': {'severity': 'critical', 'label': 'ritual_killings', 'confidence': 0.7},
      'help': {'severity': 'high', 'label': 'distress', 'confidence': 0.5},
      'emergency': {'severity': 'high', 'label': 'distress', 'confidence': 0.5},
      'danger': {'severity': 'high', 'label': 'distress', 'confidence': 0.5},
      'attack': {'severity': 'high', 'label': 'distress', 'confidence': 0.5},
      'kill': {'severity': 'high', 'label': 'violence', 'confidence': 0.5},
      'murder': {'severity': 'critical', 'label': 'violence', 'confidence': 0.6},
      'political violence': {'severity': 'high', 'label': 'political_violence', 'confidence': 0.6},
      'communal clash': {'severity': 'high', 'label': 'communal_clash', 'confidence': 0.7},
      'ethnic clash': {'severity': 'high', 'label': 'communal_clash', 'confidence': 0.7},
      'suspicious': {'severity': 'medium', 'label': 'suspicious_activity', 'confidence': 0.5},
      'surveillance': {'severity': 'medium', 'label': 'suspicious_activity', 'confidence': 0.5},
      'following me': {'severity': 'high', 'label': 'suspicious_activity', 'confidence': 0.6},
    };

    final matched = <Map<String, dynamic>>[];
    for (final entry in threatKeywords.entries) {
      if (lower.contains(entry.key)) {
        matched.add(entry.value);
      }
    }

    if (matched.isEmpty) return null;

    matched.sort((a, b) {
      final severityOrder = {'critical': 4, 'high': 3, 'medium': 2, 'low': 1};
      final aOrder = severityOrder[a['severity']] ?? 0;
      final bOrder = severityOrder[b['severity']] ?? 0;
      return bOrder.compareTo(aOrder);
    });

    final best = matched.first;
    final severity = best['severity'] as String;
    final label = best['label'] as String;
    final confidence = best['confidence'] as double;

    if (severity != 'high' && severity != 'critical') return null;

    final typeLabel = _getIncidentTypeLabel(label);
    final matchedKeywords = matched
        .map((m) => m['label'] as String)
        .toSet()
        .map((l) => _getIncidentTypeLabel(l))
        .join(', ');

    return {
      'title': '⚠️ $typeLabel Suspected (Offline)',
      'description': 'Message contains keywords related to: $matchedKeywords',
      'severity': severity,
      'confidence': confidence,
      'label': label,
    };
  }

  // ---------------------------------------------------------------------------
  // Manual Threat Check
  // ---------------------------------------------------------------------------

  AmbientAudioMonitor get ambientAudioMonitor => _ambientAudioMonitor;

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

  Future<void> clearAlerts() async {
    _alerts.clear();
    _currentThreatLevel = 0.0;
    _nearbyIncidentCount = 0;
    _nearbyDangerZoneCount = 0;
    _predictedHotspotCount = 0;
    await _storage.removeSetting(_alertsStorageKey);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Internal Helpers
  // ---------------------------------------------------------------------------

  void addAlert(ThreatAlert alert) {
    _addAlert(alert);
  }

  void _addAlert(ThreatAlert alert) {
    final exists = _alerts.any((a) =>
        a.type == alert.type &&
        a.title == alert.title &&
        a.timestamp.difference(alert.timestamp).inMinutes < 5);

    if (!exists) {
      _alerts.insert(0, alert);
      notifyListeners();

      if (alert.severity == 'critical' || alert.severity == 'high') {
        _triggerUrgentNotification(alert);
      }
    }
  }

  void _triggerUrgentNotification(ThreatAlert alert) {
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}

    if (_notificationsInitialized) {
      try {
        final androidDetails = AndroidNotificationDetails(
          'threat_alerts',
          'Threat Alerts',
          channelDescription: 'Urgent threat and danger alerts',
          importance: alert.severity == 'critical'
              ? Importance.max
              : Importance.high,
          priority: alert.severity == 'critical'
              ? Priority.max
              : Priority.high,
          playSound: true,
          enableVibration: true,
          vibrationPattern: alert.severity == 'critical'
              ? [0, 500, 200, 500, 200, 500]
              : [0, 300, 100, 300],
          showWhen: true,
          autoCancel: true,
          color: alert.severity == 'critical'
              ? const Color(0xFFFF0000)
              : const Color(0xFFFF9800),
          ledColor: alert.severity == 'critical'
              ? const Color(0xFFFF0000)
              : const Color(0xFFFF9800),
          ledOnMs: 1000,
          ledOffMs: 500,
        );
        final iosDetails = DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          sound: alert.severity == 'critical'
              ? 'alert_critical.wav'
              : 'alert_high.wav',
        );
        final details = NotificationDetails(
          android: androidDetails,
          iOS: iosDetails,
        );
        _localNotifications.show(
          alert.id.hashCode,
          alert.title,
          alert.description,
          details,
        );
      } catch (e) {
        debugPrint('ThreatAwarenessService: Failed to show notification: $e');
      }
    }

    try {
      onCriticalAlert?.call(alert);
    } catch (e) {
      debugPrint('ThreatAwarenessService: onCriticalAlert callback failed: $e');
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

      if (id != null && _alerts.any((a) => a.sourceData?['incidentId'] == id)) {
        continue;
      }

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

    if (incidents.length > 10) level += 0.4;
    else if (incidents.length > 5) level += 0.3;
    else if (incidents.length > 2) level += 0.2;
    else if (incidents.length > 0) level += 0.1;

    if (zones.length > 5) level += 0.3;
    else if (zones.length > 2) level += 0.2;
    else if (zones.length > 0) level += 0.1;

    if (alerts.length > 3) level += 0.3;
    else if (alerts.length > 0) level += 0.15;

    final hasCritical = incidents.any((i) =>
        (i['severity'] as String? ?? '') == 'critical') ||
        zones.any((z) => (z is Map && z['severity'] == 'critical'));
    if (hasCritical) level += 0.2;

    // Boost from ML-predicted hotspots
    if (_predictedHotspotCount > 10) level += 0.35;
    else if (_predictedHotspotCount > 5) level += 0.25;
    else if (_predictedHotspotCount > 2) level += 0.15;
    else if (_predictedHotspotCount > 0) level += 0.08;

    // Check for critical-level predictions
    final hasCriticalPrediction = _alerts.any((a) =>
        a.type == 'prediction' && a.severity == 'critical');
    if (hasCriticalPrediction) level += 0.15;

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
      case 'predicted_hotspot': return 'Predicted Hotspot';
      default: return type[0].toUpperCase() + type.substring(1);
    }
  }

  Future<void> _cachePollDataToSqlite(
    List<Map<String, dynamic>> incidents,
    List<dynamic> zones,
    List<dynamic> alerts,
  ) async {
    try {
      for (final inc in incidents) {
        final id = inc['id'] as String?;
        if (id == null) continue;
        await _storage.upsert('incidents', {
          'id': id,
          'title': inc['incidentType'] as String? ?? 'Unknown',
          'description': inc['description'] as String? ?? '',
          'type': inc['incidentType'] as String? ?? 'unknown',
          'severity': inc['severity'] as String? ?? 'medium',
          'latitude': inc['latitude'],
          'longitude': inc['longitude'],
          'status': inc['status'] as String? ?? 'reported',
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        });
      }

      for (final z in zones) {
        final zone = z as Map<String, dynamic>;
        final id = zone['id'] as String?;
        if (id == null) continue;
        await _storage.upsert('zones', {
          'id': id,
          'name': zone['name'] as String? ?? 'Unknown Zone',
          'type': zone['type'] as String? ?? 'danger',
          'description': zone['description'] as String? ?? '',
          'latitude': zone['latitude'],
          'longitude': zone['longitude'],
          'radius': (zone['radius'] as num?)?.toDouble() ?? 100.0,
          'severity': zone['severity'] as String? ?? 'medium',
          'status': 'active',
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        });
      }

      for (final a in alerts) {
        final alert = a as Map<String, dynamic>;
        final id = alert['id'] as String?;
        if (id == null) continue;
        await _storage.upsert('sos_alerts', {
          'id': id,
          'user_id': alert['userId'] as String? ?? 'unknown',
          'alert_type': alert['type'] as String? ?? 'sos',
          'description': alert['message'] as String? ?? '',
          'latitude': alert['latitude'],
          'longitude': alert['longitude'],
          'status': 'active',
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        });
      }
    } catch (e) {
      debugPrint('ThreatAwarenessService: Failed to cache poll data: $e');
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
      final encoded = json.encode(_alerts.map((a) => a.toJson()).toList());
      await _storage.saveSetting(_alertsStorageKey, encoded);
    } catch (e) {
      debugPrint('ThreatAwarenessService: Failed to cache alerts: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // ML Prediction Integration
  // ---------------------------------------------------------------------------

  /// Connect to WebSocket for real-time ML prediction updates.
  /// Subscribes to /topic/predictions/hotspots and /topic/predictions/updates.
  Future<void> _connectPredictionWebSocket() async {
    try {
      _disconnectPredictionWebSocket();

      final wsUrl = AppConstants.wsBaseUrl;
      final wsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _predictionWsChannel = wsChannel;

      // Send STOMP CONNECT frame
      _sendPredictionStompFrame('CONNECT', {
        'accept-version': '1.2',
        'host': 'sectop.resultscaleai.com',
      });

      // Wait briefly for CONNECT acknowledgment, then subscribe
      await Future.delayed(const Duration(milliseconds: 500));

      // Subscribe to hotspot predictions topic
      _sendPredictionStompFrame('SUBSCRIBE', {
        'id': 'sub-predict-hotspots',
        'destination': '/topic/predictions/hotspots',
      });

      // Subscribe to general prediction updates topic
      _sendPredictionStompFrame('SUBSCRIBE', {
        'id': 'sub-predict-updates',
        'destination': '/topic/predictions/updates',
      });

      _isPredictionWsConnected = true;
      debugPrint('ThreatAwarenessService: Prediction WebSocket connected');

      // Listen for incoming messages
      _predictionWsSubscription = wsChannel.stream.listen(
        (dynamic data) {
          _handlePredictionWsMessage(data as String);
        },
        onError: (dynamic error) {
          debugPrint('ThreatAwarenessService: Prediction WS error: $error');
          _isPredictionWsConnected = false;
          _schedulePredictionWsReconnect();
        },
        onDone: () {
          debugPrint('ThreatAwarenessService: Prediction WS closed');
          _isPredictionWsConnected = false;
          _schedulePredictionWsReconnect();
        },
      );
    } catch (e) {
      debugPrint('ThreatAwarenessService: Prediction WS connection failed: $e');
      _isPredictionWsConnected = false;
    }
  }

  /// Send a raw STOMP frame over the prediction WebSocket.
  void _sendPredictionStompFrame(String command, Map<String, String> headers, {String? body}) {
    if (_predictionWsChannel == null) return;
    try {
      final buffer = StringBuffer();
      buffer.writeln(command);
      for (final entry in headers.entries) {
        buffer.writeln('${entry.key}:${entry.value}');
      }
      buffer.writeln();
      if (body != null) {
        buffer.writeln(body);
      }
      buffer.write('\u0000'); // STOMP null frame terminator
      _predictionWsChannel!.sink.add(buffer.toString());
    } catch (e) {
      debugPrint('ThreatAwarenessService: Failed to send STOMP frame: $e');
    }
  }

  /// Handle an incoming WebSocket message from the prediction topics.
  void _handlePredictionWsMessage(String raw) {
    try {
      // Parse STOMP frame
      if (raw.startsWith('MESSAGE')) {
        final lines = raw.split('\n');
        String? destination;
        int headerEnd = 0;

        for (int i = 1; i < lines.length; i++) {
          final line = lines[i];
          if (line.isEmpty) {
            headerEnd = i + 1;
            break;
          }
          if (line.startsWith('destination:')) {
            destination = line.substring('destination:'.length);
          }
        }

        if (destination == null) return;

        // Extract body
        final bodyLines = lines.sublist(headerEnd);
        String body = bodyLines.join('\n').trim();
        // Remove STOMP null terminator
        body = body.replaceAll('\u0000', '').trim();

        if (body.isEmpty) return;

        final Map<String, dynamic> data = json.decode(body);

        if (destination == '/topic/predictions/hotspots') {
          _processHotspotPredictionMessage(data);
        } else if (destination == '/topic/predictions/updates') {
          _processPredictionUpdateMessage(data);
        }
      }
    } catch (e) {
      debugPrint('ThreatAwarenessService: Failed to parse prediction WS message: $e');
    }
  }

  /// Process a hotspot prediction message received via WebSocket.
  void _processHotspotPredictionMessage(Map<String, dynamic> data) {
    try {
      final hotspots = data['hotspots'] as List<dynamic>? ?? [];
      final count = data['count'] as int? ?? hotspots.length;

      _predictedHotspotCount = count;
      debugPrint('ThreatAwarenessService: Received $count hotspot predictions via WebSocket');

      // Process each hotspot into a ThreatAlert
      for (final h in hotspots) {
        final hotspot = h as Map<String, dynamic>;
        final cellLat = (hotspot['cell_lat'] as num?)?.toDouble();
        final cellLng = (hotspot['cell_lng'] as num?)?.toDouble();
        final riskScore = (hotspot['risk_score'] as num?)?.toDouble() ?? 0.0;
        final state = hotspot['state'] as String? ?? 'Unknown';
        final lga = hotspot['lga'] as String? ?? 'Unknown';
        final alertLevel = hotspot['alert_level'] as String? ?? 'Normal';
        final trend = hotspot['trend_direction'] as String? ?? 'stable';
        final expectedCount = (hotspot['expected_count_24h'] as num?)?.toInt() ?? 0;

        // Map alert level to severity
        final severity = _mapAlertLevelToSeverity(alertLevel);

        // Only alert for High+ severity predictions
        if (severity == 'low' || severity == 'medium') continue;

        // Build a unique ID from cell coordinates
        final hotspotId = 'pred_${cellLat?.toStringAsFixed(2)}_${cellLng?.toStringAsFixed(2)}';

        // Skip if already alerted for this hotspot
        if (_alerts.any((a) => a.sourceData?['hotspotId'] == hotspotId)) continue;

        final trendIcon = trend == 'rising' ? '\u2191' : (trend == 'falling' ? '\u2193' : '\u2192');

        _addAlert(ThreatAlert(
          id: hotspotId,
          type: 'prediction',
          title: 'ML Prediction: $alertLevel Risk in $state',
          description: 'AI model predicts $alertLevel terrorist activity risk near $lga, $state '
              '(score: ${(riskScore * 100).toStringAsFixed(0)}%) '
              'with $expectedCount expected incidents in 24h $trendIcon',
          latitude: cellLat,
          longitude: cellLng,
          severity: severity,
          confidence: riskScore,
          timestamp: DateTime.now(),
          sourceData: {
            'hotspotId': hotspotId,
            'state': state,
            'lga': lga,
            'riskScore': riskScore,
            'alertLevel': alertLevel,
            'trendDirection': trend,
            'expectedCount24h': expectedCount,
            'source': 'websocket',
          },
        ));
      }

      // Recalculate threat level with new prediction data
      notifyListeners();
    } catch (e) {
      debugPrint('ThreatAwarenessService: Failed to process hotspot prediction: $e');
    }
  }

  /// Process a general prediction update notification.
  void _processPredictionUpdateMessage(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    debugPrint('ThreatAwarenessService: Prediction update received: $type');

    if (type == 'HOTSPOT_UPDATE') {
      // A hotspot update occurred — trigger a poll to get fresh data
      _pollHotspotPredictions();
    } else if (type == 'TRAINING_COMPLETE') {
      // Model was retrained — evict local prediction state
      debugPrint('ThreatAwarenessService: ML model retrained, refreshing predictions');
      _pollHotspotPredictions();
    }
  }

  /// Schedule WebSocket reconnection with delay.
  void _schedulePredictionWsReconnect() {
    _predictionWsReconnectTimer?.cancel();
    _predictionWsReconnectTimer = Timer(const Duration(seconds: 10), () {
      debugPrint('ThreatAwarenessService: Attempting prediction WS reconnect...');
      _connectPredictionWebSocket();
    });
  }

  /// Disconnect prediction WebSocket.
  void _disconnectPredictionWebSocket() {
    _predictionWsReconnectTimer?.cancel();
    _predictionWsReconnectTimer = null;
    _predictionWsSubscription?.cancel();
    _predictionWsSubscription = null;
    try {
      if (_predictionWsChannel != null) {
        _sendPredictionStompFrame('DISCONNECT', {});
        _predictionWsChannel!.sink.close();
      }
    } catch (_) {}
    _predictionWsChannel = null;
    _isPredictionWsConnected = false;
  }

  /// Start periodic polling of ML hotspot predictions as fallback
  /// when WebSocket is unavailable.
  void _startPredictionPolling() {
    _predictionPollTimer?.cancel();
    // Poll predictions every 5 minutes (300 seconds)
    _predictionPollTimer = Timer.periodic(
      const Duration(seconds: 300),
      (_) => _pollHotspotPredictions(),
    );
    // Do an initial poll immediately
    _pollHotspotPredictions();
  }

  /// Poll ML hotspot predictions from the backend API.
  /// Uses the user's current location to get relevant predictions.
  Future<void> _pollHotspotPredictions() async {
    try {
      final mapService = MapService();
      final position = mapService.currentPosition;
      if (position == null) {
        debugPrint('ThreatAwarenessService: No position for prediction poll');
        return;
      }

      final result = await _api.detectHotspots(
        latitude: position.latitude,
        longitude: position.longitude,
        radiusKm: 100.0,
      );

      final hotspots = result['hotspots'] as List<dynamic>? ?? [];
      _predictedHotspotCount = hotspots.length;

      // Process each hotspot into a ThreatAlert
      for (final h in hotspots) {
        final hotspot = h as Map<String, dynamic>;
        final cellLat = (hotspot['cell_lat'] as num?)?.toDouble();
        final cellLng = (hotspot['cell_lng'] as num?)?.toDouble();
        final riskScore = (hotspot['risk_score'] as num?)?.toDouble() ?? 0.0;
        final state = hotspot['state'] as String? ?? 'Unknown';
        final lga = hotspot['lga'] as String? ?? 'Unknown';
        final alertLevel = hotspot['alert_level'] as String? ?? 'Normal';
        final trend = hotspot['trend_direction'] as String? ?? 'stable';
        final expectedCount = (hotspot['expected_count_24h'] as num?)?.toInt() ?? 0;

        final severity = _mapAlertLevelToSeverity(alertLevel);
        if (severity == 'low' || severity == 'medium') continue;

        final hotspotId = 'pred_${cellLat?.toStringAsFixed(2)}_${cellLng?.toStringAsFixed(2)}';
        if (_alerts.any((a) => a.sourceData?['hotspotId'] == hotspotId)) continue;

        final trendIcon = trend == 'rising' ? '\u2191' : (trend == 'falling' ? '\u2193' : '\u2192');

        _addAlert(ThreatAlert(
          id: hotspotId,
          type: 'prediction',
          title: 'ML Prediction: $alertLevel Risk in $state',
          description: 'AI model predicts $alertLevel terrorist activity risk near $lga, $state '
              '(score: ${(riskScore * 100).toStringAsFixed(0)}%) '
              'with $expectedCount expected incidents in 24h $trendIcon',
          latitude: cellLat,
          longitude: cellLng,
          severity: severity,
          confidence: riskScore,
          timestamp: DateTime.now(),
          sourceData: {
            'hotspotId': hotspotId,
            'state': state,
            'lga': lga,
            'riskScore': riskScore,
            'alertLevel': alertLevel,
            'trendDirection': trend,
            'expectedCount24h': expectedCount,
            'source': 'polling',
          },
        ));
      }

      // Recalculate threat level
      _calculateThreatLevel(
        [],
        [],
        [],
      );
      notifyListeners();
    } catch (e) {
      debugPrint('ThreatAwarenessService: Hotspot prediction poll failed: $e');
    }
  }

  /// Map ML alert level to ThreatAlert severity string.
  String _mapAlertLevelToSeverity(String alertLevel) {
    switch (alertLevel.toLowerCase()) {
      case 'critical':
        return 'critical';
      case 'severe':
        return 'critical';
      case 'high':
        return 'high';
      case 'elevated':
        return 'medium';
      case 'normal':
        return 'low';
      default:
        return 'medium';
    }
  }
