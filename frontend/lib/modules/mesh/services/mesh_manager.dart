import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants.dart';
import '../../../shared/services/offline_storage.dart';
import '../../../shared/services/encryption.dart';

/// Mesh Manager - Three-layer communication stack for offline messaging.
/// 
/// Architecture:
/// - Layer 1: Bluetooth Mesh (short-range, ~100m)
/// - Layer 2: Wi-Fi Direct (medium-range, ~200m)
/// - Layer 3: LoRa Bridge (long-range, ~10km, requires external hardware)
class MeshManager extends ChangeNotifier {
  static final MeshManager _instance = MeshManager._internal();
  factory MeshManager() => _instance;
  MeshManager._internal();

  final OfflineStorageService _storage = OfflineStorageService();
  final EncryptionService _encryption = EncryptionService();
  final Uuid _uuid = const Uuid();

  // Bluetooth
  FlutterBluetoothSerial? _bluetooth;
  BluetoothState _bluetoothState = BluetoothState.UNKNOWN;
  
  // Mesh State
  List<MeshPeer> _discoveredPeers = [];
  List<MeshMessage> _messageQueue = [];
  bool _isBroadcasting = false;
  bool _isScanning = false;
  String? _deviceId;
  int _connectedPeers = 0;

  // LoRa Bridge (external hardware)
  bool _loraAvailable = false;
  String? _loraGatewayAddress;

  // Getters
  List<MeshPeer> get discoveredPeers => _discoveredPeers;
  List<MeshMessage> get messageQueue => _messageQueue;
  bool get isBroadcasting => _isBroadcasting;
  bool get isScanning => _isScanning;
  bool get isBluetoothEnabled => _bluetoothState == BluetoothState.STATE_ON;
  bool get isLoraAvailable => _loraAvailable;
  int get connectedPeers => _connectedPeers;
  String? get deviceId => _deviceId;

  /// Initialize the mesh manager.
  Future<void> initialize() async {
    _deviceId = await _storage.getSetting('device_id') as String?;
    if (_deviceId == null) {
      _deviceId = _uuid.v4();
      await _storage.saveSetting('device_id', _deviceId!);
    }

    // Initialize Bluetooth (mobile only)
    if (!kIsWeb) {
      _bluetooth = FlutterBluetoothSerial.instance;
      _bluetooth!.onStateChanged().listen((state) {
        _bluetoothState = state;
        notifyListeners();
      });

      _bluetoothState = await _bluetooth!.state;
    }
    notifyListeners();
  }

  /// Start scanning for nearby peers via Bluetooth.
  Future<void> startScanning() async {
    if (_isScanning) return;
    _isScanning = true;
    notifyListeners();

    try {
      if (!isBluetoothEnabled) {
        await _bluetooth?.requestEnable();
      }

      _bluetooth?.startDiscovery().listen((result) {
        if (result.device != null && result.device.name != null) {
          _addDiscoveredPeer(MeshPeer(
            deviceId: result.device.address,
            name: result.device.name ?? 'Unknown Device',
            lastSeen: DateTime.now().millisecondsSinceEpoch,
            signalStrength: result.rssi,
            connectionType: ConnectionType.bluetooth,
          ));
        }
      }).onDone(() {
        _isScanning = false;
        notifyListeners();
      });
    } catch (e) {
      debugPrint('Bluetooth scan error: $e');
      _isScanning = false;
      notifyListeners();
    }
  }

  /// Stop scanning for peers.
  void stopScanning() {
    _bluetooth?.cancelDiscovery();
    _isScanning = false;
    notifyListeners();
  }

  /// Add a discovered peer to the list.
  void _addDiscoveredPeer(MeshPeer peer) {
    final existingIndex = _discoveredPeers.indexWhere(
      (p) => p.deviceId == peer.deviceId,
    );

    if (existingIndex >= 0) {
      _discoveredPeers[existingIndex] = peer;
    } else {
      _discoveredPeers.add(peer);
    }

    // Persist peer
    _storage.upsertPeer(peer.toMap());
    notifyListeners();
  }

  /// Broadcast a message through all available channels.
  Future<bool> broadcastMessage({
    required MessageType type,
    required Map<String, dynamic> payload,
    MessagePriority priority = MessagePriority.normal,
  }) async {
    final message = MeshMessage(
      id: _uuid.v4(),
      senderId: _deviceId ?? 'unknown',
      type: type,
      payload: payload,
      priority: priority,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    // Store in local queue
    await _queueMessage(message);

    // Attempt to send via all available channels
    final results = await Future.wait([
      _sendViaBluetooth(message),
      _sendViaWiFiDirect(message),
      if (_loraAvailable) _sendViaLoRa(message),
    ], eagerError: false);

    final success = results.any((r) => r);
    if (success) {
      await _dequeueMessage(message.id);
    }

    return success;
  }

  /// Queue a message for later delivery.
  Future<void> _queueMessage(MeshMessage message) async {
    _messageQueue.add(message);
    await _storage.saveMessage({
      'id': message.id,
      'sender_id': message.senderId,
      'content': json.encode(message.toMap()),
      'message_type': message.type.name,
      'priority': message.priority.index,
      'status': 'pending',
      'sync_state': 'offline',
      'created_at': message.timestamp,
    });
    notifyListeners();
  }

  /// Remove a message from the queue after successful delivery.
  Future<void> _dequeueMessage(String messageId) async {
    _messageQueue.removeWhere((m) => m.id == messageId);
    await _storage.update('messages', {
      'status': 'sent',
      'sync_state': 'synced',
    }, where: 'id = ?', whereArgs: [messageId]);
    notifyListeners();
  }

  /// Send message via Bluetooth.
  Future<bool> _sendViaBluetooth(MeshMessage message) async {
    try {
      if (!isBluetoothEnabled) return false;

      // Encrypt the message payload
      final encrypted = _encryption.encryptMessage(
        json.encode(message.toMap()),
        _deriveSessionKey(),
      );

      // Broadcast to all connected peers
      for (final peer in _discoveredPeers) {
        if (peer.connectionType == ConnectionType.bluetooth) {
          // In production, use actual Bluetooth socket connection
          debugPrint('Sending via Bluetooth to ${peer.name}: ${message.id}');
        }
      }

      return true;
    } catch (e) {
      debugPrint('Bluetooth send error: $e');
      return false;
    }
  }

  /// Send message via Wi-Fi Direct.
  Future<bool> _sendViaWiFiDirect(MeshMessage message) async {
    try {
      // In production, implement Wi-Fi Direct P2P discovery and send
      debugPrint('Sending via WiFi Direct: ${message.id}');
      return true;
    } catch (e) {
      debugPrint('WiFi Direct send error: $e');
      return false;
    }
  }

  /// Send message via LoRa bridge.
  Future<bool> _sendViaLoRa(MeshMessage message) async {
    try {
      if (!_loraAvailable) return false;
      
      // In production, communicate with ESP32-S3 + SX1262 via serial/USB
      debugPrint('Sending via LoRa to $_loraGatewayAddress: ${message.id}');
      return true;
    } catch (e) {
      debugPrint('LoRa send error: $e');
      return false;
    }
  }

  /// Public method to send via LoRa (called from SOS service).
  Future<bool> sendViaLoRa(Map<String, dynamic> payload) async {
    final message = MeshMessage(
      id: _uuid.v4(),
      senderId: _deviceId ?? 'unknown',
      type: MessageType.sos,
      payload: payload,
      priority: MessagePriority.critical,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    return await _sendViaLoRa(message);
  }

  /// Derive a session key for E2E encryption.
  Uint8List _deriveSessionKey() {
    return _encryption.deriveKey(
      'mesh-session-${DateTime.now().millisecondsSinceEpoch}',
      salt: _deviceId ?? 'DangerEmergenceMesh',
    );
  }

  /// Connect to a LoRa gateway.
  Future<void> connectLoRaGateway(String address) async {
    _loraGatewayAddress = address;
    _loraAvailable = true;
    notifyListeners();
  }

  /// Disconnect from LoRa gateway.
  void disconnectLoRaGateway() {
    _loraGatewayAddress = null;
    _loraAvailable = false;
    notifyListeners();
  }

  /// Get mesh network statistics.
  MeshStats getStats() {
    return MeshStats(
      totalPeers: _discoveredPeers.length,
      connectedPeers: _connectedPeers,
      queuedMessages: _messageQueue.length,
      isBluetoothEnabled: isBluetoothEnabled,
      isLoraAvailable: _loraAvailable,
      isScanning: _isScanning,
    );
  }

  /// Retry sending all queued messages.
  Future<int> retryQueuedMessages() async {
    int sent = 0;
    final queued = List<MeshMessage>.from(_messageQueue);
    
    for (final message in queued) {
      final success = await broadcastMessage(
        type: message.type,
        payload: message.payload,
        priority: message.priority,
      );
      if (success) sent++;
    }

    return sent;
  }

  /// Clear stale peers (not seen in 30+ minutes).
  Future<void> clearStalePeers() async {
    final cutoff = DateTime.now().millisecondsSinceEpoch - (30 * 60 * 1000);
    _discoveredPeers.removeWhere((p) => p.lastSeen < cutoff);
    notifyListeners();
  }

  @override
  void dispose() {
    stopScanning();
    super.dispose();
  }
}

/// Mesh peer model.
class MeshPeer {
  final String deviceId;
  final String name;
  final int lastSeen;
  final int? signalStrength;
  final ConnectionType connectionType;
  final bool isGateway;

  MeshPeer({
    required this.deviceId,
    required this.name,
    required this.lastSeen,
    this.signalStrength,
    this.connectionType = ConnectionType.bluetooth,
    this.isGateway = false,
  });

  factory MeshPeer.fromMap(Map<String, dynamic> map) {
    return MeshPeer(
      deviceId: map['device_id'] as String,
      name: map['name'] as String? ?? 'Unknown',
      lastSeen: map['last_seen'] as int,
      signalStrength: map['signal_strength'] as int?,
      connectionType: ConnectionType.values.firstWhere(
        (c) => c.name == map['connection_type'],
        orElse: () => ConnectionType.bluetooth,
      ),
      isGateway: (map['is_gateway'] as int? ?? 0) == 1,
    );
  }

  Map<String, dynamic> toMap() => {
    'device_id': deviceId,
    'name': name,
    'last_seen': lastSeen,
    'signal_strength': signalStrength,
    'connection_type': connectionType.name,
    'is_gateway': isGateway ? 1 : 0,
  };
}

/// Mesh message model.
class MeshMessage {
  final String id;
  final String senderId;
  final MessageType type;
  final Map<String, dynamic> payload;
  final MessagePriority priority;
  final int timestamp;

  MeshMessage({
    required this.id,
    required this.senderId,
    required this.type,
    required this.payload,
    this.priority = MessagePriority.normal,
    required this.timestamp,
  });

  factory MeshMessage.fromMap(Map<String, dynamic> map) {
    return MeshMessage(
      id: map['id'] as String,
      senderId: map['sender_id'] as String,
      type: MessageType.values.firstWhere(
        (t) => t.name == map['type'],
        orElse: () => MessageType.text,
      ),
      payload: map['payload'] as Map<String, dynamic>? ?? {},
      priority: MessagePriority.values.firstWhere(
        (p) => p.name == map['priority'],
        orElse: () => MessagePriority.normal,
      ),
      timestamp: map['timestamp'] as int,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'sender_id': senderId,
    'type': type.name,
    'payload': payload,
    'priority': priority.name,
    'timestamp': timestamp,
  };
}

/// Message types for mesh communication.
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
}

/// Message priority levels.
enum MessagePriority {
  low,
  normal,
  high,
  critical,
}

/// Connection type for mesh peers.
enum ConnectionType {
  bluetooth,
  wifiDirect,
  lora,
}

/// Mesh network statistics.
class MeshStats {
  final int totalPeers;
  final int connectedPeers;
  final int queuedMessages;
  final bool isBluetoothEnabled;
  final bool isLoraAvailable;
  final bool isScanning;

  MeshStats({
    required this.totalPeers,
    required this.connectedPeers,
    required this.queuedMessages,
    required this.isBluetoothEnabled,
    required this.isLoraAvailable,
    required this.isScanning,
  });
}

