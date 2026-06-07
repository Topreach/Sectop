import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../shared/services/backend_api.dart';

/// Thin API wrapper for predictive analytics.
///
/// All time series decomposition, LSTM anomaly detection, and Hungarian
/// algorithm resource optimization have been moved to the backend.
class PredictiveEngine {
  static final PredictiveEngine _instance = PredictiveEngine._internal();
  factory PredictiveEngine() => _instance;
  PredictiveEngine._internal();

  final BackendApi _api = BackendApi();

  /// Initialize — no-op in thin client mode.
  Future<void> initialize() async {
    debugPrint('PredictiveEngine: Thin client mode — computation is server-side');
  }

  /// Forecast danger zones via backend API.
  Future<PredictionResult> forecastDangerZones(
    List<ZoneInfo> zones, {
    int historyHours = 72,
    int forecastHours = 6,
  }) async {
    try {
      final result = await _api.forecastDangerZones(
        zones.map((z) => z.id).toList(),
        historyHours: historyHours,
        forecastHours: forecastHours,
      );

      final forecasts = <TimeSeriesForecast>[];
      if (result['forecasts'] is List) {
        for (final f in result['forecasts'] as List) {
          final fMap = f as Map<String, dynamic>;
          final timestamps = (fMap['timestamps'] as List?)
                  ?.map((e) => DateTime.fromMillisecondsSinceEpoch((e as num).toInt()))
                  .toList() ??
              [];
          final predictedValues = (fMap['predictedValues'] as List?)
                  ?.map((e) => (e as num).toDouble())
                  .toList() ??
              [];
          final hotspots = (fMap['hotspots'] as List?)
                  ?.map((h) => Hotspot(
                        time: DateTime.fromMillisecondsSinceEpoch(
                            ((h as Map)['time'] as num).toInt()),
                        value: ((h as Map)['value'] as num).toDouble(),
                        severity: (h as Map)['severity'] as String? ?? 'medium',
                      ))
                  .toList() ??
              [];

          forecasts.add(TimeSeriesForecast(
            zoneId: fMap['zoneId'] as String? ?? '',
            timestamps: timestamps,
            predictedValues: predictedValues,
            trend: fMap['trend'] as String? ?? 'stable',
            hotspots: hotspots,
            escalationTime: fMap['escalationTime'] != null
                ? DateTime.tryParse(fMap['escalationTime'] as String)
                : null,
          ));
        }
      }

      return PredictionResult(forecasts: forecasts);
    } catch (e) {
      debugPrint('PredictiveEngine: Forecast API failed: $e');
      return PredictionResult(forecasts: [], error: e.toString());
    }
  }

  /// Detect anomalies in a time series via backend API.
  Future<List<AnomalyResult>> detectAnomalies(List<double> values) async {
    try {
      final result = await _api.detectAnomaly(values);
      final anomalies = <AnomalyResult>[];

      if (result['anomalies'] is List) {
        for (final a in result['anomalies'] as List) {
          final aMap = a as Map<String, dynamic>;
          anomalies.add(AnomalyResult(
            index: (aMap['index'] as num).toInt(),
            value: (aMap['value'] as num).toDouble(),
            zScore: (aMap['zScore'] as num).toDouble(),
            severity: aMap['severity'] as String? ?? 'warning',
          ));
        }
      }

      return anomalies;
    } catch (e) {
      debugPrint('PredictiveEngine: Anomaly detection API failed: $e');
      return [];
    }
  }

  /// Optimize resource deployment via backend API.
  Future<ResourcePlan> optimizeResourceDeployment(
    List<ZoneInfo> zones,
    List<ResponderInfo> responders,
  ) async {
    try {
      final zoneMaps = zones
          .map((z) => {
                'id': z.id,
                'latitude': z.latitude,
                'longitude': z.longitude,
                'priority': z.priority,
                'requiredSkill': z.requiredSkill,
              })
          .toList();

      final responderMaps = responders
          .map((r) => {
                'id': r.id,
                'name': r.name,
                'latitude': r.latitude,
                'longitude': r.longitude,
                'skill': r.skill,
                'availability': r.availability,
              })
          .toList();

      final result = await _api.optimizeResources(zoneMaps, responderMaps);

      final assignments = <Assignment>[];
      if (result['assignments'] is List) {
        for (final a in result['assignments'] as List) {
          final aMap = a as Map<String, dynamic>;
          assignments.add(Assignment(
            zoneId: aMap['zoneId'] as String? ?? '',
            responderId: aMap['responderId'] as String? ?? '',
            responderName: aMap['responderName'] as String? ?? '',
            cost: (aMap['cost'] as num?)?.toDouble() ?? 0.0,
            etaMinutes: (aMap['etaMinutes'] as num?)?.toInt() ?? 0,
          ));
        }
      }

      return ResourcePlan(
        assignments: assignments,
        unassignedZones: (result['unassignedZones'] as num?)?.toInt() ?? 0,
        unassignedResponders: (result['unassignedResponders'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      debugPrint('PredictiveEngine: Resource optimization API failed: $e');
      return ResourcePlan(assignments: []);
    }
  }
}

// ---------------------------------------------------------------------------
// Data classes (preserved for UI compatibility)
// ---------------------------------------------------------------------------

class ZoneInfo {
  final String id;
  final double latitude;
  final double longitude;
  final int priority;
  final String requiredSkill;

  ZoneInfo({
    required this.id,
    required this.latitude,
    required this.longitude,
    this.priority = 0,
    this.requiredSkill = 'general',
  });
}

class ResponderInfo {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String skill;
  final int availability;

  ResponderInfo({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.skill = 'general',
    this.availability = 100,
  });
}

class PredictionResult {
  final List<TimeSeriesForecast> forecasts;
  final String? error;

  PredictionResult({required this.forecasts, this.error});
}

class TimeSeriesForecast {
  final String zoneId;
  final List<DateTime> timestamps;
  final List<double> predictedValues;
  final String trend;
  final List<Hotspot> hotspots;
  final DateTime? escalationTime;

  TimeSeriesForecast({
    required this.zoneId,
    required this.timestamps,
    required this.predictedValues,
    required this.trend,
    required this.hotspots,
    this.escalationTime,
  });
}

class Hotspot {
  final DateTime time;
  final double value;
  final String severity;

  Hotspot({required this.time, required this.value, required this.severity});
}

class AnomalyResult {
  final int index;
  final double value;
  final double zScore;
  final String severity;

  AnomalyResult({
    required this.index,
    required this.value,
    required this.zScore,
    required this.severity,
  });
}

class ResourcePlan {
  final List<Assignment> assignments;
  final int unassignedZones;
  final int unassignedResponders;

  ResourcePlan({
    required this.assignments,
    this.unassignedZones = 0,
    this.unassignedResponders = 0,
  });
}

class Assignment {
  final String zoneId;
  final String responderId;
  final String responderName;
  final double cost;
  final int etaMinutes;

  Assignment({
    required this.zoneId,
    required this.responderId,
    required this.responderName,
    required this.cost,
    required this.etaMinutes,
  });
}
