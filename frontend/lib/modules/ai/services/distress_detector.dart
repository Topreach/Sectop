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
      debugPrint('DistressDetector: API call failed, using local fallback: $e');
      notifyListeners();

      // Offline fallback: lightweight keyword analysis matching backend's ruleBasedAnalysis
      return _localKeywordAnalysis(text);
    }
  }

  /// Local keyword-based fallback when backend is unreachable.
  /// Mirrors the backend's ruleBasedAnalysis() in AIController.java.
  Future<DistressResult> _localKeywordAnalysis(String text) async {
    final lower = text.toLowerCase();
    int score = 0;
    final reasons = <String>[];

    // Nigerian language keywords (Hausa, Yoruba, Igbo)
    const regionalKeywords = {
      // Hausa
      'garkuwa': 4, 'bindiga': 3, 'bom': 4, "ta'addanci": 4, 'yaki': 3,
      'fashi': 3, 'taimako': 2, 'harbi': 4, 'kashe': 4, 'makami': 3,
      'maharbi': 4, 'wuta': 3, "yan fashi": 4, "yan ta'adda": 4,
      'doki': 2, 'dare': 2, 'suna zuwa': 3, 'a gudu': 2, 'mahaukata': 3,
      'fulani': 3, 'ballal': 2, 'fijo': 4, 'nyifta': 2, 'war': 3,
      // Yoruba
      'gbigbe': 4, 'ibon': 3, 'panumopa': 3, 'iranlowo': 2, 'ikọlu': 4,
      'apaniyan': 4, 'ina': 3, 'sare': 2, 'ologun': 3, 'ipalara': 2,
      // Igbo
      'atogboro': 4, 'nkwatogbo': 4, 'egbe': 3, 'enyemaka': 2, 'ogu': 3,
      'igbu': 4, 'oku': 3, 'oso': 2, 'nwakpọrọ': 4, 'ndi ọjọọ': 3,
    };

    for (final entry in regionalKeywords.entries) {
      if (lower.contains(entry.key)) {
        score += entry.value;
        reasons.add('local_kw_${entry.key}');
      }
    }

    // English critical keywords
    const criticalKeywords = [
      'help', 'emergency', 'sos', 'fire', 'flood', 'earthquake',
      'collapse', 'trapped', 'injured', 'bleeding', 'heart attack', 'gun',
      'hostage', 'bomb', 'tsunami', 'hurricane', 'tornado', 'kidnap', 'terrorist',
    ];
    for (final kw in criticalKeywords) {
      if (lower.contains(kw)) {
        score += 3;
        reasons.add('local_kw_${kw.replaceAll(' ', '_')}');
      }
    }

    // English high keywords
    const highKeywords = [
      'danger', 'urgent', 'accident', 'medical', 'unconscious',
      'burn', 'fracture', 'stroke', 'overdose', 'drowning',
    ];
    for (final kw in highKeywords) {
      if (lower.contains(kw)) {
        score += 2;
        reasons.add('local_kw_$kw');
      }
    }

    // English medium keywords
    const mediumKeywords = ['need', 'help me', 'please', 'stuck', 'lost', 'alone', 'scared', 'dark', 'cold', 'hungry'];
    for (final kw in mediumKeywords) {
      if (lower.contains(kw)) {
        score += 1;
        reasons.add('local_kw_${kw.replaceAll(' ', '_')}');
      }
    }

    // Exclamation marks
    final exclamationCount = '!'.allMatches(text).length;
    if (exclamationCount > 0) {
      score += exclamationCount > 3 ? 3 : exclamationCount;
      reasons.add('local_exclamation_x$exclamationCount');
    }

    String priority;
    if (score >= 6) {
      priority = 'critical';
    } else if (score >= 4) {
      priority = 'high';
    } else if (score >= 2) {
      priority = 'medium';
    } else {
      priority = 'low';
    }

    final confidence = score / 10.0 > 1.0 ? 1.0 : score / 10.0;
    final label = score >= 4 ? 'distress_detected' : 'normal';

    return DistressResult(
      priority: priority,
      confidence: confidence,
      label: label,
      inferenceTime: 0,
      method: 'local_fallback',
      reasons: reasons,
    );
  }

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
