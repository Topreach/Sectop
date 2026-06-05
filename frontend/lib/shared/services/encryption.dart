import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// Encryption service for the Danger Emergence System.
/// Provides end-to-end encryption for messages and secure storage.
class EncryptionService {
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;
  EncryptionService._internal();

  // Key pair for E2E encryption
  AsymmetricKeyPair<PublicKey, PrivateKey>? _keyPair;

  /// Generate a new RSA key pair for E2E encryption.
  Future<AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>> generateKeyPair() async {
    final keyGen = RSAKeyGenerator()
      ..init(ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64),
        SecureRandom('Fortuna')
          ..seed(KeyParameter(_generateSecureSeed())),
      ));

    final pair = keyGen.generateKeyPair();
    return AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>(
      pair.publicKey as RSAPublicKey,
      pair.privateKey as RSAPrivateKey,
    );
  }

  /// Generate a secure random seed.
  Uint8List _generateSecureSeed() {
    final random = SecureRandom('Fortuna')
      ..seed(KeyParameter(Uint8List.fromList(
        List.generate(32, (_) => DateTime.now().microsecondsSinceEpoch % 256),
      )));
    return random.nextBytes(32);
  }

  /// Encrypt a message using AES-256-GCM.
  EncryptedMessage encryptMessage(String plaintext, Uint8List key) {
    // Generate random IV
    final iv = _generateIV();
    
    // Create AES cipher
    final cipher = CBCBlockCipher(AESEngine())
      ..init(true, ParametersWithIV(KeyParameter(key), iv));

    // Pad and encrypt
    final plaintextBytes = utf8.encode(plaintext);
    final padded = _pad(plaintextBytes);
    final ciphertext = Uint8List(padded.length);
    
    for (var i = 0; i < padded.length; i += 16) {
      cipher.processBlock(padded, i, ciphertext, i);
    }

    // Generate HMAC for integrity
    final hmacSha256 = Hmac(sha256, key);
    final digest = hmacSha256.convert(ciphertext);

    return EncryptedMessage(
      ciphertext: ciphertext,
      iv: iv,
      hmac: digest.bytes,
    );
  }

  /// Decrypt a message using AES-256-GCM.
  String decryptMessage(EncryptedMessage encrypted, Uint8List key) {
    // Verify HMAC
    final hmacSha256 = Hmac(sha256, key);
    final digest = hmacSha256.convert(encrypted.ciphertext);
    
    if (digest.bytes.toString() != encrypted.hmac.toString()) {
      throw Exception('Message integrity check failed');
    }

    // Create AES cipher
    final cipher = CBCBlockCipher(AESEngine())
      ..init(false, ParametersWithIV(KeyParameter(key), encrypted.iv));

    // Decrypt
    final plaintext = Uint8List(encrypted.ciphertext.length);
    for (var i = 0; i < encrypted.ciphertext.length; i += 16) {
      cipher.processBlock(encrypted.ciphertext, i, plaintext, i);
    }

    // Remove padding
    final unpadded = _unpad(plaintext);
    return utf8.decode(unpadded);
  }

  /// Generate a random IV for AES encryption.
  Uint8List _generateIV() {
    final random = SecureRandom('Fortuna')
      ..seed(KeyParameter(_generateSecureSeed()));
    return random.nextBytes(16);
  }

  /// PKCS7 padding.
  Uint8List _pad(Uint8List data) {
    final blockSize = 16;
    final padLength = blockSize - (data.length % blockSize);
    final padded = Uint8List(data.length + padLength);
    padded.setAll(0, data);
    for (var i = data.length; i < padded.length; i++) {
      padded[i] = padLength;
    }
    return padded;
  }

  /// Remove PKCS7 padding.
  Uint8List _unpad(Uint8List data) {
    final padLength = data[data.length - 1];
    if (padLength > 16 || padLength == 0) {
      throw Exception('Invalid padding');
    }
    return data.sublist(0, data.length - padLength);
  }

  /// Hash a string using SHA-256.
  String hashString(String input) {
    return sha256.convert(utf8.encode(input)).toString();
  }

  /// Generate a symmetric key from a passphrase.
  Uint8List deriveKey(String passphrase, {String salt = 'DangerEmergence'}) {
    final key = pbkdf2(
      passphrase: passphrase,
      salt: salt,
      iterations: 100000,
      keyLength: 32, // 256 bits
    );
    return key;
  }

  /// PBKDF2 key derivation.
  Uint8List pbkdf2({
    required String passphrase,
    required String salt,
    required int iterations,
    required int keyLength,
  }) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
    derivator.init(Pbkdf2Parameters(
      utf8.encode(salt) as Uint8List,
      iterations,
      keyLength,
    ));

    return derivator.process(utf8.encode(passphrase) as Uint8List);
  }

  /// Generate a device fingerprint for offline authentication.
  String generateDeviceFingerprint(String deviceId, String userId) {
    final data = '$deviceId:$userId:DangerEmergence2024';
    return hashString(data);
  }

  /// Encode public key to Base64 string.
  String publicKeyToBase64(RSAPublicKey publicKey) {
    final encoded = ASN1Encoder().encode(ASN1Sequence()
      ..add(ASN1Integer(publicKey.modulus!))
      ..add(ASN1Integer(publicKey.exponent!)));
    return base64.encode(encoded);
  }

  /// Decode public key from Base64 string.
  RSAPublicKey publicKeyFromBase64(String base64Str) {
    final decoded = base64.decode(base64Str);
    final asn1Parser = ASN1Parser(Uint8List.fromList(decoded));
    final sequence = asn1Parser.nextObject() as ASN1Sequence;
    final modulus = (sequence.elements![0] as ASN1Integer).integer!;
    final exponent = (sequence.elements![1] as ASN1Integer).integer!;
    return RSAPublicKey(modulus, exponent);
  }
}

/// Represents an encrypted message with IV and HMAC.
class EncryptedMessage {
  final Uint8List ciphertext;
  final Uint8List iv;
  final Uint8List hmac;

  EncryptedMessage({
    required this.ciphertext,
    required this.iv,
    required this.hmac,
  });

  Map<String, dynamic> toJson() => {
    'ciphertext': base64.encode(ciphertext),
    'iv': base64.encode(iv),
    'hmac': base64.encode(hmac),
  };

  factory EncryptedMessage.fromJson(Map<String, dynamic> json) => EncryptedMessage(
    ciphertext: base64.decode(json['ciphertext'] as String),
    iv: base64.decode(json['iv'] as String),
    hmac: base64.decode(json['hmac'] as String),
  );
}
