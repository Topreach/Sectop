import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../core/constants.dart';
import '../../../core/themes.dart';
import '../../../shared/services/backend_api.dart';
import '../../../shared/services/evidence_service.dart';
import '../../../shared/services/offline_storage.dart';
import '../../../shared/widgets/nigeria_location_picker.dart';

/// Screen to submit an anonymous tip-off / intelligence report.
class TipOffScreen extends StatefulWidget {
  const TipOffScreen({Key? key}) : super(key: key);

  @override
  State<TipOffScreen> createState() => _TipOffScreenState();
}

class _TipOffScreenState extends State<TipOffScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _targetController = TextEditingController();
  final _suspectController = TextEditingController();

  String _tipType = 'suspicious_person';
  bool _isAnonymous = true;
  bool _isSubmitting = false;

  // WebSocket/STOMP for fast tip-off submission
  WebSocketChannel? _wsChannel;
  bool _isWsConnected = false;
  StreamSubscription<dynamic>? _wsSubscription;

  // Location state (from NigeriaLocationPicker)
  double? _latitude;
  double? _longitude;
  String? _locationName;

  // Evidence capture state
  final EvidenceService _evidenceService = EvidenceService();
  final ImagePicker _picker = ImagePicker();
  List<EvidenceFile> _capturedEvidence = [];
  bool _isCapturing = false;

  // ---------------------------------------------------------------------------
  // Evidence Capture Methods
  // ---------------------------------------------------------------------------

  Future<void> _capturePhoto() async {
    setState(() => _isCapturing = true);
    try {
      final evidence = await _evidenceService.capturePhoto();
      if (evidence != null) {
        setState(() => _capturedEvidence.add(evidence));
      }
    } finally {
      setState(() => _isCapturing = false);
    }
  }

  Future<void> _captureVideo() async {
    setState(() => _isCapturing = true);
    try {
      final evidence = await _evidenceService.captureVideo();
      if (evidence != null) {
        setState(() => _capturedEvidence.add(evidence));
      }
    } finally {
      setState(() => _isCapturing = false);
    }
  }

  Future<void> _recordAudio() async {
    setState(() => _isCapturing = true);
    try {
      final evidence = await _evidenceService.recordAudio(durationSeconds: 30);
      if (evidence != null) {
        setState(() => _capturedEvidence.add(evidence));
      }
    } finally {
      setState(() => _isCapturing = false);
    }
  }

  void _removeEvidence(int index) {
    setState(() => _capturedEvidence.removeAt(index));
  }

  @override
  void initState() {
    super.initState();
    _connectWebSocket();
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

      debugPrint('TipOffScreen: WebSocket connected for STOMP fast path');
    } catch (e) {
      debugPrint('TipOffScreen: WebSocket connection failed: $e');
      _isWsConnected = false;
    }
  }

  /// Send a raw STOMP frame over the WebSocket.
  void _sendStompFrame(String command, Map<String, String> headers, {String? body}) {
    if (_wsChannel == null) return;
    try {
      final buffer = StringBuffer();
      buffer.writeln(command);
      headers.forEach((key, value) {
        buffer.writeln('$key:$value');
      });
      buffer.writeln();
      if (body != null && body.isNotEmpty) {
        buffer.write(body);
      }
      buffer.write('\0'); // STOMP null frame terminator
      _wsChannel!.sink.add(buffer.toString());
    } catch (e) {
      debugPrint('TipOffScreen: Failed to send STOMP frame: $e');
    }
  }

  /// Send tip-off via STOMP SEND for instant delivery.
  void _sendTipViaStomp(Map<String, dynamic> tipData) {
    if (_wsChannel == null || !_isWsConnected) {
      debugPrint('TipOffScreen: WebSocket not connected, using HTTP');
      return;
    }
    try {
      final body = json.encode(tipData);
      _sendStompFrame('SEND', {
        'destination': '/app/tip-offs/submit',
        'content-type': 'application/json',
      }, body: body);
      debugPrint('TipOffScreen: Tip submitted via STOMP SEND');
    } catch (e) {
      debugPrint('TipOffScreen: STOMP SEND failed: $e');
    }
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    _wsChannel?.sink.close();
    _descriptionController.dispose();
    _targetController.dispose();
    _suspectController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    final tipData = {
      'tipType': _tipType,
      'description': _descriptionController.text.trim(),
      'targetDescription': _targetController.text.trim().isEmpty
          ? null : _targetController.text.trim(),
      'suspectDescription': _suspectController.text.trim().isEmpty
          ? null : _suspectController.text.trim(),
      'latitude': _latitude,
      'longitude': _longitude,
      'anonymous': _isAnonymous,
    };

    // STEP 1: Send via STOMP SEND over existing WebSocket (FASTEST PATH - ~1ms)
    _sendTipViaStomp(tipData);

    // Show success immediately — optimistic UI
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tip submitted anonymously. Thank you.')),
      );
      Navigator.of(context).pop();
    }

    // STEP 2: Fire HTTP POST in the background as reliability fallback
    unawaited(_submitViaHttp(tipData));
  }

  /// Fallback: submit tip via HTTP POST.
  Future<void> _submitViaHttp(Map<String, dynamic> tipData) async {
    try {
      await BackendApi().submitTip(tipData);
    } catch (e) {
      debugPrint('TipOffScreen: HTTP fallback failed: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Submit Tip-Off'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.list),
            onPressed: () => Navigator.of(context).pushNamed('/tip-review'),
            tooltip: 'Review Tips',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Anonymous notice
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.indigo[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.indigo[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.shield, color: Colors.indigo[700]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your identity is protected. Anonymous tips help keep communities safe.',
                        style: TextStyle(fontSize: 12, color: Colors.indigo[900]),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                value: _tipType,
                decoration: InputDecoration(
                  labelText: 'Tip Type',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.category),
                ),
                items: [
                  DropdownMenuItem(value: 'suspicious_person', child: Text('Suspicious Person')),
                  DropdownMenuItem(value: 'suspicious_vehicle', child: Text('Suspicious Vehicle')),
                  DropdownMenuItem(value: 'planned_attack', child: Text('Planned Attack')),
                  DropdownMenuItem(value: 'hidden_weapons', child: Text('Hidden Weapons')),
                  DropdownMenuItem(value: 'kidnapping_plot', child: Text('Kidnapping Plot')),
                  DropdownMenuItem(value: 'bombing_plot', child: Text('Bombing Plot')),
                  DropdownMenuItem(value: 'suspicious_radio_activity', child: Text('Suspicious Radio / Walkie-Talkie')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (v) => setState(() => _tipType = v!),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: 'Description *',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.description),
                ),
                maxLines: 5,
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _targetController,
                decoration: InputDecoration(
                  labelText: 'Target Description (optional)',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.person_search),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _suspectController,
                decoration: InputDecoration(
                  labelText: 'Suspect Description (optional)',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.face),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),

              NigeriaLocationPicker(
                label: 'Location (optional)',
                onLocationSelected: (lat, lng, name) {
                  setState(() {
                    _latitude = lat;
                    _longitude = lng;
                    _locationName = name;
                  });
                },
              ),
              const SizedBox(height: 16),

              // Evidence Capture Section
              Text(
                'Attach Evidence (Optional)',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildEvidenceButton(
                      icon: Icons.camera_alt,
                      label: 'Photo',
                      color: Colors.blue,
                      onTap: _capturePhoto,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildEvidenceButton(
                      icon: Icons.videocam,
                      label: 'Video',
                      color: Colors.purple,
                      onTap: _captureVideo,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildEvidenceButton(
                      icon: Icons.mic,
                      label: 'Audio',
                      color: Colors.teal,
                      onTap: _recordAudio,
                    ),
                  ),
                ],
              ),
              if (_isCapturing)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(),
                ),

              // Evidence Preview Thumbnails
              if (_capturedEvidence.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 80,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _capturedEvidence.length,
                    itemBuilder: (context, index) {
                      final ev = _capturedEvidence[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Stack(
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey[300]!),
                                color: Colors.grey[100],
                              ),
                              child: _buildEvidenceThumbnail(ev),
                            ),
                            Positioned(
                              top: 2,
                              right: 2,
                              child: GestureDetector(
                                onTap: () => _removeEvidence(index),
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 16),

              SwitchListTile(
                title: Text('Submit Anonymously'),
                subtitle: Text('Your identity will not be shared'),
                value: _isAnonymous,
                onChanged: (v) => setState(() => _isAnonymous = v),
                secondary: Icon(
                  _isAnonymous ? Icons.shield : Icons.person,
                  color: _isAnonymous ? Colors.indigo : Colors.grey,
                ),
              ),
              const SizedBox(height: 24),

              ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submit,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send),
                label: Text(_isSubmitting ? 'Submitting...' : 'Submit Tip'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  // ---------------------------------------------------------------------------
  // Evidence Capture Helper Widgets
  // ---------------------------------------------------------------------------

  Widget _buildEvidenceButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: _isCapturing ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEvidenceThumbnail(EvidenceFile evidence) {
    switch (evidence.type) {
      case EvidenceType.photo:
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(evidence.filePath),
            fit: BoxFit.cover,
            width: 80,
            height: 80,
          ),
        );
      case EvidenceType.video:
        return Stack(
          alignment: Alignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(evidence.filePath),
                fit: BoxFit.cover,
                width: 80,
                height: 80,
              ),
            ),
            Icon(
              Icons.play_circle_fill,
              color: Colors.white.withOpacity(0.8),
              size: 28,
            ),
          ],
        );
      case EvidenceType.audio:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.audio_file, color: Colors.teal, size: 32),
            Text(
              'Audio',
              style: TextStyle(fontSize: 10, color: Colors.teal[700]),
            ),
          ],
        );
    }
  }
}
