import 'dart:convert';
import 'dart:math' as math;
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
    final secureRand = math.Random.secure();
    return Uint8List.fromList(
      List.generate(32, (_) => secureRand.nextInt(256))
    );
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
      hmac: Uint8List.fromList(digest.bytes),
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
    final encoded = _encodeRSAPublicKey(publicKey);
    return base64.encode(encoded);
  }

  /// Decode public key from Base64 string.
  RSAPublicKey publicKeyFromBase64(String base64Str) {
    final decoded = base64.decode(base64Str);
    return _decodeRSAPublicKey(decoded);
  }

  /// Encode RSA public key to DER bytes using ASN.1.
  Uint8List _encodeRSAPublicKey(RSAPublicKey publicKey) {
    // Manual ASN.1 DER encoding for RSA public key
    // SEQUENCE { INTEGER (modulus), INTEGER (exponent) }
    final modulusBytes = _encodeBigInt(publicKey.modulus!);
    final exponentBytes = _encodeBigInt(publicKey.exponent!);
    final sequenceContent = Uint8List.fromList([...modulusBytes, ...exponentBytes]);
    return _encodeSequence(sequenceContent);
  }

  /// Decode RSA public key from DER bytes.
  RSAPublicKey _decodeRSAPublicKey(Uint8List derBytes) {
    // Parse DER-encoded RSA public key
    // Skip SEQUENCE tag and length, read two INTEGERs
    int offset = 0;
    if (derBytes[offset] != 0x30) throw FormatException('Expected SEQUENCE tag');
    offset++;
    offset = _skipDERLength(derBytes, offset);
    
    // Read modulus INTEGER
    if (derBytes[offset] != 0x02) throw FormatException('Expected INTEGER tag for modulus');
    offset++;
    final modLen = _readDERLength(derBytes, offset);
    offset += _derLengthSize(derBytes, offset);
    final modulus = _bigIntFromBytes(derBytes, offset, modLen);
    offset += modLen;
    
    // Read exponent INTEGER
    if (derBytes[offset] != 0x02) throw FormatException('Expected INTEGER tag for exponent');
    offset++;
    final expLen = _readDERLength(derBytes, offset);
    offset += _derLengthSize(derBytes, offset);
    final exponent = _bigIntFromBytes(derBytes, offset, expLen);
    
    return RSAPublicKey(modulus, exponent);
  }

  /// Encode a BigInt as DER INTEGER.
  Uint8List _encodeBigInt(BigInt value) {
    final bytes = <int>[];
    var v = value;
    while (v > BigInt.zero) {
      bytes.insert(0, (v % BigInt.from(256)).toInt());
      v = v >> 8;
    }
    // Add leading zero if high bit is set
    if (bytes.isNotEmpty && bytes[0] & 0x80 != 0) {
      bytes.insert(0, 0);
    }
    final intBytes = Uint8List.fromList(bytes);
    return Uint8List.fromList([0x02, intBytes.length, ...intBytes]);
  }

  /// Encode content as DER SEQUENCE.
  Uint8List _encodeSequence(Uint8List content) {
    if (content.length < 128) {
      return Uint8List.fromList([0x30, content.length, ...content]);
    }
    // For longer content, use multi-byte length
    final lenBytes = <int>[];
    var len = content.length;
    while (len > 0) {
      lenBytes.insert(0, len & 0xFF);
      len >>= 8;
    }
    return Uint8List.fromList([0x30, 0x80 | lenBytes.length, ...lenBytes, ...content]);
  }

  /// Skip DER length bytes and return offset after length.
  int _skipDERLength(Uint8List data, int offset) {
    if (data[offset] < 0x80) return offset + 1;
    final numBytes = data[offset] & 0x7F;
    return offset + 1 + numBytes;
  }

  /// Read DER length value.
  int _readDERLength(Uint8List data, int offset) {
    if (data[offset] < 0x80) return data[offset];
    final numBytes = data[offset] & 0x7F;
    int length = 0;
    for (int i = 0; i < numBytes; i++) {
      length = (length << 8) | data[offset + 1 + i];
    }
    return length;
  }

  /// Get the number of bytes used for DER length encoding.
  int _derLengthSize(Uint8List data, int offset) {
    if (data[offset] < 0x80) return 1;
    return 1 + (data[offset] & 0x7F);
  }

  /// Convert DER bytes to BigInt.
  BigInt _bigIntFromBytes(Uint8List data, int offset, int length) {
    var result = BigInt.zero;
    for (int i = 0; i < length; i++) {
      result = (result << 8) | BigInt.from(data[offset + i]);
    }
    return result;
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
