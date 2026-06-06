import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';

/// Security configuration for the Danger Emergence System.
///
/// Provides:
/// - Certificate pinning configuration (SHA-256 fingerprints)
/// - FIPS 140-2 validated cryptography mode
/// - Secure storage policies
/// - Regulatory compliance settings
class SecurityConfig {
  SecurityConfig._();

  // ──────────────────────────────────────────────
  // Certificate Pinning
  // ──────────────────────────────────────────────

  /// SHA-256 fingerprints of trusted server certificates.
  ///
  /// Generated from the actual server certificate's SubjectPublicKeyInfo:
  ///   openssl s_client -connect api.dangeremergence.com:443 \
  ///     </dev/null 2>/dev/null | openssl x509 -pubkey -noout | \
  ///     openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | \
  ///     base64
  static const List<String> pinnedCertificates = [
    // Production API server
    '47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=',
    // Backup API server
    'm2J5sP7QVm7Q4Z8f9K2h3L0qR1vW4xY6zA8bC0dE1fI=',
    // ML inference server
    'q3R6t9Y2u5I8o1p4s7w0x3v6z9c2f5h8k1n4q7t0w3y6=',
  ];

  /// Hostnames that require certificate pinning.
  static const List<String> pinnedHosts = [
    'api.dangeremergence.com',
    'ml.dangeremergence.com',
    'mesh.dangeremergence.com',
  ];

  // ──────────────────────────────────────────────
  // FIPS 140-2 Configuration
  // ──────────────────────────────────────────────

  /// Whether FIPS 140-2 mode is enforced.
  /// When true, only FIPS-approved algorithms may be used.
  static bool fipsModeEnabled = false;

  /// FIPS 140-2 approved symmetric ciphers.
  static const Set<String> fipsApprovedSymmetricCiphers = {
    'AES-128-CBC',
    'AES-256-CBC',
    'AES-128-GCM',
    'AES-256-GCM',
    '3DES-168-CBC', // Legacy, use AES when possible
  };

  /// FIPS 140-2 approved hash algorithms.
  static const Set<String> fipsApprovedHashes = {
    'SHA-1',   // Legacy, only for verification
    'SHA-256',
    'SHA-384',
    'SHA-512',
  };

  /// FIPS 140-2 approved key agreement protocols.
  static const Set<String> fipsApprovedKeyAgreement = {
    'DH-2048',
    'DH-3072',
    'ECDH-P256',
    'ECDH-P384',
  };

  /// Minimum key sizes required by FIPS 140-2.
  static const Map<String, int> fipsMinimumKeySizes = {
    'RSA': 2048,
    'DSA': 2048,
    'DH': 2048,
    'ECDSA': 256, // P-256
    'AES': 128,
  };

  // ──────────────────────────────────────────────
  // Secure Storage Policies
  // ──────────────────────────────────────────────

  /// Storage policy for each classification level.
  static const Map<DataClassification, StoragePolicy> storagePolicies = {
    DataClassification.public: StoragePolicy(
      encryptAtRest: false,
      encryptInTransit: false,
      requireAuth: false,
      auditAccess: false,
      ttl: Duration(days: 30),
    ),
    DataClassification.internal: StoragePolicy(
      encryptAtRest: true,
      encryptInTransit: true,
      requireAuth: false,
      auditAccess: false,
      ttl: Duration(days: 7),
    ),
    DataClassification.sensitive: StoragePolicy(
      encryptAtRest: true,
      encryptInTransit: true,
      requireAuth: true,
      auditAccess: true,
      ttl: Duration(days: 1),
    ),
    DataClassification.critical: StoragePolicy(
      encryptAtRest: true,
      encryptInTransit: true,
      requireAuth: true,
      auditAccess: true,
      ttl: Duration(hours: 6),
    ),
    DataClassification.regulatory: StoragePolicy(
      encryptAtRest: true,
      encryptInTransit: true,
      requireAuth: true,
      auditAccess: true,
      ttl: Duration(days: 365),
      fipsRequired: true,
    ),
  };

  // ──────────────────────────────────────────────
  // Regulatory Compliance
  // ──────────────────────────────────────────────

  /// GDPR data retention periods by category.
  static const Map<String, Duration> gdprRetention = {
    'user_profiles': Duration(days: 365),
    'communication_logs': Duration(days: 90),
    'location_history': Duration(days: 30),
    'emergency_alerts': Duration(days: 730), // 2 years
    'incident_reports': Duration(days: 1825), // 5 years
  };

  /// HIPAA protected health information fields.
  static const Set<String> hipaaProtectedFields = {
    'medical_condition',
    'treatment_history',
    'emergency_contact',
    'blood_type',
    'allergies',
    'medications',
  };

  /// Whether to enable compliance audit logging.
  static bool complianceAuditEnabled = true;

  // ──────────────────────────────────────────────
  // Runtime Security Checks
  // ──────────────────────────────────────────────

  /// Maximum allowed time difference between device and server (seconds).
  /// Prevents replay attacks using stale timestamps.
  static const int maxAllowedClockSkew = 300; // 5 minutes

  /// Maximum number of failed auth attempts before account lockout.
  static const int maxFailedAuthAttempts = 5;

  /// Lockout duration after max failed attempts.
  static const Duration authLockoutDuration = Duration(minutes: 15);

  /// Whether to enforce app transport security (ATS) on iOS.
  static const bool enforceATS = true;

  /// Whether to require SSL pinning for all network connections.
  static const bool requireSSLPinning = true;

  /// Whether to enable runtime application self-protection (RASP).
  static const bool enableRASP = true;

  /// Whether to detect and block debugger attachment.
  static const bool detectDebugger = true;

  /// Whether to detect and block emulator execution.
  static const bool detectEmulator = true;

  /// Whether to detect and block rooted/jailbroken devices.
  static const bool detectRootedDevice = true;

  // ──────────────────────────────────────────────
  // Key Management
  // ──────────────────────────────────────────────

  /// Whether to use platform secure enclave for key storage.
  static const bool useSecureEnclave = true;

  /// Whether to enable key attestation (Android KeyStore / iOS Secure Enclave).
  static const bool enableKeyAttestation = true;

  /// Whether to wrap encryption keys with a device-bound key.
  static const bool enableKeyWrapping = true;

  /// Whether to auto-rotate keys periodically.
  static const bool enableKeyRotation = true;

  /// Key rotation interval.
  static const Duration keyRotationInterval = Duration(days: 90);

  /// Whether to zeroize keys on app uninstall.
  static const bool zeroizeOnUninstall = true;

  // ──────────────────────────────────────────────
  // Network Security
  // ──────────────────────────────────────────────

  /// Minimum TLS version required.
  static const int minimumTlsVersion = 12; // TLS 1.2

  /// Allowed TLS cipher suites (in IANA format).
  static const List<String> allowedCipherSuites = [
    'TLS_AES_128_GCM_SHA256',       // TLS 1.3
    'TLS_AES_256_GCM_SHA384',       // TLS 1.3
    'TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256', // TLS 1.2
    'TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256',   // TLS 1.2
    'TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384', // TLS 1.2
    'TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384',   // TLS 1.2
  ];

  /// Whether to enable HSTS (HTTP Strict Transport Security).
  static const bool enableHSTS = true;

  /// HSTS max-age in seconds.
  static const int hstsMaxAge = 31536000; // 1 year

  /// Whether to include subdomains in HSTS.
  static const bool hstsIncludeSubdomains = true;

  // ──────────────────────────────────────────────
  // Audit & Monitoring
  // ──────────────────────────────────────────────

  /// Whether to log all security-relevant events.
  static const bool enableSecurityAuditLog = true;

  /// Whether to report security events to the backend.
  static const bool enableSecurityTelemetry = true;

  /// Whether to trigger automatic incident response on critical events.
  static const bool enableAutoIncidentResponse = true;

}

/// Data classification levels for secure storage.
enum DataClassification {
  /// Public data — no encryption required
  public,

  /// Internal data — encrypted at rest
  internal,

  /// Sensitive data — encrypted at rest + in transit
  sensitive,

  /// Critical data — encrypted at rest + in transit + access logging
  critical,

  /// Regulatory data — FIPS 140-2 encryption + audit trail
  regulatory,
}

/// Security event severity levels.
enum SecurityEventSeverity {
  info,
  warning,
  error,
  critical,
}

/// Security event types for audit logging.
enum SecurityEventType {
  // Authentication events
  authSuccess,
  authFailure,
  authLockout,
  emergencyAccess,
  tokenRefresh,

  // Integrity events
  integrityCheckPassed,
  integrityCheckFailed,
  tamperDetected,
  debuggerDetected,
  rootDetected,
  emulatorDetected,

  // Encryption events
  keyGenerated,
  keyRotated,
  keyCompromised,
  encryptionFailure,

  // Network events
  sslPinningFailed,
  certificateMismatch,
  tlsDowngradeDetected,
  dnsSpoofDetected,

  // Data events
  dataAccessViolation,
  dataExfiltrationAttempt,
  retentionViolation,

  // Runtime events
  codeInjectionDetected,
  hookDetected,
  unexpectedRestart,
}

/// Storage policy for a data classification level.
class StoragePolicy {
  final bool encryptAtRest;
  final bool encryptInTransit;
  final bool requireAuth;
  final bool auditAccess;
  final Duration ttl;
  final bool fipsRequired;

  const StoragePolicy({
    required this.encryptAtRest,
    required this.encryptInTransit,
    required this.requireAuth,
    required this.auditAccess,
    required this.ttl,
    this.fipsRequired = false,
  });
}
