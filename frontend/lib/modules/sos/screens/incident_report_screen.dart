import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../../../core/constants.dart';
import '../../../core/themes.dart';
import '../../../shared/services/offline_storage.dart';
import '../../../shared/services/nigeria_location_service.dart';
import '../../../shared/services/evidence_service.dart';
import '../../../shared/widgets/nigeria_location_picker.dart';
import '../../incidents/services/incident_service.dart';
import '../../maps/services/map_service.dart';
import '../../../core/localization.dart';

class IncidentReportScreen extends StatefulWidget {
  const IncidentReportScreen({Key? key}) : super(key: key);

  @override
  State<IncidentReportScreen> createState() => _IncidentReportScreenState();
}

class _IncidentReportScreenState extends State<IncidentReportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _uuid = const Uuid();

  String _incidentType = 'kidnapping';
  String _severity = 'high';
  double? _latitude;
  double? _longitude;
  String? _locationName;
  bool _isSubmitting = false;
  bool _isAnonymous = false;
  bool _useManualLocation = false;

  // Evidence capture state
  final EvidenceService _evidenceService = EvidenceService();
  final ImagePicker _picker = ImagePicker();
  List<EvidenceFile> _capturedEvidence = [];
  bool _isCapturing = false;

  /// Nigeria-specific incident types for insecurity tracking.
  /// Nigeria-specific incident types for insecurity tracking.
  final List<Map<String, dynamic>> _incidentTypes = [
    {'value': 'kidnapping', 'label': 'Kidnapping', 'icon': Icons.people_outline, 'color': 0xFFD32F2F},
    {'value': 'terrorism', 'label': 'Terrorism / Bombing', 'icon': Icons.warning_amber_rounded, 'color': 0xFFB71C1C},
    {'value': 'banditry', 'label': 'Banditry', 'icon': Icons.gavel, 'color': 0xFFE65100},
    {'value': 'armed_robbery', 'label': 'Armed Robbery', 'icon': Icons.money_off, 'color': 0xFFF57C00},
    {'value': 'suspicious_activity', 'label': 'Suspicious Activity', 'icon': Icons.visibility, 'color': 0xFFFBC02D},
    {'value': 'herdsmen_attack', 'label': 'Herdsmen Attack', 'icon': Icons.agriculture, 'color': 0xFF5D4037},
    {'value': 'cult_violence', 'label': 'Cult Violence', 'icon': Icons.groups, 'color': 0xFF880E4F},
    {'value': 'ritual_killings', 'label': 'Ritual Killings', 'icon': Icons.dark_mode, 'color': 0xFF311B92},
    {'value': 'political_violence', 'label': 'Political Violence', 'icon': Icons.account_balance, 'color': 0xFF1A237E},
    {'value': 'communal_clash', 'label': 'Communal Clash', 'icon': Icons.fireplace, 'color': 0xFFBF360C},
    {'value': 'suspicious_radio_activity', 'label': 'Suspicious Radio / Walkie-Talkie', 'icon': Icons.radio, 'color': 0xFF4A148C},
    {'value': 'fire', 'label': 'Fire', 'icon': Icons.local_fire_department, 'color': 0xFFFF6F00},
    {'value': 'flood', 'label': 'Flood', 'icon': Icons.water_drop, 'color': 0xFF1565C0},
    {'value': 'medical', 'label': 'Medical Emergency', 'icon': Icons.medical_services, 'color': 0xFF2E7D32},
    {'value': 'accident', 'label': 'Accident', 'icon': Icons.car_crash, 'color': 0xFFEF6C00},
    {'value': 'other', 'label': 'Other', 'icon': Icons.help_outline, 'color': 0xFF757575},
  ];
  final List<Map<String, dynamic>> _severityLevels = [
    {'value': 'low', 'label': 'Low - Minor incident, no immediate danger', 'color': Colors.green},
    {'value': 'medium', 'label': 'Medium - Requires attention', 'color': Colors.orange},
    {'value': 'high', 'label': 'High - Serious threat, may escalate', 'color': Colors.deepOrange},
    {'value': 'critical', 'label': 'Critical - Immediate danger, lives at risk', 'color': Colors.red},
  ];

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  Future<void> _loadLocation() async {
    try {
      final mapService = context.read<MapService>();
      final position = mapService.currentPosition ??
          await mapService.getCurrentLocation();
      if (position != null) {
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
          // Try to resolve GPS coordinates to a location name
          final resolved = NigeriaLocationService.searchByCoordinates(
            position.latitude,
            position.longitude,
          );
          _locationName = resolved?['displayName'] as String?;
        });
      }
    } catch (e) {
      debugPrint('IncidentReport: Failed to get location: $e');
    }
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
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submitReport() async {
    if (!_formKey.currentState!.validate()) return;

    if (_latitude == null || _longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location not available. Please enable GPS.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // Try to submit via backend API first
      final incidentService = IncidentService();
      final result = await incidentService.reportIncident(
        incidentType: _incidentType,
        description: _descriptionController.text.trim(),
        latitude: _latitude!,
        longitude: _longitude!,
        severity: _severity,
        isAnonymous: _isAnonymous,
      );

      if (result != null) {
        // Successfully submitted to backend
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _isAnonymous
                    ? 'Incident reported anonymously. Authorities have been notified.'
                    : 'Incident reported successfully. Stay safe!',
              ),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, result);
        }
        return;
      }
    } catch (_) {
      // Backend unavailable - fall back to local storage
      debugPrint('IncidentReport: Backend unavailable, saving locally');
    }

    // Fallback: save to local offline storage
    try {
      final report = {
        'id': _uuid.v4(),
        'type': _incidentType,
        'description': _descriptionController.text.trim(),
        'latitude': _latitude,
        'longitude': _longitude,
        'severity': _severity,
        'isAnonymous': _isAnonymous,
        'status': 'reported',
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      };

      final storage = OfflineStorageService();
      await storage.insert(AppConstants.tableIncidents, report);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report saved offline. Will sync when connected.'),
            backgroundColor: Colors.blue,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('IncidentReport: Failed to submit: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit report: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('report_incident')),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          // Anonymous toggle in app bar
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Anonymous',
                style: TextStyle(
                  color: _isAnonymous ? Colors.amber[300] : Colors.white70,
                  fontSize: 12,
                ),
              ),
              Switch(
                value: _isAnonymous,
                onChanged: (v) => setState(() => _isAnonymous = v),
                activeColor: Colors.amber,
                inactiveThumbColor: Colors.white54,
                inactiveTrackColor: Colors.white24,
              ),
            ],
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
              // Anonymous reporting info banner
              if (_isAnonymous)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.visibility_off, color: Colors.amber[700], size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Your identity will NOT be shared. Only the incident details and location will be sent to authorities.',
                          style: TextStyle(
                            color: Colors.amber[900],
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Incident Type Selection
              Text(
                'Incident Type',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[800],
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const ClampingScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 1.0,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _incidentTypes.length,
                  itemBuilder: (context, index) {
                    final type = _incidentTypes[index];
                    final isSelected = _incidentType == type['value'];
                    return GestureDetector(
                      onTap: () => setState(() => _incidentType = type['value'] as String),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Color(type['color'] as int).withOpacity(0.15)
                              : Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? Color(type['color'] as int)
                                : Colors.grey[300]!,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              type['icon'] as IconData,
                              color: isSelected
                                  ? Color(type['color'] as int)
                                  : Colors.grey[500],
                              size: 24,
                            ),
                            const SizedBox(height: 4),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Text(
                                type['label'] as String,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isSelected
                                      ? Color(type['color'] as int)
                                      : Colors.grey[700],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Severity Selection
              Text(
                'Severity Level',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[800],
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              ..._severityLevels.map((severity) {
                final isSelected = _severity == severity['value'];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () => setState(() => _severity = severity['value'] as String),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? (severity['color'] as Color).withOpacity(0.1)
                            : Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected
                              ? severity['color'] as Color
                              : Colors.grey[300]!,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: severity['color'] as Color,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              severity['label'] as String,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                color: isSelected
                                    ? severity['color'] as Color
                                    : Colors.grey[700],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),

              // Description
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  prefixIcon: Icon(Icons.description_outlined),
                  hintText: 'Describe what happened... Include details like number of suspects, vehicles, weapons seen, direction of travel...',
                ),
                maxLines: 5,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please provide a description';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Location Section
              if (!_useManualLocation) ...[
                // Auto-detected GPS Location Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _latitude != null ? Icons.my_location : Icons.location_off,
                              color: _latitude != null ? Colors.green : Colors.orange,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Your Current Location',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[800],
                                fontSize: 14,
                              ),
                            ),
                            const Spacer(),
                            if (_latitude != null)
                              GestureDetector(
                                onTap: () => setState(() => _useManualLocation = true),
                                child: Text(
                                  'Change',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Show resolved location name if available
                        if (_locationName != null)
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.green[50],
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.location_on, size: 16, color: Colors.green[700]),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _locationName!,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.green[800],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          _latitude != null
                              ? 'GPS: ${_latitude!.toStringAsFixed(4)}, ${_longitude!.toStringAsFixed(4)}'
                              : 'Unable to get location. Enable GPS.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        if (_latitude == null)
                          TextButton(
                            onPressed: _loadLocation,
                            child: const Text('Retry GPS'),
                          ),
                      ],
                    ),
                  ),
                ),
              ] else
                NigeriaLocationPicker(
                  label: 'Select Location',
                  initialLatitude: _latitude,
                  initialLongitude: _longitude,
                  onLocationSelected: (lat, lng, name) {
                    setState(() {
                      _latitude = lat;
                      _longitude = lng;
                      _locationName = name;
                    });
                  },
                ),
              if (_useManualLocation)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _useManualLocation = false);
                      _loadLocation();
                    },
                    child: Text(
                      'Use GPS location instead',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue[600],
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 16),

              // Evidence Capture Section
              const Text(
                'Attach Evidence (Optional)',
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
                      label: context.tr('photo'),
                      color: Colors.blue,
                      onTap: _capturePhoto,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildEvidenceButton(
                      icon: Icons.videocam,
                      label: context.tr('video'),
                      color: Colors.purple,
                      onTap: _captureVideo,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildEvidenceButton(
                      icon: Icons.mic,
                      label: context.tr('audio'),
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

              // Safety tips card
              Card(
                color: Colors.blue[50],
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue[700], size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Your safety is the priority. If you are in immediate danger, '
                          'use the SOS button instead. Do not stay in a dangerous area '
                          'to report an incident.',
                          style: TextStyle(
                            color: Colors.blue[800],
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Submit button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _submitReport,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(_isAnonymous ? Icons.shield_outlined : Icons.send),
                  label: Text(
                    _isSubmitting
                        ? 'Submitting...'
                        : _isAnonymous
                            ? 'Submit Anonymously'
                            : 'Submit Report',
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: _isAnonymous ? Colors.amber[700] : AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                  ),
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
