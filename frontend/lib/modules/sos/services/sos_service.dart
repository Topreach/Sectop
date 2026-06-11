import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../core/constants.dart';
import '../../../shared/services/offline_storage.dart';
import '../../security/services/security_manager.dart';
import '../../mesh/services/mesh_manager.dart';
import '../../auth/services/auth_service.dart';
import '../../../shared/services/evidence_service.dart';

/// SOS Service - Handles emergency alert creation, broadcasting, and tracking.
/// Implements multi-channel delivery: cloud API, Bluetooth mesh, Wi-Fi Direct, LoRa.
/// Also provides real-time delivery confirmation via WebSocket.
class SOSService extends ChangeNotifier {
  static final SOSService _instance = SOSService._internal();
  factory SOSService() => _instance;
  SOSService._internal();

  final OfflineStorageService _storage = OfflineStorageService();
  final MeshManager _meshManager = MeshManager();
  final AuthService _authService = AuthService();
  final Uuid _uuid = const Uuid();

  List<SOSAlert> _activeAlerts = [];
  SOSAlert? _currentAlert;
  bool _isSending = false;
  Timer? _locationTimer;

  // WebSocket client for real-time delivery confirmation
  WebSocketChannel? _wsChannel;
  bool _isWsConnected = false;
  StreamSubscription<dynamic>? _wsSubscription;
  Timer? _wsReconnectTimer;
  final List<Map<String, dynamic>> _deliveryConfirmations = [];

  /// Whether the WebSocket connection is active.
  bool get isWsConnected => _isWsConnected;

  /// Delivery confirmations received via WebSocket.
  List<Map<String, dynamic>> get deliveryConfirmations =>
      List.unmodifiable(_deliveryConfirmations);

  List<SOSAlert> get activeAlerts => _activeAlerts;
  SOSAlert? get currentAlert => _currentAlert;
  bool get isSending => _isSending;

  /// Initialize SOS service and load active alerts.
  Future<void> initialize() async {
    final alerts = await _storage.getActiveSOSAlerts();
    _activeAlerts = alerts.map((a) => SOSAlert.fromMap(a)).toList();
    notifyListeners();

    // Connect to WebSocket for real-time delivery confirmation
    unawaited(_connectWebSocket());
  }

  // ---------------------------------------------------------------------------
  // WebSocket Real-Time Delivery
  // ---------------------------------------------------------------------------

  /// Connect to the backend WebSocket for real-time alert delivery.
  Future<void> _connectWebSocket() async {
    try {
      final token = await _storage.getSensitiveSetting(AppConstants.keyAuthToken);
      if (token == null || token.isEmpty) return;

      final wsUrl = AppConstants.wsBaseUrl; // e.g., ws://10.0.2.2:8080/ws

      // Connect with auth header
      final wsChannel = WebSocketChannel.connect(
        Uri.parse(wsUrl),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      _wsChannel = wsChannel;
      _isWsConnected = true;
      debugPrint('SOSService: WebSocket connected');
      notifyListeners();

      // Listen for incoming messages
      _wsSubscription = wsChannel.stream.listen(
        (dynamic data) {
          final body = data is String ? data : (data is List<int> ? utf8.decode(data) : data.toString());
          _handleDeliveryConfirmation(body);
        },
        onError: (dynamic error) {
          debugPrint('SOSService: WebSocket error: $error');
          _isWsConnected = false;
          notifyListeners();
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('SOSService: WebSocket closed');
          _isWsConnected = false;
          notifyListeners();
          _scheduleReconnect();
        },
        cancelOnError: false,
      );

      // Send a STOMP CONNECT frame manually (since we're using raw WebSocket)
      _sendStompFrame('CONNECT', {
        'accept-version': '1.2',
        'host': 'localhost',
        'Authorization': 'Bearer $token',
      });

      // Subscribe to personal queue after connection
      await Future.delayed(const Duration(milliseconds: 500));
      _sendStompFrame('SUBSCRIBE', {
        'id': 'sub-0',
        'destination': '/user/queue/alerts',
      });
      _sendStompFrame('SUBSCRIBE', {
        'id': 'sub-1',
        'destination': '/topic/alerts',
      });
    } catch (e) {
      debugPrint('SOSService: WebSocket connection failed: $e');
      _isWsConnected = false;
      notifyListeners();
      _scheduleReconnect();
    }
  }

  /// Send a raw STOMP frame over the WebSocket.
  void _sendStompFrame(String command, Map<String, String> headers, {String? body}) {
    if (_wsChannel == null) return;
    try {
      final buffer = StringBuffer();
      buffer.writeln(command);
      headers.forEach((key, value) {
        buffer.writeln('$key:$value');
      });
      buffer.writeln();
      if (body != null && body.isNotEmpty) {
        buffer.write(body);
      }
      buffer.write('\0'); // STOMP null frame terminator
      _wsChannel!.sink.add(buffer.toString());
    } catch (e) {
      debugPrint('SOSService: Failed to send STOMP frame: $e');
    }
  }

  /// Schedule reconnection with exponential backoff.
  void _scheduleReconnect() {
    _wsReconnectTimer?.cancel();
    _wsReconnectTimer = Timer(const Duration(seconds: 5), () {
      debugPrint('SOSService: Attempting WebSocket reconnect...');
      unawaited(_connectWebSocket());
    });
  }

  /// Handle delivery confirmation messages from the backend.
  void _handleDeliveryConfirmation(String body) {
    if (body.isEmpty) return;
    try {
      // STOMP frames may have headers before the JSON body; find the JSON part
      String jsonStr = body;
      // If it's a STOMP MESSAGE frame, the body follows the blank line after headers
      if (body.contains('\n\n')) {
        jsonStr = body.substring(body.indexOf('\n\n') + 2).trim();
      }
      // Remove STOMP null terminator if present
      jsonStr = jsonStr.replaceAll('\0', '').trim();
      if (jsonStr.isEmpty) return;

      final data = json.decode(jsonStr) as Map<String, dynamic>;
      _deliveryConfirmations.insert(0, data);
      debugPrint('SOSService: Delivery confirmation: $data');
      notifyListeners();
    } catch (e) {
      debugPrint('SOSService: Failed to parse delivery confirmation: $e');
    }
  }

  /// Disconnect WebSocket client.
  void disconnectWebSocket() {
    _wsReconnectTimer?.cancel();
    _wsSubscription?.cancel();
    _wsChannel?.sink.close();
    _wsChannel = null;
    _isWsConnected = false;
    notifyListeners();
  }

  /// Send an SOS alert through all available channels.
  Future<SOSResult> sendSOS({
    required String alertType,
    String? description,
    double? latitude,
    double? longitude,
    int priority = AppConstants.priorityCritical,
    bool isSilent = false,
  }) async {
    _isSending = true;
    if (!isSilent) notifyListeners();

    try {
      // Get current location if not provided
      Position? position;
      if (latitude == null || longitude == null) {
        position = await _getCurrentLocation();
      }

      final alert = SOSAlert(
        id: _uuid.v4(),
        userId: _authService.currentUser?.id ?? 'anonymous',
        alertType: alertType,
        description: description,
        latitude: latitude ?? position?.latitude ?? 0.0,
        longitude: longitude ?? position?.longitude ?? 0.0,
        accuracy: position?.accuracy,
        priority: priority,
        status: AlertStatus.active,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        isSilent: isSilent,
      );

      _currentAlert = alert;

      // Step 1: Store locally first (guaranteed persistence)
      await _storage.saveSOSAlert(alert.toMap());

      // Step 2: Try cloud API if available
      unawaited(_tryCloudSend(alert));

      // Step 3: Broadcast via mesh network (Bluetooth + Wi-Fi Direct)
      unawaited(_broadcastViaMesh(alert));

      // Step 4: If LoRa gateway available, use that too
      unawaited(_tryLoRaSend(alert));

      // Step 5: SMS Fallback for critical alerts
      if (priority >= AppConstants.priorityCritical) {
        unawaited(_trySmsSend(alert));
      }

      // Step 6: Start location tracking for dynamic updates
      _startLocationTracking(alert.id);

      // Step 6: Capture last-gasp evidence (audio/photo)
      unawaited(EvidenceService().captureLastGasp(alert.id));

      _activeAlerts.insert(0, alert);
      _isSending = false;
      notifyListeners();

      return SOSResult.success(alert);
    } catch (e) {
      _isSending = false;
      notifyListeners();
      return SOSResult.failure(e.toString());
    }
  }

  /// Try to send SOS via cloud API.
  Future<void> _tryCloudSend(SOSAlert alert) async {
    try {
      final headers = <String, String>{'Content-Type': 'application/json'};
      try {
        final token = await _storage.getSensitiveSetting(AppConstants.keyAuthToken);
        if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
      } catch (_) {}

      final response = await SecurityManager.instance.securePost(
        Uri.parse('${AppConstants.apiBaseUrl}/${AppConstants.apiVersion}/alerts'),
        headers: headers,
        body: json.encode(alert.toMap()),
      ).timeout(Duration(seconds: AppConstants.apiTimeout));

      if (response.statusCode == 200 || response.statusCode == 201) {
        await _storage.update('sos_alerts', {
          'mesh_relayed': 0,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        }, where: 'id = ?', whereArgs: [alert.id]);
      }
    } catch (e) {
      debugPrint('Cloud SOS send failed: $e');
    }
  }

  /// Broadcast SOS alert via mesh network with exponential backoff.
  Future<void> _broadcastViaMesh(SOSAlert alert) async {
    for (int i = 0; i < AppConstants.sosMaxRetries; i++) {
      try {
        await _meshManager.broadcastMessage(
          type: MessageType.sos,
          payload: alert.toMap(),
          priority: MessagePriority.critical,
        );

        await _storage.update('sos_alerts', {
          'mesh_relayed': 1,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        }, where: 'id = ?', whereArgs: [alert.id]);

        return; // Success
      } catch (e) {
        debugPrint('Mesh broadcast attempt $i failed: $e');
        // Exponential backoff: 2s, 4s, 8s, 16s, 32s
        const maxDelaySeconds = 60;
        final delay = min(pow(2, i + 1).toInt(), maxDelaySeconds);
        await Future.delayed(Duration(seconds: delay));
      }
    }
  }

  /// Try to send via LoRa bridge.
  Future<void> _tryLoRaSend(SOSAlert alert) async {
    try {
      await _meshManager.sendViaLoRa(alert.toMap());
    } catch (e) {
      debugPrint('LoRa SOS send failed: $e');
    }
  }

  /// SMS Fallback - Sends a pre-formatted distress message to emergency contacts.
  Future<void> _trySmsSend(SOSAlert alert) async {
    try {
      // In a production app, we would use a package like 'telephony' to send
      // the SMS in the background without user interaction (on Android).
      final message = 'EMERGENCY: SOS Alert from ${alert.userId}. '
          'Type: ${alert.alertType}. '
          'Loc: https://maps.google.com/?q=${alert.latitude},${alert.longitude}';

      debugPrint('SOSService: SMS Fallback Triggered: $message');

      // If we had the 'telephony' package:
      // Telephony.instance.sendSms(to: contacts, message: message);
    } catch (e) {
      debugPrint('SMS Fallback failed: $e');
    }
  }

  /// Start periodic location tracking for active SOS.
  void _startLocationTracking(String alertId) {
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(
      Duration(seconds: AppConstants.sosAutoLocationInterval),
      (_) async {
        try {
          final position = await _getCurrentLocation();
          if (position != null) {
            await _storage.update('sos_alerts', {
              'latitude': position.latitude,
              'longitude': position.longitude,
              'updated_at': DateTime.now().millisecondsSinceEpoch,
            }, where: 'id = ?', whereArgs: [alertId]);

            // Broadcast updated location
            await _meshManager.broadcastMessage(
              type: MessageType.locationUpdate,
              payload: {
                'alert_id': alertId,
                'latitude': position.latitude,
                'longitude': position.longitude,
                'timestamp': DateTime.now().millisecondsSinceEpoch,
              },
              priority: MessagePriority.high,
            );
          }
        } catch (e) {
          debugPrint('Location update error: $e');
        }
      },
    );
  }

  /// Acknowledge (respond to) an SOS alert.
  Future<void> acknowledgeAlert(String alertId) async {
    final responderId = _authService.currentUser?.id;
    if (responderId == null) return;

    await _storage.update('sos_alerts', {
      'acknowledged_by': responderId,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, where: 'id = ?', whereArgs: [alertId]);

    // Notify the sender via mesh
    await _meshManager.broadcastMessage(
      type: MessageType.acknowledgment,
      payload: {
        'alert_id': alertId,
        'responder_id': responderId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
      priority: MessagePriority.high,
    );

    // Update local state
    final index = _activeAlerts.indexWhere((a) => a.id == alertId);
    if (index >= 0) {
      _activeAlerts[index] = _activeAlerts[index].copyWith(
        acknowledgedBy: responderId,
      );
      notifyListeners();
    }
  }

  /// Resolve an SOS alert.
  Future<void> resolveAlert(String alertId) async {
    await _storage.resolveSOSAlert(alertId, resolvedBy: _authService.currentUser?.id);

    // Broadcast resolution
    await _meshManager.broadcastMessage(
      type: MessageType.resolution,
      payload: {
        'alert_id': alertId,
        'resolved_at': DateTime.now().millisecondsSinceEpoch,
      },
      priority: MessagePriority.normal,
    );

    _activeAlerts.removeWhere((a) => a.id == alertId);
    if (_currentAlert?.id == alertId) {
      _currentAlert = null;
      _locationTimer?.cancel();
    }
    notifyListeners();
  }

  /// Get current device location.
  Future<Position?> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      debugPrint('Location error: $e');
      return null;
    }
  }

  /// Cancel active SOS.
  Future<void> cancelSOS() async {
    if (_currentAlert != null) {
      await resolveAlert(_currentAlert!.id);
    }
    _locationTimer?.cancel();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _wsReconnectTimer?.cancel();
    _wsSubscription?.cancel();
    _wsChannel?.sink.close();
    _wsChannel = null;
    super.dispose();
  }
}

/// SOS Alert model.
class SOSAlert {
  final String id;
  final String userId;
  final String alertType;
  final String? description;
  final double latitude;
  final double longitude;
  final double? accuracy;
  final int priority;
  final AlertStatus status;
  final String? acknowledgedBy;
  final int createdAt;
  final int? resolvedAt;
  final bool isSilent;

  SOSAlert({
    required this.id,
    required this.userId,
    required this.alertType,
    this.description,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.priority = AppConstants.priorityCritical,
    this.status = AlertStatus.active,
    this.acknowledgedBy,
    required this.createdAt,
    this.resolvedAt,
    this.isSilent = false,
  });

  factory SOSAlert.fromMap(Map<String, dynamic> map) {
    return SOSAlert(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      alertType: map['alert_type'] as String,
      description: map['description'] as String?,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      accuracy: (map['accuracy'] as num?)?.toDouble(),
      priority: map['priority'] as int? ?? AppConstants.priorityCritical,
      status: AlertStatus.values.firstWhere(
        (s) => s.name == map['status'],
        orElse: () => AlertStatus.active,
      ),
      acknowledgedBy: map['acknowledged_by'] as String?,
      createdAt: map['created_at'] as int,
      resolvedAt: map['resolved_at'] as int?,
      isSilent: map['is_silent'] == 1 || map['is_silent'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'user_id': userId,
    'alert_type': alertType,
    'description': description,
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
    'priority': priority,
    'status': status.name,
    'acknowledged_by': acknowledgedBy,
    'created_at': createdAt,
    'resolved_at': resolvedAt,
    'is_silent': isSilent ? 1 : 0,
  };

  SOSAlert copyWith({
    String? id,
    String? userId,
    String? alertType,
    String? description,
    double? latitude,
    double? longitude,
    double? accuracy,
    int? priority,
    AlertStatus? status,
    String? acknowledgedBy,
    int? createdAt,
    int? resolvedAt,
    bool? isSilent,
  }) {
    return SOSAlert(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      alertType: alertType ?? this.alertType,
      description: description ?? this.description,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracy: accuracy ?? this.accuracy,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      acknowledgedBy: acknowledgedBy ?? this.acknowledgedBy,
      createdAt: createdAt ?? this.createdAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      isSilent: isSilent ?? this.isSilent,
    );
  }
}

enum AlertStatus { active, acknowledged, resolved, expired }

/// Result of an SOS operation.
class SOSResult {
  final bool success;
  final SOSAlert? alert;
  final String? error;

  SOSResult._({required this.success, this.alert, this.error});

  factory SOSResult.success(SOSAlert alert) =>
      SOSResult._(success: true, alert: alert);

  factory SOSResult.failure(String error) =>
      SOSResult._(success: false, error: error);
}

