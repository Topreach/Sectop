import '../../../shared/models/location.dart';

/// Drone operational status.
enum DroneStatus {
  idle,
  arming,
  airborne,
  returning,
  emergency,
  offline,
}

/// Types of payload a drone can carry.
enum PayloadType {
  loraRelay,
  camera,
  thermalSensor,
  gpsRepeater,
  meshNode,
}

/// Drone flight modes (MAVLink standard).
enum FlightMode {
  stabilize,
  loiter,
  auto,
  rtl,
  guided,
  followMe,
}

/// Action to perform at a waypoint.
enum ActionType {
  none,
  captureImage,
  startVideo,
  dropPayload,
  activateRelay,
  scanForPeople,
}

/// Damage level for building assessment.
enum DamageLevel {
  none,
  minor,
  moderate,
  severe,
  destroyed,
}

/// Type of road obstruction.
enum ObstructionType {
  debris,
  flood,
  fire,
  vehicle,
  unknown,
}

/// Represents a single drone in the fleet.
class Drone {
  final String id;
  final String name;
  DroneStatus status;
  FlightMode flightMode;
  Location location;
  double batteryPercent;
  double altitudeAGL;
  List<PayloadType> payloads;
  DateTime lastSeen;

  Drone({
    required this.id,
    required this.name,
    this.status = DroneStatus.offline,
    this.flightMode = FlightMode.loiter,
    required this.location,
    this.batteryPercent = 0,
    this.altitudeAGL = 0,
    this.payloads = const [],
    required this.lastSeen,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'status': status.index,
        'flightMode': flightMode.index,
        'location': location.toJson(),
        'batteryPercent': batteryPercent,
        'altitudeAGL': altitudeAGL,
        'payloads': payloads.map((p) => p.index).toList(),
        'lastSeen': lastSeen.toIso8601String(),
      };

  factory Drone.fromJson(Map<String, dynamic> json) => Drone(
        id: json['id'] as String,
        name: json['name'] as String,
        status: DroneStatus.values[json['status'] as int],
        flightMode: FlightMode.values[json['flightMode'] as int],
        location: Location.fromJson(json['location'] as Map<String, dynamic>),
        batteryPercent: (json['batteryPercent'] as num).toDouble(),
        altitudeAGL: (json['altitudeAGL'] as num).toDouble(),
        payloads: (json['payloads'] as List)
            .map((e) => PayloadType.values[e as int])
            .toList(),
        lastSeen: DateTime.parse(json['lastSeen'] as String),
      );
}

/// A waypoint in a drone mission.
class Waypoint {
  final String id;
  final Location location;
  final double altitude;
  final double speed;
  final Duration loiterTime;
  final ActionType action;

  const Waypoint({
    required this.id,
    required this.location,
    this.altitude = 50,
    this.speed = 10,
    this.loiterTime = Duration.zero,
    this.action = ActionType.none,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'location': location.toJson(),
        'altitude': altitude,
        'speed': speed,
        'loiterTime': loiterTime.inSeconds,
        'action': action.index,
      };
}

/// Result of an autonomous damage assessment mission.
class DamageAssessment {
  final List<DamagedBuilding> damagedBuildings;
  final List<FireHotspot> fireHotspots;
  final List<BlockedRoad> blockedRoads;
  final List<Casualty> casualtiesDetected;
  final DateTime timestamp;

  DamageAssessment({
    required this.damagedBuildings,
    required this.fireHotspots,
    required this.blockedRoads,
    required this.casualtiesDetected,
    required this.timestamp,
  });

  int get totalCasualties => casualtiesDetected.length;
  int get fireCount => fireHotspots.length;

  Map<String, dynamic> toJson() => {
        'damagedBuildings': damagedBuildings.map((b) => b.toJson()).toList(),
        'fireHotspots': fireHotspots.map((f) => f.toJson()).toList(),
        'blockedRoads': blockedRoads.map((b) => b.toJson()).toList(),
        'casualties': casualtiesDetected.map((c) => c.toJson()).toList(),
        'timestamp': timestamp.toIso8601String(),
      };
}

/// A building with assessed damage level.
class DamagedBuilding {
  final String buildingId;
  final Location location;
  final DamageLevel damageLevel;
  final double confidence;

  const DamagedBuilding({
    required this.buildingId,
    required this.location,
    required this.damageLevel,
    required this.confidence,
  });

  Map<String, dynamic> toJson() => {
        'buildingId': buildingId,
        'location': location.toJson(),
        'damageLevel': damageLevel.index,
        'confidence': confidence,
      };
}

/// A fire hotspot detected by thermal imaging.
class FireHotspot {
  final Location center;
  final double radiusMeters;
  final double intensity;
  final double temperatureCelsius;

  const FireHotspot({
    required this.center,
    required this.radiusMeters,
    required this.intensity,
    required this.temperatureCelsius,
  });

  Map<String, dynamic> toJson() => {
        'center': center.toJson(),
        'radiusMeters': radiusMeters,
        'intensity': intensity,
        'temperatureCelsius': temperatureCelsius,
      };
}

/// A blocked road detected during assessment.
class BlockedRoad {
  final String roadId;
  final Location start;
  final Location end;
  final ObstructionType type;

  const BlockedRoad({
    required this.roadId,
    required this.start,
    required this.end,
    required this.type,
  });

  Map<String, dynamic> toJson() => {
        'roadId': roadId,
        'start': start.toJson(),
        'end': end.toJson(),
        'type': type.index,
      };
}

/// A casualty detected by onboard computer vision.
class Casualty {
  final Location location;
  final String? description;
  final double confidence;
  final DateTime detectedAt;

  const Casualty({
    required this.location,
    this.description,
    required this.confidence,
    required this.detectedAt,
  });

  Map<String, dynamic> toJson() => {
        'location': location.toJson(),
        'description': description,
        'confidence': confidence,
        'detectedAt': detectedAt.toIso8601String(),
      };
}

/// A temporary mesh network formed by a drone swarm.
class SwarmMesh {
  final List<Drone> drones;
  final List<CoverageGap> coverageArea;
  final Duration estimatedUptime;
  final double averageSignalStrength;

  const SwarmMesh({
    required this.drones,
    required this.coverageArea,
    required this.estimatedUptime,
    required this.averageSignalStrength,
  });
}

/// A gap in communication coverage that needs a drone relay.
class CoverageGap {
  final Location center;
  final double radius;
  final String reason;
  final double severity;

  const CoverageGap({
    required this.center,
    required this.radius,
    this.reason = 'Coverage gap detected',
    this.severity = 1.0,
  });
}

/// MAVLink command types.
enum Command {
  requestAutopilotVersion,
  armDisarm,
  navigateTakeoff,
  navigateWaypoint,
  navigateReturnToLaunch,
  doSetMode,
  missionClearAll,
  missionItem,
  missionStart,
}

/// Parsed MAVLink message.
class MAVLinkMessage {
  final int messageId;
  final Map<String, dynamic> fields;

  const MAVLinkMessage({
    required this.messageId,
    required this.fields,
  });

  dynamic getField(String key) => fields[key];
}
