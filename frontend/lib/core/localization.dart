import 'package:flutter/material.dart';

/// Simple localization stub.
/// TODO: Replace with flutter_localizations + ARB files for production:
///   - Add flutter_localizations to pubspec.yaml
///   - Generate .arb files in lib/l10n/
///   - Use AppLocalizations.of(context)!.translate('key')
class AppLocalizations {
  final Locale locale;
  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const Map<String, Map<String, String>> _localizedStrings = {
    'en': {
      'app_name': 'Danger Emergence',
      'send_sos': 'SEND SOS',
      'tap_emergency': 'Tap for emergency alert',
      'quick_actions': 'Quick Actions',
      'safe_zones': 'Safe Zones',
      'mesh_network': 'Mesh Network',
      'messages': 'Messages',
      'first_aid': 'First Aid',
      'system_status': 'System Status',
      'cloud_connection': 'Cloud Connection',
      'connected': 'Connected',
      'offline': 'Offline',
      'location_tracking': 'Location Tracking',
      'active': 'Active',
      'inactive': 'Inactive',
      'sync_status': 'Sync Status',
      'sos_active': 'SOS Active',
      'cancel': 'Cancel',
      'ok': 'OK',
      'error': 'Error',
      'loading': 'Loading...',
      'retry': 'Retry',
    },
  };

  String translate(String key) {
    return _localizedStrings[locale.languageCode]?[key] ?? key;
  }
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) => ['en'].contains(locale.languageCode);
  @override
  Future<AppLocalizations> load(Locale locale) async => AppLocalizations(locale);
  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
