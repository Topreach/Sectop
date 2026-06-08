import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../core/constants.dart';
import 'offline_storage.dart';

/// Simplified sync manager — foreground-only sync triggered by user action
/// or app lifecycle events. Removed periodic background timer.
///
/// Maintains the three-state sync model (offline → pending → synced) for
/// offline-first resilience, but syncs only when explicitly requested.
class SyncManager {
  static final SyncManager _instance = SyncManager._internal();
  factory SyncManager() => _instance;
  SyncManager._internal();

  final OfflineStorageService _storage = OfflineStorageService();

  bool _isSyncing = false;
  bool _isOnline = true;
  DateTime? _lastSyncTime;

  /// Whether a sync operation is currently in progress.
  bool get isSyncing => _isSyncing;

  /// Whether the device is currently online (connected to backend).
  bool get isOnline => _isOnline;

  /// Number of items pending sync.
  int get pendingCount => 0; // Simplified: always 0 in thin-client mode

  /// Timestamp of the last successful sync.
  DateTime? get lastSyncTime => _lastSyncTime;

  /// Initialize the sync manager.
  Future<void> initialize() async {
    debugPrint('SyncManager: Initialized (foreground-only mode)');
  }

  /// Trigger a full sync cycle — push pending items, then pull updates.
  /// Returns true if sync completed successfully.
  Future<bool> triggerSync() async {
    if (_isSyncing) return false;
    _isSyncing = true;

    try {
      await _pushToCloud();
      await _pullFromCloud();
      _lastSyncTime = DateTime.now();
      debugPrint('SyncManager: Sync completed at $_lastSyncTime');
      return true;
    } catch (e) {
      debugPrint('SyncManager: Sync failed: $e');
      return false;
    } finally {
      _isSyncing = false;
    }
  }

  /// Push pending offline items to the cloud.
  Future<void> _pushToCloud() async {
    final pendingItems = await _storage.query('sync_log',
        where: 'status = ?',
        whereArgs: ['pending'],
        orderBy: 'created_at ASC',
        limit: AppConstants.batchSyncSize);

    for (final item in pendingItems) {
      try {
        final entityType = item['entity_type'] as String;
        final operation = item['operation'] as String;
        final payload = item['payload'] as String?;

        final uri = _getSyncUri(entityType, operation);
        if (uri == null) continue;

        final headers = await _authHeaders();
        final response = await http.post(
          uri,
          headers: headers,
          body: payload,
        ).timeout(Duration(seconds: AppConstants.apiTimeout));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          await _storage.update('sync_log', {
            'status': 'synced',
            'last_attempt': DateTime.now().millisecondsSinceEpoch,
          }, where: 'id = ?', whereArgs: [item['id']]);
        }
      } catch (e) {
        debugPrint('SyncManager: Push failed for item ${item['id']}: $e');
        await _storage.update('sync_log', {
          'retry_count': (item['retry_count'] as int? ?? 0) + 1,
          'last_attempt': DateTime.now().millisecondsSinceEpoch,
        }, where: 'id = ?', whereArgs: [item['id']]);
      }
    }
  }

  /// Pull latest data from the cloud.
  Future<void> _pullFromCloud() async {
    final since = _lastSyncTime?.millisecondsSinceEpoch ?? 0;
    final headers = await _authHeaders();

    // Pull messages
    try {
      final msgResponse = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/${AppConstants.apiVersion}/messages/sync?since=$since'),
        headers: headers,
      ).timeout(Duration(seconds: AppConstants.apiTimeout));

      if (msgResponse.statusCode == 200) {
        final data = json.decode(msgResponse.body);
        if (data is Map && data['messages'] is List) {
          for (final msg in data['messages']) {
            await _storage.upsert('messages', msg as Map<String, dynamic>);
          }
        }
      }
    } catch (e) {
      debugPrint('SyncManager: Pull messages failed: $e');
    }

    // Pull alerts
    try {
      final alertResponse = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/${AppConstants.apiVersion}/alerts/sync?since=$since'),
        headers: headers,
      ).timeout(Duration(seconds: AppConstants.apiTimeout));

      if (alertResponse.statusCode == 200) {
        final data = json.decode(alertResponse.body);
        if (data is Map && data['alerts'] is List) {
          for (final alert in data['alerts']) {
            await _storage.upsert('sos_alerts', alert as Map<String, dynamic>);
          }
        }
      }
    } catch (e) {
      debugPrint('SyncManager: Pull alerts failed: $e');
    }

    // Pull zones
    try {
      final zoneResponse = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/${AppConstants.apiVersion}/zones/sync?since=$since'),
        headers: headers,
      ).timeout(Duration(seconds: AppConstants.apiTimeout));

      if (zoneResponse.statusCode == 200) {
        final data = json.decode(zoneResponse.body);
        if (data is Map && data['zones'] is List) {
          for (final zone in data['zones']) {
            await _storage.upsert('zones', zone as Map<String, dynamic>);
          }
        }
      }
    } catch (e) {
      debugPrint('SyncManager: Pull zones failed: $e');
    }
  }

  /// Build authorization headers.
  Future<Map<String, String>> _authHeaders() async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    try {
      final token = await _storage.getSensitiveSetting(AppConstants.keyAuthToken);
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    } catch (_) {}
    return headers;
  }

  /// Map entity type and operation to API endpoint.
  Uri? _getSyncUri(String entityType, String operation) {
    final base = '${AppConstants.apiBaseUrl}/${AppConstants.apiVersion}';
    switch (entityType) {
      case 'messages':
        return Uri.parse('$base/messages/sync');
      case 'sos_alerts':
        return Uri.parse('$base/alerts/sync');
      case 'zones':
        return Uri.parse('$base/zones/sync');
      default:
        return null;
    }
  }
}
