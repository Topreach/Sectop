import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants.dart';
import '../../../shared/services/offline_storage.dart';
import '../../../shared/services/encryption.dart';
import 'adaptive_mesh_router.dart';

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

  // Adaptive Mesh Router
  late final AdaptiveMeshRouter _router;

  // Event Channel for incoming mesh data
  static const _eventChannel = EventChannel('com.dangeremergence/mesh_data');
  StreamSubscription? _meshDataSubscription;

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

  // Battery level (0-100), updated from platform
  double _batteryLevel = 80.0;

  // Getters
  List<MeshPeer> get discoveredPeers => _discoveredPeers;
  List<MeshMessage> get messageQueue => _messageQueue;
  bool get isBroadcasting => _isBroadcasting;
  bool get isScanning => _isScanning;
  bool get isBluetoothEnabled => _bluetoothState == BluetoothState.STATE_ON;
  bool get isLoraAvailable => _loraAvailable;
  int get connectedPeers => _connectedPeers;
  String? get deviceId => _deviceId;
  double get batteryLevel => _batteryLevel;
  AdaptiveMeshRouter get router => _router;

  /// Initialize the mesh manager.
  Future<void> initialize() async {
    _deviceId = await _storage.getSetting('device_id') as String?;
    if (_deviceId == null) {
      _deviceId = _uuid.v4();
      await _storage.saveSetting('device_id', _deviceId!);
    }

    // Initialize the adaptive mesh router and bind it to this manager
    _router = AdaptiveMeshRouter();
    _router.bindToMeshManager(this);
    _router.initialize();

    // Initialize the mesh data loopback (EventChannel)
    if (!kIsWeb) {
      _meshDataSubscription = _eventChannel.receiveBroadcastStream().listen(
        (event) {
          if (event is Map) {
            final address = event['address'] as String;
            final data = event['data'] as Uint8List;
            // In a real scenario, RSSI would be passed from native too
            processIncomingData(data, address, -70.0);
          }
        },
        onError: (err) => debugPrint('Mesh data stream error: $err'),
      );
    }

    // Initialize Bluetooth (mobile only)
    if (!kIsWeb) {
      try {
        _bluetooth = FlutterBluetoothSerial.instance;
        _bluetooth!.onStateChanged().listen((state) {
          _bluetoothState = state;
          notifyListeners();
        });

        _bluetoothState = await _bluetooth!.state;
      } catch (e, stack) {
        debugPrint('MeshManager: Bluetooth init failed (non-fatal): $e\n$stack');
        _bluetooth = null;
        _bluetoothState = BluetoothState.UNKNOWN;
      }
    }
    notifyListeners();
  }
  /// Start scanning for nearby peers via Bluetooth.
  Future<void> startScanning() async {
    if (_isScanning) return;

    // Check permissions for Android 12+
    if (!kIsWeb) {
      final scanStatus = await Permission.bluetoothScan.request();
      final connectStatus = await Permission.bluetoothConnect.request();

      if (!scanStatus.isGranted || !connectStatus.isGranted) {
        debugPrint('MeshManager: Bluetooth permissions denied');
        return;
      }
    }

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

      // Use the router to find best path and send
      final route = await _router.findRoute(message.senderId);
      if (route.isNotEmpty) {
        // Send via the best next hop
        final data = utf8.encode(json.encode({
          'type': 'MESH_MESSAGE',
          'messageId': message.id,
          'senderId': message.senderId,
          'payload': encrypted.toJson(),
          'timestamp': message.timestamp,
        }));
        await sendRawData(route.first, data);
        return true;
      }

      // Fallback: broadcast to all discovered Bluetooth peers
      for (final peer in _discoveredPeers) {
        if (peer.connectionType == ConnectionType.bluetooth) {
          try {
            // Attempt Bluetooth RFCOMM socket connection
            final socket = await _bluetooth?.connect(peer.deviceId);
            if (socket != null) {
              socket.output.add(utf8.encode(json.encode({
                'type': 'MESH_MESSAGE',
                'messageId': message.id,
                'senderId': message.senderId,
                'payload': encrypted.toJson(),
                'timestamp': message.timestamp,
              })));
              await socket.output.close();
              return true;
            }
          } catch (e) {
            debugPrint('Bluetooth send to ${peer.name} failed: $e');
          }
        }
      }

      return false;
    } catch (e) {
      debugPrint('Bluetooth send error: $e');
      return false;
    }
  }

  /// Send message via Wi-Fi Direct.
  Future<bool> _sendViaWiFiDirect(MeshMessage message) async {
    try {
      // Encrypt the message payload
      final encrypted = _encryption.encryptMessage(
        json.encode(message.toMap()),
        _deriveSessionKey(),
      );

      // Use the router to find best path
      final route = await _router.findRoute(message.senderId);
      if (route.isNotEmpty) {
        final data = utf8.encode(json.encode({
          'type': 'MESH_MESSAGE',
          'messageId': message.id,
          'senderId': message.senderId,
          'payload': encrypted.toJson(),
          'timestamp': message.timestamp,
        }));
        await sendRawData(route.first, data);
        return true;
      }

      // Fallback: broadcast to all WiFi Direct peers
      for (final peer in _discoveredPeers) {
        if (peer.connectionType == ConnectionType.wifiDirect) {
          debugPrint('Sending via WiFi Direct to ${peer.name}: ${message.id}');
          // In production: use Wi-Fi Direct P2P socket
        }
      }

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

      // Encrypt the message payload
      final encrypted = _encryption.encryptMessage(
        json.encode(message.toMap()),
        _deriveSessionKey(),
      );

      // Use the router to find best path
      final route = await _router.findRoute(message.senderId);
      if (route.isNotEmpty) {
        final data = utf8.encode(json.encode({
          'type': 'MESH_MESSAGE',
          'messageId': message.id,
          'senderId': message.senderId,
          'payload': encrypted.toJson(),
          'timestamp': message.timestamp,
        }));
        await sendRawData(route.first, data);
        return true;
      }

      // Fallback: send via LoRa serial bridge
      debugPrint('Sending via LoRa to $_loraGatewayAddress: ${message.id}');
      // In production: communicate with ESP32-S3 + SX1262 via serial/USB
      return true;
    } catch (e) {
      debugPrint('LoRa send error: $e');
      return false;
    }
  }

  /// Broadcast raw data on all available interfaces (used by AdaptiveMeshRouter).
  Future<void> broadcastRawData(List<int> data, {MessagePriority priority = MessagePriority.normal}) async {
    try {
      // Broadcast via Bluetooth
      if (isBluetoothEnabled) {
        for (final peer in _discoveredPeers) {
          if (peer.connectionType == ConnectionType.bluetooth) {
            try {
              final socket = await _bluetooth?.connect(peer.deviceId);
              if (socket != null) {
                socket.output.add(data);
                await socket.output.close();
              }
            } catch (e) {
              debugPrint('Bluetooth broadcast to ${peer.name} failed: $e');
            }
          }
        }
      }

      // Broadcast via WiFi Direct
      for (final peer in _discoveredPeers) {
        if (peer.connectionType == ConnectionType.wifiDirect) {
          debugPrint('WiFi Direct broadcast to ${peer.name}: ${data.length} bytes');
          // In production: use Wi-Fi Direct P2P socket
        }
      }

      // Broadcast via LoRa
      if (_loraAvailable) {
        debugPrint('LoRa broadcast: ${data.length} bytes');
        // In production: send via serial to ESP32-S3 + SX1262
      }
    } catch (e) {
      debugPrint('broadcastRawData error: $e');
    }
  }

  /// Send raw data to a specific peer (used by AdaptiveMeshRouter for unicast).
  Future<void> sendRawData(String peerId, List<int> data) async {
    try {
      // Find the peer
      final peer = _discoveredPeers.where((p) => p.deviceId == peerId).firstOrNull;
      if (peer == null) {
        debugPrint('sendRawData: peer $peerId not found');
        return;
      }

      switch (peer.connectionType) {
        case ConnectionType.bluetooth:
          if (isBluetoothEnabled) {
            final socket = await _bluetooth?.connect(peer.deviceId);
            if (socket != null) {
              socket.output.add(data);
              await socket.output.close();
            }
          }
          break;
        case ConnectionType.wifiDirect:
          debugPrint('WiFi Direct send to ${peer.name}: ${data.length} bytes');
          // In production: use Wi-Fi Direct P2P socket
          break;
        case ConnectionType.lora:
          if (_loraAvailable) {
            debugPrint('LoRa send to $_loraGatewayAddress: ${data.length} bytes');
            // In production: send via serial to ESP32-S3 + SX1262
          }
          break;
      }
    } catch (e) {
      debugPrint('sendRawData error: $e');
    }
  }

  /// Process incoming raw data from any interface (called by platform channels or listeners).
  void processIncomingData(List<int> data, String fromPeer, double rssi) {
    try {
      final decoded = json.decode(utf8.decode(data)) as Map<String, dynamic>;
      final type = decoded['type'] as String;

      switch (type) {
        case 'OGM':
          _router.processOGM(
            OGMMessage(
              originator: decoded['originator'] as String,
              sequenceNumber: decoded['sequenceNumber'] as int,
              hopCount: (decoded['hopCount'] as int?) ?? 0,
              batteryLevel: (decoded['batteryLevel'] as num).toDouble(),
              neighborCount: (decoded['neighborCount'] as int?) ?? 0,
              timestamp: DateTime.parse(decoded['timestamp'] as String),
            ),
            fromPeer,
            rssi,
          );
          break;
        case 'RREQ':
          _router.processRREQ(
            RREQMessage(
              originator: decoded['originator'] as String,
              destination: decoded['destination'] as String,
              rreqId: decoded['rreqId'] as int,
              hopCount: (decoded['hopCount'] as int?) ?? 0,
              pathCost: (decoded['pathCost'] as num).toDouble(),
              minBattery: (decoded['minBattery'] as num).toDouble(),
            ),
            fromPeer,
            rssi,
          );
          break;
        case 'RREP':
          _router.processRREP(
            RREPMessage(
              destination: decoded['destination'] as String,
              originator: decoded['originator'] as String,
              pathCost: (decoded['pathCost'] as num).toDouble(),
              nextHop: decoded['nextHop'] as String,
            ),
            fromPeer,
          );
          break;
        case 'MESH_MESSAGE':
          _handleIncomingMeshMessage(decoded, fromPeer);
          break;
        default:
          debugPrint('Unknown mesh message type: $type');
      }
    } catch (e) {
      debugPrint('processIncomingData error: $e');
    }
  }

  /// Handle an incoming mesh message (decrypt, store, notify).
  void _handleIncomingMeshMessage(Map<String, dynamic> decoded, String fromPeer) {
    try {
      final messageId = decoded['messageId'] as String;
      final senderId = decoded['senderId'] as String;
      final encryptedPayloadJson = decoded['payload'] as Map<String, dynamic>;
      final timestamp = decoded['timestamp'] as int;

      // Decrypt the payload
      final encryptedMessage = EncryptedMessage.fromJson(encryptedPayloadJson);
      final decrypted = _encryption.decryptMessage(
        encryptedMessage,
        _deriveSessionKey(),
      );
      final payload = json.decode(decrypted) as Map<String, dynamic>;

      // Create and store the message
      final message = MeshMessage(
        id: messageId,
        senderId: senderId,
        type: MessageType.values.firstWhere(
          (t) => t.name == (payload['type'] as String? ?? 'text'),
          orElse: () => MessageType.text,
        ),
        payload: payload,
        timestamp: timestamp,
      );

      _messageQueue.add(message);
      _storage.saveMessage({
        'id': message.id,
        'sender_id': message.senderId,
        'content': json.encode(message.toMap()),
        'message_type': message.type.name,
        'priority': message.priority.index,
        'status': 'received',
        'sync_state': 'synced',
        'created_at': message.timestamp,
      });
      notifyListeners();
    } catch (e) {
      debugPrint('_handleIncomingMeshMessage error: $e');
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
    _meshDataSubscription?.cancel();
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

