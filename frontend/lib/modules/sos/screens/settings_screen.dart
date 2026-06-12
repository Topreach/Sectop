import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants.dart';
import '../../../core/localization.dart';
import '../../../core/routes.dart';
import '../../../core/themes.dart';

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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_language', languageCode);
    setState(() => _selectedLanguage = languageCode);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Language changed to ${_languages[languageCode]}')),
      );
    }
  }

  Future<void> _deleteLocalData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Local Data'),
        content: const Text(
          'This will delete all locally stored messages, cached data, and preferences. '
          'Your account (if any) will NOT be affected. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
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
          const SnackBar(content: Text('Local data deleted successfully')),
        );
      }
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
        const SnackBar(content: Text('Cache cleared successfully')),
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
            const SnackBar(content: Text('Could not open Play Store')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open Play Store: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
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
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Notifications',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Push Notifications'),
                  subtitle: const Text('Receive alerts and messages'),
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
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Appearance',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('Light Mode'),
                  value: ThemeMode.light,
                  groupValue: _themeMode,
                  onChanged: (value) => _saveThemeMode(value!),
                  activeColor: AppTheme.primaryColor,
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('Dark Mode'),
                  value: ThemeMode.dark,
                  groupValue: _themeMode,
                  onChanged: (value) => _saveThemeMode(value!),
                  activeColor: AppTheme.primaryColor,
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('System Default'),
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
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Language',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Data Usage',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Data Saver Mode'),
                  subtitle: const Text('Reduce data usage for maps and sync'),
                  value: _dataSaverMode,
                  onChanged: _saveDataSaverMode,
                  activeColor: AppTheme.primaryColor,
                ),
                SwitchListTile(
                  title: const Text('Auto-download Maps'),
                  subtitle: const Text('Preload map tiles for offline use'),
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
                  const Text(
                    'Cache Management',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Cache size: ${_cacheSize.toStringAsFixed(1)} MB',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _clearCache,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Clear Cache'),
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
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Data Management',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined, color: Colors.orange),
                  title: const Text('Delete Local Data'),
                  subtitle: const Text('Clear messages, cache, and preferences (keeps account)'),
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
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Account',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('Delete Account'),
                  subtitle: const Text('Permanently remove your account and data'),
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
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Support',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.star_rounded, color: Colors.amber),
                  title: const Text('Rate on Play Store'),
                  subtitle: const Text('Rate this app and leave a suggestion'),
                  onTap: _rateOnPlayStore,
                ),
                ListTile(
                  leading: const Icon(Icons.support_agent, color: AppTheme.primaryColor),
                  title: const Text('Contact Support'),
                  subtitle: Text(AppConstants.supportEmail),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Contact: ${AppConstants.supportEmail}'),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.menu_book, color: AppTheme.primaryColor),
                  title: const Text('How to Use'),
                  subtitle: const Text('Learn how to use the app'),
                  onTap: () {
                    Navigator.of(context).pushNamed(AppRoutes.howToUse);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined, color: AppTheme.primaryColor),
                  title: const Text('Privacy Policy'),
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
              'Sectop v${AppConstants.appVersion}',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
