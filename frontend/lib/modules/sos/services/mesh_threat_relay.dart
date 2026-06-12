import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../mesh/services/mesh_manager.dart';

/// Relay service that broadcasts walkie-talkie threat detections to nearby
/// mesh peers and listens for incoming threat alerts from other devices.
///
/// This extends the detection range of the Walkie-Talkie Monitor by
/// crowdsourcing threat intelligence through the Bluetooth mesh network.
/// When one user's phone detects a walkie-talkie threat, all nearby
/// mesh-connected devices are alerted immediately.
class MeshThreatRelayService extends ChangeNotifier {
  static final MeshThreatRelayService _instance =
      MeshThreatRelayService._internal();
  factory MeshThreatRelayService() => _instance;
  MeshThreatRelayService._internal();

  final MeshManager _meshManager = MeshManager();

  /// Incoming threat alerts received from mesh peers.
  final List<RemoteThreatAlert> _incomingThreats = [];

  /// Callback when a remote threat alert is received.
  void Function(RemoteThreatAlert alert)? onRemoteThreatReceived;

  /// Whether the relay is actively listening.
  bool _isListening = false;

  /// Incoming threat alerts from remote peers.
  List<RemoteThreatAlert> get incomingThreats =>
      List.unmodifiable(_incomingThreats);

  /// Whether the relay is active.
  bool get isListening => _isListening;

  /// Start listening for incoming mesh threat alerts.
  void startListening() {
    if (_isListening) return;
    _isListening = true;
    _meshManager.addListener(_onMeshMessage);
    debugPrint('MeshThreatRelay: Started listening for remote threats');
    notifyListeners();
  }

  /// Stop listening for incoming mesh threat alerts.
  void stopListening() {
    if (!_isListening) return;
    _isListening = false;
    _meshManager.removeListener(_onMeshMessage);
    debugPrint('MeshThreatRelay: Stopped listening for remote threats');
    notifyListeners();
  }

  /// Broadcast a walkie-talkie threat detection to all mesh peers.
  ///
  /// [confidence] — detection confidence (0.0–1.0)
  /// [method] — analysis method used (e.g., "hybrid_energy_keyword_analysis")
  /// [latitude]/[longitude] — location where threat was detected
  /// [threatLevel] — severity level (low/medium/high/critical)
  Future<void> broadcastThreat({
    required double confidence,
    required String method,
    double? latitude,
    double? longitude,
    String threatLevel = 'high',
  }) async {
    final payload = {
      'confidence': confidence,
      'method': method,
      'latitude': latitude,
      'longitude': longitude,
      'threatLevel': threatLevel,
      'sourceType': 'walkie_talkie',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'deviceId': _meshManager.deviceId,
    };

    debugPrint(
        'MeshThreatRelay: Broadcasting threat (confidence=${(confidence * 100).toStringAsFixed(0)}%, level=$threatLevel)');

    await _meshManager.broadcastMessage(
      type: MessageType.walkieTalkieThreat,
      payload: payload,
      priority: MessagePriority.critical,
    );

    notifyListeners();
  }

  /// Handle incoming mesh messages — filter for walkie-talkie threats.
  void _onMeshMessage() {
    // Check the last N messages for walkieTalkieThreat type
    final recentMessages = _meshManager.messages.take(10).toList();
    for (final msg in recentMessages) {
      if (msg.type == MessageType.walkieTalkieThreat) {
        final alert = RemoteThreatAlert.fromMeshMessage(msg);
        // Avoid duplicates — check if we already have this alert
        final exists =
            _incomingThreats.any((a) => a.id == alert.id);
        if (!exists) {
          _incomingThreats.insert(0, alert);
          // Keep only last 50 remote threats
          if (_incomingThreats.length > 50) {
            _incomingThreats.removeRange(50, _incomingThreats.length);
          }
          debugPrint(
              'MeshThreatRelay: Received remote threat from ${alert.deviceId} '
              '(confidence=${(alert.confidence * 100).toStringAsFixed(0)}%)');
          onRemoteThreatReceived?.call(alert);
          notifyListeners();
        }
      }
    }
  }

  /// Clear all incoming threat alerts.
  void clearThreats() {
    _incomingThreats.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    stopListening();
    super.dispose();
  }
}

/// Represents a walkie-talkie threat alert received from a remote mesh peer.
class RemoteThreatAlert {
  final String id;
  final String deviceId;
  final double confidence;
  final String method;
  final double? latitude;
  final double? longitude;
  final String threatLevel;
  final int timestamp;
  final DateTime receivedAt;

  RemoteThreatAlert({
    required this.id,
    required this.deviceId,
    required this.confidence,
    required this.method,
    this.latitude,
    this.longitude,
    required this.threatLevel,
    required this.timestamp,
    DateTime? receivedAt,
  }) : receivedAt = receivedAt ?? DateTime.now();

  /// Parse from a MeshMessage payload.
  factory RemoteThreatAlert.fromMeshMessage(MeshMessage msg) {
    final payload = msg.payload;
    return RemoteThreatAlert(
      id: msg.id,
      deviceId: payload['deviceId'] as String? ?? msg.senderDeviceId,
      confidence: (payload['confidence'] as num?)?.toDouble() ?? 0.0,
      method: payload['method'] as String? ?? 'unknown',
      latitude: (payload['latitude'] as num?)?.toDouble(),
      longitude: (payload['longitude'] as num?)?.toDouble(),
      threatLevel: payload['threatLevel'] as String? ?? 'high',
      timestamp: (payload['timestamp'] as num?)?.toInt() ?? msg.timestamp,
    );
  }

  /// Whether this alert is recent (within the last 5 minutes).
  bool get isRecent =>
      DateTime.now().difference(receivedAt).inMinutes < 5;

  /// Human-readable time ago string.
  String get timeAgo {
    final diff = DateTime.now().difference(receivedAt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}
