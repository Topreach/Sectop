import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../core/constants.dart';
import '../../../shared/services/offline_storage.dart';

/// Lightweight observability service — crash reporting and critical error
/// logging only. All trace spans, metrics collection, and adaptive sampling
/// have been moved to the backend.
class ObservabilityService extends ChangeNotifier {
  static ObservabilityService? _instance;
  static ObservabilityService get instance => _instance ??= ObservabilityService._();
  ObservabilityService._();

  final OfflineStorageService _storage = OfflineStorageService();
  bool _isInitialized = false;

  /// Whether the service has been initialized.
  bool get isInitialized => _isInitialized;

  /// Initialize the observability service.
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    debugPrint('ObservabilityService: Initialized (lightweight mode)');
  }

  /// Report a crash to the backend telemetry endpoint.
  Future<void> reportCrash({
    required String error,
    required String stackTrace,
    String? context,
  }) async {
    try {
      final token = await _storage.getSensitiveSetting(AppConstants.keyAuthToken);

      await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}${AppConstants.observabilityCrashReportEndpoint}'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'error': error,
          'stack_trace': stackTrace,
          'context': context,
          'timestamp': DateTime.now().toIso8601String(),
          'app_version': AppConstants.appVersion,
          'platform': defaultTargetPlatform.name,
        }),
      ).timeout(Duration(seconds: AppConstants.observabilityCrashTimeoutMs ~/ 1000));
    } catch (e) {
      debugPrint('ObservabilityService: Crash report failed: $e');
    }
  }

  /// Log a critical error locally (no network call).
  void logError(String message, {String? stackTrace}) {
    debugPrint('🚨 [CRITICAL] $message');
    if (stackTrace != null) {
      debugPrint(stackTrace);
    }
  }

  /// Log a warning locally (no network call).
  void logWarning(String message) {
    debugPrint('⚠️ [WARNING] $message');
  }

  /// Log an info message locally (no network call).
  void logInfo(String message) {
    debugPrint('ℹ️ [INFO] $message');
  }
}
