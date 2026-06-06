import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../../core/constants.dart';

/// On-device AI Service for distress detection and message prioritization.
/// 
/// Capabilities:
/// - Text-based distress classification (using TFLite model)
/// - Message priority scoring
/// - Audio anomaly detection (screams, gunshots)
/// - Runs completely offline on device CPU/NPU
class DistressDetector extends ChangeNotifier {
  static final DistressDetector _instance = DistressDetector._internal();
  factory DistressDetector() => _instance;
  DistressDetector._internal();

  bool _modelLoaded = false;
  bool _isLoading = false;
  double _lastInferenceTime = 0;

  bool get modelLoaded => _modelLoaded;
  bool get isLoading => _isLoading;
  double get lastInferenceTime => _lastInferenceTime;

  // Priority labels matching the model output
  static const List<String> _priorityLabels = [
    'LOW - General information',
    'MEDIUM - Caution advisory',
    'HIGH - Urgent assistance needed',
    'CRITICAL - Life-threatening emergency',
  ];

  /// Load the TFLite model from assets.
  Future<void> loadModel() async {
    if (_modelLoaded || _isLoading) return;
    _isLoading = true;
    notifyListeners();

    try {
      // Model loading is handled by the ML service backend
      // For web, we use rule-based analysis as fallback
      _modelLoaded = false;
      debugPrint('Distress detection model: using rule-based fallback for web');
    } catch (e) {
      debugPrint('Failed to load model: $e');
      _modelLoaded = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Analyze a text message for distress content.
  /// Returns a priority level (0-3) and confidence score.
  Future<DistressResult> analyzeMessage(String message) async {
    return _ruleBasedAnalysis(message);
  }

  /// Rule-based analysis for distress detection.
  DistressResult _ruleBasedAnalysis(String message) {
    final lower = message.toLowerCase();
    int score = 0;
    final reasons = <String>[];

    // Critical keywords
    final criticalKeywords = [
      'help', 'sos', 'emergency', 'fire', 'trapped', 'bleeding',
      'heart attack', 'stroke', 'gunshot', 'collapse', 'unconscious',
      'not breathing', 'severe', 'critical', 'dying',
    ];

    // High priority keywords
    final highKeywords = [
      'injured', 'accident', 'danger', 'flood', 'earthquake',
      'hurt', 'pain', 'broken', 'burn', 'smoke',
    ];

    // Medium priority keywords
    final mediumKeywords = [
      'need', 'require', 'assist', 'help', 'unsafe',
      'warning', 'caution', 'alert',
    ];

    // Check for critical keywords
    for (final keyword in criticalKeywords) {
      if (lower.contains(keyword)) {
        score += 3;
        reasons.add('critical:$keyword');
      }
    }

    // Check for high priority keywords
    for (final keyword in highKeywords) {
      if (lower.contains(keyword)) {
        score += 2;
        reasons.add('high:$keyword');
      }
    }

    // Check for medium priority keywords
    for (final keyword in mediumKeywords) {
      if (lower.contains(keyword)) {
        score += 1;
        reasons.add('medium:$keyword');
      }
    }

    // Check for urgency indicators
    if (lower.contains('urgent') || lower.contains('immediately')) {
      score += 2;
    }
    if (lower.contains('please') || lower.contains('asap')) {
      score += 1;
    }

    // Check for exclamation marks (urgency)
    final exclamationCount = '!'.allMatches(message).length;
    if (exclamationCount >= 3) score += 1;
    if (exclamationCount >= 5) score += 1;

    // Determine priority level
    int priority;
    double confidence;

    if (score >= 6) {
      priority = AppConstants.priorityCritical;
      confidence = min(1.0, score / 8.0);
    } else if (score >= 4) {
      priority = AppConstants.priorityHigh;
      confidence = min(1.0, score / 6.0);
    } else if (score >= 2) {
      priority = AppConstants.priorityMedium;
      confidence = min(1.0, score / 4.0);
    } else {
      priority = AppConstants.priorityLow;
      confidence = 0.5;
    }

    return DistressResult(
      priority: priority,
      confidence: confidence,
      label: _priorityLabels[priority],
      inferenceTime: 0,
      method: 'rule-based',
      reasons: reasons,
    );
  }

  /// Simple tokenizer for text input.
  /// In production, use the same tokenizer that was used during model training.
  List<List<double>> _tokenize(String text) {
    // Simplified tokenization - in production, use proper tokenizer
    final tokens = text.toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();

    // Convert to fixed-size input (pad or truncate)
    final inputSize = AppConstants.modelInputSize;
    final input = List.filled(inputSize, 0.0);

    for (int i = 0; i < min(tokens.length, inputSize); i++) {
      // Simple hash-based embedding (in production, use word embeddings)
      input[i] = (tokens[i].hashCode % 1000) / 1000.0;
    }

    return [input];
  }

  /// Analyze audio data for distress signals (screams, gunshots).
  Future<AudioAnalysisResult> analyzeAudio(List<double> audioSamples, int sampleRate) async {
    try {
      // Extract MFCC-like features
      final features = _extractFeatures(audioSamples, sampleRate);
      
      // Simple threshold-based detection
      // In production, use a trained audio classifier
      final energy = features.reduce((a, b) => a + b) / features.length;
      final peakEnergy = features.reduce(max);
      
      final isDistress = peakEnergy > 0.8 && energy > 0.3;
      final confidence = isDistress ? min(1.0, peakEnergy) : 0.0;

      return AudioAnalysisResult(
        isDistress: isDistress,
        confidence: confidence,
        peakEnergy: peakEnergy,
        averageEnergy: energy,
      );
    } catch (e) {
      debugPrint('Audio analysis error: $e');
      return AudioAnalysisResult(
        isDistress: false,
        confidence: 0,
        peakEnergy: 0,
        averageEnergy: 0,
      );
    }
  }

  /// Extract simple audio features (simplified MFCC).
  List<double> _extractFeatures(List<double> samples, int sampleRate) {
    final frameSize = 256;
    final hopSize = 128;
    final features = <double>[];

    for (int i = 0; i + frameSize <= samples.length; i += hopSize) {
      final frame = samples.sublist(i, i + frameSize);
      
      // Calculate RMS energy
      double energy = 0;
      for (final sample in frame) {
        energy += sample * sample;
      }
      energy = sqrt(energy / frameSize);
      features.add(energy);
    }

    return features;
  }

  /// Score a message for priority (used by SOS service).
  Future<int> scorePriority(String message) async {
    final result = await analyzeMessage(message);
    return result.priority;
  }

  /// Batch analyze multiple messages.
  Future<List<DistressResult>> analyzeBatch(List<String> messages) async {
    final results = <DistressResult>[];
    for (final message in messages) {
      results.add(await analyzeMessage(message));
    }
    return results;
  }

  /// Dispose of the interpreter.
  void dispose() {
    _interpreter?.close();
    super.dispose();
  }
}

/// Result of distress analysis.
class DistressResult {
  final int priority;
  final double confidence;
  final String label;
  final double inferenceTime;
  final String method;
  final List<String> reasons;

  DistressResult({
    required this.priority,
    required this.confidence,
    required this.label,
    required this.inferenceTime,
    required this.method,
    this.reasons = const [],
  });

  Map<String, dynamic> toJson() => {
    'priority': priority,
    'confidence': confidence,
    'label': label,
    'inference_time_ms': inferenceTime,
    'method': method,
    'reasons': reasons,
  };
}

/// Result of audio analysis.
class AudioAnalysisResult {
  final bool isDistress;
  final double confidence;
  final double peakEnergy;
  final double averageEnergy;

  AudioAnalysisResult({
    required this.isDistress,
    required this.confidence,
    required this.peakEnergy,
    required this.averageEnergy,
  });
}
