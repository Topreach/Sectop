import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants.dart';
import '../../../shared/services/encryption.dart';
import '../../../shared/services/offline_storage.dart';
import '../../../shared/services/backend_api.dart';

/// Authentication service supporting offline-first authentication
/// with emergency bypass mode for disaster situations.
class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final OfflineStorageService _storage = OfflineStorageService();
  final EncryptionService _encryption = EncryptionService();

  http.Client _client = http.Client();

  @visibleForTesting
  void setClient(http.Client client) => _client = client;

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
  /// Online-first: requires internet for authentication.
  /// Falls back to offline credentials only if server is unreachable.
  Future<AuthResult> login(String email, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Try online authentication first
      final response = await _client.post(
        Uri.parse('${AppConstants.apiBaseUrl}/${AppConstants.apiVersion}/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email, 'password': password}),
      ).timeout(Duration(seconds: AppConstants.apiTimeout));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await _handleSuccessfulAuth(data);
        return AuthResult.success({'email': email});
      }

      // Server responded with an error (e.g. 401 Unauthorized)
      String serverError = 'Invalid email or password';
      try {
        final errorBody = json.decode(response.body);
        if (errorBody is Map && errorBody.containsKey('error')) {
          serverError = errorBody['error'] as String;
        }
      } catch (_) {}
      _currentUser = null;
      _isLoading = false;
      notifyListeners();
      return AuthResult.failure(serverError);
    } catch (_) {
      // Network error — try offline authentication as fallback
      debugPrint('Online auth failed (no internet), trying offline fallback...');
    }

    // Offline authentication fallback (only reached when server is unreachable)
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
          _isLoading = false;
          notifyListeners();
          return AuthResult.success(user, offline: true);
        }
      }
    }

    _isLoading = false;
    notifyListeners();
    return AuthResult.failure('No internet connection. Offline credentials not found.');
  }

  /// Register a new user.
  /// Register a new user.
  /// Online-first: requires internet for registration.
  /// Falls back to offline storage only if server is unreachable.
  Future<AuthResult> register(UserProfile profile, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Try online registration
      final response = await _client.post(
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
        return AuthResult.success({'email': profile.email});
      }

      // Server responded with an error
      String serverError = 'Registration failed';
      try {
        final errorBody = json.decode(response.body);
        if (errorBody is Map && errorBody.containsKey('error')) {
          serverError = errorBody['error'] as String;
        }
      } catch (_) {}
      _currentUser = null;
      _isLoading = false;
      notifyListeners();
      return AuthResult.failure(serverError);
    } catch (_) {
      debugPrint('Online registration failed (no internet), saving offline...');
    }

    // Offline registration fallback (only when server is unreachable)
    final userMap = profile.toMap();
    userMap['auth_hash'] = _encryption.hashString(password);
    userMap['created_at'] = DateTime.now().millisecondsSinceEpoch;
    userMap['updated_at'] = DateTime.now().millisecondsSinceEpoch;

    await _storage.insert('users', userMap);
    _currentUser = profile;
    await _storage.saveSetting(AppConstants.keyUserId, profile.id);
    _isLoading = false;
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
  /// Backend returns fields at the top level (userId, name, email, etc.)
  /// Map them to the format expected by UserProfile.fromMap.
  Future<void> _handleSuccessfulAuth(Map<String, dynamic> data) async {
    final token = data['token'] as String?;

    // Map backend response fields to UserProfile format
    final userData = <String, dynamic>{
      'id': data['userId'] ?? data['id'],
      'name': data['name'] ?? 'Unknown',
      'email': data['email'],
      'phone': data['phone'],
      'role': data['role']?.toString().toLowerCase() ?? 'citizen',
      'public_key': data['publicKey'] ?? data['public_key'],
      'created_at': data['created_at'] ?? DateTime.now().millisecondsSinceEpoch,
    };

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
  /// Saves locally immediately, then attempts server sync in background.
  /// If server is unreachable, queues the update for later sync.
  Future<void> updateProfile(UserProfile updatedProfile) async {
    final map = updatedProfile.toMap();
    map['updated_at'] = DateTime.now().millisecondsSinceEpoch;

    await _storage.update('users', map,
        where: 'id = ?',
        whereArgs: [updatedProfile.id]);

    _currentUser = updatedProfile;
    notifyListeners();

    // Attempt server sync in background
    unawaited(_syncProfileToServer(updatedProfile));
  }

  /// Sync profile update to server. Queues for retry if offline.
  Future<void> _syncProfileToServer(UserProfile updatedProfile) async {
    try {
      final token = await _storage.getSensitiveSetting(AppConstants.keyAuthToken);
      if (token == null || token.isEmpty) return; // Offline/emergency user

      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

      final body = json.encode({
        'name': updatedProfile.name,
        'email': updatedProfile.email,
        'phone': updatedProfile.phone,
      });

      final response = await http.put(
        Uri.parse('${AppConstants.apiBaseUrl}/${AppConstants.apiVersion}/auth/users/${updatedProfile.id}'),
        headers: headers,
        body: body,
      ).timeout(Duration(seconds: AppConstants.apiTimeout));

      if (response.statusCode == 200 || response.statusCode == 204) {
        debugPrint('AuthService: Profile synced to server');
      } else {
        debugPrint('AuthService: Profile sync returned ${response.statusCode}, queuing for retry');
        await _storage.logSync('users', updatedProfile.id, AppConstants.opUpdate, map);
      }
    } catch (e) {
      debugPrint('AuthService: Profile sync failed (offline), queuing for retry: $e');
      try {
        await _storage.logSync('users', updatedProfile.id, AppConstants.opUpdate, map);
      } catch (_) {}
    }
  }

  /// Get user by ID from local storage.
  Future<UserProfile?> getUserById(String userId) async {
    final data = await _storage.getById('users', userId);
    if (data != null) {
      return UserProfile.fromMap(data);
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Password Reset (Store Compliance)
  // ---------------------------------------------------------------------------

  /// Request a password reset email.
  Future<AuthResult> forgotPassword(String email) async {
    try {
      final api = BackendApi();
      await api.forgotPassword(email);
      return AuthResult.success({'email': email});
    } catch (e) {
      debugPrint('forgotPassword error: $e');
      return AuthResult.failure('Failed to send reset email. Check your internet connection.');
    }
  }

  /// Reset password using the token from the email.
  Future<AuthResult> resetPassword(String token, String newPassword) async {
    try {
      final api = BackendApi();
      final response = await api.resetPassword(token, newPassword);
      return AuthResult.success(response);
    } catch (e) {
      debugPrint('resetPassword error: $e');
      return AuthResult.failure('Failed to reset password. The link may have expired.');
    }
  }

  // ---------------------------------------------------------------------------
  // Account Deletion (Store Compliance)
  // ---------------------------------------------------------------------------

  /// Request account deletion (30-day grace period).
  Future<AuthResult> requestAccountDeletion() async {
    if (_currentUser == null) {
      return AuthResult.failure('No user logged in');
    }
    try {
      final api = BackendApi();
      await api.requestAccountDeletion(_currentUser!.id);
      return AuthResult.success({'userId': _currentUser!.id});
    } catch (e) {
      debugPrint('requestAccountDeletion error: $e');
      return AuthResult.failure('Failed to request deletion. Try again later.');
    }
  }

  /// Cancel a pending account deletion request.
  Future<AuthResult> cancelAccountDeletion() async {
    if (_currentUser == null) {
      return AuthResult.failure('No user logged in');
    }
    try {
      final api = BackendApi();
      await api.cancelAccountDeletion(_currentUser!.id);
      return AuthResult.success({'userId': _currentUser!.id});
    } catch (e) {
      debugPrint('cancelAccountDeletion error: $e');
      return AuthResult.failure('Failed to cancel deletion. Try again later.');
    }
  }

  /// Permanently delete the account and log out.
  Future<AuthResult> deleteAccount() async {
    if (_currentUser == null) {
      return AuthResult.failure('No user logged in');
    }
    try {
      final api = BackendApi();
      await api.deleteAccount(_currentUser!.id);
      // Clear local data
      await logout();
      return AuthResult.success({'deleted': true});
    } catch (e) {
      debugPrint('deleteAccount error: $e');
      return AuthResult.failure('Failed to delete account. Try again later.');
    }
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
