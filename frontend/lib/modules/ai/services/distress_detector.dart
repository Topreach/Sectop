import 'package:flutter/foundation.dart';
import '../../../shared/services/backend_api.dart';

/// Thin API wrapper for distress detection.
///
/// All ML inference (TFLite) and rule-based analysis have been moved to the
/// backend. This class simply calls the backend API and returns results.
class DistressDetector extends ChangeNotifier {
  static final DistressDetector _instance = DistressDetector._internal();
  factory DistressDetector() => _instance;
  DistressDetector._internal();

  final BackendApi _api = BackendApi();

  bool _isAvailable = false;

  /// Whether the backend AI service is reachable.
  bool get isAvailable => _isAvailable;

  /// Load model — no-op in thin client mode. Models are server-side.
  Future<void> loadModel() async {
    _isAvailable = true;
    debugPrint('DistressDetector: Thin client mode — models are server-side');
    notifyListeners();
  }

  /// Analyze a text message for distress signals via backend API.
  Future<DistressResult> analyzeMessage(String text) async {
    try {
      final result = await _api.analyzeMessage(text);
      _isAvailable = true;

      return DistressResult(
        priority: result['priority'] as String? ?? 'low',
        confidence: (result['confidence'] as num?)?.toDouble() ?? 0.0,
        label: result['label'] as String? ?? 'normal',
        inferenceTime: (result['inferenceTimeMs'] as num?)?.toInt() ?? 0,
        method: result['method'] as String? ?? 'api',
        reasons: result['reasons'] != null
            ? List<String>.from(result['reasons'] as List)
            : <String>[],
      );
    } catch (e) {
      _isAvailable = false;
      debugPrint('DistressDetector: API call failed: $e');
      notifyListeners();

      return DistressResult(
        priority: 'low',
        confidence: 0.0,
        label: 'error',
        inferenceTime: 0,
        method: 'error',
        reasons: ['api_error: $e'],
      );
    }
  }

  /// Analyze audio — delegates to backend.
  /// Analyze audio — delegates to backend.
  Future<AudioAnalysisResult> analyzeAudio(String base64Audio) async {
    try {
      final result = await _api.analyzeAudio(base64Audio);
      return AudioAnalysisResult(
        hasDistress: result['hasDistress'] as bool? ?? false,
        confidence: (result['confidence'] as num?)?.toDouble() ?? 0.0,
        method: result['method'] as String? ?? 'api',
        threatLevel: result['threatLevel'] as String? ?? 'low',
      );
    } catch (e) {
      debugPrint('DistressDetector: Audio analysis API failed: $e');
      return AudioAnalysisResult(
        hasDistress: false,
        confidence: 0.0,
        method: 'error',
        threatLevel: 'low',
      );
    }
  }

/// Result of a distress analysis.
class DistressResult {
  final String priority;
  final double confidence;
  final String label;
  final int inferenceTime;
  final String method;
  final List<String> reasons;

  DistressResult({
    required this.priority,
    required this.confidence,
    required this.label,
    required this.inferenceTime,
    required this.method,
    required this.reasons,
  });
}

/// Result of an audio analysis.
class AudioAnalysisResult {
  final bool hasDistress;
  final double confidence;
  final String method;
  final String threatLevel;

  AudioAnalysisResult({
    required this.hasDistress,
    required this.confidence,
    required this.method,
    this.threatLevel = 'low',
  });
}
