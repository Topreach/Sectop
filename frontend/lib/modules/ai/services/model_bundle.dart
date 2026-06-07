import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../../../core/constants.dart';

/// Manages TFLite model files: download, verification, caching, and loading.
///
/// Handles:
/// - Downloading model files from a remote CDN or bundled assets
/// - SHA-256 integrity verification
/// - Version checking for model updates
/// - Fallback to bundled assets when offline
/// - Model file caching in app documents directory
class ModelBundle {
  static final ModelBundle _instance = ModelBundle._internal();
  factory ModelBundle() => _instance;
  ModelBundle._internal();

  // Model registry: maps model name to its metadata
  final Map<String, ModelMeta> _registry = {};

  // Download progress callbacks
  void Function(String modelName, double progress)? onDownloadProgress;

  bool _isInitialized = false;

  /// Register all known models with their metadata.
  Future<void> initialize() async {
    if (_isInitialized) return;

    _registry[AppConstants.distressModelPath] = ModelMeta(
      name: 'distress_model.tflite',
      displayName: 'Distress Detection (FP32)',
      description: 'Full-precision text classifier for emergency message prioritization',
      version: 1,
      expectedSha256: null, // Set when model is finalized
      remoteUrl: 'https://models.dangeremergence.com/v1/distress_model.tflite',
      bundledInAssets: true,
      fileSize: 0, // Unknown until downloaded
    );

    _registry['models/distress_quant.tflite'] = ModelMeta(
      name: 'distress_quant.tflite',
      displayName: 'Distress Detection (INT8 Quantized)',
      description: 'Quantized text classifier — 4x smaller, ~1% accuracy loss',
      version: 1,
      expectedSha256: null,
      remoteUrl: 'https://models.dangeremergence.com/v1/distress_quant.tflite',
      bundledInAssets: false,
      fileSize: 0,
    );

    _registry['models/danger_forecast.tflite'] = ModelMeta(
      name: 'danger_forecast.tflite',
      displayName: 'Danger Zone Forecast (LSTM)',
      description: 'LSTM time-series model for predicting danger zone escalation',
      version: 1,
      expectedSha256: null,
      remoteUrl: 'https://models.dangeremergence.com/v1/danger_forecast.tflite',
      bundledInAssets: false,
      fileSize: 0,
    );

    _isInitialized = true;
    debugPrint('ModelBundle: Registered ${_registry.length} models');
  }

  /// Get the best available path for a model.
  ///
  /// Priority:
  /// 1. Cached in app documents directory (downloaded)
  /// 2. Bundled in app assets
  /// 3. Remote URL (requires download)
  Future<String> getModelPath(String modelPath) async {
    final meta = _registry[modelPath];
    if (meta == null) {
      throw ArgumentError('Unknown model: $modelPath');
    }

    // 1. Check cache
    final cachePath = await _getCachePath(meta.name);
    if (await _fileExists(cachePath)) {
      debugPrint('ModelBundle: Using cached model at $cachePath');
      return cachePath;
    }

    // 2. Check bundled assets
    if (meta.bundledInAssets) {
      try {
        // For bundled assets, TFLite can load directly from assets
        debugPrint('ModelBundle: Using bundled asset: $modelPath');
        return modelPath; // TFLite Interpreter.fromAsset handles this
      } catch (e) {
        debugPrint('ModelBundle: Bundled asset not found: $e');
      }
    }

    // 3. Return modelPath anyway — caller will handle fallback
    debugPrint('ModelBundle: Model not cached, returning path for download: $modelPath');
    return modelPath;
  }

  /// Download a model file from remote URL.
  Future<bool> downloadModel(String modelPath, {bool force = false}) async {
    final meta = _registry[modelPath];
    if (meta == null || meta.remoteUrl == null) return false;

    final cachePath = await _getCachePath(meta.name);

    // Skip if already cached and not forced
    if (!force && await _fileExists(cachePath)) {
      debugPrint('ModelBundle: Model already cached: ${meta.name}');
      return true;
    }

    try {
      debugPrint('ModelBundle: Downloading ${meta.name} from ${meta.remoteUrl}');
      final response = await http.get(Uri.parse(meta.remoteUrl));

      if (response.statusCode != 200) {
        debugPrint('ModelBundle: Download failed with status ${response.statusCode}');
        return false;
      }

      // Verify integrity
      if (meta.expectedSha256 != null) {
        final hash = sha256.convert(response.bodyBytes).toString();
        if (hash != meta.expectedSha256) {
          debugPrint('ModelBundle: SHA-256 mismatch for ${meta.name}');
          return false;
        }
      }

      // Write to cache
      final file = File(cachePath);
      await file.writeAsBytes(response.bodyBytes);
      meta.fileSize = response.bodyBytes.length;

      debugPrint('ModelBundle: Downloaded ${meta.name} (${meta.fileSize} bytes)');
      return true;
    } catch (e) {
      debugPrint('ModelBundle: Download error for ${meta.name}: $e');
      return false;
    }
  }

  /// Check if a model is available (cached or bundled).
  Future<bool> isModelAvailable(String modelPath) async {
    final meta = _registry[modelPath];
    if (meta == null) return false;

    // Check cache
    final cachePath = await _getCachePath(meta.name);
    if (await _fileExists(cachePath)) return true;

    // Check bundled assets
    if (meta.bundledInAssets) return true;

    return false;
  }

  /// Get cache directory path for a model file.
  Future<String> _getCachePath(String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${dir.path}/models');
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }
    return '${modelDir.path}/$filename';
  }

  Future<bool> _fileExists(String path) async {
    try {
      return await File(path).exists();
    } catch (_) {
      return false;
    }
  }

  /// Get metadata for a registered model.
  ModelMeta? getModelMeta(String modelPath) => _registry[modelPath];

  /// Get all registered models.
  List<ModelMeta> get allModels => _registry.values.toList();

  /// Clear the model cache.
  Future<void> clearCache() async {
    final dir = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${dir.path}/models');
    if (await modelDir.exists()) {
      await modelDir.delete(recursive: true);
    }
  }
}

/// Metadata for a registered ML model.
class ModelMeta {
  final String name;
  final String displayName;
  final String description;
  final int version;
  final String? expectedSha256;
  final String? remoteUrl;
  final bool bundledInAssets;
  int fileSize;

  ModelMeta({
    required this.name,
    required this.displayName,
    required this.description,
    required this.version,
    this.expectedSha256,
    this.remoteUrl,
    this.bundledInAssets = false,
    this.fileSize = 0,
  });
}
