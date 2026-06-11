import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'backend_api.dart';
import 'offline_storage.dart';
import '../../modules/mesh/services/mesh_manager.dart';

/// Evidence types that can be captured.
enum EvidenceType { photo, video, audio }

/// Metadata for a captured evidence file.
class EvidenceFile {
  final String id;
  final EvidenceType type;
  final String filePath;
  final int sizeBytes;
  final DateTime capturedAt;
  final String? mimeType;

  EvidenceFile({
    required this.id,
    required this.type,
    required this.filePath,
    required this.sizeBytes,
    required this.capturedAt,
    this.mimeType,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'type': type.name,
    'filePath': filePath,
    'sizeBytes': sizeBytes,
    'capturedAt': capturedAt.toIso8601String(),
    'mimeType': mimeType,
  };

  factory EvidenceFile.fromMap(Map<String, dynamic> map) => EvidenceFile(
    id: map['id'] as String,
    type: EvidenceType.values.firstWhere((e) => e.name == map['type']),
    filePath: map['filePath'] as String,
    sizeBytes: map['sizeBytes'] as int,
    capturedAt: DateTime.parse(map['capturedAt'] as String),
    mimeType: map['mimeType'] as String?,
  );
}

/// Service to capture, store, and upload evidence (photo/video/audio).
///
/// Triggered during SOS events, incident reports, and tip-offs.
/// Stores evidence locally first (offline-first), then uploads async to backend.
class EvidenceService {
  static final EvidenceService _instance = EvidenceService._internal();
  factory EvidenceService() => _instance;
  EvidenceService._internal();

  final BackendApi _api = BackendApi();
  final MeshManager _meshManager = MeshManager();
  final OfflineStorageService _storage = OfflineStorageService();
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();

  /// In-memory cache of evidence files for the current session.
  final List<EvidenceFile> _evidenceCache = [];

  /// Get all evidence files captured in this session.
  List<EvidenceFile> get evidenceFiles => List.unmodifiable(_evidenceCache);

  // ---------------------------------------------------------------------------
  // Photo Capture
  // ---------------------------------------------------------------------------

  /// Capture a photo using the device camera.
  Future<EvidenceFile?> capturePhoto({int maxDurationSeconds = 30}) async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (photo == null) return null;

      final file = File(photo.path);
      final evidenceFile = EvidenceFile(
        id: 'ev_${DateTime.now().millisecondsSinceEpoch}_${file.hashCode}',
        type: EvidenceType.photo,
        filePath: photo.path,
        sizeBytes: await file.length(),
        capturedAt: DateTime.now(),
        mimeType: 'image/jpeg',
      );

      _evidenceCache.add(evidenceFile);
      debugPrint('EvidenceService: Photo captured: ${evidenceFile.filePath}');
      return evidenceFile;
    } catch (e) {
      debugPrint('EvidenceService: Photo capture failed: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Video Capture
  // ---------------------------------------------------------------------------

  /// Capture a video using the device camera.
  Future<EvidenceFile?> captureVideo({int maxDurationSeconds = 30}) async {
    try {
      final XFile? video = await _picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: Duration(seconds: maxDurationSeconds),
      );
      if (video == null) return null;

      final file = File(video.path);
      final evidenceFile = EvidenceFile(
        id: 'ev_${DateTime.now().millisecondsSinceEpoch}_${file.hashCode}',
        type: EvidenceType.video,
        filePath: video.path,
        sizeBytes: await file.length(),
        capturedAt: DateTime.now(),
        mimeType: 'video/mp4',
      );

      _evidenceCache.add(evidenceFile);
      debugPrint('EvidenceService: Video captured: ${evidenceFile.filePath}');
      return evidenceFile;
    } catch (e) {
      debugPrint('EvidenceService: Video capture failed: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Audio Recording
  // ---------------------------------------------------------------------------

  /// Record audio for a specified duration (seconds).
  Future<EvidenceFile?> recordAudio({int durationSeconds = 10}) async {
    try {
      // Check and request microphone permission
      final hasPermission = await _audioRecorder.hasPermission(request: true);
      if (!hasPermission) {
        debugPrint('EvidenceService: Microphone permission denied');
        return null;
      }

      // Get temp directory for audio file
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/evidence_audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

      // Start recording
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: filePath,
      );

      // Record for the specified duration
      await Future.delayed(Duration(seconds: durationSeconds));

      // Stop recording
      final recordedPath = await _audioRecorder.stop();
      if (recordedPath == null) return null;

      final file = File(recordedPath);
      final evidenceFile = EvidenceFile(
        id: 'ev_${DateTime.now().millisecondsSinceEpoch}_${file.hashCode}',
        type: EvidenceType.audio,
        filePath: recordedPath,
        sizeBytes: await file.length(),
        capturedAt: DateTime.now(),
        mimeType: 'audio/mp4',
      );

      _evidenceCache.add(evidenceFile);
      debugPrint('EvidenceService: Audio recorded: ${evidenceFile.filePath}');
      return evidenceFile;
    } catch (e) {
      debugPrint('EvidenceService: Audio recording failed: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Last-Gasp Evidence (Auto-capture on SOS)
  // ---------------------------------------------------------------------------

  /// Record 10 seconds of audio and a photo, then broadcast via all channels.
  Future<void> captureLastGasp(String alertId) async {
    debugPrint('EvidenceService: Capturing last-gasp evidence for $alertId');

    try {
      // 1. Record 10 seconds of audio
      final audioFile = await recordAudio(durationSeconds: 10);

      // 2. Take a quick photo
      final photoFile = await capturePhoto(maxDurationSeconds: 5);

      // 3. Store and broadcast each evidence file
      for (final evidence in [audioFile, photoFile].whereType<EvidenceFile>()) {
        // Save locally
        await _saveEvidenceLocally(evidence, alertId);

        // Broadcast via mesh (chunked if necessary)
        final bytes = await File(evidence.filePath).readAsBytes();
        final base64Content = base64Encode(bytes);

        await _meshManager.broadcastMessage(
          type: MessageType.text,
          payload: {
            'alert_id': alertId,
            'evidence_id': evidence.id,
            'data_type': '${evidence.type.name}_evidence',
            'mime_type': evidence.mimeType,
            'content': base64Content,
          },
          priority: MessagePriority.critical,
        );

        // Upload to cloud if available
        unawaited(_uploadEvidence(evidence, alertId));
      }
    } catch (e) {
      debugPrint('EvidenceService: Last-gasp capture failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Local Storage
  // ---------------------------------------------------------------------------

  /// Save evidence metadata to local storage.
  Future<void> _saveEvidenceLocally(EvidenceFile evidence, String parentId) async {
    try {
      await _storage.insert('evidence', {
        'id': evidence.id,
        'parent_id': parentId,
        'type': evidence.type.name,
        'file_path': evidence.filePath,
        'size_bytes': evidence.sizeBytes,
        'captured_at': evidence.capturedAt.toIso8601String(),
        'mime_type': evidence.mimeType,
        'uploaded': 0,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint('EvidenceService: Local save failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Cloud Upload
  // ---------------------------------------------------------------------------

  /// Upload evidence file to the backend.
  Future<bool> _uploadEvidence(EvidenceFile evidence, String parentId) async {
    try {
      final file = File(evidence.filePath);
      if (!await file.exists()) return false;

      final bytes = await file.readAsBytes();
      final base64Content = base64Encode(bytes);

      await _api.uploadEvidence(
        parentId: parentId,
        evidenceType: evidence.type.name,
        fileName: evidence.filePath.split('/').last,
        fileBytes: base64Content,
        mimeType: evidence.mimeType ?? 'application/octet-stream',
      );

      // Mark as uploaded in local storage
      await _storage.update('evidence', {
        'uploaded': 1,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      }, where: 'id = ?', whereArgs: [evidence.id]);

      debugPrint('EvidenceService: Uploaded ${evidence.id} for parent $parentId');
      return true;
    } catch (e) {
      debugPrint('EvidenceService: Upload failed for ${evidence.id}: $e');
      return false;
    }
  }

  /// Upload all pending (not yet uploaded) evidence for a parent entity.
  Future<void> uploadPendingEvidence(String parentId) async {
    try {
      final pending = await _storage.query('evidence',
        where: 'parent_id = ? AND uploaded = 0',
        whereArgs: [parentId],
      );

      for (final row in pending) {
        final evidence = EvidenceFile(
          id: row['id'] as String,
          type: EvidenceType.values.firstWhere((e) => e.name == row['type']),
          filePath: row['file_path'] as String,
          sizeBytes: row['size_bytes'] as int,
          capturedAt: DateTime.parse(row['captured_at'] as String),
          mimeType: row['mime_type'] as String?,
        );
        await _uploadEvidence(evidence, parentId);
      }
    } catch (e) {
      debugPrint('EvidenceService: Pending upload failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Evidence Retrieval
  // ---------------------------------------------------------------------------

  /// Get all evidence files for a parent entity (alert, incident, tip).
  Future<List<EvidenceFile>> getEvidenceForParent(String parentId) async {
    try {
      final rows = await _storage.query('evidence',
        where: 'parent_id = ?',
        whereArgs: [parentId],
        orderBy: 'captured_at DESC',
      );

      return rows.map((row) => EvidenceFile(
        id: row['id'] as String,
        type: EvidenceType.values.firstWhere((e) => e.name == row['type']),
        filePath: row['file_path'] as String,
        sizeBytes: row['size_bytes'] as int,
        capturedAt: DateTime.parse(row['captured_at'] as String),
        mimeType: row['mime_type'] as String?,
      )).toList();
    } catch (e) {
      debugPrint('EvidenceService: Get evidence failed: $e');
      return [];
    }
  }

  /// Delete an evidence file from local storage and disk.
  Future<void> deleteEvidence(String evidenceId) async {
    try {
      // Delete from local DB
      await _storage.delete('evidence', where: 'id = ?', whereArgs: [evidenceId]);

      // Delete from cache
      _evidenceCache.removeWhere((e) => e.id == evidenceId);

      // Delete file from disk
      final rows = await _storage.query('evidence',
        where: 'id = ?',
        whereArgs: [evidenceId],
      );
      if (rows.isNotEmpty) {
        final filePath = rows.first['file_path'] as String;
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (e) {
      debugPrint('EvidenceService: Delete failed: $e');
    }
  }

  /// Clear all evidence from the current session cache.
  void clearSessionCache() {
    _evidenceCache.clear();
  }

  /// Dispose audio recorder resources.
  void dispose() {
    _audioRecorder.dispose();
  }
}
