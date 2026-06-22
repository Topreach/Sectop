import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../core/constants.dart';
import 'backend_api.dart';
import 'offline_storage.dart';

/// Service that integrates Firebase Cloud Messaging (FCM) push notifications
/// with the Sectop emergency system.
///
/// Responsibilities:
///   1. Initialize Firebase and FCM
///   2. Request notification permissions (Android 13+)
///   3. Obtain and refresh the FCM registration token
///   4. Send the FCM token to the backend for server-side push delivery
///   5. Handle incoming push messages (foreground, background, terminated)
///   6. Display push notifications as local notifications via flutter_local_notifications
///
/// The backend [FcmPushService.java] uses these tokens to deliver:
///   - SOS alert notifications to nearby responders
///   - Covert alert notifications to emergency contacts
///   - Acknowledgement notifications when someone responds to an SOS
///   - Resolution notifications when an SOS is resolved
///   - Threat alert broadcasts to users in affected areas
class PushNotificationService {
  static final PushNotificationService _instance =
      PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  final BackendApi _api = BackendApi();
  final OfflineStorageService _storage = OfflineStorageService();
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _firebaseInitialized = false;
  String? _currentToken;

  /// Whether the service has been initialized.
  bool get isInitialized => _initialized;

  /// The current FCM registration token, if available.
  String? get currentToken => _currentToken;

  /// Initialize Firebase, FCM, and local notifications.
  ///
  /// Safe to call multiple times — subsequent calls are no-ops.
  Future<void> initialize() async {
    if (_initialized) return;
    debugPrint('PushNotificationService: Initializing...');

    try {
      // Step 1: Initialize Firebase
      await Firebase.initializeApp(
        options: Firebase.app().options, // Uses google-services.json
      );
      _firebaseInitialized = true;
      debugPrint('PushNotificationService: Firebase initialized');
    } catch (e) {
      debugPrint('PushNotificationService: Firebase init failed: $e');
      // Non-fatal — app works without push notifications
      _initialized = true;
      return;
    }

    // Step 2: Initialize local notifications channel
    await _initLocalNotifications();

    // Step 3: Set up FCM message handlers
    _setupMessageHandlers();

    // Step 4: Request notification permission (Android 13+)
    await _requestPermission();

    // Step 5: Get and register the FCM token
    await _refreshToken();

    _initialized = true;
    debugPrint('PushNotificationService: Initialization complete');
  }

  /// Initialize flutter_local_notifications for displaying push payloads.
  Future<void> _initLocalNotifications() async {
    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: false, // Already requested via FCM
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTap,
      );
      debugPrint('PushNotificationService: Local notifications initialized');
    } catch (e) {
      debugPrint('PushNotificationService: Local notifications init failed: $e');
    }
  }

  /// Set up handlers for incoming FCM messages in all app states.
  void _setupMessageHandlers() {
    final messaging = FirebaseMessaging.instance;

    // ── Foreground messages ──
    // When the app is in the foreground, FCM does NOT display a notification
    // automatically. We must show it ourselves via flutter_local_notifications.
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // ── Background message handler ──
    // When the app is in the background, FCM may display the notification
    // automatically (if the payload includes a 'notification' section).
    // We still handle 'data' messages here.
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    // ── App opened from notification ──
    // When the user taps a notification while the app is in the background.
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationOpenedApp);

    // ── App opened from terminated state ──
    // When the app was terminated and the user taps a notification.
    messaging.getInitialMessage().then(_handleInitialMessage);

    // ── Token refresh ──
    // FCM tokens can be rotated by the Firebase SDK at any time.
    messaging.onTokenRefresh.listen(_onTokenRefresh);

    debugPrint('PushNotificationService: Message handlers registered');
  }

  /// Request notification permission on Android 13+.
  /// On older Android versions, permission is granted at install time.
  Future<void> _requestPermission() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: true, // Emergency alerts can bypass silent mode
        provisional: false,
        sound: true,
      );

      debugPrint(
        'PushNotificationService: Permission status: ${settings.authorizationStatus}',
      );
    } catch (e) {
      debugPrint('PushNotificationService: Permission request failed: $e');
    }
  }

  /// Get the current FCM token and register it with the backend.
  Future<void> _refreshToken() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        _currentToken = token;
        debugPrint('PushNotificationService: FCM token obtained');
        await _registerTokenWithBackend(token);
      }
    } catch (e) {
      debugPrint('PushNotificationService: Failed to get FCM token: $e');
    }
  }

  /// Called when the FCM token is refreshed by the Firebase SDK.
  Future<void> _onTokenRefresh(String token) async {
    debugPrint('PushNotificationService: FCM token refreshed');
    _currentToken = token;
    await _registerTokenWithBackend(token);
  }

  /// Send the FCM token to the backend so it can send push notifications.
  ///
  /// Uses the [BackendApi] to call the user profile update endpoint
  /// with the 'fcmToken' field. The backend [AuthController.updateUser]
  /// saves it to the [User.fcmToken] column.
  Future<void> _registerTokenWithBackend(String token) async {
    try {
      // Get the current user ID from local storage
      final userId = await _storage.getSetting(AppConstants.keyUserId);
      if (userId == null || userId.isEmpty) {
        debugPrint('PushNotificationService: No user logged in, skipping token registration');
        return;
      }

      // Get the auth token for the request
      final authToken = await _storage.getSensitiveSetting(AppConstants.keyAuthToken);
      if (authToken == null || authToken.isEmpty) {
        debugPrint('PushNotificationService: No auth token, skipping token registration');
        return;
      }

      await _api.registerFcmToken(userId, token);
      debugPrint('PushNotificationService: FCM token registered with backend');
    } catch (e) {
      debugPrint('PushNotificationService: Failed to register FCM token: $e');
      // Non-fatal — will retry on next token refresh or app restart
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Incoming Message Handlers
  // ─────────────────────────────────────────────────────────────────────────

  /// Handle a push message received while the app is in the foreground.
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    debugPrint('PushNotificationService: Foreground message: ${message.messageId}');

    // Extract notification data
    final notification = message.notification;
    final data = message.data;

    if (notification != null) {
      await _showLocalNotification(
        id: message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch.hashCode,
        title: notification.title ?? 'Sectop Alert',
        body: notification.body ?? '',
        payload: json.encode(data),
      );
    } else if (data.isNotEmpty) {
      // Data-only message — construct notification from payload
      final title = data['title'] as String? ?? 'Sectop Alert';
      final body = data['body'] as String? ?? '';
      await _showLocalNotification(
        id: data['alertId']?.hashCode ?? DateTime.now().millisecondsSinceEpoch.hashCode,
        title: title,
        body: body,
        payload: json.encode(data),
      );
    }
  }

  /// Handle a notification tap when the app was in the background.
  Future<void> _handleNotificationOpenedApp(RemoteMessage message) async {
    debugPrint('PushNotificationService: App opened from notification: ${message.messageId}');
    // The app is now in the foreground — navigate based on payload
    _navigateFromPayload(message.data);
  }

  /// Handle the initial message that launched the app from a terminated state.
  Future<void> _handleInitialMessage(RemoteMessage? message) async {
    if (message != null) {
      debugPrint('PushNotificationService: App launched from terminated notification: ${message.messageId}');
      _navigateFromPayload(message.data);
    }
  }

  /// Handle a local notification tap (from flutter_local_notifications).
  void _onNotificationTap(NotificationResponse response) {
    if (response.payload != null && response.payload!.isNotEmpty) {
      try {
        final data = json.decode(response.payload!) as Map<String, dynamic>;
        _navigateFromPayload(data);
      } catch (e) {
        debugPrint('PushNotificationService: Failed to parse notification payload: $e');
      }
    }
  }

  /// Navigate to the appropriate screen based on push notification payload.
  void _navigateFromPayload(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    final alertId = data['alertId'] as String?;

    debugPrint('PushNotificationService: Navigate from payload — type=$type, alertId=$alertId');

    // TODO: Implement navigation to specific screens based on notification type.
    // For now, the app will open to its default screen.
    // Future enhancement: Use a navigation service/route to deep-link to:
    //   - 'sos_alert' / 'covert_alert' → SOS detail screen
    //   - 'acknowledgement' → SOS detail screen showing who acknowledged
    //   - 'resolution' → SOS detail screen showing resolved status
    //   - 'threat_alert' → Threat awareness / map screen
  }

  /// Display a local notification using flutter_local_notifications.
  Future<void> _showLocalNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'emergency_alerts', // Channel ID
        'Emergency Alerts', // Channel name
        channelDescription: 'Critical safety alerts and SOS notifications',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        icon: '@mipmap/ic_launcher',
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications.show(
        id,
        title,
        body,
        details,
        payload: payload,
      );
    } catch (e) {
      debugPrint('PushNotificationService: Failed to show local notification: $e');
    }
  }

  /// Public method to register the FCM token after login.
  ///
  /// Called by [AuthService] after a successful login to ensure the
  /// FCM token is associated with the authenticated user.
  Future<void> registerTokenAfterLogin(String userId, String authToken) async {
    if (!_firebaseInitialized) {
      debugPrint('PushNotificationService: Firebase not initialized, cannot register token');
      return;
    }
    await _refreshToken();
  }

  /// Public method to clear the FCM token on logout.
  Future<void> clearToken() async {
    _currentToken = null;
  }
}

/// Top-level background message handler for FCM.
///
/// This must be a top-level function (not a method) because the
/// Firebase plugin runs it in a separate isolate.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  debugPrint('PushNotificationService (background): ${message.messageId}');

  // In background isolate, we need to initialize Firebase again
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('PushNotificationService (background): Firebase init failed: $e');
    return;
  }

  // For background messages with notification payload, the system
  // displays the notification automatically. For data-only messages,
  // we could use flutter_local_notifications, but the background
  // isolate has limited capabilities.
  final data = message.data;
  if (data.isNotEmpty) {
    debugPrint('PushNotificationService (background): Data: $data');
  }
}
