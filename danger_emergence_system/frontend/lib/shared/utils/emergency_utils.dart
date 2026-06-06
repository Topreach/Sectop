import 'dart:math';

/// Utility functions for emergency-related calculations and formatting.

class EmergencyUtils {
  /// Priority levels matching the backend constants.
  static const int priorityLow = 0;
  static const int priorityMedium = 1;
  static const int priorityHigh = 2;
  static const int priorityCritical = 3;

  /// Get priority label text.
  static String getPriorityLabel(int priority) {
    switch (priority) {
      case priorityCritical:
        return 'CRITICAL';
      case priorityHigh:
        return 'HIGH';
      case priorityMedium:
        return 'MEDIUM';
      case priorityLow:
        return 'LOW';
      default:
        return 'UNKNOWN';
    }
  }

  /// Get priority color.
  static int getPriorityColor(int priority) {
    switch (priority) {
      case priorityCritical:
        return 0xFFD32F2F; // Red
      case priorityHigh:
        return 0xFFFFA726; // Orange
      case priorityMedium:
        return 0xFFFFF176; // Yellow
      case priorityLow:
        return 0xFF66BB6A; // Green
      default:
        return 0xFF9E9E9E; // Grey
    }
  }

  /// Format a timestamp for display.
  static String formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }

  /// Generate a unique emergency ID.
  static String generateEmergencyId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(99999);
    return 'EMG-$timestamp-$random';
  }

  /// Calculate severity score based on multiple factors.
  static double calculateSeverityScore({
    required int priority,
    required double? distanceToResponder,
    required bool hasMedicalNeeds,
    required bool isInDangerZone,
    int hoursSinceReported = 0,
  }) {
    double score = 0;

    // Priority factor (0-40 points)
    score += (priority / priorityCritical) * 40;

    // Distance factor (0-20 points) - closer = more urgent
    if (distanceToResponder != null) {
      score += max(0, 20 - (distanceToResponder / 100));
    }

    // Medical needs (15 points)
    if (hasMedicalNeeds) score += 15;

    // Danger zone (15 points)
    if (isInDangerZone) score += 15;

    // Time factor (0-10 points) - older = less urgent
    score += max(0, 10 - hoursSinceReported);

    return min(100, score);
  }

  /// Get emergency alert type emoji/icon name.
  static String getAlertTypeIcon(String alertType) {
    switch (alertType.toLowerCase()) {
      case 'medical emergency':
        return 'medical_services';
      case 'fire':
        return 'local_fire_department';
      case 'natural disaster':
        return 'thunderstorm';
      case 'violence/attack':
        return 'gpp_bad';
      case 'trapped':
        return 'lock';
      case 'lost':
        return 'explore';
      case 'structural damage':
        return 'house';
      default:
        return 'warning_amber';
    }
  }

  /// Get battery-efficient location update interval based on battery level.
  static Duration getLocationUpdateInterval(double batteryLevel) {
    if (batteryLevel > 0.5) {
      return const Duration(seconds: 30);
    } else if (batteryLevel > 0.2) {
      return const Duration(minutes: 2);
    } else {
      return const Duration(minutes: 5);
    }
  }
}
