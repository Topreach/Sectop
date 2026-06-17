import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../modules/sos/services/sos_service.dart';
import 'covert_mode_manager.dart';

/// Service to handle hardware-based SOS triggers (Stealth Mode).
///
/// In a kidnapping scenario, the user might not be able to look at the screen.
/// This service listens for specific hardware events to trigger a silent SOS.
///
/// Supports two modes:
/// - **Stealth Mode**: SOS is silent (no UI shown) but still broadcast publicly.
/// - **Covert Mode**: SOS is sent ONLY to emergency contacts and verified
///   responders via backend recipient filtering. No public broadcast.
///   Covert mode implies stealth (silent) behavior.
class HardwareTriggerService {
  static final HardwareTriggerService _instance = HardwareTriggerService._internal();
  factory HardwareTriggerService() => _instance;
  HardwareTriggerService._internal();

  static const String _stealthModePrefKey = 'stealth_mode_enabled';
  static const String _channelName = 'com.dangeremergence/hardware_triggers';
  static const String _panicEvent = 'panic_sequence_detected';

  bool _isStealthModeEnabled = false;
  StreamSubscription? _volumeSubscription;
  EventChannel? _eventChannel;
  StreamSubscription? _panicSubscription;

  bool get isStealthModeEnabled => _isStealthModeEnabled;

  /// Initialize hardware triggers.
  /// Loads persisted stealth mode state and registers native hardware listeners.
  Future<void> initialize() async {
    // Load persisted stealth mode state
    final prefs = await SharedPreferences.getInstance();
    _isStealthModeEnabled = prefs.getBool(_stealthModePrefKey) ?? false;
    debugPrint('HardwareTriggerService: Initialized, stealth mode = $_isStealthModeEnabled');

    // Register native hardware button listener via EventChannel
    _eventChannel = const EventChannel(_channelName);
    _panicSubscription = _eventChannel!
        .receiveBroadcastStream()
        .listen((event) {
      if (event == _panicEvent) {
        triggerPanicSOS();
      }
    }, onError: (error) {
      debugPrint('HardwareTriggerService: EventChannel error: $error');
    });

    debugPrint('HardwareTriggerService: Native hardware listener registered');
  }

  /// Toggle stealth mode. When enabled, SOS triggers will not show any UI.
  /// The setting is persisted to SharedPreferences.
  void setStealthMode(bool enabled) {
    _isStealthModeEnabled = enabled;
    debugPrint('HardwareTriggerService: Stealth mode ${enabled ? 'ON' : 'OFF'}');

    // Persist to SharedPreferences (fire-and-forget)
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool(_stealthModePrefKey, enabled);
    });
  }

  /// Triggered when the "Panic" hardware sequence is detected.
  /// (e.g., Volume Up + Volume Down pressed together, or 5 quick presses)
  ///
  /// If Covert Mode is active, the SOS is sent as a covert alert (recipient
  /// filtering on the backend — no public broadcast). Covert mode implies
  /// silent behavior regardless of the stealth mode setting.
  Future<void> triggerPanicSOS() async {
    debugPrint('HardwareTriggerService: Panic sequence detected!');

    // Provide haptic feedback so the user knows the trigger worked without looking.
    await HapticFeedback.vibrate();

    // Check if Covert Mode is active — if so, send as covert (implies silent)
    final covertMode = CovertModeManager();
    final isCovert = covertMode.isCovertModeEnabled;

    // Trigger SOS via the SOSService.
    // If stealth mode is ON, the SOSService should handle it silently.
    // If covert mode is ON, the alert is only sent to trusted recipients.
    final sosService = SOSService();
    await sosService.sendSOS(
      alertType: 'silent_panic',
      description: 'Triggered via hardware buttons',
      isSilent: _isStealthModeEnabled || isCovert,
      isCovert: isCovert,
    );
  }

  /// Clean up resources.
  void dispose() {
    _panicSubscription?.cancel();
    _volumeSubscription?.cancel();
  }
}
