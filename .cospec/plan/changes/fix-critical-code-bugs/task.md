## Implementation
- [x] 2.1 Fix sed pattern in build-android-apk.sh
     【Target Object】`deploy/scripts/build-android-apk.sh` (lines 93, 95, 97, 99)
     【Purpose】Fix broken sed backreference pattern `\134` which should be `\1 34` (backreference group 1 + space + "34"). Currently `\134` is interpreted as literal characters instead of the intended backreference.
     【Method】Replace `\134` with `\1 34` on all 4 sed lines
     【Dependencies】None
     【Content】
        - Line 93: Change `sed -i 's/\(compileSdk \)[0-9][0-9]*safeExtGet([^)]*)/\134/g'` to `sed -i 's/\(compileSdk \)[0-9][0-9]*safeExtGet([^)]*)/\1 34/g'`
        - Line 95: Change `sed -i 's/\(compileSdkVersion \)[0-9][0-9]*safeExtGet([^)]*)/\134/g'` to `sed -i 's/\(compileSdkVersion \)[0-9][0-9]*safeExtGet([^)]*)/\1 34/g'`
        - Line 97: Change `sed -i 's/\(compileSdk \)[0-9][0-9]*= [0-9][0-9]*.*/\134/g'` to `sed -i 's/\(compileSdk \)[0-9][0-9]*= [0-9][0-9]*.*/\1 34/g'`
        - Line 99: Change `sed -i 's/\(compileSdkVersion \)[0-9][0-9]*= [0-9][0-9]*.*/\134/g'` to `sed -i 's/\(compileSdkVersion \)[0-9][0-9]*= [0-9][0-9]*.*/\1 34/g'`

- [x] 2.2 Add user authentication to Android KeyStore keys
     【Target Object】`frontend/android/app/src/main/kotlin/com/dangeremergence/security/SecurityProvider.kt` (lines 306-313)
     【Purpose】Device key generated without `setUserAuthenticationRequired(true)`, meaning keys can be used without any user authentication (fingerprint/biometric). This is a security vulnerability.
     【Method】Add `.setUserAuthenticationRequired(true)` and `.setUserAuthenticationValidityDurationSeconds(30)` to the KeyGenParameterSpec.Builder chain
     【Dependencies】None
     【Content】
        - After `.setKeySize(256)`, add:
          ```kotlin
          .setUserAuthenticationRequired(true)
          .setUserAuthenticationValidityDurationSeconds(30)
          ```
        - The full builder should be:
          ```kotlin
          val spec = KeyGenParameterSpec.Builder(
              DEVICE_KEY_ALIAS,
              KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
          )
              .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
              .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
              .setKeySize(256)
              .setUserAuthenticationRequired(true)
              .setUserAuthenticationValidityDurationSeconds(30)
              .build()
          ```

- [x] 2.3 Replace placeholder certificate pins
     【Target Object】`frontend/lib/modules/security/services/security_config.dart` (lines 27-34)
     【Purpose】The pinned certificates are placeholder values. The first one (`47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=`) is the SHA-256 of an empty string, providing no actual security. Replace with a TODO comment instructing the developer to generate real pins.
     【Method】Replace the pinnedCertificates list with an empty list and a clear TODO comment
     【Dependencies】None
     【Content】
        - Replace the current list with:
          ```dart
          static const List<String> pinnedCertificates = [
            // TODO: Generate real certificate pins using:
            //   openssl s_client -connect your-api.com:443 -servername your-api.com \
            //     </dev/null 2>/dev/null | openssl x509 -pubkey -noout | \
            //     openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64
          ];
          ```

- [x] 2.4 Add kIsWeb check in _fileExists
     【Target Object】`frontend/lib/modules/security/services/app_integrity.dart` (lines 643-649)
     【Purpose】`File(path).exists()` crashes on web platform where there is no file system. Need to guard with kIsWeb check.
     【Method】Add `if (kIsWeb) return false;` at the start of `_fileExists` method
     【Dependencies】None
     【Content】
        - Change the method from:
          ```dart
          Future<bool> _fileExists(String path) async {
            try {
              return await File(path).exists();
            } catch (_) {
              return false;
            }
          }
          ```
        - To:
          ```dart
          Future<bool> _fileExists(String path) async {
            if (kIsWeb) return false;
            try {
              return await File(path).exists();
            } catch (_) {
              return false;
            }
          }
          ```
        - Note: `kIsWeb` is already imported via `package:flutter/foundation.dart` (line 3)

- [x] 2.5 Use proper secure random seed
     【Target Object】`frontend/lib/shared/services/encryption.dart` (lines 33-38)
     【Purpose】Uses `DateTime.now().microsecondsSinceEpoch % 256` as entropy source, which is predictable and not cryptographically secure.
     【Method】Replace with `dart:math` `Random.secure()` which provides cryptographically secure random bytes
     【Dependencies】None
     【Content】
        - Add import: `import 'dart:math' as math;`
        - Replace the method:
          ```dart
          Uint8List _generateSecureSeed() {
            final secureRand = math.Random.secure();
            return Uint8List.fromList(
              List.generate(32, (_) => secureRand.nextInt(256))
            );
          }
          ```

- [x] 2.6 Add Bluetooth permission checks to mesh_manager
     【Target Object】`frontend/lib/modules/mesh/services/mesh_manager.dart` (lines 52-57)
     【Purpose】`startScanning()` has no permission checks for `BLUETOOTH_SCAN` (required on Android 12+) or location permission (required for Bluetooth discovery). This will crash on Android 12+ devices.
     【Method】Change to `Future<void> startScanning() async` and add permission checks
     【Dependencies】Requires `permission_handler` package in pubspec.yaml
     【Content】
        - Change method signature from `void startScanning()` to `Future<void> startScanning() async`
        - Add permission check:
          ```dart
          Future<void> startScanning() async {
            if (_isScanning) return;
            
            // Check Bluetooth permissions (required for Android 12+)
            if (Platform.isAndroid) {
              final status = await Permission.bluetoothScan.status;
              if (!status.isGranted) {
                final result = await Permission.bluetoothScan.request();
                if (!result.isGranted) {
                  debugPrint('MeshManager: BLUETOOTH_SCAN permission denied');
                  return;
                }
              }
            }
            
            _isScanning = true;
            debugPrint('MeshManager: Scanning started');
            notifyListeners();
          }
          ```
        - Add imports at top of file: `import 'dart:io';` and `import 'package:permission_handler/permission_handler.dart';`
        - Add `permission_handler` to pubspec.yaml dependencies

- [x] 2.7 Cap exponential backoff delays in sos_service
     【Target Object】`frontend/lib/modules/sos/services/sos_service.dart` (line 158)
     【Purpose】`pow(2, i + 1)` grows exponentially with no cap. With `sosMaxRetries=5`, the last delay is 32s, but if retries increase, delays could grow unbounded.
     【Method】Cap the delay at 60 seconds using `min()`
     【Dependencies】None
     【Content】
        - Change line 158 from:
          ```dart
          await Future.delayed(Duration(seconds: pow(2, i + 1).toInt()));
          ```
        - To:
          ```dart
          const maxDelaySeconds = 60;
          final delay = min(pow(2, i + 1).toInt(), maxDelaySeconds);
          await Future.delayed(Duration(seconds: delay));
          ```
        - Add import if not present: `import 'dart:math';`
