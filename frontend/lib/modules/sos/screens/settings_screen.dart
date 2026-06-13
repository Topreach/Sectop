import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants.dart';
import '../../../core/localization.dart';
import '../../../core/routes.dart';
import '../../../core/themes.dart';
import '../../../shared/services/locale_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  ThemeMode _themeMode = ThemeMode.system;
  bool _dataSaverMode = false;
  bool _autoDownloadMaps = true;
  double _cacheSize = 0;
  String _selectedLanguage = 'en';

  static const Map<String, String> _languages = {
    'en': 'English',
    'yo': 'Yoruba (Èdè Yorùbá)',
    'ig': 'Igbo (Asụsụ Igbo)',
    'ha': 'Hausa (Harshen Hausa)',
  };

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
      final themeIndex = prefs.getInt('theme_mode') ?? 0;
      _themeMode = ThemeMode.values[themeIndex];
      _dataSaverMode = prefs.getBool('data_saver_mode') ?? false;
      _autoDownloadMaps = prefs.getBool('auto_download_maps') ?? true;
      _cacheSize = prefs.getDouble('cache_size') ?? 0;
      _selectedLanguage = prefs.getString('app_language') ?? 'en';
    });
  }

  Future<void> _changeLanguage(String languageCode) async {
    if (!mounted) return;
    final localeProvider = context.read<LocaleProvider>();
    await localeProvider.setLocale(
      Locale(languageCode, languageCode == 'en' ? 'US' : 'NG'),
    );
    if (mounted) {
      setState(() {
        _selectedLanguage = languageCode;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${context.tr('language_changed_to')} ${_languages[languageCode]}')),
      );
    }
  }

  Future<void> _deleteLocalData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('delete_local_data_title')),
        content: Text(context.tr('delete_local_data_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.tr('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      setState(() {
        _cacheSize = 0;
        _notificationsEnabled = true;
        _themeMode = ThemeMode.system;
        _dataSaverMode = false;
        _autoDownloadMaps = true;
        _selectedLanguage = 'en';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('local_data_deleted'))),
        );
      }
    }
  }

  Future<void> _saveNotificationSetting(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', value);
    setState(() => _notificationsEnabled = value);
  }

  Future<void> _saveThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_mode', mode.index);
    setState(() => _themeMode = mode);
  }

  Future<void> _saveDataSaverMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('data_saver_mode', value);
    setState(() => _dataSaverMode = value);
  }

  Future<void> _saveAutoDownloadMaps(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_download_maps', value);
    setState(() => _autoDownloadMaps = value);
  }

  Future<void> _clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('cache_size', 0);
    setState(() => _cacheSize = 0);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('cache_cleared'))),
      );
    }
  }

  Future<void> _rateOnPlayStore() async {
    final packageName = AppConstants.packageName;
    final uri = Uri.parse('market://details?id=$packageName');
    final fallbackUri = Uri.parse('https://play.google.com/store/apps/details?id=$packageName');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(fallbackUri)) {
        await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.tr('could_not_open_play_store'))),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.tr('could_not_open_play_store')}: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('settings')),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Notifications
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    context.tr('notifications'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                SwitchListTile(
                  title: Text(context.tr('push_notifications')),
                  subtitle: Text(context.tr('receive_alerts_messages')),
                  value: _notificationsEnabled,
                  onChanged: _saveNotificationSetting,
                  activeColor: AppTheme.primaryColor,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Theme
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    context.tr('appearance'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                RadioListTile<ThemeMode>(
                  title: Text(context.tr('light_mode')),
                  value: ThemeMode.light,
                  groupValue: _themeMode,
                  onChanged: (value) => _saveThemeMode(value!),
                  activeColor: AppTheme.primaryColor,
                ),
                RadioListTile<ThemeMode>(
                  title: Text(context.tr('dark_mode')),
                  value: ThemeMode.dark,
                  groupValue: _themeMode,
                  onChanged: (value) => _saveThemeMode(value!),
                  activeColor: AppTheme.primaryColor,
                ),
                RadioListTile<ThemeMode>(
                  title: Text(context.tr('system_default')),
                  value: ThemeMode.system,
                  groupValue: _themeMode,
                  onChanged: (value) => _saveThemeMode(value!),
                  activeColor: AppTheme.primaryColor,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Language
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    context.tr('language'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                ..._languages.entries.map((entry) => RadioListTile<String>(
                  title: Text(entry.value),
                  value: entry.key,
                  groupValue: _selectedLanguage,
                  onChanged: (value) => _changeLanguage(value!),
                  activeColor: AppTheme.primaryColor,
                  dense: true,
                )),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Data Usage
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    context.tr('data_usage'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                SwitchListTile(
                  title: Text(context.tr('data_saver_mode')),
                  subtitle: Text(context.tr('reduce_data_usage')),
                  value: _dataSaverMode,
                  onChanged: _saveDataSaverMode,
                  activeColor: AppTheme.primaryColor,
                ),
                SwitchListTile(
                  title: Text(context.tr('auto_download_maps')),
                  subtitle: Text(context.tr('preload_map_tiles')),
                  value: _autoDownloadMaps,
                  onChanged: _saveAutoDownloadMaps,
                  activeColor: AppTheme.primaryColor,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Cache Management
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('cache_management'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${context.tr('cache_size')}: ${_cacheSize.toStringAsFixed(1)} MB',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _clearCache,
                      icon: const Icon(Icons.delete_outline),
                      label: Text(context.tr('clear_cache')),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Data Management
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    context.tr('data_management'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined, color: Colors.orange),
                  title: Text(context.tr('delete_local_data')),
                  subtitle: Text(context.tr('clear_messages_cache')),
                  onTap: _deleteLocalData,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Account
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    context.tr('account'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: Text(context.tr('delete_account')),
                  subtitle: Text(context.tr('permanently_remove_account')),
                  onTap: () {
                    Navigator.of(context).pushNamed(AppRoutes.deleteAccount);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Support
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    context.tr('support'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.star_rounded, color: Colors.amber),
                  title: Text(context.tr('rate_on_play_store')),
                  subtitle: Text(context.tr('rate_this_app')),
                  onTap: _rateOnPlayStore,
                ),
                ListTile(
                  leading: const Icon(Icons.support_agent, color: AppTheme.primaryColor),
                  title: Text(context.tr('contact_support')),
                  subtitle: Text(AppConstants.supportEmail),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${context.tr('contact')}: ${AppConstants.supportEmail}'),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.menu_book, color: AppTheme.primaryColor),
                  title: Text(context.tr('how_to_use')),
                  subtitle: Text(context.tr('learn_how_to_use')),
                  onTap: () {
                    Navigator.of(context).pushNamed(AppRoutes.howToUse);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined, color: AppTheme.primaryColor),
                  title: Text(context.tr('privacy_policy')),
                  onTap: () {
                    Navigator.of(context).pushNamed(AppRoutes.privacyPolicy);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // App Info
          Center(
            child: Text(
              '${context.tr('version')}${AppConstants.appVersion}',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
