import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/drone_models.dart';

/// MAVLink protocol implementation for drone communication.
///
/// Handles:
/// - WebSocket connection to drone hub
/// - Command encoding/decoding
/// - Telemetry streaming (heartbeat, position, battery)
/// - Automatic reconnection with exponential backoff
class MAVLinkService {
  static final MAVLinkService _instance = MAVLinkService._();
  factory MAVLinkService() => _instance;
  MAVLinkService._();

  WebSocketChannel? _channel;
  final Map<String, Drone> _drones = {};
  final Map<String, StreamController<MAVLinkMessage>> _messageStreams = {};
  bool _isConnected = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  String? _serverUrl;
  String? _authToken;

  // MAVLink message IDs
  static const int msgHeartbeat = 0;
  static const int msgGlobalPositionInt = 33;
  static const int msgBatteryStatus = 147;
  static const int msgCommandAck = 77;
  static const int msgStatustext = 253;
  static const int msgSysStatus = 1;

  bool get isConnected => _isConnected;
  Map<String, Drone> get drones => Map.unmodifiable(_drones);

  /// Connect to the MAVLink drone hub via WebSocket.
  Future<void> connect(String serverUrl, {String? authToken}) async {
    _serverUrl = serverUrl;
    _authToken = authToken;

    try {
      final uri = Uri.parse('ws://$serverUrl:5760');
      _channel = WebSocketChannel.connect(uri);

      // Authenticate
      if (authToken != null) {
        _channel!.sink.add(jsonEncode({
          'type': 'auth',
          'token': authToken,
        }));
      }

      // Listen for messages
      _channel!.stream.listen(
        _handleMessage,
        onError: (error) {
          debugPrint('MAVLink error: $error');
          _attemptReconnect();
        },
        onDone: () {
          _isConnected = false;
          _attemptReconnect();
        },
      );

      _isConnected = true;
      _reconnectAttempts = 0;
      debugPrint('MAVLink connected to $serverUrl');
    } catch (e) {
      debugPrint('MAVLink connection failed: $e');
      _attemptReconnect();
    }
  }

  /// Disconnect from the drone hub.
  void disconnect() {
    _channel?.sink.close();
    _isConnected = false;
    for (final stream in _messageStreams.values) {
      stream.close();
    }
    _messageStreams.clear();
  }

  /// Discover available drones on the network.
  Future<List<Drone>> discoverDrones({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final discovered = <Drone>[];
    final completer = Completer<List<Drone>>();

    // Request system list
    _sendCommand(Command.requestAutopilotVersion, targetSystem: 0);

    Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.complete(discovered);
      }
    });

    // Listen for heartbeats from new drones
    final subscription = _channel?.stream.listen((data) {
      final msg = _parseMAVLinkMessage(data);
      if (msg.messageId == msgHeartbeat) {
        final droneId = msg.getField('systemId').toString();
        if (!_drones.containsKey(droneId)) {
          final newDrone = Drone(
            id: droneId,
            name: 'Drone-$droneId',
            status: DroneStatus.idle,
            location: const Location(0, 0),
            lastSeen: DateTime.now(),
          );
          _drones[droneId] = newDrone;
          discovered.add(newDrone);
        }
      }
    });

    final result = await completer.future;
    await subscription?.cancel();
    return result;
  }

  /// Arm a drone's motors.
  Future<void> armDrone(String droneId) async {
    await _sendCommand(
      Command.armDisarm,
      targetSystem: int.parse(droneId),
      params: [1.0], // 1 = arm, 0 = disarm
    );
  }

  /// Command drone to take off to specified altitude.
  Future<void> takeoff(String droneId, double altitudeMeters) async {
    await _sendCommand(
      Command.navigateTakeoff,
      targetSystem: int.parse(droneId),
      params: [0, 0, 0, 0, 0, 0, altitudeMeters],
    );
  }

  /// Command drone to fly to a specific GPS location.
  Future<void> gotoLocation(
      String droneId, Location location, double altitude) async {
    await _sendCommand(
      Command.navigateWaypoint,
      targetSystem: int.parse(droneId),
      params: [
        0, 0, 0, 0,
        location.latitude,
        location.longitude,
        altitude,
      ],
    );
  }

  /// Command drone to return to its launch point.
  Future<void> returnToHome(String droneId) async {
    await _sendCommand(
      Command.navigateReturnToLaunch,
      targetSystem: int.parse(droneId),
    );
  }

  /// Enable a specific payload on the drone.
  Future<void> enablePayload(String droneId, PayloadType payload) async {
    await _sendCommand(
      Command.doSetMode,
      targetSystem: int.parse(droneId),
      params: [1.0, payload.index.toDouble()],
    );
  }

  /// Upload a mission (list of waypoints) to the drone.
  Future<void> uploadMission(
      String droneId, List<Waypoint> waypoints) async {
    // Clear current mission
    await _sendCommand(
      Command.missionClearAll,
      targetSystem: int.parse(droneId),
    );

    // Upload waypoints one by one
    for (int i = 0; i < waypoints.length; i++) {
      await _sendCommand(
        Command.missionItem,
        targetSystem: int.parse(droneId),
        params: [
          i.toDouble(),
          0, 0, 0,
          waypoints[i].location.latitude,
          waypoints[i].location.longitude,
          waypoints[i].altitude,
        ],
      );
    }

    // Start mission
    await _sendCommand(
      Command.missionStart,
      targetSystem: int.parse(droneId),
    );
  }

  /// Send a MAVLink command to the drone hub.
  Future<void> _sendCommand(
    Command command, {
    int targetSystem = 0,
    List<double> params = const [],
  }) async {
    if (_channel == null || !_isConnected) {
      throw StateError('MAVLink not connected');
    }

    final message = jsonEncode({
      'type': 'command',
      'target_system': targetSystem,
      'command': command.index,
      'params': params,
    });

    _channel!.sink.add(message);
  }

  /// Parse an incoming MAVLink message.
  MAVLinkMessage _parseMAVLinkMessage(dynamic data) {
    try {
      final json = jsonDecode(data as String) as Map<String, dynamic>;
      return MAVLinkMessage(
        messageId: json['message_id'] as int,
        fields: json['fields'] as Map<String, dynamic>,
      );
    } catch (e) {
      return MAVLinkMessage(messageId: -1, fields: {});
    }
  }

  /// Handle an incoming message from the drone hub.
  void _handleMessage(dynamic data) {
    final msg = _parseMAVLinkMessage(data);
    if (msg.messageId == -1) return;

    switch (msg.messageId) {
      case msgHeartbeat:
        _updateDroneHeartbeat(msg);
        break;
      case msgGlobalPositionInt:
        _updateDronePosition(msg);
        break;
      case msgBatteryStatus:
        _updateDroneBattery(msg);
        break;
      case msgSysStatus:
        _updateDroneSystemStatus(msg);
        break;
    }

    // Forward to specific drone's stream
    final droneId = msg.getField('systemId')?.toString();
    if (droneId != null && _messageStreams.containsKey(droneId)) {
      _messageStreams[droneId]!.add(msg);
    }
  }

  /// Update drone status from heartbeat message.
  void _updateDroneHeartbeat(MAVLinkMessage msg) {
    final droneId = msg.getField('systemId').toString();
    final drone = _drones[droneId];
    if (drone != null) {
      drone.status = DroneStatus.airborne;
      drone.lastSeen = DateTime.now();
    }
  }

  /// Update drone GPS position from position message.
  void _updateDronePosition(MAVLinkMessage msg) {
    final droneId = msg.getField('systemId').toString();
    final drone = _drones[droneId];
    if (drone != null) {
      final lat = (msg.getField('lat') as num?)?.toDouble() ?? 0;
      final lon = (msg.getField('lon') as num?)?.toDouble() ?? 0;
      final alt = (msg.getField('alt') as num?)?.toDouble() ?? 0;
      drone.location = Location(lat / 1e7, lon / 1e7);
      drone.altitudeAGL = alt / 1000;
    }
  }

  /// Update drone battery from battery status message.
  void _updateDroneBattery(MAVLinkMessage msg) {
    final droneId = msg.getField('systemId').toString();
    final drone = _drones[droneId];
    if (drone != null) {
      final voltages = msg.getField('voltages') as List<dynamic>?;
      if (voltages != null && voltages.isNotEmpty) {
        final voltage = (voltages[0] as num).toDouble() / 1000;
        // LiPo: 4.2V full, 3.3V empty
        drone.batteryPercent =
            ((voltage - 3.3) / (4.2 - 3.3)).clamp(0.0, 1.0) * 100;
      }
    }
  }

  /// Update drone system status.
  void _updateDroneSystemStatus(MAVLinkMessage msg) {
    final droneId = msg.getField('systemId').toString();
    final drone = _drones[droneId];
    if (drone != null) {
      final mode = msg.getField('flightMode');
      if (mode != null) {
        drone.flightMode = FlightMode.values[mode as int];
      }
    }
  }

  /// Attempt to reconnect with exponential backoff.
  void _attemptReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('MAVLink max reconnection attempts reached');
      return;
    }

    _reconnectAttempts++;
    final delay = Duration(
      seconds: (_reconnectAttempts * _reconnectAttempts).clamp(1, 60),
    );

    debugPrint(
      'MAVLink reconnecting in ${delay.inSeconds}s '
      '(attempt $_reconnectAttempts/$_maxReconnectAttempts)',
    );

    Future.delayed(delay, () {
      if (_serverUrl != null) {
        connect(_serverUrl!, authToken: _authToken);
      }
    });
  }

  /// Clean up resources.
  void dispose() {
    disconnect();
  }
}
