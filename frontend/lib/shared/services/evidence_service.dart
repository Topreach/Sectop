import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'backend_api.dart';
import 'offline_storage.dart';
import '../../modules/mesh/services/mesh_manager.dart';

/// Service to record and upload "Last-Gasp" evidence (audio/photo).
///
/// Triggered during an SOS event to capture immediate surroundings.
class EvidenceService {
  static final EvidenceService _instance = EvidenceService._internal();
  factory EvidenceService() => _instance;
  EvidenceService._internal();

  final BackendApi _api = BackendApi();
  final MeshManager _meshManager = MeshManager();
  final OfflineStorageService _storage = OfflineStorageService();

  /// Record 10 seconds of audio and a photo, then broadcast via all channels.
  Future<void> captureLastGasp(String alertId) async {
    debugPrint('EvidenceService: Capturing last-gasp evidence for $alertId');

    try {
      // 1. Record audio (placeholder for actual recording logic)
      final audioPath = await _recordQuickAudio();

      // 2. Take photo (placeholder for actual camera logic)
      final photoPath = await _takeQuickPhoto();

      if (audioPath != null) {
        final audioBytes = await File(audioPath).readAsBytes();
        final base64Audio = base64Encode(audioBytes);

        // Broadcast audio via mesh (chunked if necessary)
        await _meshManager.broadcastMessage(
          type: MessageType.text, // Using text for payload for now
          payload: {
            'alert_id': alertId,
            'data_type': 'audio_evidence',
            'content': base64Audio,
          },
          priority: MessagePriority.critical,
        );

        // Upload to cloud if available
        await _api.analyzeAudio(base64Audio);
      }
    } catch (e) {
      debugPrint('EvidenceService: Capture failed: $e');
    }
  }

  Future<String?> _recordQuickAudio() async {
    // In a real app, use 'flutter_sound' or 'record' package.
    return null;
  }

  Future<String?> _takeQuickPhoto() async {
    // In a real app, use 'camera' or 'image_picker' package.
    return null;
  }
}
