import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/constants.dart';
import '../../../core/routes.dart';
import '../../../core/themes.dart';
import '../../../shared/services/offline_storage.dart';
import '../../../shared/services/backend_api.dart';
import '../../../modules/auth/services/auth_service.dart';
import '../../monetization/widgets/feature_gate.dart';
import '../../monetization/services/monetization_service.dart';

/// Enhanced Emergency Contacts screen with:
/// 1. Device contact picker to select contacts from the phonebook
/// 2. In-app user detection — shows which contacts already use the app
/// 3. App sharing — allows sharing the app download link with non-users
/// 4. In-app push notification (via FCM) when SOS is triggered
class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({Key? key}) : super(key: key);

  @override
  State<EmergencyContactsScreen> createState() => _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> with FeatureGateMixin {
  static const int _freeContactLimit = 3;
  static const int _extraContactCost = 3; // points per extra contact

  final _storage = OfflineStorageService();
  final _api = BackendApi();
  final _monetizationService = MonetizationService();
  List<Map<String, String>> _contacts = [];
  bool _isLoading = true;
  bool _isSyncing = false;
  bool _isCheckingUsers = false;

  // Cache of phone -> { id, name } for contacts that are app users
  Map<String, Map<String, String>> _appUsers = {};

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    setState(() => _isLoading = true);
    try {
      final value = await _storage.getSetting('emergency_contacts');
      if (value != null && value is String) {
        final decoded = json.decode(value) as List;
        _contacts = decoded.map((e) => Map<String, String>.from(e)).toList();
      }
      // After loading contacts, check which are app users
      await _checkAppUsers();
    } catch (e) {
      debugPrint('EmergencyContactsScreen: Failed to load: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  /// Check which saved contacts are registered app users.
  Future<void> _checkAppUsers() async {
    final phones = _contacts
        .map((c) => c['phone'] ?? '')
        .where((p) => p.isNotEmpty)
        .toList();
    if (phones.isEmpty) return;

    setState(() => _isCheckingUsers = true);
    try {
      final result = await _api.checkUsersByPhone(phones);
      final results = result['results'] as Map<String, dynamic>? ?? {};
      final Map<String, Map<String, String>> appUsers = {};
      for (final entry in results.entries) {
        if (entry.value is Map) {
          appUsers[entry.key] = Map<String, String>.from(
            (entry.value as Map).map((k, v) => MapEntry(k.toString(), v.toString())),
          );
        }
      }
      _appUsers = appUsers;

      // Auto-fill userId for contacts that are app users
      bool changed = false;
      for (int i = 0; i < _contacts.length; i++) {
        final phone = _contacts[i]['phone'] ?? '';
        final matched = _appUsers[phone];
        if (matched != null && matched['id'] != null) {
          final matchedId = matched['id'] as String;
          if (_contacts[i]['userId'] != matchedId) {
            _contacts[i]['userId'] = matchedId;
            changed = true;
          }
        }
      }
      if (changed) {
        await _saveContacts();
      }
    } catch (e) {
      debugPrint('EmergencyContactsScreen: Failed to check app users: $e');
    }
    if (mounted) setState(() => _isCheckingUsers = false);
  }

  Future<void> _saveContacts() async {
    await _storage.saveSetting('emergency_contacts', json.encode(_contacts));
    // Sync to backend server so Covert SOS can notify these contacts
    await _syncContactsToServer();
  }

  /// Sync emergency contact user IDs to the backend server.
  /// The backend CovertAlertService reads emergency contacts from the
  /// User.emergencyContacts field to know who to notify during a covert SOS.
  Future<void> _syncContactsToServer() async {
    final auth = AuthService();
    final currentUser = auth.currentUser;
    if (currentUser == null) {
      debugPrint('EmergencyContactsScreen: No authenticated user, skipping server sync');
      return;
    }

    setState(() => _isSyncing = true);
    try {
      // Extract user IDs from contacts that have them
      final List<String> contactIds = [];
      for (final contact in _contacts) {
        final userId = contact['userId']?.trim();
        if (userId != null && userId.isNotEmpty) {
          contactIds.add(userId);
        }
      }
      await _api.updateEmergencyContacts(currentUser.id, json.encode(contactIds));
      debugPrint('EmergencyContactsScreen: Synced ${contactIds.length} contact IDs to server');
    } catch (e) {
      debugPrint('EmergencyContactsScreen: Failed to sync contacts to server: $e');
      // Don't block the user — local save already succeeded
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  /// Check if user can add more contacts beyond the free limit.
  /// Returns true if they can proceed, false if they need to earn points or subscribe.
  Future<bool> _canAddMoreContacts() async {
    if (_contacts.length < _freeContactLimit) return true;
    // Beyond free limit — check if user has premium subscription or enough points
    final hasAccess = await checkFeatureAccess('extra_contacts', 'Extra Emergency Contacts');
    return hasAccess;
  }

  /// Spend points for adding an extra contact beyond the free limit.
  Future<void> _spendForExtraContact() async {
    if (_contacts.length >= _freeContactLimit) {
      await spendPointsForFeature('extra_contacts');
    }
  }

  /// Open device contact picker to select contacts.
  Future<void> _pickFromDeviceContacts() async {
    // Check contact limit before proceeding
    if (!await _canAddMoreContacts()) return;

    // Request permission
    if (!await FlutterContacts.requestPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Contact permission is required to pick contacts'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    try {
      // Get all contacts with phone numbers
      final deviceContacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
      );

      if (!mounted) return;

      // Filter to contacts that have phone numbers
      final contactsWithPhones = deviceContacts
          .where((c) => c.phones.isNotEmpty)
          .toList();

      if (contactsWithPhones.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No contacts with phone numbers found')),
        );
        return;
      }

      // Show a dialog to pick contacts
      final selected = await _showContactPickerDialog(contactsWithPhones);
      if (selected == null || selected.isEmpty) return;

      // Add selected contacts
      for (final contact in selected) {
        final phone = contact.phones.first.number.replaceAll(RegExp(r'[\s\-\(\)]'), '');
        // Check if already added
        final exists = _contacts.any((c) =>
            c['phone'] == phone || c['phone'] == contact.phones.first.number);
        if (!exists) {
          _contacts.add({
            'name': '${contact.name.first} ${contact.name.last}'.trim(),
            'phone': phone,
            'userId': '', // Will be filled by _checkAppUsers
          });
        }
      }

      await _saveContacts();
      await _checkAppUsers();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('EmergencyContactsScreen: Failed to pick contacts: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to access contacts: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Show a multi-select dialog for picking contacts from the device.
  Future<List<Contact>?> _showContactPickerDialog(List<Contact> contacts) {
    final selected = <Contact>[];
    final searchController = TextEditingController();
    List<Contact> filteredContacts = List.from(contacts);

    return showDialog<List<Contact>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Select Contacts'),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: Column(
                  children: [
                    // Search field
                    TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        hintText: 'Search contacts...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onChanged: (value) {
                        setDialogState(() {
                          if (value.isEmpty) {
                            filteredContacts = List.from(contacts);
                          } else {
                            final query = value.toLowerCase();
                            filteredContacts = contacts.where((c) {
                              final name = '${c.name.first} ${c.name.last}'.toLowerCase();
                              final phone = c.phones.isNotEmpty ? c.phones.first.number : '';
                              return name.contains(query) || phone.contains(query);
                            }).toList();
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    // Contact list
                    Expanded(
                      child: ListView.builder(
                        itemCount: filteredContacts.length,
                        itemBuilder: (context, index) {
                          final contact = filteredContacts[index];
                          final name = '${contact.name.first} ${contact.name.last}'.trim();
                          final phone = contact.phones.isNotEmpty
                              ? contact.phones.first.number
                              : 'No phone';
                          final isSelected = selected.contains(contact);

                          return CheckboxListTile(
                            value: isSelected,
                            title: Text(name.isEmpty ? 'Unknown' : name),
                            subtitle: Text(phone),
                            onChanged: (checked) {
                              setDialogState(() {
                                if (checked == true) {
                                  selected.add(contact);
                                } else {
                                  selected.remove(contact);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCEL'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, selected),
                  child: Text('ADD (${selected.length})'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Share the app download link with a specific contact.
  Future<void> _shareAppWithContact(Map<String, String> contact) async {
    final name = contact['name'] ?? 'there';
    final message = 'Hey $name,\n\n'
        'I use Sectop — an emergency safety app that helps keep our community safe. '
        'Download it here so we can stay connected during emergencies:\n\n'
        'https://sectop.app/download\n\n'
        'Stay safe!';
    await Share.share(message);
  }

  /// Share the app download link generically (no specific contact).
  Future<void> _shareAppLink() async {
    const message =
        '🚨 Download Sectop — Emergency Safety App\n\n'
        'Stay connected and safe during emergencies. '
        'Get real-time alerts, share your location, and notify loved ones instantly.\n\n'
        '📲 Download: https://sectop.app/download\n\n'
        'Stay safe!';
    await Share.share(message);
  }

  void _showAddEditContact({Map<String, String>? initialData, int? index}) {
    final nameController = TextEditingController(text: initialData?['name'] ?? '');
    final phoneController = TextEditingController(text: initialData?['phone'] ?? '');
    final userIdController = TextEditingController(text: initialData?['userId'] ?? '');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(initialData != null ? 'Edit Contact' : 'Add Contact'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Show contact limit info when adding new contacts
              if (initialData == null && _contacts.length >= _freeContactLimit)
                Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.orange, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Free limit ($_freeContactLimit) reached. Adding more costs $_extraContactCost points each.',
                          style: const TextStyle(fontSize: 12, color: Colors.orange),
                        ),
                      ),
                    ],
                  ),
                ),
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Full Name',
                  prefixIcon: const Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                decoration: InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: const Icon(Icons.phone_outlined),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: userIdController,
                decoration: InputDecoration(
                  labelText: 'App User ID (optional)',
                  hintText: 'Enter their Sectop user ID',
                  prefixIcon: const Icon(Icons.fingerprint),
                ),
                keyboardType: TextInputType.text,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () async {
                // Check contact limit for new contacts
                if (index == null && _contacts.length >= _freeContactLimit) {
                  Navigator.pop(context);
                  final canProceed = await _canAddMoreContacts();
                  if (!canProceed) return;
                  // Spend points for the extra contact
                  await _spendForExtraContact();
                  if (!mounted) return;
                  // Re-open dialog to add the contact
                  _showAddEditContact(initialData: initialData, index: index);
                  return;
                }
                final contact = {
                  'name': nameController.text.trim(),
                  'phone': phoneController.text.trim(),
                  'userId': userIdController.text.trim(),
                };
                if (index != null) {
                  _contacts[index] = contact;
                } else {
                  _contacts.add(contact);
                }
                await _saveContacts();
                await _checkAppUsers();
                if (mounted) {
                  Navigator.pop(context);
                  setState(() {});
                }
              },
              child: Text('SAVE'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteContact(int index) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Contact'),
        content: Text('Are you sure you want to delete this contact?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('DELETE'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _contacts.removeAt(index);
      await _saveContacts();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Emergency Contacts'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          // Sync indicator
          if (_isSyncing)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Info banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: AppTheme.primaryColor, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'When you trigger an SOS, your emergency contacts will be notified '
                          'through the app (push notification). Contacts who use Sectop will '
                          'receive your alert instantly.',
                          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                        ),
                      ),
                    ],
                  ),
                ),
                // Share App section — prominent card for generating app download link
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primaryColor.withOpacity(0.15),
                        AppTheme.primaryColor.withOpacity(0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.primaryColor.withOpacity(0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.share,
                              color: AppTheme.primaryColor,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Invite Family & Friends',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primaryColor,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Share the app link so your loved ones can download '
                                  'Sectop and stay connected during emergencies.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _shareAppLink,
                          icon: const Icon(Icons.send, size: 18),
                          label: const Text('Share App Download Link'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Main content
                Expanded(
                  child: _contacts.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.contacts_outlined, size: 64, color: Colors.grey[300]),
                              const SizedBox(height: 16),
                              Text(
                                'No emergency contacts',
                                style: TextStyle(fontSize: 16, color: Colors.grey[500]),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Add contacts who should be notified in an emergency.\n'
                                'Tap + to pick from your device contacts or enter manually.',
                                style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadContacts,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: _contacts.length,
                            itemBuilder: (context, index) {
                              final contact = _contacts[index];
                              final phone = contact['phone'] ?? '';
                              final isAppUser = _appUsers.containsKey(phone);
                              final appUserInfo = _appUsers[phone];

                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: isAppUser
                                        ? Colors.green
                                        : AppTheme.primaryColor,
                                    child: Text(
                                      (contact['name'] != null && contact['name']!.isNotEmpty
                                          ? contact['name']![0]
                                          : '?')
                                          .toUpperCase(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          contact['name'] ?? '',
                                          style: const TextStyle(fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      // App user badge
                                      if (isAppUser)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.green.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'App User',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.green,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        )
                                      else
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.orange.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'Not on App',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.orange,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(phone),
                                      if (contact['userId'] != null && contact['userId']!.isNotEmpty)
                                        Text(
                                          'ID: ${contact['userId']}',
                                          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                        ),
                                    ],
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Share app button — for non-app-users
                                      if (!isAppUser)
                                        IconButton(
                                          icon: const Icon(Icons.share, size: 20, color: Colors.orange),
                                          tooltip: 'Share App',
                                          onPressed: () => _shareAppWithContact(contact),
                                        ),
                                      // View Profile button — only if userId is present
                                      if (contact['userId'] != null && contact['userId']!.isNotEmpty)
                                        IconButton(
                                          icon: const Icon(Icons.person_outline, size: 20, color: AppTheme.primaryColor),
                                          tooltip: 'View Profile',
                                          onPressed: () {
                                            Navigator.of(context).pushNamed(
                                              AppRoutes.communityUserProfile,
                                              arguments: {
                                                'id': contact['userId'],
                                                'name': contact['name'] ?? contact['userId'],
                                                'phone': contact['phone'] ?? '',
                                                'email': '',
                                              },
                                            );
                                          },
                                        ),
                                      // Send Message button — only if userId is present
                                      if (contact['userId'] != null && contact['userId']!.isNotEmpty)
                                        IconButton(
                                          icon: const Icon(Icons.message_outlined, size: 20, color: Colors.blue),
                                          tooltip: 'Send Message',
                                          onPressed: () {
                                            Navigator.of(context).pushNamed(
                                              AppRoutes.inbox,
                                              arguments: {
                                                'recipient_id': contact['userId'],
                                                'recipient_name': contact['name'] ?? contact['userId'],
                                              },
                                            );
                                          },
                                        ),
                                      IconButton(
                                        icon: const Icon(Icons.edit, size: 20),
                                        onPressed: () => _showAddEditContact(
                                          initialData: contact,
                                          index: index,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                                        onPressed: () => _deleteContact(index),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pick from device contacts
          FloatingActionButton.small(
            heroTag: 'pick_contacts',
            onPressed: _pickFromDeviceContacts,
            backgroundColor: Colors.green,
            child: const Icon(Icons.contacts, color: Colors.white),
          ),
          const SizedBox(height: 8),
          // Manual entry
          FloatingActionButton(
            heroTag: 'add_manual',
            onPressed: () => _showAddEditContact(),
            backgroundColor: AppTheme.primaryColor,
            child: const Icon(Icons.add, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
