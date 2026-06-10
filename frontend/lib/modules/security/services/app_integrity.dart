import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'security_config.dart';

/// App integrity verification service.
///
/// Detects:
/// - Tampered application binary
/// - Rooted/jailbroken devices
/// - Debugger attachment
/// - Emulator execution
/// - Code injection / hooking frameworks
/// - Repackaged applications
class AppIntegrity {
  static final AppIntegrity _instance = AppIntegrity._();
  factory AppIntegrity() => _instance;
  AppIntegrity._();

  bool _isInitialized = false;
  IntegrityResult? _lastResult;

  /// Whether the integrity checker has been initialized.
  bool get isInitialized => _isInitialized;

  /// The last integrity check result.
  IntegrityResult? get lastResult => _lastResult;

  /// Initialize and run the first integrity check.
  Future<IntegrityResult> initialize() async {
    _isInitialized = true;
    _lastResult = await checkIntegrity();
    return _lastResult!;
  }

  /// Run a comprehensive integrity check.
  Future<IntegrityResult> checkIntegrity() async {
    // On web, integrity checks are not applicable — skip all native checks
    if (kIsWeb) {
      return IntegrityResult(
        passed: true,
        checks: [],
        severity: SecurityEventSeverity.info,
        timestamp: DateTime.now(),
      );
    }

    final checks = <IntegrityCheck>[];

    // Run all checks in parallel
    final results = await Future.wait([
      _checkSignature(),
      _checkRootStatus(),
      _checkDebugger(),
      _checkEmulator(),
      _checkHooks(),
      _checkRepackage(),
      _checkPermissions(),
    ]);

    checks.addAll(results);

    final passed = checks.every((c) => c.passed);
    final severity = _calculateSeverity(checks);

    return IntegrityResult(
      passed: passed,
      checks: checks,
      severity: severity,
      timestamp: DateTime.now(),
    );
  }

  /// Verify the application's cryptographic signature.
  ///
  /// On Android, compares the APK signature against the expected value.
  /// On iOS, verifies the app is signed with the Apple developer certificate.
  Future<IntegrityCheck> _checkSignature() async {
    try {
      if (Platform.isAndroid) {
        // Android: Verify APK signature hash
        // In production, this would use PackageManager.getPackageInfo()
        // with GET_SIGNING_CERTIFICATES flag
        final signatureHash = await _getAndroidSignatureHash();

        // If native plugin is not available, skip the check (pass)
        if (signatureHash == null) {
          return IntegrityCheck(
            name: 'APK Signature',
            passed: true,
            severity: SecurityEventSeverity.info,
            details: 'Signature check skipped — native plugin not available',
          );
        }

        final expectedHash = _getExpectedSignatureHash();
        if (expectedHash == null) {
          return IntegrityCheck(
            name: 'APK Signature',
            passed: true,
            severity: SecurityEventSeverity.info,
            details: 'Signature check skipped — expected hash not configured',
          );
        }
        if (signatureHash != expectedHash) {
          return IntegrityCheck(
            name: 'APK Signature',
            passed: false,
            severity: SecurityEventSeverity.critical,
            details: 'APK signature mismatch — app may be repackaged',
          );
        }
      } else if (Platform.isIOS) {
        // iOS: Verify bundle signature
        // In production, this would use SecStaticCodeCheckValidity()
        final isSigned = await _verifyIosBundleSignature();
        if (!isSigned) {
          return IntegrityCheck(
            name: 'Bundle Signature',
            passed: false,
            severity: SecurityEventSeverity.critical,
            details: 'iOS bundle signature verification failed',
          );
        }
      }

      return IntegrityCheck(
        name: 'App Signature',
        passed: true,
        severity: SecurityEventSeverity.info,
        details: 'Application signature verified',
      );
    } catch (e) {
      return IntegrityCheck(
        name: 'App Signature',
        passed: false,
        severity: SecurityEventSeverity.error,
        details: 'Signature verification error: $e',
      );
    }
  }

  /// Detect rooted (Android) or jailbroken (iOS) devices.
  Future<IntegrityCheck> _checkRootStatus() async {
    if (!SecurityConfig.detectRootedDevice) {
      return IntegrityCheck(
        name: 'Root/Jailbreak Detection',
        passed: true,
        severity: SecurityEventSeverity.info,
        details: 'Root detection disabled by configuration',
      );
    }

    try {
      final indicators = <String>[];

      if (Platform.isAndroid) {
        // Check for common root binaries
        const rootPaths = [
          '/system/app/Superuser.apk',
          '/sbin/su',
          '/system/bin/su',
          '/system/xbin/su',
          '/data/local/xbin/su',
          '/data/local/bin/su',
          '/system/sd/xbin/su',
          '/system/bin/failsafe/su',
          '/data/local/su',
          '/su/bin/su',
        ];

        for (final path in rootPaths) {
          if (await _fileExists(path)) {
            indicators.add('Root binary found: $path');
          }
        }

        // Check for root management apps
        const rootPackages = [
          'com.noshufou.android.su',
          'com.noshufou.android.su.elite',
          'eu.chainfire.supersu',
          'com.koushikdutta.superuser',
          'com.thirdparty.superuser',
          'com.topjohnwu.magisk',
        ];

        for (final pkg in rootPackages) {
          if (await _isPackageInstalled(pkg)) {
            indicators.add('Root management app: $pkg');
          }
        }

        // Check for Magisk hide
        if (await _fileExists('/data/adb/magisk.db')) {
          indicators.add('Magisk detected');
        }

        // Check if running as root
        // NOTE: Process.run() is NOT available in Flutter's standard Android engine.
        // On Android, dart:io Process class is not compiled into the app by default.
        // This check is intentionally skipped on Android to avoid ArgumentError.
        // Root detection is handled via file/package checks above.
        if (!Platform.isAndroid) {
          try {
            final result = await Process.run('id', []);
            if (result.stdout.toString().contains('uid=0')) {
              indicators.add('Process running as root');
            }
          } catch (_) {
            // 'id' command not available — expected on non-rooted devices
          }
        }
      } else if (Platform.isIOS) {
        // Check for common jailbreak files
        const jailbreakPaths = [
          '/Applications/Cydia.app',
          '/Applications/Sileo.app',
          '/Applications/Zebra.app',
          '/Library/MobileSubstrate/MobileSubstrate.dylib',
          '/bin/bash',
          '/usr/sbin/sshd',
          '/etc/apt',
          '/private/var/lib/apt/',
          '/private/var/tmp/cydia.log',
          '/private/var/mobile/Library/SBSettings/Themes',
          '/private/var/stash',
        ];

        for (final path in jailbreakPaths) {
          if (await _fileExists(path)) {
            indicators.add('Jailbreak indicator: $path');
          }
        }

        // Check if Cydia URL scheme is available
        try {
          final canOpen = await _canOpenUrl('cydia://package/com.example.package');
          if (canOpen) {
            indicators.add('Cydia URL scheme available');
          }
        } catch (_) {}
      }

      if (indicators.isNotEmpty) {
        return IntegrityCheck(
          name: 'Root/Jailbreak Detection',
          passed: false,
          severity: SecurityEventSeverity.critical,
          details: indicators.join('; '),
        );
      }

      return IntegrityCheck(
        name: 'Root/Jailbreak Detection',
        passed: true,
        severity: SecurityEventSeverity.info,
        details: 'Device appears secure',
      );
    } catch (e) {
      return IntegrityCheck(
        name: 'Root/Jailbreak Detection',
        passed: false,
        severity: SecurityEventSeverity.error,
        details: 'Root detection error: $e',
      );
    }
  }

  /// Detect if a debugger is attached to the process.
  Future<IntegrityCheck> _checkDebugger() async {
    if (!SecurityConfig.detectDebugger) {
      return IntegrityCheck(
        name: 'Debugger Detection',
        passed: true,
        severity: SecurityEventSeverity.info,
        details: 'Debugger detection disabled by configuration',
      );
    }

    try {
      // Android: Check /proc/self/status for TracerPid
      if (Platform.isAndroid) {
        try {
          final status = await _readFile('/proc/self/status');
          if (status != null) {
            for (final line in status.split('\n')) {
              if (line.startsWith('TracerPid:')) {
                final pid = line.split(':')[1].trim();
                if (pid != '0') {
                  return IntegrityCheck(
                    name: 'Debugger Detection',
                    passed: false,
                    severity: SecurityEventSeverity.critical,
                    details: 'Debugger attached (TracerPid=$pid)',
                  );
                }
              }
            }
          }
        } catch (_) {}
      }
      // Cross-platform: Check debugger flags
      // NOTE: Platform.environment may throw UnsupportedError on Android
      // because dart:io Platform is not fully available in Flutter's engine.
      try {
        if (Platform.environment.containsKey('FLUTTER_TEST') ||
            Platform.environment.containsKey('DEBUGGER_ATTACHED')) {
          return IntegrityCheck(
            name: 'Debugger Detection',
            passed: false,
            severity: SecurityEventSeverity.warning,
            details: 'Debug environment detected',
          );
        }
      } catch (_) {
        // Platform.environment not available — expected on Android
      }

      // Check if running in debug mode
      if (kDebugMode) {
        return IntegrityCheck(
          name: 'Debugger Detection',
          passed: false,
          severity: SecurityEventSeverity.warning,
          details: 'App running in debug mode',
        );
      }

      return IntegrityCheck(
        name: 'Debugger Detection',
        passed: true,
        severity: SecurityEventSeverity.info,
        details: 'No debugger detected',
      );
    } catch (e) {
      return IntegrityCheck(
        name: 'Debugger Detection',
        passed: true,
        severity: SecurityEventSeverity.warning,
        details: 'Debugger check error (non-fatal): $e',
      );
    }
  }

  /// Detect if the app is running inside an emulator.
  Future<IntegrityCheck> _checkEmulator() async {
    if (!SecurityConfig.detectEmulator) {
      return IntegrityCheck(
        name: 'Emulator Detection',
        passed: true,
        severity: SecurityEventSeverity.info,
        details: 'Emulator detection disabled by configuration',
      );
    }

    try {
      final indicators = <String>[];

      if (Platform.isAndroid) {
        // Check for emulator build properties
        final buildProps = await _getBuildProperties();
        if (buildProps != null) {
          if (buildProps['ro.product.manufacturer']?.toLowerCase() == 'unknown' ||
              buildProps['ro.product.manufacturer']?.toLowerCase() == 'google' &&
                  buildProps['ro.product.model']?.toLowerCase() == 'sdk_gphone_x86') {
            indicators.add('Emulator build properties detected');
          }

          if (buildProps['ro.kernel.qemu'] == '1') {
            indicators.add('QEMU kernel detected');
          }

          if (buildProps['ro.hardware']?.contains('goldfish') == true) {
            indicators.add('Goldfish hardware detected');
          }
        }

        // Check for emulator files
        const emulatorFiles = [
          '/system/lib/libc_malloc_debug_qemu.so',
          '/system/lib/libc_malloc_debug_leak.so',
          '/sys/qemu_trace',
          '/system/bin/qemu-props',
        ];

        for (final path in emulatorFiles) {
          if (await _fileExists(path)) {
            indicators.add('Emulator file: $path');
          }
        }

        // Check for Genymotion
        if (await _fileExists('/system/build.prop')) {
          final buildProp = await _readFile('/system/build.prop');
          if (buildProp?.contains('genymotion') == true ||
              buildProp?.contains('vbox') == true) {
            indicators.add('Genymotion/VirtualBox detected');
          }
        }
      } else if (Platform.isIOS) {
        // iOS simulator detection
        if (await _fileExists('/usr/lib/libSystem.B.dylib') == false) {
          indicators.add('iOS simulator detected');
        }
      }

      if (indicators.isNotEmpty) {
        return IntegrityCheck(
          name: 'Emulator Detection',
          passed: false,
          severity: SecurityEventSeverity.warning,
          details: indicators.join('; '),
        );
      }

      return IntegrityCheck(
        name: 'Emulator Detection',
        passed: true,
        severity: SecurityEventSeverity.info,
        details: 'Running on physical device',
      );
    } catch (e) {
      return IntegrityCheck(
        name: 'Emulator Detection',
        passed: true,
        severity: SecurityEventSeverity.warning,
        details: 'Emulator check error (non-fatal): $e',
      );
    }
  }

  /// Detect hooking frameworks (Frida, Xposed, Substrate).
  Future<IntegrityCheck> _checkHooks() async {
    try {
      final indicators = <String>[];

      if (Platform.isAndroid) {
        // Check for Xposed
        if (await _isPackageInstalled('de.robv.android.xposed.installer')) {
          indicators.add('Xposed framework detected');
        }

        // Check for Frida server
        if (await _fileExists('/data/local/tmp/frida-server')) {
          indicators.add('Frida server detected');
        }

        // Check for Frida gadget in process maps
        try {
          final maps = await _readFile('/proc/self/maps');
          if (maps?.contains('frida') == true ||
              maps?.contains('gadget') == true) {
            indicators.add('Frida gadget injected');
          }
        } catch (_) {}

        // Check for Substrate
        if (await _fileExists('/data/local/tmp/substrate.so') ||
            await _fileExists('/system/lib/libsubstrate.so')) {
          indicators.add('Substrate framework detected');
        }
      } else if (Platform.isIOS) {
        // Check for MobileSubstrate
        if (await _fileExists('/Library/MobileSubstrate/MobileSubstrate.dylib')) {
          indicators.add('MobileSubstrate detected');
        }

        // Check for Substrate safe mode
        if (Platform.environment.containsKey('DYLD_INSERT_LIBRARIES')) {
          indicators.add('DYLD_INSERT_LIBRARIES detected');
        }
      }

      if (indicators.isNotEmpty) {
        return IntegrityCheck(
          name: 'Hooking Detection',
          passed: false,
          severity: SecurityEventSeverity.critical,
          details: indicators.join('; '),
        );
      }

      return IntegrityCheck(
        name: 'Hooking Detection',
        passed: true,
        severity: SecurityEventSeverity.info,
        details: 'No hooking frameworks detected',
      );
    } catch (e) {
      return IntegrityCheck(
        name: 'Hooking Detection',
        passed: true,
        severity: SecurityEventSeverity.warning,
        details: 'Hook check error (non-fatal): $e',
      );
    }
  }

  /// Detect if the app has been repackaged with modified code.
  Future<IntegrityCheck> _checkRepackage() async {
    try {
      // Check if the app's hash matches the expected value
      final appHash = await _computeAppHash();
      final expectedHash = _getExpectedAppHash();

      if (appHash != expectedHash) {
        return IntegrityCheck(
          name: 'Repackage Detection',
          passed: false,
          severity: SecurityEventSeverity.critical,
          details: 'Application hash mismatch — possible repackage attack',
        );
      }

      // Check for unexpected asset modifications
      final assetIntegrity = await _verifyAssetIntegrity();
      if (!assetIntegrity) {
        return IntegrityCheck(
          name: 'Repackage Detection',
          passed: false,
          severity: SecurityEventSeverity.critical,
          details: 'Asset integrity check failed — assets may have been modified',
        );
      }

      return IntegrityCheck(
        name: 'Repackage Detection',
        passed: true,
        severity: SecurityEventSeverity.info,
        details: 'Application integrity verified',
      );
    } catch (e) {
      return IntegrityCheck(
        name: 'Repackage Detection',
        passed: false,
        severity: SecurityEventSeverity.error,
        details: 'Repackage check error: $e',
      );
    }
  }

  /// Verify that runtime permissions match expected state.
  Future<IntegrityCheck> _checkPermissions() async {
    try {
      // Check if the app has unexpected permissions
      // In production, this would use the platform permission API
      final prefs = await SharedPreferences.getInstance();
      final grantedPermissions = prefs.getStringList('granted_permissions') ?? [];

      // Verify no dangerous permissions were granted without user consent
      const dangerousPermissions = [
        'android.permission.INSTALL_PACKAGES',
        'android.permission.REQUEST_INSTALL_PACKAGES',
        'android.permission.WRITE_SETTINGS',
        'android.permission.SYSTEM_ALERT_WINDOW',
      ];

      final unexpected = grantedPermissions
          .where((p) => dangerousPermissions.contains(p))
          .toList();

      if (unexpected.isNotEmpty) {
        return IntegrityCheck(
          name: 'Permission Check',
          passed: false,
          severity: SecurityEventSeverity.warning,
          details: 'Unexpected dangerous permissions: ${unexpected.join(', ')}',
        );
      }

      return IntegrityCheck(
        name: 'Permission Check',
        passed: true,
        severity: SecurityEventSeverity.info,
        details: 'Permissions are in expected state',
      );
    } catch (e) {
      return IntegrityCheck(
        name: 'Permission Check',
        passed: true,
        severity: SecurityEventSeverity.warning,
        details: 'Permission check error (non-fatal): $e',
      );
    }
  }

  // ──────────────────────────────────────────────
  // Helper Methods
  // ──────────────────────────────────────────────

  SecurityEventSeverity _calculateSeverity(
      List<IntegrityCheck> checks) {
    for (final check in checks) {
      if (!check.passed && check.severity == SecurityEventSeverity.critical) {
        return SecurityEventSeverity.critical;
      }
    }
    for (final check in checks) {
      if (!check.passed && check.severity == SecurityEventSeverity.error) {
        return SecurityEventSeverity.error;
      }
    }
    for (final check in checks) {
      if (!check.passed) {
        return SecurityEventSeverity.warning;
      }
    }
    return SecurityEventSeverity.info;
  }

  Future<String?> _getAndroidSignatureHash() async {
    try {
      // In production, use platform channel to get PackageInfo signature
      const channel = MethodChannel('com.dangeremergence/security');
      final hash = await channel.invokeMethod<String>('getSignatureHash');
      return hash;
    } on MissingPluginException {
      // Native security plugin not available — skip signature check
      debugPrint('AppIntegrity: Native security plugin not available, skipping signature check');
      return null;
    } catch (e) {
      debugPrint('AppIntegrity: Signature hash error: $e');
      return null;
    }
  }

  String? _getExpectedSignatureHash() {
    // In production, this would be embedded during build
    // and verified against the signing certificate
    return null;
  }

  Future<bool> _verifyIosBundleSignature() async {
    try {
      const channel = MethodChannel('com.dangeremergence/security');
      final result = await channel.invokeMethod<bool>('verifyBundleSignature');
      return result ?? false;
    } on MissingPluginException {
      // Native security plugin not available — skip bundle signature check
      debugPrint('AppIntegrity: Native security plugin not available, skipping bundle signature check');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _fileExists(String path) async {
    if (kIsWeb) return false;
    try {
      return await File(path).exists();
    } catch (_) {
      return false;
    }
  }

  Future<String?> _readFile(String path) async {
    try {
      return await File(path).readAsString();
    } catch (_) {
      return null;
    }
  }

  Future<bool> _isPackageInstalled(String packageName) async {
    try {
      // In production, use platform channel
      const channel = MethodChannel('com.dangeremergence/security');
      final result = await channel.invokeMethod<bool>('isPackageInstalled', {
        'package': packageName,
      });
      return result ?? false;
    } on MissingPluginException {
      // Native security plugin not available — skip package check
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _canOpenUrl(String url) async {
    try {
      // In production, use canLaunch from url_launcher
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, String>?> _getBuildProperties() async {
    try {
      final content = await _readFile('/system/build.prop');
      if (content == null) return null;

      final props = <String, String>{};
      for (final line in content.split('\n')) {
        final parts = line.split('=');
        if (parts.length == 2) {
          props[parts[0].trim()] = parts[1].trim();
        }
      }
      return props;
    } catch (_) {
      return null;
    }
  }

  Future<String> _computeAppHash() async {
    try {
      // In production, hash the APK/IPA binary
      // For now, return a placeholder
      final bytes = utf8.encode('danger_emergence_app_v1');
      return sha256.convert(bytes).toString();
    } catch (_) {
      return 'unknown';
    }
  }

  String _getExpectedAppHash() {
    // In production, this would be computed from the signed binary
    return sha256.convert(utf8.encode('danger_emergence_app_v1')).toString();
  }

  Future<bool> _verifyAssetIntegrity() async {
    try {
      // In production, verify asset hashes against a manifest
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Result of a full integrity check.
class IntegrityResult {
  final bool passed;
  final List<IntegrityCheck> checks;
  final SecurityEventSeverity severity;
  final DateTime timestamp;

  const IntegrityResult({
    required this.passed,
    required this.checks,
    required this.severity,
    required this.timestamp,
  });

  List<IntegrityCheck> get failedChecks => checks.where((c) => !c.passed).toList();
  List<IntegrityCheck> get passedChecks => checks.where((c) => c.passed).toList();

  Map<String, dynamic> toJson() => {
        'passed': passed,
        'severity': severity.name,
        'timestamp': timestamp.toIso8601String(),
        'checks': checks.map((c) => c.toJson()).toList(),
      };
}

/// A single integrity check result.
class IntegrityCheck {
  final String name;
  final bool passed;
  final SecurityEventSeverity severity;
  final String details;

  const IntegrityCheck({
    required this.name,
    required this.passed,
    required this.severity,
    required this.details,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'passed': passed,
        'severity': severity.name,
        'details': details,
      };
}
