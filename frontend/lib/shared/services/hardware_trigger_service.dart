import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../modules/sos/services/sos_service.dart';

/// Service to handle hardware-based SOS triggers (Stealth Mode).
///
/// In a kidnapping scenario, the user might not be able to look at the screen.
/// This service listens for specific hardware events to trigger a silent SOS.
class HardwareTriggerService {
  static final HardwareTriggerService _instance = HardwareTriggerService._internal();
  factory HardwareTriggerService() => _instance;
  HardwareTriggerService._internal();

  bool _isStealthModeEnabled = false;
  StreamSubscription? _volumeSubscription;

  bool get isStealthModeEnabled => _isStealthModeEnabled;

  /// Initialize hardware triggers.
  /// NOTE: This would ideally use a package like 'hardware_buttons' or
  /// 'flutter_volume_key_listener' to listen for volume events.
  Future<void> initialize() async {
    // Placeholder for actual hardware button listener initialization.
    debugPrint('HardwareTriggerService: Initialized');
  }

  /// Toggle stealth mode. When enabled, SOS triggers will not show any UI.
  void setStealthMode(bool enabled) {
    _isStealthModeEnabled = enabled;
    debugPrint('HardwareTriggerService: Stealth mode ${enabled ? 'ON' : 'OFF'}');
  }

  /// Triggered when the "Panic" hardware sequence is detected.
  /// (e.g., Volume Up + Volume Down pressed together, or 5 quick presses)
  Future<void> triggerPanicSOS() async {
    debugPrint('HardwareTriggerService: Panic sequence detected!');

    // Provide haptic feedback so the user knows the trigger worked without looking.
    await HapticFeedback.vibrate();

    // Trigger SOS via the SOSService.
    // If stealth mode is ON, the SOSService should handle it silently.
    final sosService = SOSService();
    await sosService.sendSOS(
      alertType: 'silent_panic',
      description: 'Triggered via hardware buttons',
      isSilent: _isStealthModeEnabled,
    );
  }
}
