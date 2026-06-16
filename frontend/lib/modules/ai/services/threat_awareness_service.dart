import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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
  bool _isOffline = false; // True when operating in offline/fallback mode
  String? _lastError;
  double _currentThreatLevel = 0.0; // 0.0 - 1.0
  int _nearbyIncidentCount = 0;
  int _nearbyDangerZoneCount = 0;
  Timer? _pollTimer;
  Timer? _analysisTimer;

  // Notification & Vibration
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  bool _notificationsInitialized = false;

  /// Callback invoked when a critical/high alert is added.
  /// The dashboard screen sets this to show a popup dialog.
  void Function(ThreatAlert alert)? onCriticalAlert;

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
  bool get isOffline => _isOffline;
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

  /// Initialize the service — called by safeInit() in main.dart.
  /// Loads cached alerts and starts proactive threat monitoring.
  Future<void> initialize() async {
    debugPrint('ThreatAwarenessService: Initializing...');
    await _initNotifications();
    await startMonitoring();
    debugPrint('ThreatAwarenessService: Initialization complete');
  }

  /// Initialize local notifications plugin.
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
/// Tries internet first; falls back to cached data from SQLite when offline.
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

    // Online success — update counts, process, cache
    _isOffline = false;
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

    // Cache alerts to SharedPreferences
    await _cacheAlerts();

    // Cache incidents, zones, and alerts to SQLite for offline fallback
    await _cachePollDataToSqlite(incidents, zones, activeAlerts);

    _lastError = null;
    _isLoading = false;
    notifyListeners();
  } catch (e) {
    // OFFLINE FALLBACK: Load cached data from SQLite when server is unreachable
    debugPrint('ThreatAwarenessService: Poll failed (offline fallback): $e');
    _isOffline = true;
    _lastError = 'Offline mode — showing cached threat data';

    try {
      // Load cached incidents from SQLite
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

      // Load cached zones from SQLite
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

      // Load cached SOS alerts from SQLite
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

      // Update counts from cached data
      _nearbyIncidentCount = incidents.length;
      _nearbyDangerZoneCount = zones.length;

      // Calculate threat level from cached data
      _calculateThreatLevel(incidents, zones, activeAlerts);

      // Process cached data into alerts (dedup logic prevents duplicates)
      _processIncidents(incidents);
      _processDangerZones(zones);
      _processActiveAlerts(activeAlerts);

      // Trim to max
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
  }

  // ---------------------------------------------------------------------------
  // Message Analysis
  // ---------------------------------------------------------------------------

  /// Analyze recent messages from the inbox for threat content.
  /// Tries backend AI first; falls back to local keyword analysis when offline.
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

        // Try backend AI first
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
          // OFFLINE FALLBACK: Backend AI unreachable — use local keyword analysis
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

  /// Local keyword-based threat analysis fallback for offline mode.
  /// Returns null if no threat keywords are found.
  Map<String, dynamic>? _localKeywordAnalysis(String text) {
    final lower = text.toLowerCase();

    // Threat keyword categories with severity levels
    final threatKeywords = <String, Map<String, dynamic>>{
      // Kidnapping / Abduction
      'kidnap': {'severity': 'critical', 'label': 'kidnapping', 'confidence': 0.7},
      'kidnapped': {'severity': 'critical', 'label': 'kidnapping', 'confidence': 0.8},
      'abduction': {'severity': 'critical', 'label': 'kidnapping', 'confidence': 0.7},
      'abducted': {'severity': 'critical', 'label': 'kidnapping', 'confidence': 0.8},
      'ransom': {'severity': 'critical', 'label': 'kidnapping', 'confidence': 0.6},

      // Terrorism / Bombing
      'terrorist': {'severity': 'critical', 'label': 'terrorism', 'confidence': 0.7},
      'terrorism': {'severity': 'critical', 'label': 'terrorism', 'confidence': 0.8},
      'bomb': {'severity': 'critical', 'label': 'terrorism', 'confidence': 0.7},
      'bombing': {'severity': 'critical', 'label': 'terrorism', 'confidence': 0.8},
      'explosion': {'severity': 'critical', 'label': 'terrorism', 'confidence': 0.7},
      'suicide attack': {'severity': 'critical', 'label': 'terrorism', 'confidence': 0.8},
      'ied': {'severity': 'critical', 'label': 'terrorism', 'confidence': 0.7},

      // Banditry / Armed robbery
      'bandit': {'severity': 'high', 'label': 'banditry', 'confidence': 0.7},
      'banditry': {'severity': 'high', 'label': 'banditry', 'confidence': 0.8},
      'armed robbery': {'severity': 'high', 'label': 'armed_robbery', 'confidence': 0.7},
      'gunmen': {'severity': 'high', 'label': 'banditry', 'confidence': 0.6},
      'gunshot': {'severity': 'high', 'label': 'banditry', 'confidence': 0.7},

      // Herdsmen attack
      'herdsmen': {'severity': 'high', 'label': 'herdsmen_attack', 'confidence': 0.6},
      'fulani herdsmen': {'severity': 'high', 'label': 'herdsmen_attack', 'confidence': 0.7},

      // Cult / Ritual violence
      'cult': {'severity': 'high', 'label': 'cult_violence', 'confidence': 0.6},
      'ritual': {'severity': 'high', 'label': 'ritual_killings', 'confidence': 0.6},
      'ritual killing': {'severity': 'critical', 'label': 'ritual_killings', 'confidence': 0.7},

      // General danger / distress
      'help': {'severity': 'high', 'label': 'distress', 'confidence': 0.5},
      'emergency': {'severity': 'high', 'label': 'distress', 'confidence': 0.5},
      'danger': {'severity': 'high', 'label': 'distress', 'confidence': 0.5},
      'attack': {'severity': 'high', 'label': 'distress', 'confidence': 0.5},
      'kill': {'severity': 'high', 'label': 'violence', 'confidence': 0.5},
      'murder': {'severity': 'critical', 'label': 'violence', 'confidence': 0.6},

      // Political / Communal violence
      'political violence': {'severity': 'high', 'label': 'political_violence', 'confidence': 0.6},
      'communal clash': {'severity': 'high', 'label': 'communal_clash', 'confidence': 0.7},
      'ethnic clash': {'severity': 'high', 'label': 'communal_clash', 'confidence': 0.7},

      // Suspicious activity
      'suspicious': {'severity': 'medium', 'label': 'suspicious_activity', 'confidence': 0.5},
      'surveillance': {'severity': 'medium', 'label': 'suspicious_activity', 'confidence': 0.5},
      'following me': {'severity': 'high', 'label': 'suspicious_activity', 'confidence': 0.6},
    };

    // Check for keyword matches
    final matched = <Map<String, dynamic>>[];
    for (final entry in threatKeywords.entries) {
      if (lower.contains(entry.key)) {
        matched.add(entry.value);
      }
    }

    if (matched.isEmpty) return null;

    // Use the highest severity match
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

    // Only alert for high/critical in local mode
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
    await _storage.removeSetting(_alertsStorageKey);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Internal Helpers
  // ---------------------------------------------------------------------------

  /// Public method to add an alert from external sources (e.g., AmbientAudioMonitor).
  void addAlert(ThreatAlert alert) {
    _addAlert(alert);
  }

  void _addAlert(ThreatAlert alert) {
    // Avoid duplicates by checking if similar alert already exists
    final exists = _alerts.any((a) =>
        a.type == alert.type &&
        a.title == alert.title &&
        a.timestamp.difference(alert.timestamp).inMinutes < 5);

    if (!exists) {
      _alerts.insert(0, alert);
      notifyListeners();

      // Trigger notification for critical/high severity alerts
      if (alert.severity == 'critical' || alert.severity == 'high') {
        _triggerUrgentNotification(alert);
      }
    }
  }

  /// Trigger vibration, system notification, and popup callback for urgent alerts.
  void _triggerUrgentNotification(ThreatAlert alert) {
    // 1. Haptic feedback (vibration)
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}

    // 2. System notification (works even when app is in background)
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
              ? [0, 500, 200, 500, 200, 500] // S.O.S pattern
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

    // 3. Invoke popup callback (set by dashboard screen)
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

  /// Cache polled data (incidents, zones, alerts) to SQLite for offline fallback.
  Future<void> _cachePollDataToSqlite(
    List<Map<String, dynamic>> incidents,
    List<dynamic> zones,
    List<dynamic> alerts,
  ) async {
    try {
      // Cache incidents
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

      // Cache zones
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

      // Cache SOS alerts
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
}
