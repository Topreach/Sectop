import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../core/constants.dart';
import '../../../core/themes.dart';
import '../../../core/routes.dart';
import '../../../shared/services/offline_storage.dart';
import '../../ai/services/distress_detector.dart';
import '../services/mesh_threat_relay.dart';

/// Screen that monitors nearby walkie-talkie audio via the phone microphone.
///
/// Terrorists and bandits often use walkie-talkies to communicate. This screen
/// records short audio bursts and sends them to the backend AI for analysis.
/// The backend scans for threat keywords in Hausa/Fulani, Yoruba, Igbo, and
/// English — the languages commonly used by terrorist/bandit groups in Nigeria.
class WalkieTalkieMonitorScreen extends StatefulWidget {
  const WalkieTalkieMonitorScreen({Key? key}) : super(key: key);

  @override
  State<WalkieTalkieMonitorScreen> createState() =>
      _WalkieTalkieMonitorScreenState();
}
class _WalkieTalkieMonitorScreenState
    extends State<WalkieTalkieMonitorScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  final DistressDetector _detector = DistressDetector();
  final MeshThreatRelayService _threatRelay = MeshThreatRelayService();

  // WebSocket/STOMP for fast audio analysis
  WebSocketChannel? _wsChannel;
  bool _isWsConnected = false;
  StreamSubscription<dynamic>? _wsSubscription;

  bool _isMonitoring = false;
  bool _isAnalyzing = false;
  bool _hasPermission = false;

  // Analysis results history
  final List<WalkieTalkieResult> _results = [];
  Timer? _monitorTimer;
  Timer? _amplitudeTimer;

  // Amplitude for visualizer
  double _currentAmplitude = 0;

  // Threat stats
  int _totalScans = 0;
  int _threatsDetected = 0;

  // Remote threat alerts from mesh peers
  int _remoteThreatCount = 0;

  @override
  void initState() {
    super.initState();
    _checkPermission();
    _connectWebSocket();
    // Start listening for remote threat alerts from mesh peers
    _threatRelay.startListening();
    _threatRelay.onRemoteThreatReceived = (alert) {
      if (mounted) {
        setState(() => _remoteThreatCount = _threatRelay.incomingThreats.length);
        _showRemoteThreatAlert(alert);
      }
    };
  }

  /// Connect to WebSocket for STOMP SEND fast path.
  Future<void> _connectWebSocket() async {
    try {
      final storage = OfflineStorageService();
      final token = await storage.getSensitiveSetting(AppConstants.keyAuthToken);
      if (token == null || token.isEmpty) return;

      final wsUrl = AppConstants.wsBaseUrl;
      final wsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _wsChannel = wsChannel;
      _isWsConnected = true;

      // Send STOMP CONNECT frame
      _sendStompFrame('CONNECT', {
        'accept-version': '1.2',
        'host': 'localhost',
        'Authorization': 'Bearer $token',
      });

      // Subscribe to user's personal queue for audio analysis results
      _sendStompFrame('SUBSCRIBE', {
        'id': 'audio-result',
        'destination': '/user/queue/analyze/audio/result',
      });

      // Listen for incoming STOMP frames
      _wsSubscription = wsChannel.stream.listen((data) {
        _handleStompFrame(data as String);
      });

      debugPrint('WalkieTalkieMonitor: WebSocket connected for STOMP fast path');
    } catch (e) {
      debugPrint('WalkieTalkieMonitor: WebSocket connection failed: $e');
      _isWsConnected = false;
    }
  }

  /// Handle incoming STOMP frames from the server.
  void _handleStompFrame(String frame) {
    if (frame.startsWith('MESSAGE')) {
      // Extract the body after the headers
      // STOMP protocol uses \r\n line endings
      final parts = frame.split('\r\n\r\n');
      if (parts.length >= 2) {
        final body = parts.sublist(1).join('\r\n\r\n').trim().replaceAll('\0', '');
        if (body.isNotEmpty) {
          try {
            final result = json.decode(body) as Map<String, dynamic>;
            if (result['success'] == true && result['data'] != null) {
              _processAnalysisResult(result['data'] as Map<String, dynamic>);
            }
          } catch (e) {
            debugPrint('WalkieTalkieMonitor: Failed to parse STOMP message: $e');
          }
        }
      }
    }
  }

  /// Process an audio analysis result received via STOMP.
  void _processAnalysisResult(Map<String, dynamic> data) {
    if (!mounted) return;

    final hasDistress = data['hasDistress'] as bool? ?? false;
    final confidence = (data['confidence'] as num?)?.toDouble() ?? 0.0;
    final method = data['method'] as String? ?? 'stomp';
    final threatLevel = data['threatLevel'] as String?;

    final timestamp = DateTime.now();
    final walkieResult = WalkieTalkieResult(
      timestamp: timestamp,
      isThreat: hasDistress,
      confidence: confidence,
      method: method,
    );

    setState(() {
      _totalScans++;
      if (hasDistress) _threatsDetected++;
      _results.insert(0, walkieResult);
      _isAnalyzing = false;

      // Keep only last 50 results
      if (_results.length > 50) {
        _results.removeRange(50, _results.length);
      }
    });

    // If threat detected, show alert and broadcast to mesh peers
    if (hasDistress && mounted) {
      final audioResult = AudioAnalysisResult(
        hasDistress: hasDistress,
        confidence: confidence,
        method: method,
        threatLevel: threatLevel ?? 'low',
      );
      _showThreatAlert(audioResult);
      _broadcastThreatToMesh(audioResult);
    }
  }

  /// Send a raw STOMP frame over the WebSocket.
  /// Uses \r\n line endings per the STOMP protocol specification.
  void _sendStompFrame(String command, Map<String, String> headers, {String? body}) {
    if (_wsChannel == null) return;
    try {
      final buffer = StringBuffer();
      buffer.write(command);
      buffer.write('\r\n');
      headers.forEach((key, value) {
        buffer.write('$key:$value');
        buffer.write('\r\n');
      });
      buffer.write('\r\n');
      if (body != null && body.isNotEmpty) {
        buffer.write(body);
      }
      buffer.write('\0'); // STOMP null frame terminator
      _wsChannel!.sink.add(buffer.toString());
    } catch (e) {
      debugPrint('WalkieTalkieMonitor: Failed to send STOMP frame: $e');
    }
  }

  /// Send audio data via STOMP SEND for instant analysis.
  void _sendAudioViaStomp(Map<String, dynamic> audioData) {
    if (_wsChannel == null || !_isWsConnected) {
      debugPrint('WalkieTalkieMonitor: WebSocket not connected, using HTTP');
      return;
    }
    try {
      final body = json.encode(audioData);
      _sendStompFrame('SEND', {
        'destination': '/app/analyze/audio',
        'content-type': 'application/json',
      }, body: body);
      debugPrint('WalkieTalkieMonitor: Audio sent via STOMP SEND');
    } catch (e) {
      debugPrint('WalkieTalkieMonitor: STOMP SEND failed: $e');
    }
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    _wsChannel?.sink.close();
    _stopMonitoring();
    _recorder.dispose();
    _monitorTimer?.cancel();
    _amplitudeTimer?.cancel();
    _threatRelay.stopListening();
    super.dispose();
  }

  Future<void> _checkPermission() async {
    final hasPermission = await _recorder.hasPermission();
    if (mounted) {
      setState(() => _hasPermission = hasPermission);
    }
  }

  Future<void> _requestPermission() async {
    // The record package handles permission request internally
    final hasPermission = await _recorder.hasPermission();
    if (mounted) {
      setState(() => _hasPermission = hasPermission);
      if (hasPermission) {
        _startMonitoring();
      }
    }
  }

  Future<void> _startMonitoring() async {
    if (!_hasPermission) {
      await _requestPermission();
      return;
    }

    setState(() => _isMonitoring = true);

    // Start amplitude monitoring for the visualizer
    _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      // Simulate amplitude changes based on recording state
      // In production, use actual amplitude from the recorder
      setState(() {
        _currentAmplitude = _isMonitoring
            ? (0.2 + (DateTime.now().millisecondsSinceEpoch % 100) / 100.0 * 0.6)
            : 0;
      });
    });

    // Record 5-second audio clips every 8 seconds (with 3s overlap/gap)
    _monitorTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (_isMonitoring) {
        _captureAndAnalyze();
      }
    });

    // Immediate first capture
    _captureAndAnalyze();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Walkie-Talkie monitoring started'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _stopMonitoring() async {
    _monitorTimer?.cancel();
    _amplitudeTimer?.cancel();
    setState(() {
      _isMonitoring = false;
      _currentAmplitude = 0;
    });
  }

  Future<void> _captureAndAnalyze() async {
    if (!_hasPermission) return;

    setState(() => _isAnalyzing = true);

    try {
      // Get temp directory
      final dir = await getTemporaryDirectory();
      final filePath =
          '${dir.path}/walkie_talkie_${DateTime.now().millisecondsSinceEpoch}.m4a';

      // Record 5 seconds of audio
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

      if (recordedPath == null || !mounted) {
        setState(() => _isAnalyzing = false);
        return;
      }

      // Read audio file and encode to base64
      final file = File(recordedPath);
      final audioBytes = await file.readAsBytes();
      final base64Audio = base64Encode(audioBytes);

      final audioData = {
        'userId': '',
        'audio': base64Audio,
        'transcript': null,
      };

      // STEP 1: Send via STOMP SEND over existing WebSocket (FASTEST PATH - ~1ms)
      _sendAudioViaStomp(audioData);

      // STEP 2: Fire HTTP POST in the background as reliability fallback
      // The STOMP result will arrive via WebSocket subscription and update the UI
      unawaited(_analyzeViaHttp(base64Audio, file));

      // Clean up temp file
      try {
        await file.delete();
      } catch (_) {}
    } catch (e) {
      debugPrint('WalkieTalkieMonitor: Capture failed: $e');
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  /// Fallback: analyze audio via HTTP POST with offline queue.
  Future<void> _analyzeViaHttp(String base64Audio, File file) async {
    try {
      final result = await _detector.analyzeAudio(base64Audio);

      if (!mounted) return;

      final isThreat = result.hasDistress;
      final walkieResult = WalkieTalkieResult(
        timestamp: DateTime.now(),
        isThreat: isThreat,
        confidence: result.confidence,
        method: result.method,
      );

      setState(() {
        _totalScans++;
        if (isThreat) _threatsDetected++;
        _results.insert(0, walkieResult);
        _isAnalyzing = false;

        // Keep only last 50 results
        if (_results.length > 50) {
          _results.removeRange(50, _results.length);
        }
      });

      // If threat detected, show alert and broadcast to mesh peers
      if (isThreat && mounted) {
        _showThreatAlert(result);
        _broadcastThreatToMesh(result);
      }
    } catch (e) {
      final errorStr = e.toString();

      // Offline fallback — save audio analysis request locally when server is unreachable
      if (errorStr.contains('SocketException') ||
          errorStr.contains('Connection refused') ||
          errorStr.contains('HandshakeException') ||
          errorStr.contains('503') ||
          errorStr.contains('Circuit breaker')) {
        try {
          final storage = OfflineStorageService();
          await storage.insert('messages', {
            'id': 'audio_scan_${DateTime.now().millisecondsSinceEpoch}',
            'sender_id': '',
            'content': '[AUDIO_SCAN] Walkie-talkie audio captured but could not be analyzed (offline)',
            'message_type': 'audio_scan',
            'priority': 1,
            'status': 'pending',
            'sync_state': 'offline',
            'created_at': DateTime.now().millisecondsSinceEpoch,
          });
          debugPrint('WalkieTalkieMonitor: Audio scan saved offline for later analysis');
        } catch (saveError) {
          debugPrint('WalkieTalkieMonitor: Failed to save audio scan offline: $saveError');
        }
      } else {
        debugPrint('WalkieTalkieMonitor: HTTP fallback failed: $e');
      }

      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  void _showThreatAlert(AudioAnalysisResult result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Walkie-Talkie Threat Detected!',
                style: TextStyle(color: Colors.red, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Suspicious audio detected from nearby walkie-talkie communication.',
              style: TextStyle(color: Colors.grey[700]),
            ),
            const SizedBox(height: 12),
            _buildAlertRow('Confidence',
                '${(result.confidence * 100).toStringAsFixed(0)}%'),
            _buildAlertRow('Method', result.method),
            _buildAlertRow('Time', DateTime.now().toString().substring(11, 19)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Continue Monitoring'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // Navigate to incident report
              Navigator.of(context).pushNamed(AppRoutes.incidentReport);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('Report Incident'),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text('$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          Text(value, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  /// Broadcast a detected threat to all nearby mesh peers.
  void _broadcastThreatToMesh(AudioAnalysisResult result) {
    _threatRelay.broadcastThreat(
      confidence: result.confidence,
      method: result.method,
      threatLevel: result.threatLevel ?? 'high',
    );
  }

  /// Show alert dialog for a threat received from a remote mesh peer.
  void _showRemoteThreatAlert(RemoteThreatAlert alert) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.group, color: Colors.orange, size: 28),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Remote Threat Alert',
                style: TextStyle(color: Colors.orange, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A nearby device detected a walkie-talkie threat.',
              style: TextStyle(color: Colors.grey[700]),
            ),
            const SizedBox(height: 12),
            _buildAlertRow('Device', alert.deviceId.length > 12
                ? '...${alert.deviceId.substring(alert.deviceId.length - 12)}'
                : alert.deviceId),
            _buildAlertRow('Confidence',
                '${(alert.confidence * 100).toStringAsFixed(0)}%'),
            _buildAlertRow('Level', alert.threatLevel.toUpperCase()),
            _buildAlertRow('Method', alert.method),
            _buildAlertRow('Received', alert.timeAgo),
            if (alert.latitude != null && alert.longitude != null)
              _buildAlertRow(
                  'Location', '${alert.latitude!.toStringAsFixed(4)}, ${alert.longitude!.toStringAsFixed(4)}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Dismiss'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed(AppRoutes.incidentReport);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: Text('Report Incident'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Walkie-Talkie Monitor'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          if (_isMonitoring)
            IconButton(
              icon: const Icon(Icons.stop),
              onPressed: _stopMonitoring,
              tooltip: 'Stop monitoring',
            ),
        ],
      ),
      body: Column(
        children: [
          // Status & Controls
          _buildStatusHeader(),

          // Amplitude visualizer
          _buildAmplitudeVisualizer(),

          // Stats bar
          _buildStatsBar(),

          // Results list
          Expanded(
            child: _results.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _results.length,
                    itemBuilder: (context, index) =>
                        _buildResultCard(_results[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: _isMonitoring
          ? Colors.red.withOpacity(0.05)
          : Colors.grey.withOpacity(0.05),
      child: Column(
        children: [
          // Status indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isMonitoring ? Colors.red : Colors.grey,
                  boxShadow: _isMonitoring
                      ? [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.5),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ]
                      : [],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _isMonitoring
                    ? 'Monitoring walkie-talkie frequencies...'
                    : 'Monitoring stopped',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _isMonitoring ? Colors.red[700] : Colors.grey[600],
                ),
              ),
              if (_isAnalyzing) ...[
                const SizedBox(width: 12),
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),

          // Start/Stop button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isMonitoring ? _stopMonitoring : _startMonitoring,
              icon: Icon(
                _isMonitoring ? Icons.stop : Icons.mic,
                color: Colors.white,
              ),
              label: Text(
                _isMonitoring ? 'Stop Monitoring' : 'Start Monitoring',
                style: const TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _isMonitoring ? Colors.grey : Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          if (!_hasPermission && !_isMonitoring) ...[
            const SizedBox(height: 8),
            Text(
              'Microphone permission required',
              style: TextStyle(color: Colors.red[400], fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAmplitudeVisualizer() {
    return Container(
      height: 60,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: CustomPaint(
        painter: _AmplitudePainter(
          amplitude: _currentAmplitude,
          isActive: _isMonitoring,
          threatLevel: _threatsDetected > 0
              ? (_threatsDetected / (_totalScans > 0 ? _totalScans : 1))
              : 0,
        ),
        size: const Size(double.infinity, 60),
      ),
    );
  }

  Widget _buildStatsBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        children: [
          Row(
            children: [
              _buildStatChip(Icons.wifi_tethering, 'Scans', '$_totalScans',
                  Colors.blue),
              const SizedBox(width: 8),
              _buildStatChip(
                Icons.warning_amber_rounded,
                'Threats',
                '$_threatsDetected',
                _threatsDetected > 0 ? Colors.red : Colors.green,
              ),
              const Spacer(),
              if (_totalScans > 0)
                Text(
                  '${((_threatsDetected / _totalScans) * 100).toStringAsFixed(0)}% threat rate',
                  style: TextStyle(
                    fontSize: 11,
                    color: _threatsDetected > 0 ? Colors.red[400] : Colors.grey[500],
                  ),
                ),
            ],
          ),
          // Remote threat alerts from mesh peers
          if (_remoteThreatCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  _buildStatChip(
                    Icons.group,
                    'Remote Threats',
                    '$_remoteThreatCount',
                    Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'from mesh network',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.orange[400],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatChip(
      IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            '$label: $value',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.radio,
            size: 64,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            'No audio captured yet',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[500],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap "Start Monitoring" to listen for\nnearby walkie-talkie communications',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[400],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(WalkieTalkieResult result) {
    final isThreat = result.isThreat;
    final color = isThreat ? Colors.red : Colors.green;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: ListTile(
        dense: true,
        leading: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isThreat ? Icons.warning_amber_rounded : Icons.check_circle_outline,
            color: color,
            size: 20,
          ),
        ),
        title: Text(
          isThreat ? '⚠ Threat Detected' : '✅ No Threat',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: color,
          ),
        ),
        subtitle: Text(
          '${result.timestamp.toString().substring(11, 19)} · '
          '${(result.confidence * 100).toStringAsFixed(0)}% confidence · '
          '${result.method}',
          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
        ),
        trailing: isThreat
            ? Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'ALERT',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Colors.red[700],
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

/// Data model for a single walkie-talkie scan result.
class WalkieTalkieResult {
  final DateTime timestamp;
  final bool isThreat;
  final double confidence;
  final String method;

  WalkieTalkieResult({
    required this.timestamp,
    required this.isThreat,
    required this.confidence,
    required this.method,
  });
}

/// Custom painter for the amplitude visualizer.
class _AmplitudePainter extends CustomPainter {
  final double amplitude;
  final bool isActive;
  final double threatLevel;

  _AmplitudePainter({
    required this.amplitude,
    required this.isActive,
    required this.threatLevel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!isActive) return;

    final paint = Paint()
      ..color = threatLevel > 0.3
          ? Colors.red.withOpacity(0.6)
          : Colors.green.withOpacity(0.6)
      ..strokeWidth = 2;

    final centerY = size.height / 2;
    final barCount = 40;
    final barWidth = size.width / barCount;

    for (int i = 0; i < barCount; i++) {
      final barAmplitude =
          amplitude * (0.3 + (i % 7) / 7.0 * 0.7) * size.height * 0.4;
      final x = i * barWidth + barWidth / 2;

      paint.strokeWidth = barWidth * 0.6;
      paint.color = threatLevel > 0.3
          ? Color.lerp(
              Colors.orange,
              Colors.red,
              (threatLevel - 0.3) / 0.7,
            )!.withOpacity(0.6)
          : Color.lerp(
              Colors.green,
              Colors.amber,
              amplitude,
            )!.withOpacity(0.6);

      canvas.drawLine(
        Offset(x, centerY - barAmplitude),
        Offset(x, centerY + barAmplitude),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AmplitudePainter oldDelegate) {
    return oldDelegate.amplitude != amplitude ||
        oldDelegate.isActive != isActive ||
        oldDelegate.threatLevel != threatLevel;
  }
}
