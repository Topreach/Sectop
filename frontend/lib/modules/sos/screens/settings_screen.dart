import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants.dart';
import '../../../core/routes.dart';
import '../../../core/themes.dart';
import '../../../shared/services/covert_mode_manager.dart';

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

  // Covert Mode state
  bool _covertModeEnabled = false;
  bool _covertConsentGiven = false;
  bool _covertSuppressNotifications = true;
  String _covertSafeWord = '';
  final TextEditingController _safeWordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final covertMode = CovertModeManager();
    setState(() {
      _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
      final themeIndex = prefs.getInt('theme_mode') ?? 0;
      _themeMode = ThemeMode.values[themeIndex];
      _dataSaverMode = prefs.getBool('data_saver_mode') ?? false;
      _autoDownloadMaps = prefs.getBool('auto_download_maps') ?? true;
      _cacheSize = prefs.getDouble('cache_size') ?? 0;

      // Covert Mode state
      _covertModeEnabled = covertMode.isCovertModeEnabled;
      _covertConsentGiven = covertMode.consentGiven;
      _covertSuppressNotifications = covertMode.suppressNotifications;
      _covertSafeWord = covertMode.safeWord;
      _safeWordController.text = _covertSafeWord;
    });
  }

  Future<void> _deleteLocalData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Local Data'),
        content: Text('This will delete all locally stored messages, cached data, and preferences. Your account (if any) will NOT be affected. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('Delete'),
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
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Local data deleted successfully')),
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
        SnackBar(content: Text('Cache cleared successfully')),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Covert Mode Methods
  // ---------------------------------------------------------------------------

  /// Show the consent dialog for Covert Mode.
  /// The user must explicitly agree before Covert Mode can be enabled.
  Future<bool> _showCovertConsentDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Covert SOS Mode'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Covert SOS Mode is a privacy feature that changes how '
                'emergency alerts are sent.',
                style: TextStyle(fontSize: 14),
              ),
              SizedBox(height: 16),
              Text(
                'When enabled:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              SizedBox(height: 8),
              Text('• SOS alerts are sent ONLY to your emergency contacts '
                  'and verified responders'),
              Text('• Alerts are NOT broadcast publicly to nearby users'),
              Text('• Notification sounds and vibrations are suppressed '
                  'on your device'),
              Text('• The location tracking notification uses a discreet title'),
              SizedBox(height: 16),
              Text(
                'This feature is designed for situations where you need '
                'to discreetly alert your trusted contacts without '
                'drawing attention.',
                style: TextStyle(fontSize: 14),
              ),
              SizedBox(height: 16),
              Text(
                'You can enable or disable this feature at any time in Settings.',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.primaryColor),
            child: const Text('I Understand, Enable'),
          ),
        ],
      ),
    ) ?? false;
  }

  /// Toggle Covert Mode on/off.
  /// If consent hasn't been given yet, show the consent dialog first.
  Future<void> _toggleCovertMode(bool enabled) async {
    final covertMode = CovertModeManager();

    if (enabled && !_covertConsentGiven) {
      // Show consent dialog first
      final consentGiven = await _showCovertConsentDialog();
      if (!consentGiven) {
        // User declined — keep Covert Mode off
        setState(() => _covertModeEnabled = false);
        return;
      }
      await covertMode.giveConsent();
      _covertConsentGiven = true;
    }

    if (enabled) {
      await covertMode.enable();
    } else {
      await covertMode.disable();
    }
    setState(() => _covertModeEnabled = covertMode.isCovertModeEnabled);
  }

  /// Toggle notification suppression in Covert Mode.
  Future<void> _toggleCovertSuppressNotifications(bool value) async {
    final covertMode = CovertModeManager();
    await covertMode.setSuppressNotifications(value);
    setState(() => _covertSuppressNotifications = value);
  }

  /// Save the safe word for app lock.
  Future<void> _saveSafeWord() async {
    final word = _safeWordController.text.trim();
    final covertMode = CovertModeManager();
    if (word.isEmpty) {
      await covertMode.clearSafeWord();
    } else {
      await covertMode.setSafeWord(word);
    }
    setState(() => _covertSafeWord = covertMode.safeWord);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            word.isEmpty
                ? 'Safe word cleared'
                : 'Safe word set',
          ),
        ),
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
            SnackBar(content: Text('Could not open Play Store')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${'Could not open Play Store'}: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
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
                    'Notifications',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                SwitchListTile(
                  title: Text('Push Notifications'),
                  subtitle: Text('Receive alerts and messages'),
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
                    'Appearance',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                RadioListTile<ThemeMode>(
                  title: Text('Light Mode'),
                  value: ThemeMode.light,
                  groupValue: _themeMode,
                  onChanged: (value) => _saveThemeMode(value!),
                  activeColor: AppTheme.primaryColor,
                ),
                RadioListTile<ThemeMode>(
                  title: Text('Dark Mode'),
                  value: ThemeMode.dark,
                  groupValue: _themeMode,
                  onChanged: (value) => _saveThemeMode(value!),
                  activeColor: AppTheme.primaryColor,
                ),
                RadioListTile<ThemeMode>(
                  title: Text('System Default'),
                  value: ThemeMode.system,
                  groupValue: _themeMode,
                  onChanged: (value) => _saveThemeMode(value!),
                  activeColor: AppTheme.primaryColor,
                ),
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
                    'Data Usage',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                SwitchListTile(
                  title: Text('Data Saver Mode'),
                  subtitle: Text('Reduce data usage for maps and sync'),
                  value: _dataSaverMode,
                  onChanged: _saveDataSaverMode,
                  activeColor: AppTheme.primaryColor,
                ),
                SwitchListTile(
                  title: Text('Auto-download Maps'),
                  subtitle: Text('Preload map tiles for offline use'),
                  value: _autoDownloadMaps,
                  onChanged: _saveAutoDownloadMaps,
                  activeColor: AppTheme.primaryColor,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Covert Mode
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.incognito, color: AppTheme.primaryColor, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Covert SOS Mode',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                SwitchListTile(
                  title: Text('Enable Covert Mode'),
                  subtitle: Text(
                    'SOS alerts sent only to emergency contacts and verified responders',
                  ),
                  value: _covertModeEnabled,
                  onChanged: _toggleCovertMode,
                  activeColor: AppTheme.primaryColor,
                ),
                if (_covertModeEnabled) ...[
                  SwitchListTile(
                    title: Text('Suppress Notifications'),
                    subtitle: Text('Hide alert notifications on this device'),
                    value: _covertSuppressNotifications,
                    onChanged: _toggleCovertSuppressNotifications,
                    activeColor: AppTheme.primaryColor,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Safe Word',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Type this word anywhere in the app to immediately lock the screen',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _safeWordController,
                                decoration: InputDecoration(
                                  hintText: 'Enter safe word',
                                  border: const OutlineInputBorder(),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  suffixIcon: _covertSafeWord.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear, size: 18),
                                          onPressed: () {
                                            _safeWordController.clear();
                                            _saveSafeWord();
                                          },
                                        )
                                      : null,
                                ),
                                obscureText: true,
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: _saveSafeWord,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                                foregroundColor: Colors.white,
                              ),
                              child: Text(
                                _covertSafeWord.isEmpty ? 'Set' : 'Update',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
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
                    'Cache Management',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${'Cache size'}: ${_cacheSize.toStringAsFixed(1)} MB',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _clearCache,
                      icon: const Icon(Icons.delete_outline),
                      label: Text('Clear Cache'),
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
                    'Data Management',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined, color: Colors.orange),
                  title: Text('Delete Local Data'),
                  subtitle: Text('Clear messages, cache, and preferences (keeps account)'),
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
                    'Account',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: Text('Delete Account'),
                  subtitle: Text('Permanently remove your account and data'),
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
                    'Support',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.star_rounded, color: Colors.amber),
                  title: Text('Rate on Play Store'),
                  subtitle: Text('Rate this app and leave a suggestion'),
                  onTap: _rateOnPlayStore,
                ),
                ListTile(
                  leading: const Icon(Icons.support_agent, color: AppTheme.primaryColor),
                  title: Text('Contact Support'),
                  subtitle: Text(AppConstants.supportEmail),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${'Contact'}: ${AppConstants.supportEmail}'),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.menu_book, color: AppTheme.primaryColor),
                  title: Text('How to Use'),
                  subtitle: Text('Learn how to use the app'),
                  onTap: () {
                    Navigator.of(context).pushNamed(AppRoutes.howToUse);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined, color: AppTheme.primaryColor),
                  title: Text('Privacy Policy'),
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
              '${'Sectop v'}${AppConstants.appVersion}',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
