import 'package:flutter/foundation.dart';

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
