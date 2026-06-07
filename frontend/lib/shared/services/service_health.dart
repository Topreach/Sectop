import 'package:flutter/foundation.dart';

/// Severity level of a service degradation.
enum ServiceDegradation {
  /// Service is operating normally.
  none,

  /// Service is in fallback mode — basic functionality available.
  degraded,

  /// Service is unavailable — functionality completely missing.
  unavailable,

  /// Security compromise detected — critical.
  compromised,
}

/// Tracks the health status of all application services.
///
/// Provides a centralized way to:
/// - Monitor which services have failed to initialize
/// - Display a "Degraded Mode" banner to the user
/// - Log service health for telemetry
class ServiceHealthNotifier extends ChangeNotifier {
  static final ServiceHealthNotifier _instance = ServiceHealthNotifier._();
  factory ServiceHealthNotifier() => _instance;
  ServiceHealthNotifier._();

  /// Internal map of service type -> (status, reason)
  final Map<Type, _ServiceStatus> _services = {};

  /// All registered services and their current status.
  Map<Type, _ServiceStatus> get services => Map.unmodifiable(_services);

  /// Whether any service is in a degraded or worse state.
  bool get hasDegradation =>
      _services.values.any((s) => s.degradation != ServiceDegradation.none);

  /// Whether any service is completely unavailable.
  bool get hasUnavailable =>
      _services.values.any((s) => s.degradation == ServiceDegradation.unavailable);

  /// Whether a security compromise has been detected.
  bool get isCompromised =>
      _services.values.any((s) => s.degradation == ServiceDegradation.compromised);

  /// The highest severity degradation across all services.
  ServiceDegradation get worstDegradation {
    if (isCompromised) return ServiceDegradation.compromised;
    if (hasUnavailable) return ServiceDegradation.unavailable;
    if (hasDegradation) return ServiceDegradation.degraded;
    return ServiceDegradation.none;
  }

  /// Human-readable summary of all degraded services.
  String get summary {
    final degraded = _services.entries
        .where((e) => e.value.degradation != ServiceDegradation.none)
        .toList();
    if (degraded.isEmpty) return 'All services operational';
    return degraded
        .map((e) => '${_friendlyName(e.key)}: ${e.value.reason}')
        .join('\n');
  }

  /// Register a service and mark it as healthy.
  void registerService(Type serviceType) {
    _services[serviceType] = _ServiceStatus(
      degradation: ServiceDegradation.none,
      reason: 'Operational',
    );
    notifyListeners();
  }

  /// Mark a service as degraded with a reason.
  void markDegraded(Type serviceType, String reason) {
    _services[serviceType] = _ServiceStatus(
      degradation: ServiceDegradation.degraded,
      reason: reason,
    );
    debugPrint('⚠️ Service degraded: ${_friendlyName(serviceType)} — $reason');
    notifyListeners();
  }

  /// Mark a service as unavailable with a reason.
  void markUnavailable(Type serviceType, String reason) {
    _services[serviceType] = _ServiceStatus(
      degradation: ServiceDegradation.unavailable,
      reason: reason,
    );
    debugPrint('❌ Service unavailable: ${_friendlyName(serviceType)} — $reason');
    notifyListeners();
  }

  /// Mark a service as compromised (security).
  void markCompromised(Type serviceType, String reason) {
    _services[serviceType] = _ServiceStatus(
      degradation: ServiceDegradation.compromised,
      reason: reason,
    );
    debugPrint('🚨 Service compromised: ${_friendlyName(serviceType)} — $reason');
    notifyListeners();
  }

  /// Restore a service to healthy status.
  void markHealthy(Type serviceType) {
    _services[serviceType] = _ServiceStatus(
      degradation: ServiceDegradation.none,
      reason: 'Operational',
    );
    notifyListeners();
  }

  /// Get the status of a specific service.
  ServiceDegradation getStatus(Type serviceType) {
    return _services[serviceType]?.degradation ?? ServiceDegradation.unavailable;
  }

  /// Get the reason for a service's degradation.
  String? getReason(Type serviceType) {
    return _services[serviceType]?.reason;
  }

  /// Convert a service Type to a user-friendly name.
  static String _friendlyName(Type type) {
    final name = type.toString();
    // Strip generic parameters and simplify
    return name
        .replaceAll(RegExp(r'^[A-Za-z_.]+\.'), '') // Remove package prefix
        .replaceAll(RegExp(r'<.*>$'), ''); // Remove generic params
  }
}

/// Internal status record for a single service.
class _ServiceStatus {
  final ServiceDegradation degradation;
  final String reason;

  const _ServiceStatus({
    required this.degradation,
    required this.reason,
  });
}
