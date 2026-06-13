import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A ChangeNotifier that holds the current app locale and persists
/// language selection to SharedPreferences.
///
/// Wrap the app with [ChangeNotifierProvider<LocaleProvider>] and use
/// `context.watch<LocaleProvider>().locale` in MaterialApp's `locale`
/// property so that changing the language instantly rebuilds the entire
/// widget tree with the new locale.
class LocaleProvider extends ChangeNotifier {
  Locale _locale;

  LocaleProvider(this._locale);

  Locale get locale => _locale;

  /// Change the locale and persist the selection.
  Future<void> setLocale(Locale newLocale) async {
    if (newLocale.languageCode == _locale.languageCode) return;
    _locale = newLocale;
    notifyListeners();

    // Persist to SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_language', newLocale.languageCode);
    } catch (_) {
      // Non-fatal — locale still applies for this session
    }
  }

  /// Load the saved locale from SharedPreferences.
  static Future<Locale> loadSavedLocale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final languageCode = prefs.getString('app_language') ?? 'en';
      return Locale(languageCode, languageCode == 'en' ? 'US' : 'NG');
    } catch (_) {
      return const Locale('en', 'US');
    }
  }
}
