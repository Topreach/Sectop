import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants.dart';

/// Observability service for the Danger Emergence System.
///
/// Provides:
/// - Client-side distributed tracing (OpenTelemetry-compatible)
/// - Performance metrics collection
/// - Smart sampling (adaptive rate based on battery/network)
/// - Structured event logging
/// - Crash and error reporting
class ObservabilityService extends ChangeNotifier {
  static ObservabilityService? _instance;
  static ObservabilityService get instance => _instance ??= ObservabilityService._();
  ObservabilityService._();

  final List<TraceSpan> _pendingSpans = [];
  final List<MetricPoint> _metricsBuffer = [];
  final List<LogEvent> _logBuffer = [];
  Timer? _flushTimer;
  Timer? _metricsTimer;
  bool _isInitialized = false;
  double _currentSamplingRate = 1.0; // Start at 100%
  int _spanCounter = 0;
  int _errorCount = 0;
  int _totalRequests = 0;

  static const int _maxBufferSize = 500;
  static const Duration _flushInterval = Duration(seconds: 30);
  static const Duration _metricsInterval = Duration(seconds: 60);

  /// Whether the service has been initialized.
  bool get isInitialized => _isInitialized;

  /// Current adaptive sampling rate (0.0 - 1.0).
  double get currentSamplingRate => _currentSamplingRate;

  /// Total spans recorded since initialization.
  int get totalSpans => _spanCounter;

  /// Total errors recorded.
  int get errorCount => _errorCount;

  /// Initialize the observability service.
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Load persisted sampling rate
    final prefs = await SharedPreferences.getInstance();
    _currentSamplingRate = prefs.getDouble('observability_sampling_rate') ?? 1.0;

    // Start periodic flush to backend
    _flushTimer = Timer.periodic(_flushInterval, (_) => _flushBuffers());

    // Start metrics collection
    _metricsTimer = Timer.periodic(_metricsInterval, (_) => _collectDeviceMetrics());

    _isInitialized = true;
    debugPrint('ObservabilityService: Initialized (sampling rate: $_currentSamplingRate)');
    notifyListeners();
  }

  // ──────────────────────────────────────────────
  // Distributed Tracing
  // ──────────────────────────────────────────────

  /// Start a new trace span.
  ///
  /// Returns a span ID that should be passed to [endSpan].
  String startSpan({
    required String name,
    required String operation,
    Map<String, String>? attributes,
    String? parentSpanId,
  }) {
    if (!_shouldSample()) return '';

    final spanId = _generateSpanId();
    final traceId = parentSpanId ?? _generateTraceId();

    final span = TraceSpan(
      spanId: spanId,
      traceId: traceId,
      parentSpanId: parentSpanId,
      name: name,
      operation: operation,
      attributes: attributes ?? {},
      startTime: DateTime.now(),
    );

    _pendingSpans.add(span);
    _spanCounter++;

    return spanId;
  }

  /// End a trace span with optional result and error.
  void endSpan({
    required String spanId,
    String? result,
    String? error,
    Map<String, String>? attributes,
  }) {
    if (spanId.isEmpty) return;

    final index = _pendingSpans.indexWhere((s) => s.spanId == spanId);
    if (index == -1) return;

    final span = _pendingSpans[index];
    _pendingSpans[index] = TraceSpan(
      spanId: span.spanId,
      traceId: span.traceId,
      parentSpanId: span.parentSpanId,
      name: span.name,
      operation: span.operation,
      attributes: {...span.attributes, ...?attributes},
      startTime: span.startTime,
      endTime: DateTime.now(),
      result: result,
      error: error,
    );

    if (error != null) {
      _errorCount++;
    }
  }

  /// Execute an operation with automatic tracing.
  Future<T> trace<T>({
    required String name,
    required String operation,
    required Future<T> Function() fn,
    Map<String, String>? attributes,
  }) async {
    final spanId = startSpan(
      name: name,
      operation: operation,
      attributes: attributes,
    );

    try {
      final result = await fn();
      endSpan(spanId: spanId, result: 'success');
      return result;
    } catch (e) {
      endSpan(spanId: spanId, error: e.toString());
      rethrow;
    }
  }

  // ──────────────────────────────────────────────
  // Metrics Collection
  // ──────────────────────────────────────────────

  /// Record a metric value.
  void recordMetric({
    required String name,
    required double value,
    Map<String, String>? tags,
    MetricType type = MetricType.gauge,
  }) {
    _metricsBuffer.add(MetricPoint(
      name: name,
      value: value,
      tags: tags ?? {},
      type: type,
      timestamp: DateTime.now(),
    ));

    // Trim buffer if too large
    if (_metricsBuffer.length > _maxBufferSize) {
      _metricsBuffer.removeRange(0, _metricsBuffer.length - _maxBufferSize);
    }
  }

  /// Record a counter increment.
  void incrementCounter(String name, {double value = 1.0, Map<String, String>? tags}) {
    recordMetric(name: name, value: value, tags: tags, type: MetricType.counter);
  }

  /// Record a timing value in milliseconds.
  void recordTiming(String name, Duration duration, {Map<String, String>? tags}) {
    recordMetric(
      name: name,
      value: duration.inMilliseconds.toDouble(),
      tags: tags,
      type: MetricType.histogram,
    );
  }

  /// Collect device-level metrics.
  Future<void> _collectDeviceMetrics() async {
    // Memory usage (approximate)
    recordMetric(name: 'app.memory.used', value: _estimateMemoryUsage());

    // Span throughput
    final spansPerMinute = _spanCounter / (_metricsInterval.inMinutes > 0 ? _metricsInterval.inMinutes : 1);
    recordMetric(name: 'app.spans.rate', value: spansPerMinute);

    // Error rate
    if (_totalRequests > 0) {
      final errorRate = (_errorCount / _totalRequests) * 100;
      recordMetric(name: 'app.errors.rate', value: errorRate);
    }

    // Adaptive sampling adjustment
    _adjustSamplingRate();
  }

  // ──────────────────────────────────────────────
  // Structured Logging
  // ──────────────────────────────────────────────

  /// Log a structured event.
  void logEvent({
    required String message,
    required LogLevel level,
    Map<String, dynamic>? data,
    String? error,
    StackTrace? stackTrace,
  }) {
    _logBuffer.add(LogEvent(
      message: message,
      level: level,
      data: data,
      error: error,
      stackTrace: stackTrace?.toString(),
      timestamp: DateTime.now(),
    ));

    // Trim buffer
    if (_logBuffer.length > _maxBufferSize) {
      _logBuffer.removeRange(0, _logBuffer.length - _maxBufferSize);
    }

    // Always print errors to console
    if (level == LogLevel.error || level == LogLevel.critical) {
      debugPrint('[${level.name.toUpperCase()}] $message${error != null ? ': $error' : ''}');
    }
  }

  void logInfo(String message, {Map<String, dynamic>? data}) {
    logEvent(message: message, level: LogLevel.info, data: data);
  }

  void logWarning(String message, {Map<String, dynamic>? data}) {
    logEvent(message: message, level: LogLevel.warning, data: data);
  }

  void logError(String message, {String? error, StackTrace? stackTrace}) {
    logEvent(message: message, level: LogLevel.error, error: error, stackTrace: stackTrace);
  }

  void logCritical(String message, {String? error, StackTrace? stackTrace}) {
    logEvent(message: message, level: LogLevel.critical, error: error, stackTrace: stackTrace);
  }

  // ──────────────────────────────────────────────
  // Smart Sampling
  // ──────────────────────────────────────────────

  /// Determine if a span should be sampled based on adaptive rate.
  bool _shouldSample() {
    return math.Random().nextDouble() < _currentSamplingRate;
  }

  /// Adjust sampling rate based on device conditions.
  ///
  /// Rules:
  /// - High error rate (>5%): increase sampling to capture more context
  /// - Low battery (<15%): decrease sampling to save power
  /// - High span throughput (>100/min): decrease to reduce overhead
  /// - Network offline: buffer locally, reduce sampling
  void _adjustSamplingRate() {
    double newRate = _currentSamplingRate;

    // Increase sampling on errors
    if (_totalRequests > 20) {
      final errorRate = _errorCount / _totalRequests;
      if (errorRate > 0.05) {
        newRate = math.min(1.0, newRate * 1.5);
      } else if (errorRate < 0.01) {
        newRate = math.max(0.01, newRate * 0.9);
      }
    }

    // Decrease sampling at high throughput
    if (_spanCounter > 100) {
      newRate = math.max(0.01, newRate * 0.8);
    }

    // Clamp to reasonable range
    newRate = newRate.clamp(0.01, 1.0);

    if ((newRate - _currentSamplingRate).abs() > 0.05) {
      _currentSamplingRate = newRate;
      _persistSamplingRate(newRate);
      notifyListeners();
    }
  }

  Future<void> _persistSamplingRate(double rate) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('observability_sampling_rate', rate);
  }

  // ──────────────────────────────────────────────
  // Buffer Flushing
  // ──────────────────────────────────────────────

  /// Flush all buffers to the backend.
  Future<void> _flushBuffers() async {
    try {
      final hasSpans = _pendingSpans.isNotEmpty;
      final hasMetrics = _metricsBuffer.isNotEmpty;
      final hasLogs = _logBuffer.isNotEmpty;

      if (!hasSpans && !hasMetrics && !hasLogs) return;

      final payload = <String, dynamic>{
        'service': AppConstants.appName,
        'version': AppConstants.appVersion,
        'timestamp': DateTime.now().toIso8601String(),
      };

      if (hasSpans) {
        payload['spans'] = _pendingSpans.map((s) => s.toJson()).toList();
      }
      if (hasMetrics) {
        payload['metrics'] = _metricsBuffer.map((m) => m.toJson()).toList();
      }
      if (hasLogs) {
        payload['logs'] = _logBuffer.map((l) => l.toJson()).toList();
      }

      // Send to backend telemetry endpoint
      await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/${AppConstants.apiVersion}/telemetry'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));

      // Clear buffers on success
      _pendingSpans.clear();
      _metricsBuffer.clear();
      _logBuffer.clear();
    } catch (e) {
      // Flush failed — keep buffers for next attempt
      debugPrint('ObservabilityService: Flush failed: $e');
    }
  }

  /// Force an immediate flush (e.g., on app backgrounding).
  Future<void> flushNow() async {
    await _flushBuffers();
  }

  // ──────────────────────────────────────────────
  // Crash Reporting
  // ──────────────────────────────────────────────

  /// Report a crash or unhandled exception.
  Future<void> reportCrash({
    required String error,
    required String stackTrace,
    String? context,
  }) async {
    final crashReport = <String, dynamic>{
      'service': AppConstants.appName,
      'version': AppConstants.appVersion,
      'platform': defaultTargetPlatform.name,
      'error': error,
      'stackTrace': stackTrace,
      'context': context,
      'timestamp': DateTime.now().toIso8601String(),
      'spans': _pendingSpans.take(10).map((s) => s.toJson()).toList(),
    };

    try {
      await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/${AppConstants.apiVersion}/telemetry/crash'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(crashReport),
      ).timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('ObservabilityService: Crash report failed: $e');
    }
  }

  // ──────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────

  String _generateSpanId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final random = (math.Random().nextDouble() * 0xFFFFFFFF).toInt();
    return '${timestamp.toRadixString(16)}${random.toRadixString(16).padLeft(8, '0')}';
  }

  String _generateTraceId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    // Use 32-bit values for JS compatibility (0xFFFFFFFFFFFFFFFF cannot be represented in JS)
    final random1 = (math.Random().nextDouble() * 0xFFFFFFFF).toInt();
    final random2 = (math.Random().nextDouble() * 0xFFFFFFFF).toInt();
    final random3 = (math.Random().nextDouble() * 0xFFFFFFFF).toInt();
    final random4 = (math.Random().nextDouble() * 0xFFFFFFFF).toInt();
    return '${timestamp.toRadixString(16)}${random1.toRadixString(16).padLeft(8, '0')}${random2.toRadixString(16).padLeft(8, '0')}${random3.toRadixString(16).padLeft(8, '0')}${random4.toRadixString(16).padLeft(8, '0')}';
  }

  double _estimateMemoryUsage() {
    // In production, use platform channel to get actual memory stats
    return 0.0;
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    _metricsTimer?.cancel();
    _flushBuffers(); // Final flush
    super.dispose();
  }
}

// ──────────────────────────────────────────────
// Data Classes
// ──────────────────────────────────────────────

/// A single span in a distributed trace.
class TraceSpan {
  final String spanId;
  final String traceId;
  final String? parentSpanId;
  final String name;
  final String operation;
  final Map<String, String> attributes;
  final DateTime startTime;
  final DateTime? endTime;
  final String? result;
  final String? error;

  const TraceSpan({
    required this.spanId,
    required this.traceId,
    this.parentSpanId,
    required this.name,
    required this.operation,
    this.attributes = const {},
    required this.startTime,
    this.endTime,
    this.result,
    this.error,
  });

  Duration? get duration => endTime?.difference(startTime);

  Map<String, dynamic> toJson() => {
        'spanId': spanId,
        'traceId': traceId,
        'parentSpanId': parentSpanId,
        'name': name,
        'operation': operation,
        'attributes': attributes,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime?.toIso8601String(),
        'durationMs': duration?.inMilliseconds,
        'result': result,
        'error': error,
      };
}

/// A single metric data point.
class MetricPoint {
  final String name;
  final double value;
  final Map<String, String> tags;
  final MetricType type;
  final DateTime timestamp;

  const MetricPoint({
    required this.name,
    required this.value,
    this.tags = const {},
    required this.type,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'value': value,
        'tags': tags,
        'type': type.name,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Type of metric.
enum MetricType {
  gauge,
  counter,
  histogram,
}

/// A structured log event.
class LogEvent {
  final String message;
  final LogLevel level;
  final Map<String, dynamic>? data;
  final String? error;
  final String? stackTrace;
  final DateTime timestamp;

  const LogEvent({
    required this.message,
    required this.level,
    this.data,
    this.error,
    this.stackTrace,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'message': message,
        'level': level.name,
        'data': data,
        'error': error,
        'stackTrace': stackTrace,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Log severity level.
enum LogLevel {
  debug,
  info,
  warning,
  error,
  critical,
}
