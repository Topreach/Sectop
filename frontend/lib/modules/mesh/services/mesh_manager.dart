import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants.dart';
import '../../../shared/services/offline_storage.dart';
import '../../../shared/services/backend_api.dart';

/// Thin mesh manager — keeps local Bluetooth peer discovery for last-hop
/// device-to-device communication. All routing computation (B.A.T.M.A.N.,
/// AODV) and multi-hop relay logic have been moved to the backend.
class MeshManager extends ChangeNotifier {
  static final MeshManager _instance = MeshManager._internal();
  factory MeshManager() => _instance;
  MeshManager._internal();

  final OfflineStorageService _storage = OfflineStorageService();
  final BackendApi _api = BackendApi();
  final Uuid _uuid = const Uuid();

  String _deviceId = '';
  List<MeshPeer> _knownPeers = [];
  List<MeshPeer> _discoveredPeers = [];
  List<MeshMessage> _messages = [];
  bool _isInitialized = false;
  bool _isScanning = false;
  bool _isBatterySaverEnabled = false;
  Timer? _statsTimer;

  /// This device's unique mesh identifier.
  String get deviceId => _deviceId;

  /// Known peers discovered via Bluetooth or backend.
  List<MeshPeer> get knownPeers => _knownPeers;

  /// Discovered peers (alias for knownPeers for UI compatibility).
  List<MeshPeer> get discoveredPeers => _discoveredPeers;

  /// Mesh messages received.
  List<MeshMessage> get messages => _messages;

  /// Whether the mesh manager is initialized.
  bool get isInitialized => _isInitialized;

  /// Whether scanning is currently active.
  bool get isScanning => _isScanning;

  /// Whether battery saver mode is active.
  bool get isBatterySaverEnabled => _isBatterySaverEnabled;

  /// Start scanning for nearby peers.
  Future<void> startScanning() async {
    if (_isScanning) return;
    
    // Check Bluetooth permissions (required for Android 12+)
    if (Platform.isAndroid) {
      final status = await Permission.bluetoothScan.status;
      if (!status.isGranted) {
        final result = await Permission.bluetoothScan.request();
        if (!result.isGranted) {
          debugPrint('MeshManager: BLUETOOTH_SCAN permission denied');
          return;
        }
      }
    }
    
    _isScanning = true;
    debugPrint('MeshManager: Scanning started');
    notifyListeners();
  }

  /// Stop scanning for nearby peers.
  void stopScanning() {
    if (!_isScanning) return;
    _isScanning = false;
    debugPrint('MeshManager: Scanning stopped');
    notifyListeners();
  }

  /// Toggle battery saver mode.
  void setBatterySaver(bool enabled) {
    _isBatterySaverEnabled = enabled;
    debugPrint('MeshManager: Battery saver ${enabled ? 'enabled' : 'disabled'}');
    notifyListeners();
  }

  /// Initialize the mesh manager.
  Future<void> initialize() async {
    if (_isInitialized) return;

    _deviceId = 'device_${_uuid.v4().substring(0, 8)}';

    // Load cached peers from local storage
    try {
      final cachedPeers = await _storage.query('mesh_peers',
          orderBy: 'last_seen DESC');
      _knownPeers = cachedPeers.map((p) => MeshPeer.fromMap(p)).toList();
    } catch (e) {
      debugPrint('MeshManager: Failed to load cached peers: $e');
    }

    _isInitialized = true;
    debugPrint('MeshManager: Initialized (deviceId=$_deviceId, thin client mode)');

    // Start periodic stats reporting
    _startStatsReporting();

    notifyListeners();
  }

  void _startStatsReporting() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (_isBatterySaverEnabled && timer.tick % 4 != 0) {
        // In battery saver mode, only report every 20 minutes instead of 5
        return;
      }
      _reportStats();
    });
  }

  Future<void> _reportStats() async {
    try {
      final stats = {
        'deviceId': _deviceId,
        'peerCount': _knownPeers.length,
        'messageCount': _messages.length,
        'isBatterySaverEnabled': _isBatterySaverEnabled,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      await _api.reportMeshStats(stats);
    } catch (e) {
      debugPrint('MeshManager: Failed to report stats: $e');
    }
  }

  /// Broadcast a message — stores locally and attempts backend relay.
  Future<void> broadcastMessage({
    required MessageType type,
    required Map<String, dynamic> payload,
    MessagePriority priority = MessagePriority.normal,
  }) async {
    final message = MeshMessage(
      id: _uuid.v4(),
      senderDeviceId: _deviceId,
      type: type,
      payload: payload,
      priority: priority,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    // Store locally
    _messages.insert(0, message);
    if (_messages.length > AppConstants.maxOfflineMessages) {
      _messages.removeLast();
    }

    // Try backend relay
    try {
      await _api.broadcastMeshMessage(
        _deviceId,
        type.name,
        priority.index,
        payload,
      );
    } catch (e) {
      debugPrint('MeshManager: Backend broadcast failed (queued locally): $e');
    }

    notifyListeners();
  }

  /// Find route to a target device via backend.
  Future<List<String>> findRoute(String targetDeviceId) async {
    try {
      final neighborMetrics = _knownPeers
          .map((p) => {
                'deviceId': p.deviceId,
                'rssi': p.signalStrength,
                'battery': p.battery,
                'linkQuality': p.linkQuality,
              })
          .toList();

      final result = await _api.findRoute(
        _deviceId,
        targetDeviceId,
        neighborMetrics: neighborMetrics,
      );

      if (result['path'] is List) {
        return (result['path'] as List).map((e) => e as String).toList();
      }
    } catch (e) {
      debugPrint('MeshManager: findRoute failed: $e');
    }

    return [];
  }

  /// Send a message via LoRa bridge (delegates to backend).
  Future<void> sendViaLoRa(Map<String, dynamic> payload) async {
    try {
      await _api.broadcastMeshMessage(
        _deviceId,
        MessageType.text.name,
        MessagePriority.high.index,
        payload,
      );
    } catch (e) {
      debugPrint('MeshManager: LoRa send failed: $e');
    }
  }

  /// Update known peers list.
  void updatePeers(List<MeshPeer> peers) {
    _knownPeers = peers;
    notifyListeners();
  }

  /// Add a single peer.
  void addPeer(MeshPeer peer) {
    _knownPeers.removeWhere((p) => p.deviceId == peer.deviceId);
    _knownPeers.insert(0, peer);
    notifyListeners();
  }

  /// Get mesh statistics.
  MeshStats getStats() {
    return MeshStats(
      totalPeers: _knownPeers.length,
      totalMessages: _messages.length,
      activeConnections: _knownPeers.where((p) =>
          DateTime.now().millisecondsSinceEpoch - p.lastSeen < 60000).length,
      averageSignalStrength: _knownPeers.isEmpty
          ? 0
          : _knownPeers.fold(0, (sum, p) => sum + p.signalStrength) ~/
              _knownPeers.length,
    );
  }
}

// ---------------------------------------------------------------------------
// Data classes (preserved for UI compatibility)
// ---------------------------------------------------------------------------

enum MessageType {
  text,
  sos,
  alert,
  locationUpdate,
  acknowledgment,
  resolution,
  zoneUpdate,
  peerDiscovery,
  heartbeat,
  walkieTalkieThreat,
}

enum MessagePriority {
  low,
  normal,
  high,
  critical,
}

enum ConnectionType {
  bluetooth,
  wifiDirect,
  lora,
}

class MeshMessage {
  final String id;
  final String senderDeviceId;
  final MessageType type;
  final Map<String, dynamic> payload;
  final MessagePriority priority;
  final int timestamp;

  MeshMessage({
    required this.id,
    required this.senderDeviceId,
    required this.type,
    required this.payload,
    required this.priority,
    required this.timestamp,
  });
}

class MeshPeer {
  final String deviceId;
  final String? name;
  final String? userId;
  final int lastSeen;
  final int signalStrength;
  final int battery;
  final double linkQuality;
  final ConnectionType connectionType;
  final bool isGateway;

  MeshPeer({
    required this.deviceId,
    this.name,
    this.userId,
    required this.lastSeen,
    this.signalStrength = 0,
    this.battery = 100,
    this.linkQuality = 1.0,
    this.connectionType = ConnectionType.bluetooth,
    this.isGateway = false,
  });

  factory MeshPeer.fromMap(Map<String, dynamic> map) {
    return MeshPeer(
      deviceId: map['device_id'] as String? ?? '',
      name: map['name'] as String?,
      userId: map['user_id'] as String?,
      lastSeen: (map['last_seen'] as num?)?.toInt() ?? 0,
      signalStrength: (map['signal_strength'] as num?)?.toInt() ?? 0,
      battery: (map['battery'] as num?)?.toInt() ?? 100,
      linkQuality: (map['link_quality'] as num?)?.toDouble() ?? 1.0,
      connectionType: _parseConnectionType(map['connection_type'] as String?),
      isGateway: map['is_gateway'] == 1,
    );
  }

  static ConnectionType _parseConnectionType(String? type) {
    switch (type) {
      case 'wifiDirect':
        return ConnectionType.wifiDirect;
      case 'lora':
        return ConnectionType.lora;
      default:
        return ConnectionType.bluetooth;
    }
  }
}

class MeshStats {
  final int totalPeers;
  final int totalMessages;
  final int activeConnections;
  final int averageSignalStrength;

  MeshStats({
    required this.totalPeers,
    required this.totalMessages,
    required this.activeConnections,
    required this.averageSignalStrength,
  });
}
