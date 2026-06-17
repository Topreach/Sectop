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
///
/// Messages are now local-first (stored on device only) — they are NOT synced
/// to the server to prevent data accumulation. Only alerts and zones are synced.
/// However, broadcasts, tip-offs, and radio broadcasts created offline ARE synced
/// when connectivity is restored.
class SyncManager extends ChangeNotifier {
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

  /// Number of items pending sync across all tables.
  int get pendingCount => _cachedPendingCount;
  int _cachedPendingCount = 0;

  /// Timestamp of the last successful sync.
  DateTime? get lastSyncTime => _lastSyncTime;

  /// Initialize the sync manager.
  Future<void> initialize() async {
    await _refreshPendingCount();
    debugPrint('SyncManager: Initialized (foreground-only, local-first mode)');
  }

  /// Refresh the cached pending count from all offline tables.
  Future<void> _refreshPendingCount() async {
    try {
      int count = 0;

      // Count sync_log items with status = 'pending'
      final pendingLogs = await _storage.query('sync_log',
          where: 'status = ?',
          whereArgs: ['pending']);
      count += pendingLogs.length;

      // Count messages with sync_state = 'offline'
      final offlineMessages = await _storage.query(AppConstants.tableMessages,
          where: 'sync_state = ?',
          whereArgs: [AppConstants.msgSyncOffline]);
      count += offlineMessages.length;

      _cachedPendingCount = count;
    } catch (e) {
      debugPrint('SyncManager: Failed to refresh pending count: $e');
    }
  }

  /// Trigger a full sync cycle — push pending items, then pull updates.
  /// Returns true if sync completed successfully.
  Future<bool> triggerSync() async {
    if (_isSyncing) return false;
    _isSyncing = true;
    notifyListeners();

    try {
      await _pushToCloud();
      await _pullFromCloud();
      await _refreshPendingCount();
      _lastSyncTime = DateTime.now();
      _isOnline = true;
      debugPrint('SyncManager: Sync completed at $_lastSyncTime');
      notifyListeners();
      return true;
    } catch (e) {
      _isOnline = false;
      debugPrint('SyncManager: Sync failed: $e');
      notifyListeners();
      return false;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// Push pending offline items to the cloud.
  /// Processes both sync_log entries and items with sync_state='offline'.
  Future<void> _pushToCloud() async {
    // Phase 1: Process sync_log entries (created by _logSync)
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
        debugPrint('SyncManager: Push failed for sync_log item ${item['id']}: $e');
        await _storage.update('sync_log', {
          'retry_count': (item['retry_count'] as int? ?? 0) + 1,
          'last_attempt': DateTime.now().millisecondsSinceEpoch,
        }, where: 'id = ?', whereArgs: [item['id']]);
      }
    }

    // Phase 2: Process items with sync_state='offline' from messages table
    // These are broadcasts, tip-offs, and walkie-talkie scans saved offline
    final offlineItems = await _storage.query(AppConstants.tableMessages,
        where: 'sync_state = ?',
        whereArgs: [AppConstants.msgSyncOffline],
        orderBy: 'created_at ASC',
        limit: AppConstants.batchSyncSize);

    for (final item in offlineItems) {
      try {
        final messageType = item['message_type'] as String? ?? 'text';
        final uri = _getOfflineSyncUri(messageType);
        if (uri == null) continue;

        final headers = await _authHeaders();
        final body = json.encode(item);
        final response = await http.post(
          uri,
          headers: headers,
          body: body,
        ).timeout(Duration(seconds: AppConstants.apiTimeout));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          // Mark as synced locally
          await _storage.update(AppConstants.tableMessages, {
            'sync_state': AppConstants.msgSyncSynced,
            'synced_at': DateTime.now().millisecondsSinceEpoch,
          }, where: 'id = ?', whereArgs: [item['id']]);
        }
      } catch (e) {
        debugPrint('SyncManager: Push failed for offline item ${item['id']}: $e');
      }
    }
  }

  /// Pull latest data from the cloud.
  /// Messages are NOT pulled from server — they are local-first.
  /// Only alerts and zones are synced.
  Future<void> _pullFromCloud() async {
    final since = _lastSyncTime?.millisecondsSinceEpoch ?? 0;
    final headers = await _authHeaders();

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

    // Pull active broadcasts
    try {
      final broadcastResponse = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/${AppConstants.apiVersion}/broadcasts/active'),
        headers: headers,
      ).timeout(Duration(seconds: AppConstants.apiTimeout));

      if (broadcastResponse.statusCode == 200) {
        final data = json.decode(broadcastResponse.body);
        if (data is List) {
          for (final broadcast in data) {
            final bMap = broadcast as Map<String, dynamic>;
            bMap['message_type'] = 'broadcast';
            await _storage.upsert(AppConstants.tableMessages, bMap);
          }
        }
      }
    } catch (e) {
      debugPrint('SyncManager: Pull broadcasts failed: $e');
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

  /// Map entity type and operation to API endpoint (for sync_log items).
  Uri? _getSyncUri(String entityType, String operation) {
    final base = '${AppConstants.apiBaseUrl}/${AppConstants.apiVersion}';
    switch (entityType) {
      case 'messages':
        return Uri.parse('$base/messages');
      case 'sos_alerts':
        return Uri.parse('$base/alerts/sync');
      case 'zones':
        return Uri.parse('$base/zones/sync');
      default:
        return null;
    }
  }

  /// Map message_type to API endpoint for offline-synced items.
  Uri? _getOfflineSyncUri(String messageType) {
    final base = '${AppConstants.apiBaseUrl}/${AppConstants.apiVersion}';
    switch (messageType) {
      case 'broadcast':
        return Uri.parse('$base/broadcasts');
      case 'tip_off':
        return Uri.parse('$base/tips');
      case 'radio_broadcast':
        return Uri.parse('$base/radio/broadcast');
      case 'walkie_talkie_scan':
        return Uri.parse('$base/ai/analyze-audio');
      case 'text':
      case 'alert':
      case 'sos':
        return Uri.parse('$base/messages');
      default:
        return null;
    }
  }
}
