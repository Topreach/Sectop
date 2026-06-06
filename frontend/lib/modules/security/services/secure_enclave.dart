import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';
import '../../../shared/services/encryption.dart';
import 'security_config.dart';

/// Platform secure enclave integration for key management.
///
/// Provides:
/// - Android KeyStore integration (hardware-backed keys)
/// - iOS Secure Enclave integration
/// - Key attestation
/// - Key wrapping and rotation
/// - Biometric authentication binding
class SecureEnclaveService {
  static final SecureEnclaveService _instance = SecureEnclaveService._();
  factory SecureEnclaveService() => _instance;
  SecureEnclaveService._();

  final EncryptionService _encryption = EncryptionService();
  bool _isAvailable = false;
  SecureEnclaveType _enclaveType = SecureEnclaveType.software;
  Uint8List? _deviceKey;

  /// Whether a hardware secure enclave is available.
  bool get isAvailable => _isAvailable;

  /// The type of secure enclave available.
  SecureEnclaveType get enclaveType => _enclaveType;

  /// Initialize the secure enclave service.
  Future<void> initialize() async {
    try {
      // Detect platform secure enclave
      if (defaultTargetPlatform == TargetPlatform.android) {
        _enclaveType = await _detectAndroidKeyStore();
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        _enclaveType = await _detectIosSecureEnclave();
      }

      _isAvailable = _enclaveType != SecureEnclaveType.software;

      // Generate or retrieve device-bound key
      if (SecurityConfig.enableKeyWrapping) {
        _deviceKey = await _getOrCreateDeviceKey();
      }

      debugPrint('SecureEnclave: $_enclaveType available=$_isAvailable');
    } catch (e) {
      debugPrint('SecureEnclave init error: $e');
      _isAvailable = false;
      _enclaveType = SecureEnclaveType.software;
    }
  }

  /// Generate a key pair inside the secure enclave.
  ///
  /// The private key never leaves the secure hardware.
  Future<KeyPairReference> generateKeyPair({
    required String keyAlias,
    bool requireBiometrics = false,
    bool requireUserPresence = false,
  }) async {
    try {
      if (_isAvailable) {
        // Use platform secure enclave
        const channel = MethodChannel('com.dangeremergence/security');
        final result = await channel.invokeMethod<Map<String, dynamic>>(
          'generateKeyPair',
          {
            'keyAlias': keyAlias,
            'requireBiometrics': requireBiometrics,
            'requireUserPresence': requireUserPresence,
            'keySize': SecurityConfig.fipsMinimumKeySizes['RSA'] ?? 2048,
          },
        );

        if (result != null) {
          return KeyPairReference(
            keyAlias: keyAlias,
            publicKeyPem: result['publicKey'] as String? ?? '',
            isHardwareBacked: true,
            requiresBiometrics: requireBiometrics,
            attestationData: result['attestation'] as Uint8List?,
          );
        }
      }

      // Fallback to software key generation
      final pair = await _encryption.generateKeyPair();
      final publicKeyPem = _encryption.publicKeyToBase64(
        pair.publicKey as RSAPublicKey,
      );

      return KeyPairReference(
        keyAlias: keyAlias,
        publicKeyPem: publicKeyPem,
        isHardwareBacked: false,
        requiresBiometrics: requireBiometrics,
      );
    } catch (e) {
      debugPrint('Key generation error: $e');
      rethrow;
    }
  }

  /// Sign data using a key stored in the secure enclave.
  Future<Uint8List> sign({
    required String keyAlias,
    required Uint8List data,
    bool requireUserPresence = false,
  }) async {
    if (_isAvailable) {
      try {
        const channel = MethodChannel('com.dangeremergence/security');
        final result = await channel.invokeMethod<Uint8List>(
          'sign',
          {
            'keyAlias': keyAlias,
            'data': data,
            'requireUserPresence': requireUserPresence,
          },
        );

        if (result != null) return result;
      } catch (e) {
        debugPrint('Secure enclave signing error: $e');
      }
    }

    // Software fallback: use device-bound key
    if (_deviceKey != null) {
      final hmac = Hmac(sha256, _deviceKey!);
      final digest = hmac.convert(data);
      return Uint8List.fromList(digest.bytes);
    }

    throw StateError('No signing key available');
  }

  /// Verify a signature created by a secure enclave key.
  Future<bool> verify({
    required String keyAlias,
    required Uint8List data,
    required Uint8List signature,
    required String publicKeyPem,
  }) async {
    try {
      if (_isAvailable) {
        const channel = MethodChannel('com.dangeremergence/security');
        final result = await channel.invokeMethod<bool>(
          'verify',
          {
            'keyAlias': keyAlias,
            'data': data,
            'signature': signature,
          },
        );

        if (result != null) return result;
      }

      // Software verification
      final publicKey = _encryption.publicKeyFromBase64(publicKeyPem);
      final signer = RSASigner(SHA256Digest(), '0609608648016503040201');
      signer.init(false, PublicKeyParameter<RSAPublicKey>(publicKey));

      final sig = RSASignature(signature);
      return signer.verifySignature(
        Uint8List.fromList(utf8.encode(utf8.decode(data))),
        sig,
      );
    } catch (e) {
      debugPrint('Signature verification error: $e');
      return false;
    }
  }

  /// Encrypt data using a key stored in the secure enclave.
  Future<Uint8List> encrypt({
    required String keyAlias,
    required Uint8List plaintext,
  }) async {
    if (_isAvailable) {
      try {
        const channel = MethodChannel('com.dangeremergence/security');
        final result = await channel.invokeMethod<Uint8List>(
          'encrypt',
          {
            'keyAlias': keyAlias,
            'data': plaintext,
          },
        );

        if (result != null) return result;
      } catch (e) {
        debugPrint('Secure enclave encryption error: $e');
      }
    }

    // Software fallback
    if (_deviceKey != null) {
      final encrypted = _encryption.encryptMessage(
        utf8.decode(plaintext),
        _deviceKey!,
      );
      return Uint8List.fromList(utf8.encode(jsonEncode(encrypted.toJson())));
    }

    throw StateError('No encryption key available');
  }

  /// Decrypt data using a key stored in the secure enclave.
  Future<Uint8List> decrypt({
    required String keyAlias,
    required Uint8List ciphertext,
  }) async {
    if (_isAvailable) {
      try {
        const channel = MethodChannel('com.dangeremergence/security');
        final result = await channel.invokeMethod<Uint8List>(
          'decrypt',
          {
            'keyAlias': keyAlias,
            'data': ciphertext,
          },
        );

        if (result != null) return result;
      } catch (e) {
        debugPrint('Secure enclave decryption error: $e');
      }
    }

    // Software fallback
    if (_deviceKey != null) {
      final json = jsonDecode(utf8.decode(ciphertext)) as Map<String, dynamic>;
      final encrypted = EncryptedMessage.fromJson(json);
      final plaintext = _encryption.decryptMessage(encrypted, _deviceKey!);
      return Uint8List.fromList(utf8.encode(plaintext));
    }

    throw StateError('No decryption key available');
  }

  /// Delete a key from the secure enclave.
  Future<void> deleteKey(String keyAlias) async {
    if (_isAvailable) {
      try {
        const channel = MethodChannel('com.dangeremergence/security');
        await channel.invokeMethod('deleteKey', {'keyAlias': keyAlias});
      } catch (e) {
        debugPrint('Secure enclave key deletion error: $e');
      }
    }
  }

  /// Verify key attestation (Android KeyStore only).
  ///
  /// Attestation proves the key was generated inside a hardware-backed
  /// secure environment and hasn't been tampered with.
  Future<AttestationResult> verifyKeyAttestation({
    required String keyAlias,
    required Uint8List attestationData,
  }) async {
    if (!SecurityConfig.enableKeyAttestation) {
      return AttestationResult(
        verified: false,
        details: 'Key attestation disabled by configuration',
      );
    }

    try {
      if (_enclaveType == SecureEnclaveType.androidKeyStore) {
        const channel = MethodChannel('com.dangeremergence/security');
        final result = await channel.invokeMethod<Map<String, dynamic>>(
          'verifyAttestation',
          {
            'keyAlias': keyAlias,
            'attestationData': attestationData,
          },
        );

        if (result != null) {
          return AttestationResult(
            verified: result['verified'] as bool? ?? false,
            details: result['details'] as String? ?? '',
            deviceSecure: result['deviceSecure'] as bool? ?? false,
            hardwareBacked: result['hardwareBacked'] as bool? ?? false,
            bootloaderUnlocked: result['bootloaderUnlocked'] as bool? ?? false,
            rollbackResistant: result['rollbackResistant'] as bool? ?? false,
          );
        }
      }

      return AttestationResult(
        verified: false,
        details: 'Attestation not supported on this platform',
      );
    } catch (e) {
      return AttestationResult(
        verified: false,
        details: 'Attestation verification error: $e',
      );
    }
  }

  /// Rotate a key — generate a new key and securely delete the old one.
  Future<KeyPairReference> rotateKey({
    required String oldKeyAlias,
    required String newKeyAlias,
    bool requireBiometrics = false,
  }) async {
    // Generate new key
    final newKey = await generateKeyPair(
      keyAlias: newKeyAlias,
      requireBiometrics: requireBiometrics,
    );

    // Delete old key
    await deleteKey(oldKeyAlias);

    return newKey;
  }

  /// Zeroize all keys — used on app uninstall or security breach.
  Future<void> zeroizeAllKeys() async {
    try {
      const channel = MethodChannel('com.dangeremergence/security');
      await channel.invokeMethod('zeroizeAllKeys');
      _deviceKey = null;
      debugPrint('All secure enclave keys zeroized');
    } catch (e) {
      debugPrint('Key zeroization error: $e');
    }
  }

  // ──────────────────────────────────────────────
  // Platform Detection
  // ──────────────────────────────────────────────

  Future<SecureEnclaveType> _detectAndroidKeyStore() async {
    try {
      const channel = MethodChannel('com.dangeremergence/security');
      final level = await channel.invokeMethod<String>('getKeyStoreLevel');
      switch (level) {
        case 'strongbox':
          return SecureEnclaveType.androidStrongBox;
        case 'tee':
          return SecureEnclaveType.androidKeyStore;
        default:
          return SecureEnclaveType.software;
      }
    } catch (_) {
      return SecureEnclaveType.software;
    }
  }

  Future<SecureEnclaveType> _detectIosSecureEnclave() async {
    try {
      const channel = MethodChannel('com.dangeremergence/security');
      final available = await channel.invokeMethod<bool>('isSecureEnclaveAvailable');
      return available == true
          ? SecureEnclaveType.iosSecureEnclave
          : SecureEnclaveType.software;
    } catch (_) {
      return SecureEnclaveType.software;
    }
  }

  Future<Uint8List> _getOrCreateDeviceKey() async {
    try {
      const channel = MethodChannel('com.dangeremergence/security');
      final keyData = await channel.invokeMethod<Uint8List>('getDeviceKey');
      if (keyData != null) return keyData;
    } catch (_) {}

    // Generate software device key as fallback
    final random = SecureRandom('Fortuna')
      ..seed(KeyParameter(Uint8List.fromList(
        List.generate(32, (i) => DateTime.now().microsecondsSinceEpoch % 256),
      )));
    return random.nextBytes(32);
  }
}

/// Type of secure enclave available on the device.
enum SecureEnclaveType {
  /// No hardware secure enclave — keys stored in software
  software,

  /// Android KeyStore (TEE-backed)
  androidKeyStore,

  /// Android StrongBox KeyStore (dedicated secure chip)
  androidStrongBox,

  /// iOS Secure Enclave
  iosSecureEnclave,
}

/// Reference to a key stored in the secure enclave.
class KeyPairReference {
  final String keyAlias;
  final String publicKeyPem;
  final bool isHardwareBacked;
  final bool requiresBiometrics;
  final Uint8List? attestationData;

  const KeyPairReference({
    required this.keyAlias,
    required this.publicKeyPem,
    this.isHardwareBacked = false,
    this.requiresBiometrics = false,
    this.attestationData,
  });

  Map<String, dynamic> toJson() => {
        'keyAlias': keyAlias,
        'publicKeyPem': publicKeyPem,
        'isHardwareBacked': isHardwareBacked,
        'requiresBiometrics': requiresBiometrics,
      };
}

/// Result of a key attestation verification.
class AttestationResult {
  final bool verified;
  final String details;
  final bool deviceSecure;
  final bool hardwareBacked;
  final bool bootloaderUnlocked;
  final bool rollbackResistant;

  const AttestationResult({
    required this.verified,
    required this.details,
    this.deviceSecure = false,
    this.hardwareBacked = false,
    this.bootloaderUnlocked = false,
    this.rollbackResistant = false,
  });
}
