import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/constants.dart';
import '../../../core/themes.dart';
import '../../../shared/services/offline_storage.dart';
import '../../../shared/services/backend_api.dart';
import '../../../modules/auth/services/auth_service.dart';

class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({Key? key}) : super(key: key);

  @override
  State<EmergencyContactsScreen> createState() => _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  final _storage = OfflineStorageService();
  final _api = BackendApi();
  List<Map<String, String>> _contacts = [];
  bool _isLoading = true;
  bool _isSyncing = false;

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
    } catch (e) {
      debugPrint('EmergencyContactsScreen: Failed to load: $e');
    }
    if (mounted) setState(() => _isLoading = false);
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
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _contacts.isEmpty
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
                        'Add contacts who should be notified in an emergency',
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
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppTheme.primaryColor,
                            child: const Icon(Icons.person, color: Colors.white),
                          ),
                          title: Text(
                            contact['name'] ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(contact['phone'] ?? ''),
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditContact(),
        backgroundColor: AppTheme.primaryColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
