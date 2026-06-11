import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../../../core/constants.dart';
import '../../../core/routes.dart';
import '../../../core/themes.dart';
import '../services/sos_service.dart';
import '../../mesh/services/mesh_manager.dart';
import '../../../shared/services/evidence_service.dart';

class SOSScreen extends StatefulWidget {
  const SOSScreen({Key? key}) : super(key: key);

  @override
  State<SOSScreen> createState() => _SOSScreenState();
}

class _SOSScreenState extends State<SOSScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isSending = false;
  bool _isSent = false;
  String? _selectedAlertType;
  final _descriptionController = TextEditingController();
  Timer? _countdownTimer;
  int _countdown = 5;

  // Evidence capture state
  final EvidenceService _evidenceService = EvidenceService();
  final ImagePicker _picker = ImagePicker();
  List<EvidenceFile> _capturedEvidence = [];
  bool _isCapturing = false;

  final List<String> _alertTypes = [
    'Medical Emergency',
    'Fire',
    'Natural Disaster',
    'Violence/Attack',
    'Trapped',
    'Lost',
    'Structural Damage',
    'Other Emergency',
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _descriptionController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

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
      final evidence = await _evidenceService.recordAudio(durationSeconds: 15);
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

  Future<void> _sendSOS() async {
    setState(() => _isSending = true);

    final sosService = context.read<SOSService>();

    try {
      await sosService.sendSOS(
        alertType: _selectedAlertType ?? 'General Emergency',
        description: _descriptionController.text.trim(),
      );

      setState(() {
        _isSent = true;
        _isSending = false;
      });

      // Auto-navigate to dashboard after 3 seconds
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) {
        Navigator.of(context).pushReplacementNamed(AppRoutes.dashboard);
      }
    } catch (e) {
      setState(() => _isSending = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send SOS: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _startEmergencyCountdown() {
    setState(() => _countdown = 5);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _countdown--;
      });
      if (_countdown <= 0) {
        timer.cancel();
        _sendSOS();
      }
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    setState(() => _countdown = 5);
  }

  @override
  Widget build(BuildContext context) {
    if (_isSent) {
      return _buildSentView();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Send SOS Alert'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // SOS Button
            Center(
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulseAnimation.value,
                    child: GestureDetector(
                      onTap: _isSending ? null : _startEmergencyCountdown,
                      child: Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const RadialGradient(
                            colors: [
                              Color(0xFFFF5252),
                              Color(0xFFD32F2F),
                              Color(0xFFB71C1C),
                            ],
                            stops: [0.3, 0.7, 1.0],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryColor.withOpacity(0.5),
                              blurRadius: 30,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_isSending)
                              const SizedBox(
                                width: 48,
                                height: 48,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 4,
                                ),
                              )
                            else if (_countdown < 5)
                              Text(
                                '$_countdown',
                                style: const TextStyle(
                                  fontSize: 64,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              )
                            else ...[
                              const Icon(
                                Icons.warning_amber_rounded,
                                size: 64,
                                color: Colors.white,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'SOS',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 4,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _countdown < 5
                  ? 'Sending in $_countdown seconds...'
                  : 'Tap to send emergency alert',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            if (_countdown < 5 && _countdown > 0)
              Center(
                child: TextButton(
                  onPressed: _cancelCountdown,
                  child: const Text('Cancel'),
                ),
              ),
            const SizedBox(height: 32),

            // Alert Type
            const Text(
              'Alert Type',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedAlertType,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Select alert type',
              ),
              items: _alertTypes.map((type) {
                return DropdownMenuItem(value: type, child: Text(type));
              }).toList(),
              onChanged: (value) {
                setState(() => _selectedAlertType = value);
              },
            ),
            const SizedBox(height: 16),

            // Description
            const Text(
              'Description (Optional)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _descriptionController,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Describe your emergency situation...',
              ),
            ),
            const SizedBox(height: 16),

            // Evidence Capture Section
            const Text(
              'Capture Evidence (Optional)',
              style: TextStyle(
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

            // Info card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange[700]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Your location will be sent with this alert. '
                      'The alert will be broadcast via all available channels '
                      '(cloud, Bluetooth mesh, Wi-Fi Direct, LoRa).',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange[900],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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

  Widget _buildSentView() {
    return Scaffold(
      backgroundColor: AppTheme.primaryColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.check_circle_outline,
              size: 100,
              color: Colors.white,
            ),
            const SizedBox(height: 24),
            const Text(
              'SOS SENT',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Help is on the way',
              style: TextStyle(
                fontSize: 18,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Alert broadcast via all available channels',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 48),
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
