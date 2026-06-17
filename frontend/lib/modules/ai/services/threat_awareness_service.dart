import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../../core/constants.dart';
import '../../../shared/services/backend_api.dart';
import '../../../shared/services/offline_storage.dart';
import '../../../shared/services/covert_mode_manager.dart';
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

/// Thin API wrapper for proactive threat awareness.
///
/// All threat detection, analysis, and alerting logic has been moved to the
/// backend [ThreatController]. This service now acts as a thin client that:
///   - Polls the backend for pre-computed threat alerts and threat level
///   - Displays local notifications for critical/high alerts
///   - Caches alerts locally for offline access
///   - Delegates text analysis to the backend
///
/// Business logic previously here (_localKeywordAnalysis, _calculateThreatLevel,
/// _processIncidents, _processDangerZones, _processActiveAlerts, raw STOMP
/// WebSocket parsing, _pollHotspotPredictions) has been moved to the backend.
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

    debugPrint('ThreatAwarenessService: Monitoring started');
  }

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
  // Threat Polling (delegates to backend /api/v1/threat/*)
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

      // Fetch pre-computed threat level from backend
      final levelResponse = await _api.getThreatLevel(
        latitude: position.latitude,
        longitude: position.longitude,
        radiusKm: _threatRadiusKm,
      );

      _isOffline = false;
      _currentThreatLevel = (levelResponse['threatLevel'] as num?)?.toDouble() ?? 0.0;
      _nearbyIncidentCount = (levelResponse['incidentCount'] as num?)?.toInt() ?? 0;
      _nearbyDangerZoneCount = (levelResponse['dangerZoneCount'] as num?)?.toInt() ?? 0;
      _predictedHotspotCount = (levelResponse['predictedHotspotCount'] as num?)?.toInt() ?? 0;

      // Fetch pre-formatted threat alerts from backend
      final alertsResponse = await _api.getThreatAlerts(
        latitude: position.latitude,
        longitude: position.longitude,
        radiusKm: _threatRadiusKm,
      );

      final serverAlerts = alertsResponse['alerts'] as List<dynamic>? ?? [];
      for (final a in serverAlerts) {
        final alertJson = a as Map<String, dynamic>;
        final alert = ThreatAlert(
          id: alertJson['id'] as String,
          type: alertJson['type'] as String,
          title: alertJson['title'] as String,
          description: alertJson['description'] as String,
          latitude: alertJson['latitude'] as double?,
          longitude: alertJson['longitude'] as double?,
          severity: alertJson['severity'] as String,
          confidence: (alertJson['confidence'] as num).toDouble(),
          timestamp: DateTime.parse(alertJson['timestamp'] as String),
          sourceData: alertJson['sourceData'] as Map<String, dynamic>?,
        );
        _addAlert(alert);
      }

      if (_alerts.length > _maxAlerts) {
        _alerts = _alerts.sublist(0, _maxAlerts);
      }

      await _cacheAlerts();

      _lastError = null;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      debugPrint('ThreatAwarenessService: Poll failed (offline fallback): $e');
      _isOffline = true;
      _lastError = 'Offline mode — showing cached threat data';

      try {
        final cached = await _storage.getSetting(_alertsStorageKey);
        if (cached != null && cached.isNotEmpty) {
          final List<dynamic> decoded = json.decode(cached);
          _alerts = decoded
              .map((e) => ThreatAlert.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      } catch (cacheError) {
        debugPrint('ThreatAwarenessService: Offline fallback also failed: $cacheError');
      }

      _isLoading = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Message Analysis (delegates to backend /api/v1/ai/analyze-message)
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
        }
      }
    } catch (e) {
      debugPrint('ThreatAwarenessService: Message analysis failed: $e');
    }
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

      // In Covert Mode, suppress all notification sounds, vibration, and popups
      // to avoid alerting a nearby kidnapper that an SOS has been triggered.
      final covertMode = CovertModeManager();
      if (covertMode.isCovertModeEnabled && covertMode.suppressNotifications) {
        debugPrint('ThreatAwarenessService: Covert mode active — suppressing notification for ${alert.title}');
        return;
      }

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
              ? Int64List.fromList([0, 500, 200, 500, 200, 500])
              : Int64List.fromList([0, 300, 100, 300]),
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
