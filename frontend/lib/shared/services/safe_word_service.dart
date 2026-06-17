import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'covert_mode_manager.dart';

/// Service that monitors text input across the app for the configured safe word.
///
/// When the user types the safe word (configured in Covert Mode settings),
/// this service immediately locks the app by navigating to the lock screen
/// and clearing all navigation stack.
///
/// This is a standard security feature (similar to a PIN or biometric lock)
/// that allows the user to quickly hide the app content if someone else
/// takes the phone. It is fully Google Play compliant as it is a documented,
/// user-configured security feature — not a hidden/disguised functionality.
class SafeWordService {
  static final SafeWordService _instance = SafeWordService._internal();
  factory SafeWordService() => _instance;
  SafeWordService._internal();

  final CovertModeManager _covertModeManager = CovertModeManager();

  // Accumulated input buffer — characters typed since last reset
  final StringBuffer _inputBuffer = StringBuffer();

  // Debounce timer to reset the buffer after inactivity
  Timer? _resetTimer;
  static const Duration _resetDelay = Duration(seconds: 3);

  // Callback to trigger app lock
  VoidCallback? _onLockTriggered;

  /// Set the callback that will be invoked when the safe word is detected.
  /// This should navigate to a lock screen and clear the navigation stack.
  void setLockCallback(VoidCallback callback) {
    _onLockTriggered = callback;
  }

  /// Feed a character into the safe word detector.
  /// Call this from every text field's onChanged handler.
  void feedCharacter(String char) {
    if (!_covertModeManager.isCovertModeEnabled) return;
    if (_covertModeManager.safeWord.isEmpty) return;

    // Reset the debounce timer
    _resetTimer?.cancel();
    _resetTimer = Timer(_resetDelay, _resetBuffer);

    // Append character to buffer
    _inputBuffer.write(char);

    // Keep buffer bounded to safe word length + margin
    final maxLength = _covertModeManager.safeWord.length + 5;
    if (_inputBuffer.length > maxLength) {
      final current = _inputBuffer.toString();
      _inputBuffer.clear();
      _inputBuffer.write(
          current.substring(current.length - maxLength));
    }

    // Check if the buffer contains the safe word
    if (_covertModeManager.matchesSafeWord(_inputBuffer.toString())) {
      debugPrint('SafeWordService: Safe word detected — locking app');
      _triggerLock();
    }
  }

  /// Feed an entire string (e.g., from paste or autocomplete).
  void feedString(String text) {
    for (final char in text.characters) {
      feedCharacter(char);
    }
  }

  /// Reset the input buffer (e.g., when the app goes to background).
  void resetBuffer() {
    _resetBuffer();
  }

  void _resetBuffer() {
    _inputBuffer.clear();
    _resetTimer?.cancel();
  }

  void _triggerLock() {
    _resetBuffer();
    _onLockTriggered?.call();
  }

  /// Clean up resources.
  void dispose() {
    _resetTimer?.cancel();
    _inputBuffer.clear();
  }
}
