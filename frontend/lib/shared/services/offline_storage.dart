import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants.dart';

/// Manages all offline data storage for the Danger Emergence System.
/// Uses SQLite for structured data and SharedPreferences for settings.
class OfflineStorageService {
  static final OfflineStorageService _instance = OfflineStorageService._internal();
  factory OfflineStorageService() => _instance;
  OfflineStorageService._internal();

  Database? _database;
  bool _initialized = false;

  /// Initialize the database and create all required tables.
  Future<void> initialize() async {
    if (_initialized) return;

    // SQLite is not available on web; skip database initialization.
    // SharedPreferences-based methods (getSetting, saveSetting) still work.
    if (!kIsWeb) {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, AppConstants.dbName);

      _database = await openDatabase(
        path,
        version: AppConstants.dbVersion,
        onCreate: _createTables,
        onUpgrade: _upgradeTables,
      );
    }

    _initialized = true;
  }

  Future<void> _createTables(Database db, int version) async {
    // Users table
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        email TEXT,
        phone TEXT,
        role TEXT NOT NULL DEFAULT 'citizen',
        public_key TEXT,
        emergency_contacts TEXT,
        medical_info TEXT,
        last_seen INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // Messages table
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        sender_id TEXT NOT NULL,
        receiver_id TEXT,
        content TEXT NOT NULL,
        message_type TEXT NOT NULL DEFAULT 'text',
        priority INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'pending',
        sync_state TEXT NOT NULL DEFAULT 'offline',
        latitude REAL,
        longitude REAL,
        created_at INTEGER NOT NULL,
        delivered_at INTEGER,
        read_at INTEGER,
        expires_at INTEGER,
        FOREIGN KEY (sender_id) REFERENCES users(id)
      )
    ''');

    // SOS alerts table
    await db.execute('''
      CREATE TABLE sos_alerts (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        alert_type TEXT NOT NULL,
        description TEXT,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        accuracy REAL,
        status TEXT NOT NULL DEFAULT 'active',
        priority INTEGER NOT NULL DEFAULT 3,
        mesh_relayed INTEGER NOT NULL DEFAULT 0,
        acknowledged_by TEXT,
        resolved_at INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users(id)
      )
    ''');

    // Zones table (safe/danger zones)
    await db.execute('''
      CREATE TABLE zones (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        description TEXT,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        radius REAL NOT NULL DEFAULT 100.0,
        geometry TEXT,
        severity TEXT,
        status TEXT NOT NULL DEFAULT 'active',
        created_by TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        expires_at INTEGER
      )
    ''');

    // Mesh peers table
    await db.execute('''
      CREATE TABLE mesh_peers (
        id TEXT PRIMARY KEY,
        device_id TEXT NOT NULL UNIQUE,
        name TEXT,
        user_id TEXT,
        last_seen INTEGER NOT NULL,
        signal_strength INTEGER,
        connection_type TEXT,
        is_gateway INTEGER NOT NULL DEFAULT 0,
        public_key TEXT
      )
    ''');

    // Incidents table
    await db.execute('''
      CREATE TABLE incidents (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT,
        type TEXT NOT NULL,
        severity TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        status TEXT NOT NULL DEFAULT 'reported',
        reported_by TEXT,
        media_paths TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        resolved_at INTEGER
      )
    ''');

    // Cache table for offline resources
    await db.execute('''
      CREATE TABLE resource_cache (
        id TEXT PRIMARY KEY,
        resource_type TEXT NOT NULL,
        resource_url TEXT,
        local_path TEXT,
        data BLOB,
        size_bytes INTEGER,
        checksum TEXT,
        downloaded_at INTEGER NOT NULL,
        expires_at INTEGER
      )
    ''');

    // Sync log table
    await db.execute('''
      CREATE TABLE sync_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        payload TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        retry_count INTEGER NOT NULL DEFAULT 0,
        last_attempt INTEGER,
        created_at INTEGER NOT NULL
      )
    ''');

    // Create indexes
    await db.execute('CREATE INDEX idx_messages_sender ON messages(sender_id)');
    await db.execute('CREATE INDEX idx_messages_status ON messages(status)');
    await db.execute('CREATE INDEX idx_messages_sync ON messages(sync_state)');
    await db.execute('CREATE INDEX idx_sos_alerts_status ON sos_alerts(status)');
    await db.execute('CREATE INDEX idx_sos_alerts_location ON sos_alerts(latitude, longitude)');
    await db.execute('CREATE INDEX idx_zones_type ON zones(type)');
    await db.execute('CREATE INDEX idx_zones_location ON zones(latitude, longitude)');
    await db.execute('CREATE INDEX idx_incidents_status ON incidents(status)');
    await db.execute('CREATE INDEX idx_sync_log_status ON sync_log(status)');
  }

  Future<void> _upgradeTables(Database db, int oldVersion, int newVersion) async {
    // Handle future migrations here
  }

  // ==================== Generic CRUD Operations ====================

  /// Insert a record into the specified table.
  Future<int> insert(String table, Map<String, dynamic> data) async {
    final db = _database;
    if (db == null) return 0; // Web: SQLite not available
    return await db.insert(table, data, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Update records matching the where clause.
  Future<int> update(String table, Map<String, dynamic> data, {required String where, List<dynamic>? whereArgs}) async {
    final db = _database;
    if (db == null) return 0; // Web: SQLite not available
    return await db.update(table, data, where: where, whereArgs: whereArgs);
  }

  /// Delete records matching the where clause.
  Future<int> delete(String table, {required String where, List<dynamic>? whereArgs}) async {
    final db = _database;
    if (db == null) return 0; // Web: SQLite not available
    return await db.delete(table, where: where, whereArgs: whereArgs);
  }

  /// Query records from the specified table.
  Future<List<Map<String, dynamic>>> query(String table,
      {String? where, List<dynamic>? whereArgs, String? orderBy, int? limit, int? offset}) async {
    final db = _database;
    if (db == null) return []; // Web: SQLite not available, return empty results
    return await db.query(table,
        where: where, whereArgs: whereArgs, orderBy: orderBy, limit: limit, offset: offset);
  }

  /// Get a single record by id.
  Future<Map<String, dynamic>?> getById(String table, String id) async {
    final db = _database;
    if (db == null) return null; // Web: SQLite not available
    final results = await db.query(table, where: 'id = ?', whereArgs: [id]);
    return results.isNotEmpty ? results.first : null;
  }

  // ==================== Message Operations ====================

  /// Save a message to local storage.
  Future<void> saveMessage(Map<String, dynamic> message) async {
    await insert('messages', message);
    await _logSync('messages', message['id'], 'create', message);
  }

  /// Get pending (unsent) messages.
  Future<List<Map<String, dynamic>>> getPendingMessages() async {
    return await query('messages',
        where: 'sync_state = ? AND status = ?',
        whereArgs: ['offline', 'pending'],
        orderBy: 'priority DESC, created_at ASC');
  }

  /// Get messages for a specific user.
  Future<List<Map<String, dynamic>>> getMessagesForUser(String userId,
      {int limit = 50, int offset = 0}) async {
    return await query('messages',
        where: 'sender_id = ? OR receiver_id = ?',
        whereArgs: [userId, userId],
        orderBy: 'created_at DESC',
        limit: limit,
        offset: offset);
  }

  /// Mark message as delivered.
  Future<void> markMessageDelivered(String messageId) async {
    await update('messages',
        {'status': 'delivered', 'delivered_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [messageId]);
  }

  // ==================== SOS Operations ====================

  /// Save an SOS alert locally.
  Future<void> saveSOSAlert(Map<String, dynamic> alert) async {
    await insert('sos_alerts', alert);
    await _logSync('sos_alerts', alert['id'], 'create', alert);
  }

  /// Get active SOS alerts.
  Future<List<Map<String, dynamic>>> getActiveSOSAlerts() async {
    return await query('sos_alerts',
        where: 'status = ?',
        whereArgs: ['active'],
        orderBy: 'priority DESC, created_at DESC');
  }

  /// Resolve an SOS alert.
  Future<void> resolveSOSAlert(String alertId, {String? resolvedBy}) async {
    await update('sos_alerts', {
      'status': 'resolved',
      'acknowledged_by': resolvedBy,
      'resolved_at': DateTime.now().millisecondsSinceEpoch,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, where: 'id = ?', whereArgs: [alertId]);
  }

  // ==================== Zone Operations ====================

  /// Save a zone (safe/danger/evacuation).
  Future<void> saveZone(Map<String, dynamic> zone) async {
    await insert('zones', zone);
  }

  /// Get zones near a location.
  Future<List<Map<String, dynamic>>> getZonesNearLocation(
      double latitude, double longitude, {double radiusKm = 5.0}) async {
    // Approximate bounding box calculation
    final latDelta = radiusKm / 111.0;
    final lonDelta = radiusKm / (111.0 * _cosDegrees(latitude));

    return await query('zones',
        where: 'latitude BETWEEN ? AND ? AND longitude BETWEEN ? AND ? AND status = ?',
        whereArgs: [
          latitude - latDelta,
          latitude + latDelta,
          longitude - lonDelta,
          longitude + lonDelta,
          'active'
        ]);
  }

  double _cosDegrees(double degrees) {
    return cos(_degreesToRadians(degrees));
  }

  double _degreesToRadians(double degrees) {
    return degrees * (3.141592653589793 / 180.0);
  }

  // ==================== Peer Operations ====================

  /// Save or update a mesh peer.
  Future<void> upsertPeer(Map<String, dynamic> peer) async {
    final existing = await query('mesh_peers',
        where: 'device_id = ?', whereArgs: [peer['device_id']]);
    if (existing.isNotEmpty) {
      await update('mesh_peers', peer, where: 'device_id = ?', whereArgs: [peer['device_id']]);
    } else {
      await insert('mesh_peers', peer);
    }
  }

  /// Get recently seen peers.
  Future<List<Map<String, dynamic>>> getRecentPeers({int minutes = 30}) async {
    final cutoff = DateTime.now().millisecondsSinceEpoch - (minutes * 60 * 1000);
    return await query('mesh_peers',
        where: 'last_seen > ?',
        whereArgs: [cutoff],
        orderBy: 'signal_strength DESC');
  }

  // ==================== Sync Operations ====================

  Future<void> _logSync(String entityType, String entityId, String operation, Map<String, dynamic>? payload) async {
    await insert('sync_log', {
      'entity_type': entityType,
      'entity_id': entityId,
      'operation': operation,
      'payload': payload != null ? payload.toString() : null,
      'status': 'pending',
      'retry_count': 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Get pending sync items.
  Future<List<Map<String, dynamic>>> getPendingSyncItems({int limit = 50}) async {
    return await query('sync_log',
        where: 'status = ? AND retry_count < ?',
        whereArgs: ['pending', AppConstants.apiRetryCount],
        orderBy: 'created_at ASC',
        limit: limit);
  }

  /// Mark sync item as completed.
  Future<void> markSyncCompleted(int syncId) async {
    await update('sync_log', {'status': 'completed'}, where: 'id = ?', whereArgs: [syncId]);
  }

  /// Increment retry count for a sync item.
  Future<void> incrementSyncRetry(int syncId) async {
    final item = await query('sync_log', where: 'id = ?', whereArgs: [syncId]);
    if (item.isNotEmpty) {
      final retryCount = (item.first['retry_count'] as int) + 1;
      final status = retryCount >= AppConstants.apiRetryCount ? 'failed' : 'pending';
      await update('sync_log', {
        'retry_count': retryCount,
        'status': status,
        'last_attempt': DateTime.now().millisecondsSinceEpoch,
      }, where: 'id = ?', whereArgs: [syncId]);
    }
  }

  // ==================== Settings Operations ====================

  /// Save a setting to SharedPreferences.
  Future<void> saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is String) {
      await prefs.setString(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is double) {
      await prefs.setDouble(key, value);
    } else if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is List<String>) {
      await prefs.setStringList(key, value);
    }
  }

  /// Get a setting from SharedPreferences.
  Future<dynamic> getSetting(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.get(key);
  }

  /// Remove a setting.
  Future<void> removeSetting(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  // ==================== Cleanup ====================

  /// Clean up expired data.
  Future<void> cleanupExpiredData() async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // Delete expired messages
    await delete('messages',
        where: 'expires_at IS NOT NULL AND expires_at < ?',
        whereArgs: [now]);

    // Delete expired zones
    await delete('zones',
        where: 'expires_at IS NOT NULL AND expires_at < ?',
        whereArgs: [now]);

    // Delete old sync logs (keep last 7 days)
    final weekAgo = now - (7 * 24 * 60 * 60 * 1000);
    await delete('sync_log',
        where: 'created_at < ?',
        whereArgs: [weekAgo]);
  }

  /// Close the database connection.
  Future<void> close() async {
    await _database?.close();
    _database = null;
    _initialized = false;
  }
}
