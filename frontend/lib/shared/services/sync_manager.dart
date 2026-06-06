import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import '../../core/constants.dart';
import 'offline_storage.dart';

/// Manages data synchronization between local storage and cloud backend.
/// Implements a three-state sync model: offline -> pending -> synced.
class SyncManager {
  static final SyncManager _instance = SyncManager._internal();
  factory SyncManager() => _instance;
  SyncManager._internal();

  final OfflineStorageService _storage = OfflineStorageService();
  final Connectivity _connectivity = Connectivity();

  Timer? _syncTimer;
  bool _isSyncing = false;
  StreamSubscription? _connectivitySubscription;

  // Cached sync status for synchronous access in build methods
  bool _cachedIsOnline = false;
  int _cachedPendingCount = 0;

  /// Whether the device is currently online (cached value).
  bool get isOnline => _cachedIsOnline;

  /// Whether a sync is currently in progress.
  bool get isSyncing => _isSyncing;

  /// Number of items pending sync (cached value).
  int get pendingCount => _cachedPendingCount;

  /// Initialize the sync manager and start listening for connectivity changes.
  Future<void> initialize() async {
    // Cache initial connectivity state
    final initialResult = await _connectivity.checkConnectivity();
    _cachedIsOnline = initialResult != ConnectivityResult.none;
    _cachedPendingCount = (await _storage.getPendingSyncItems()).length;

    // Listen for connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((result) {
      _cachedIsOnline = result != ConnectivityResult.none;
      if (_cachedIsOnline) {
        _performSync();
      }
    });

    // Start periodic sync
    _startPeriodicSync();
  }

  /// Start periodic sync timer.
  void _startPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(
      Duration(minutes: AppConstants.syncIntervalMinutes),
      (_) => _performSync(),
    );
  }

  /// Perform synchronization with the cloud backend.
  Future<SyncResult> _performSync() async {
    if (_isSyncing) return SyncResult(isSyncing: true);
    _isSyncing = true;
    // Refresh cached pending count
    _cachedPendingCount = (await _storage.getPendingSyncItems()).length;

    try {
      // Check connectivity
      final connectivityResult = await _connectivity.checkConnectivity();
      final hasInternet = connectivityResult != ConnectivityResult.none;

      if (!hasInternet) {
        return SyncResult(synced: false, reason: 'No internet connection');
      }

      // Pull new data from cloud
      final pullResult = await _pullFromCloud();

      // Push pending offline data
      final pushResult = await _pushToCloud();

      // Resolve conflicts
      await _resolveConflicts();

      return SyncResult(
        synced: true,
        pulled: pullResult,
        pushed: pushResult,
      );
    } catch (e) {
      return SyncResult(synced: false, reason: e.toString());
    } finally {
      _isSyncing = false;
      // Refresh cached values after sync completes
      _cachedPendingCount = (await _storage.getPendingSyncItems()).length;
      final connectivityResult = await _connectivity.checkConnectivity();
      _cachedIsOnline = connectivityResult != ConnectivityResult.none;
    }
  }

  /// Pull new data from the cloud backend.
  Future<int> _pullFromCloud() async {
    int pulledCount = 0;
    final lastSync = await _storage.getSetting(AppConstants.keyLastSync);
    final lastSyncTimestamp = lastSync as int? ?? 0;

    try {
      // Pull messages
      final messagesResponse = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/${AppConstants.apiVersion}/messages/sync')
            .replace(queryParameters: {
          'since': lastSyncTimestamp.toString(),
          'limit': AppConstants.batchSyncSize.toString(),
        }),
        headers: {'Content-Type': 'application/json'},
      );

      if (messagesResponse.statusCode == 200) {
        final data = json.decode(messagesResponse.body) as List;
        for (final msg in data) {
          await _storage.saveMessage(msg as Map<String, dynamic>);
          pulledCount++;
        }
      }

      // Pull SOS alerts
      final sosResponse = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/${AppConstants.apiVersion}/alerts/sync')
            .replace(queryParameters: {
          'since': lastSyncTimestamp.toString(),
        }),
        headers: {'Content-Type': 'application/json'},
      );

      if (sosResponse.statusCode == 200) {
        final data = json.decode(sosResponse.body) as List;
        for (final alert in data) {
          await _storage.saveSOSAlert(alert as Map<String, dynamic>);
          pulledCount++;
        }
      }

      // Pull zones
      final zonesResponse = await http.get(
        Uri.parse('${AppConstants.apiBaseUrl}/${AppConstants.apiVersion}/zones/sync')
            .replace(queryParameters: {
          'since': lastSyncTimestamp.toString(),
        }),
        headers: {'Content-Type': 'application/json'},
      );

      if (zonesResponse.statusCode == 200) {
        final data = json.decode(zonesResponse.body) as List;
        for (final zone in data) {
          await _storage.saveZone(zone as Map<String, dynamic>);
          pulledCount++;
        }
      }

      // Update last sync timestamp
      await _storage.saveSetting(AppConstants.keyLastSync, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      // Log error but don't fail the entire sync
      print('Pull sync error: $e');
    }

    return pulledCount;
  }

  /// Push pending offline data to the cloud backend.
  Future<int> _pushToCloud() async {
    int pushedCount = 0;
    final pendingItems = await _storage.getPendingSyncItems();

    for (final item in pendingItems) {
      try {
        final entityType = item['entity_type'] as String;
        final entityId = item['entity_id'] as String;
        final operation = item['operation'] as String;
        final syncId = item['id'] as int;

        // Determine the API endpoint based on entity type
        String endpoint;
        switch (entityType) {
          case 'messages':
            endpoint = '/messages';
            break;
          case 'sos_alerts':
            endpoint = '/alerts';
            break;
          default:
            await _storage.markSyncCompleted(syncId);
            continue;
        }

        // Get the full entity data
        final entity = await _storage.getById(entityType, entityId);
        if (entity == null) {
          await _storage.markSyncCompleted(syncId);
          continue;
        }

        // Send to cloud
        final response = await http.post(
          Uri.parse('${AppConstants.apiBaseUrl}/${AppConstants.apiVersion}$endpoint'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(entity),
        );

        if (response.statusCode == 200 || response.statusCode == 201) {
          await _storage.markSyncCompleted(syncId);
          pushedCount++;
        } else {
          await _storage.incrementSyncRetry(syncId);
        }
      } catch (e) {
        await _storage.incrementSyncRetry(item['id'] as int);
        print('Push sync error for item ${item['id']}: $e');
      }
    }

    return pushedCount;
  }

  /// Resolve conflicts between local and cloud data.
  Future<void> _resolveConflicts() async {
    // Last-write-wins strategy for simplicity
    // In production, implement CRDT or version vectors
  }

  /// Manually trigger a sync.
  Future<SyncResult> triggerSync() async {
    return await _performSync();
  }

  /// Get the current sync status.
  Future<SyncStatus> getSyncStatus() async {
    final pendingCount = (await _storage.getPendingSyncItems()).length;
    final lastSync = await _storage.getSetting(AppConstants.keyLastSync);
    final connectivityResult = await _connectivity.checkConnectivity();
    final isOnline = connectivityResult != ConnectivityResult.none;

    // Update cached values
    _cachedIsOnline = isOnline;
    _cachedPendingCount = pendingCount;

    return SyncStatus(
      isOnline: isOnline,
      isSyncing: _isSyncing,
      pendingCount: pendingCount,
      lastSyncTimestamp: lastSync as int?,
    );
  }

  /// Dispose of the sync manager.
  void dispose() {
    _syncTimer?.cancel();
    _connectivitySubscription?.cancel();
  }
}

/// Result of a sync operation.
class SyncResult {
  final bool synced;
  final bool isSyncing;
  final String? reason;
  final int pulled;
  final int pushed;

  SyncResult({
    this.synced = false,
    this.isSyncing = false,
    this.reason,
    this.pulled = 0,
    this.pushed = 0,
  });
}

/// Current sync status.
class SyncStatus {
  final bool isOnline;
  final bool isSyncing;
  final int pendingCount;
  final int? lastSyncTimestamp;

  SyncStatus({
    required this.isOnline,
    required this.isSyncing,
    required this.pendingCount,
    this.lastSyncTimestamp,
  });

  String get lastSyncFormatted {
    if (lastSyncTimestamp == null) return 'Never';
    final diff = DateTime.now().millisecondsSinceEpoch - lastSyncTimestamp!;
    if (diff < 60000) return 'Just now';
    if (diff < 3600000) return '${diff ~/ 60000}m ago';
    if (diff < 86400000) return '${diff ~/ 3600000}h ago';
    return '${diff ~/ 86400000}d ago';
  }
}
