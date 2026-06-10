import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Abstract crash reporter interface.
/// Replace ConsoleCrashReporter with SentryCrashReporter or
/// FirebaseCrashlyticsReporter in production.
abstract class CrashReporter {
  void recordError(dynamic exception, StackTrace stack, {String? context});
  void recordFlutterError(FlutterErrorDetails details);
}

/// Console-based crash reporter for development.
class ConsoleCrashReporter implements CrashReporter {
  @override
  void recordError(dynamic exception, StackTrace stack, {String? context}) {
    debugPrint('══════════════════════════════════════════════════');
    debugPrint('⚠️ CRASH: $context');
    debugPrint('Exception: $exception');
    debugPrint('Stack: $stack');
    debugPrint('══════════════════════════════════════════════════');
    // TODO: Send to Sentry / Firebase Crashlytics:
    //   await Sentry.captureException(exception, stackTrace: stack);
  }

  @override
  void recordFlutterError(FlutterErrorDetails details) {
    debugPrint('══════════════════════════════════════════════════');
    debugPrint('⚠️ FLUTTER ERROR: ${details.exception}');
    debugPrint('Stack: ${details.stack}');
    debugPrint('══════════════════════════════════════════════════');
    // TODO: Send to Sentry / Firebase Crashlytics:
    //   await Sentry.captureException(details.exception, stackTrace: details.stack);
  }
}

/// File-based crash reporter that writes crash details to the app's documents
/// directory. Useful in debug builds to persist crash data for later retrieval.
class FileCrashReporter implements CrashReporter {
  final CrashReporter _inner;

  FileCrashReporter(this._inner);

  @override
  void recordError(dynamic exception, StackTrace stack, {String? context}) {
    _inner.recordError(exception, stack, context: context);
    _writeToFile(
      timestamp: DateTime.now().toIso8601String(),
      type: 'CRASH',
      message: '$exception',
      stack: '$stack',
      context: context,
    );
  }

  @override
  void recordFlutterError(FlutterErrorDetails details) {
    _inner.recordFlutterError(details);
    _writeToFile(
      timestamp: DateTime.now().toIso8601String(),
      type: 'FLUTTER_ERROR',
      message: '${details.exception}',
      stack: '${details.stack}',
      context: details.context?.toString(),
    );
  }

  Future<void> _writeToFile({
    required String timestamp,
    required String type,
    required String message,
    required String stack,
    String? context,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/crash_reports.log');
      final entry = StringBuffer()
        ..writeln('[$timestamp] $type')
        ..writeln('  Context: $context')
        ..writeln('  Message: $message')
        ..writeln('  Stack:')
        ..writeln(stack)
        ..writeln('---');
      await file.writeAsString(entry.toString(), mode: FileMode.append);
    } catch (_) {
      // Silently fail — file writes should never crash the app
    }
  }
}
