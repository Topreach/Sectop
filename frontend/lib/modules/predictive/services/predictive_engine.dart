import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../shared/services/backend_api.dart';

/// Thin API wrapper for predictive analytics.
///
/// All time series decomposition, LSTM anomaly detection, and Hungarian
/// algorithm resource optimization have been moved to the backend.
///
/// New ML-powered endpoints (Prophet + XGBoost) provide spatio-temporal
/// terrorist activity forecasting with 30-feature risk scoring.
class PredictiveEngine {
  static final PredictiveEngine _instance = PredictiveEngine._internal();
  factory PredictiveEngine() => _instance;
  PredictiveEngine._internal();

  final BackendApi _api = BackendApi();

  /// Initialize — no-op in thin client mode.
  Future<void> initialize() async {
    debugPrint('PredictiveEngine: Thin client mode — computation is server-side');
  }

  // ========================================================================
  // ML-Powered Endpoints (Prophet + XGBoost)
  // ========================================================================

  /// Get ML-powered forecast for a geographic area.
  ///
  /// Returns a [MLForecastResult] with time-series forecast points and
  /// hotspot predictions for the specified area.
  Future<MLForecastResult> getMLForecast({
    required double latitude,
    required double longitude,
    double radiusKm = 50.0,
    int hours = 48,
  }) async {
    try {
      final result = await _api.mlForecast(
        latitude: latitude,
        longitude: longitude,
        radiusKm: radiusKm,
        hours: hours,
      );

      final forecastPoints = <ForecastPoint>[];
      if (result['forecast'] is List) {
        for (final f in result['forecast'] as List) {
          final fMap = f as Map<String, dynamic>;
          forecastPoints.add(ForecastPoint(
            timestamp: DateTime.parse(fMap['timestamp'] as String),
            riskScore: (fMap['risk_score'] as num).toDouble(),
            alertLevel: fMap['alert_level'] as String? ?? 'Normal',
          ));
        }
      }

      final hotspots = <HotspotPrediction>[];
      if (result['hotspots'] is List) {
        for (final h in result['hotspots'] as List) {
          final hMap = h as Map<String, dynamic>;
          hotspots.add(HotspotPrediction(
            latitude: (hMap['latitude'] as num).toDouble(),
            longitude: (hMap['longitude'] as num).toDouble(),
            riskScore: (hMap['risk_score'] as num).toDouble(),
            alertLevel: hMap['alert_level'] as String? ?? 'Normal',
            peakTime: hMap['peak_time'] != null
                ? DateTime.tryParse(hMap['peak_time'] as String)
                : null,
            expectedCount24h: (hMap['expected_count_24h'] as num?)?.toDouble() ?? 0.0,
            trendDirection: hMap['trend_direction'] as String? ?? 'stable',
            contributingFactors: (hMap['contributing_factors'] as List?)
                    ?.map((e) => e.toString())
                    .toList() ??
                [],
            state: hMap['state'] as String?,
            lga: hMap['lga'] as String?,
          ));
        }
      }

      return MLForecastResult(
        latitude: (result['latitude'] as num?)?.toDouble() ?? latitude,
        longitude: (result['longitude'] as num?)?.toDouble() ?? longitude,
        forecastPoints: forecastPoints,
        hotspots: hotspots,
        source: result['source'] as String? ?? 'ml_service',
      );
    } catch (e) {
      debugPrint('PredictiveEngine: ML forecast API failed: $e');
      return MLForecastResult(
        latitude: latitude,
        longitude: longitude,
        forecastPoints: [],
        hotspots: [],
        error: e.toString(),
      );
    }
  }

  /// Detect hotspots (high-risk areas) via ML model.
  Future<HotspotResult> getHotspots({
    required double latitude,
    required double longitude,
    double radiusKm = 100.0,
  }) async {
    try {
      final result = await _api.detectHotspots(
        latitude: latitude,
        longitude: longitude,
        radiusKm: radiusKm,
      );

      final hotspots = <HotspotPrediction>[];
      if (result['hotspots'] is List) {
        for (final h in result['hotspots'] as List) {
          final hMap = h as Map<String, dynamic>;
          hotspots.add(HotspotPrediction(
            latitude: (hMap['latitude'] as num).toDouble(),
            longitude: (hMap['longitude'] as num).toDouble(),
            riskScore: (hMap['risk_score'] as num).toDouble(),
            alertLevel: hMap['alert_level'] as String? ?? 'Normal',
            peakTime: hMap['peak_time'] != null
                ? DateTime.tryParse(hMap['peak_time'] as String)
                : null,
            expectedCount24h: (hMap['expected_count_24h'] as num?)?.toDouble() ?? 0.0,
            trendDirection: hMap['trend_direction'] as String? ?? 'stable',
            contributingFactors: (hMap['contributing_factors'] as List?)
                    ?.map((e) => e.toString())
                    .toList() ??
                [],
            state: hMap['state'] as String?,
            lga: hMap['lga'] as String?,
          ));
        }
      }

      return HotspotResult(
        hotspots: hotspots,
        cached: result['cached'] as bool? ?? false,
      );
    } catch (e) {
      debugPrint('PredictiveEngine: Hotspot detection API failed: $e');
      return HotspotResult(hotspots: [], error: e.toString());
    }
  }

  /// Get forecast for all 36 Nigerian states + FCT.
  Future<AllStatesForecastResult> getAllStatesForecast() async {
    try {
      final result = await _api.forecastAllStates();

      final stateForecasts = <StateForecast>[];
      if (result['forecasts'] is List) {
        for (final f in result['forecasts'] as List) {
          final fMap = f as Map<String, dynamic>;
          stateForecasts.add(StateForecast(
            state: fMap['state'] as String? ?? 'Unknown',
            riskScore: (fMap['risk_score'] as num?)?.toDouble() ?? 0.0,
            alertLevel: fMap['alert_level'] as String? ?? 'Normal',
            trendDirection: fMap['trend_direction'] as String? ?? 'stable',
            hotspotCount: (fMap['hotspot_count'] as num?)?.toInt() ?? 0,
          ));
        }
      }

      return AllStatesForecastResult(
        forecasts: stateForecasts,
        generatedAt: result['generated_at'] != null
            ? DateTime.tryParse(result['generated_at'] as String)
            : null,
      );
    } catch (e) {
      debugPrint('PredictiveEngine: All-states forecast API failed: $e');
      return AllStatesForecastResult(forecasts: [], error: e.toString());
    }
  }

  /// Trigger model training on the ML service.
  Future<Map<String, dynamic>> triggerTraining({bool forceRetrain = false}) async {
    try {
      return await _api.triggerTraining(forceRetrain: forceRetrain);
    } catch (e) {
      debugPrint('PredictiveEngine: Training trigger failed: $e');
      return {'status': 'failed', 'error': e.toString()};
    }
  }

  /// Get current training status.
  Future<Map<String, dynamic>> getTrainingStatus() async {
    try {
      return await _api.getTrainingStatus();
    } catch (e) {
      return {'is_training': false, 'status': 'unknown'};
    }
  }

  /// Get model information (version, metrics, feature importance).
  Future<Map<String, dynamic>> getModelInfo() async {
    try {
      return await _api.getModelInfo();
    } catch (e) {
      return {'status': 'unavailable', 'error': e.toString()};
    }
  }

  // ========================================================================
  // Legacy Endpoints (preserved for backward compatibility)
  // ========================================================================

  /// Forecast danger zones via backend API (legacy — synthetic data).
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

  /// Detect anomalies in a time series via backend API (legacy).
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

  /// Optimize resource deployment via backend API (legacy).
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

// ========================================================================
// ML-Powered Data Classes
// ========================================================================

/// Result of an ML-powered forecast for a geographic area.
class MLForecastResult {
  final double latitude;
  final double longitude;
  final List<ForecastPoint> forecastPoints;
  final List<HotspotPrediction> hotspots;
  final String? error;
  final String source;

  MLForecastResult({
    required this.latitude,
    required this.longitude,
    required this.forecastPoints,
    required this.hotspots,
    this.error,
    this.source = 'ml_service',
  });
}

/// A single forecast point in a time series.
class ForecastPoint {
  final DateTime timestamp;
  final double riskScore;
  final String alertLevel;

  ForecastPoint({
    required this.timestamp,
    required this.riskScore,
    required this.alertLevel,
  });
}

/// A hotspot prediction from the ML model.
class HotspotPrediction {
  final double latitude;
  final double longitude;
  final double riskScore;
  final String alertLevel;
  final DateTime? peakTime;
  final double expectedCount24h;
  final String trendDirection;
  final List<String> contributingFactors;
  final String? state;
  final String? lga;

  HotspotPrediction({
    required this.latitude,
    required this.longitude,
    required this.riskScore,
    required this.alertLevel,
    this.peakTime,
    required this.expectedCount24h,
    required this.trendDirection,
    required this.contributingFactors,
    this.state,
    this.lga,
  });
}

/// Result of hotspot detection.
class HotspotResult {
  final List<HotspotPrediction> hotspots;
  final bool cached;
  final String? error;

  HotspotResult({required this.hotspots, this.cached = false, this.error});
}

/// Forecast for a single state.
class StateForecast {
  final String state;
  final double riskScore;
  final String alertLevel;
  final String trendDirection;
  final int hotspotCount;

  StateForecast({
    required this.state,
    required this.riskScore,
    required this.alertLevel,
    required this.trendDirection,
    required this.hotspotCount,
  });
}

/// Result of all-states forecast.
class AllStatesForecastResult {
  final List<StateForecast> forecasts;
  final DateTime? generatedAt;
  final String? error;

  AllStatesForecastResult({required this.forecasts, this.generatedAt, this.error});
}

// ========================================================================
// Legacy Data Classes (preserved for UI compatibility)
// ========================================================================

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
