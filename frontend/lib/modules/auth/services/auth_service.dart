import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants.dart';
import '../../../shared/services/encryption.dart';
import '../../../shared/services/offline_storage.dart';

/// Authentication service supporting offline-first authentication
/// with emergency bypass mode for disaster situations.
class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final OfflineStorageService _storage = OfflineStorageService();
  final EncryptionService _encryption = EncryptionService();

  UserProfile? _currentUser;
  bool _isLoading = false;
  bool _isEmergencyMode = false;

  UserProfile? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _currentUser != null;
  bool get isEmergencyMode => _isEmergencyMode;
  bool get isResponder => _currentUser?.role == AppConstants.roleResponder;
  bool get isCoordinator => _currentUser?.role == AppConstants.roleCoordinator;

  /// Initialize auth service and check for existing session.
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Check for existing offline credentials
      final userId = await _storage.getSetting(AppConstants.keyUserId);
      final authToken = await _storage.getSensitiveSetting(AppConstants.keyAuthToken);

      if (userId != null && authToken != null) {
        // Load user profile from local storage
        final userData = await _storage.getById('users', userId as String);
        if (userData != null) {
          _currentUser = UserProfile.fromMap(userData);
        }
      }
    } catch (e) {
      debugPrint('Auth initialization error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Authenticate user with email and password.
  /// Falls back to offline credentials if no internet.
  Future<AuthResult> login(String email, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Try online authentication first
      final response = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/${AppConstants.apiVersion}/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email, 'password': password}),
      ).timeout(Duration(seconds: AppConstants.apiTimeout));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await _handleSuccessfulAuth(data);
        return AuthResult.success(data['user']);
      }
    } catch (_) {
      // Network error - try offline authentication
      debugPrint('Online auth failed, trying offline...');
    }

    // Offline authentication
    final users = await _storage.query('users',
        where: 'email = ?',
        whereArgs: [email]);

    if (users.isNotEmpty) {
      final user = users.first;
      final storedHash = user['auth_hash'] as String?;
      if (storedHash != null) {
        final inputHash = _encryption.hashString(password);
        if (storedHash == inputHash) {
          _currentUser = UserProfile.fromMap(user);
          await _storage.saveSetting(AppConstants.keyUserId, user['id']);
          notifyListeners();
          return AuthResult.success(user);
        }
      }
    }

    _isLoading = false;
    notifyListeners();
    return AuthResult.failure('Invalid credentials or no internet connection');
  }

  /// Register a new user.
  Future<AuthResult> register(UserProfile profile, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Try online registration
      final response = await http.post(
        Uri.parse('${AppConstants.apiBaseUrl}/${AppConstants.apiVersion}/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          ...profile.toMap(),
          'password': password,
        }),
      ).timeout(Duration(seconds: AppConstants.apiTimeout));

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        await _handleSuccessfulAuth(data);
        return AuthResult.success(data['user']);
      }
    } catch (_) {
      debugPrint('Online registration failed, saving offline...');
    }

    // Offline registration - store locally for later sync
    final userMap = profile.toMap();
    userMap['auth_hash'] = _encryption.hashString(password);
    userMap['created_at'] = DateTime.now().millisecondsSinceEpoch;
    userMap['updated_at'] = DateTime.now().millisecondsSinceEpoch;

    await _storage.insert('users', userMap);
    _currentUser = profile;
    await _storage.saveSetting(AppConstants.keyUserId, profile.id);
    notifyListeners();

    return AuthResult.success(userMap, offline: true);
  }

  /// Emergency bypass - one-tap access for disaster situations.
  Future<AuthResult> emergencyAccess() async {
    _isLoading = true;
    _isEmergencyMode = true;
    notifyListeners();

    // Create or retrieve emergency profile
    final emergencyToken = await _storage.getSensitiveSetting(AppConstants.keyEmergencyToken);
    
    if (emergencyToken != null) {
      // Restore existing emergency session
      final userData = await _storage.query('users',
          where: 'role = ? AND id LIKE ?',
          whereArgs: ['citizen', 'emergency_%']);
      
      if (userData.isNotEmpty) {
        _currentUser = UserProfile.fromMap(userData.first);
        notifyListeners();
        return AuthResult.success(userData.first);
      }
    }

    // Create new emergency profile
    final emergencyId = 'emergency_${DateTime.now().millisecondsSinceEpoch}';
    final emergencyProfile = UserProfile(
      id: emergencyId,
      name: 'Emergency User',
      role: AppConstants.roleCitizen,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    final userMap = emergencyProfile.toMap();
    userMap['created_at'] = DateTime.now().millisecondsSinceEpoch;
    userMap['updated_at'] = DateTime.now().millisecondsSinceEpoch;

    await _storage.insert('users', userMap);
    await _storage.saveSensitiveSetting(AppConstants.keyEmergencyToken, emergencyId);
    await _storage.saveSetting(AppConstants.keyUserId, emergencyId);

    _currentUser = emergencyProfile;
    notifyListeners();

    return AuthResult.success(userMap, offline: true);
  }

  /// Handle successful authentication response.
  Future<void> _handleSuccessfulAuth(Map<String, dynamic> data) async {
    final userData = data['user'] as Map<String, dynamic>;
    final token = data['token'] as String?;

    // Save to local storage
    await _storage.insert('users', {
      ...userData,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });

    await _storage.saveSetting(AppConstants.keyUserId, userData['id']);
    if (token != null) {
      await _storage.saveSensitiveSetting(AppConstants.keyAuthToken, token);
    }

    _currentUser = UserProfile.fromMap(userData);
  }

  /// Logout the current user.
  Future<void> logout() async {
    _currentUser = null;
    _isEmergencyMode = false;
    await _storage.removeSetting(AppConstants.keyUserId);
    await _storage.removeSensitiveSetting(AppConstants.keyAuthToken);
    notifyListeners();
  }

  /// Update user profile.
  Future<void> updateProfile(UserProfile updatedProfile) async {
    final map = updatedProfile.toMap();
    map['updated_at'] = DateTime.now().millisecondsSinceEpoch;

    await _storage.update('users', map,
        where: 'id = ?',
        whereArgs: [updatedProfile.id]);

    _currentUser = updatedProfile;
    notifyListeners();
  }

  /// Get user by ID from local storage.
  Future<UserProfile?> getUserById(String userId) async {
    final data = await _storage.getById('users', userId);
    if (data != null) {
      return UserProfile.fromMap(data);
    }
    return null;
  }
}

/// User profile model.
class UserProfile {
  final String id;
  final String name;
  final String? email;
  final String? phone;
  final String role;
  final String? publicKey;
  final List<String> emergencyContacts;
  final String? medicalInfo;
  final int? lastSeen;
  final int createdAt;

  UserProfile({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.role = AppConstants.roleCitizen,
    this.publicKey,
    this.emergencyContacts = const [],
    this.medicalInfo,
    this.lastSeen,
    required this.createdAt,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'] as String,
      name: map['name'] as String? ?? 'Unknown',
      email: map['email'] as String?,
      phone: map['phone'] as String?,
      role: map['role'] as String? ?? AppConstants.roleCitizen,
      publicKey: map['public_key'] as String?,
      emergencyContacts: map['emergency_contacts'] != null
          ? List<String>.from(json.decode(map['emergency_contacts'] as String))
          : [],
      medicalInfo: map['medical_info'] as String?,
      lastSeen: map['last_seen'] as int?,
      createdAt: map['created_at'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'role': role,
      'public_key': publicKey,
      'emergency_contacts': json.encode(emergencyContacts),
      'medical_info': medicalInfo,
      'last_seen': lastSeen ?? DateTime.now().millisecondsSinceEpoch,
      'created_at': createdAt,
    };
  }
}

/// Result of an authentication operation.
class AuthResult {
  final bool success;
  final Map<String, dynamic>? userData;
  final String? error;
  final bool isOffline;

  AuthResult._({
    required this.success,
    this.userData,
    this.error,
    this.isOffline = false,
  });

  factory AuthResult.success(Map<String, dynamic> userData, {bool offline = false}) {
    return AuthResult._(success: true, userData: userData, isOffline: offline);
  }

  factory AuthResult.failure(String error) {
    return AuthResult._(success: false, error: error);
  }
}
