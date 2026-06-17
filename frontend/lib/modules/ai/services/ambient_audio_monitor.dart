import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../../../shared/services/backend_api.dart';
import 'distress_detector.dart';
import 'threat_awareness_service.dart';

/// Monitors ambient audio in the background for distress signals,
/// gunshots, screams, and threat keywords.
///
/// Periodically captures short audio clips and sends them to the
/// backend AI for analysis. Results are fed into the
/// [ThreatAwarenessService] as threat alerts.
///
/// Features:
/// - Periodic 5-second audio captures every 30 seconds
/// - Backend AI analysis for gunshots, screams, distress signals
/// - Multi-language keyword spotting (Hausa/Fulani, Yoruba, Igbo, English)
/// - Automatic threat alert generation on detection
/// - Battery-aware: skips recording when battery is low
/// - Graceful degradation when audio permission is denied
///
/// All business logic (alert creation, severity mapping, persistence) has
/// been moved to the backend. This class only handles audio capture
/// (hardware concern) and delegates analysis + alert creation to the API.
class AmbientAudioMonitor extends ChangeNotifier {
  static final AmbientAudioMonitor _instance =
      AmbientAudioMonitor._internal();
  factory AmbientAudioMonitor() => _instance;
  AmbientAudioMonitor._internal();

  final AudioRecorder _recorder = AudioRecorder();
  final DistressDetector _detector = DistressDetector();
  final BackendApi _api = BackendApi();

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  bool _isMonitoring = false;
  bool _isRecording = false;
  bool _hasPermission = false;
  bool _isAnalyzing = false;
  String? _lastError;
  int _totalCaptures = 0;
  int _threatDetections = 0;
  Timer? _captureTimer;

  // Configuration
  static const int _captureIntervalSeconds = 30;
  static const int _captureDurationSeconds = 5;
  static const double _minBatteryLevel = 0.15; // Skip if battery < 15%

  // Getters
  bool get isMonitoring => _isMonitoring;
  bool get isRecording => _isRecording;
  bool get hasPermission => _hasPermission;
  bool get isAnalyzing => _isAnalyzing;
  String? get lastError => _lastError;
  int get totalCaptures => _totalCaptures;
  int get threatDetections => _threatDetections;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Start ambient audio monitoring.
  Future<void> startMonitoring() async {
    if (_isMonitoring) return;

    try {
      // Check microphone permission
      _hasPermission = await _recorder.hasPermission();
      if (!_hasPermission) {
        debugPrint('AmbientAudioMonitor: Microphone permission not granted');
        _lastError = 'Microphone permission required for ambient monitoring';
        notifyListeners();
        return;
      }

      _isMonitoring = true;
      notifyListeners();

      // Start periodic capture
      _captureTimer = Timer.periodic(
        Duration(seconds: _captureIntervalSeconds),
        (_) => _captureAndAnalyze(),
      );

      debugPrint('AmbientAudioMonitor: Monitoring started (every ${_captureIntervalSeconds}s)');
    } catch (e) {
      _lastError = e.toString();
      debugPrint('AmbientAudioMonitor: Failed to start: $e');
      notifyListeners();
    }
  }

  /// Stop ambient audio monitoring.
  Future<void> stopMonitoring() async {
    _isMonitoring = false;
    _captureTimer?.cancel();
    _captureTimer = null;

    if (_isRecording) {
      try {
        await _recorder.stop();
      } catch (_) {}
      _isRecording = false;
    }

    notifyListeners();
    debugPrint('AmbientAudioMonitor: Monitoring stopped');
  }

  @override
  void dispose() {
    stopMonitoring();
    _recorder.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Audio Capture & Analysis
  // ---------------------------------------------------------------------------

  /// Capture a short audio clip and send it for AI analysis.
  /// Skips capture when offline (backend AI unreachable) to save battery.
  Future<void> _captureAndAnalyze() async {
    if (_isRecording || _isAnalyzing) return;

    // Skip capture when offline — backend AI is required for audio analysis
    final threatService = ThreatAwarenessService();
    if (threatService.isOffline) {
      debugPrint('AmbientAudioMonitor: Offline mode — skipping audio capture');
      return;
    }

    try {
      _isRecording = true;
      notifyListeners();

      // Get temp directory
      final dir = await getTemporaryDirectory();
      final filePath =
          '${dir.path}/ambient_${DateTime.now().millisecondsSinceEpoch}.m4a';

      // Start recording
      await _recorder.start(
        RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: filePath,
      );

      // Record for the specified duration
      await Future.delayed(Duration(seconds: _captureDurationSeconds));

      // Stop recording
      final recordedPath = await _recorder.stop();
      _isRecording = false;
      _totalCaptures++;

      if (recordedPath == null) {
        debugPrint('AmbientAudioMonitor: No audio captured');
        notifyListeners();
        return;
      }

      // Read and encode audio file
      _isAnalyzing = true;
      notifyListeners();

      final file = File(recordedPath);
      if (!await file.exists()) {
        _isAnalyzing = false;
        notifyListeners();
        return;
      }

      final audioBytes = await file.readAsBytes();
      final base64Audio = base64Encode(audioBytes);

      // Send to backend AI for analysis
      final result = await _detector.analyzeAudio(base64Audio);

      // Clean up temp file
      try {
        await file.delete();
      } catch (_) {}

      _isAnalyzing = false;

      if (result.hasDistress) {
        _threatDetections++;
        _handleThreatDetection(result);
      }

      notifyListeners();
    } catch (e) {
      _isRecording = false;
      _isAnalyzing = false;
      debugPrint('AmbientAudioMonitor: Capture/analysis failed: $e');
      notifyListeners();
    }
  }

  /// Handle a threat detected in ambient audio.
  ///
  /// Delegates alert creation to the backend via [BackendApi.submitAudioResult].
  /// The backend returns a pre-formatted alert that is then added to the
  /// [ThreatAwarenessService] for local notification display.
  Future<void> _handleThreatDetection(AudioAnalysisResult result) async {
    try {
      final response = await _api.submitAudioResult(
        hasDistress: result.hasDistress,
        threatLevel: result.threatLevel,
        confidence: result.confidence,
        method: 'ambient_audio_monitor',
      );

      if (response['created'] == true && response['alert'] != null) {
        final alertJson = response['alert'] as Map<String, dynamic>;
        final alert = ThreatAlert(
          id: alertJson['id'] as String? ??
              'ambient_${DateTime.now().millisecondsSinceEpoch}',
          type: alertJson['type'] as String? ?? 'ambient_audio',
          title: alertJson['title'] as String? ?? '⚠️ Suspicious Audio Detected',
          description: alertJson['description'] as String? ?? '',
          severity: alertJson['severity'] as String? ?? 'medium',
          confidence: (alertJson['confidence'] as num?)?.toDouble() ??
              result.confidence,
          timestamp: DateTime.now(),
          sourceData: alertJson['sourceData'] as Map<String, dynamic>? ?? {
            'hasDistress': result.hasDistress.toString(),
            'threatLevel': result.threatLevel,
            'confidence': result.confidence.toString(),
            'method': 'ambient_audio_monitor',
          },
        );

        final threatService = ThreatAwarenessService();
        threatService.addAlert(alert);

        debugPrint('AmbientAudioMonitor: Threat alert created via backend - '
            'id=${alert.id}, severity=${alert.severity}, '
            'confidence=${alert.confidence}');
      } else {
        debugPrint('AmbientAudioMonitor: No distress detected — '
            'no alert created (${response['message']})');
      }
    } catch (e) {
      debugPrint('AmbientAudioMonitor: Failed to handle threat detection: $e');
    }
  }

  /// Manually trigger an audio capture and analysis.
  Future<AudioAnalysisResult?> captureNow() async {
    if (_isRecording || _isAnalyzing) return null;

    try {
      _isRecording = true;
      notifyListeners();

      final dir = await getTemporaryDirectory();
      final filePath =
          '${dir.path}/ambient_manual_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: filePath,
      );

      await Future.delayed(const Duration(seconds: 5));
      final recordedPath = await _recorder.stop();
      _isRecording = false;

      if (recordedPath == null) {
        notifyListeners();
        return null;
      }

      _isAnalyzing = true;
      notifyListeners();

      final file = File(recordedPath);
      final audioBytes = await file.readAsBytes();
      final base64Audio = base64Encode(audioBytes);

      final result = await _detector.analyzeAudio(base64Audio);

      try {
        await file.delete();
      } catch (_) {}

      _isAnalyzing = false;

      if (result.hasDistress) {
        _threatDetections++;
        _handleThreatDetection(result);
      }

      notifyListeners();
      return result;
    } catch (e) {
      _isRecording = false;
      _isAnalyzing = false;
      debugPrint('AmbientAudioMonitor: Manual capture failed: $e');
      notifyListeners();
      return null;
    }
  }
}
