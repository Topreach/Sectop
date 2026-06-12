import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants.dart';
import '../../../core/routes.dart';
import '../../../core/themes.dart';
import '../../../shared/services/offline_storage.dart';
import '../../../shared/services/hardware_trigger_service.dart';
import '../../auth/services/auth_service.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await authService.logout();
              if (context.mounted) {
                Navigator.of(context).pushReplacementNamed(AppRoutes.login);
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const CircleAvatar(
              radius: 48,
              backgroundColor: AppTheme.primaryColor,
              child: Icon(Icons.person, size: 48, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Text(
              authService.currentUser?.name ?? 'Emergency User',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              authService.currentUser?.email ?? 'Offline Mode',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            _ProfileOption(Icons.person_outline, 'Edit Profile', () {
              _showEditProfileDialog(context, authService);
            }),
            _ProfileOption(Icons.medical_services_outlined, 'Medical Info', () {
              _showMedicalInfoDialog(context);
            }),
            _ProfileOption(Icons.contacts_outlined, 'Emergency Contacts', () {
              _showEmergencyContactsDialog(context);
            }),
            _ProfileOption(Icons.shield_outlined, 'Privacy & Security', () {
              _showPrivacySecurityDialog(context);
            }),
            _ProfileOption(Icons.info_outline, 'About', () {
              _showAboutDialog(context);
            }),
            const Divider(height: 24),
            _ProfileOption(Icons.settings_outlined, 'Settings', () {
              Navigator.of(context).pushNamed(AppRoutes.settings);
            }),
            _ProfileOption(Icons.delete_outline, 'Delete Local Data', () {
              _showDeleteLocalDataDialog(context);
            }),
          ],
        ),
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Sectop',
      applicationVersion: '1.0.0 (Nigeria Edition)',
      applicationIcon: const Icon(Icons.security, color: AppTheme.primaryColor, size: 48),
      children: [
        const SizedBox(height: 16),
        const Text(
          'A specialized emergency system designed for high-risk security environments.',
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () {
            debugPrint('Opening Privacy Policy...');
          },
          child: const Text('Read Privacy Policy'),
        ),
      ],
    );
  }

  void _showDeleteLocalDataDialog(BuildContext context) {
    showDialog(
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
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (ctx.mounted) {
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Local data deleted successfully')),
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showPrivacySecurityDialog(BuildContext context) {
    final triggerService = Provider.of<HardwareTriggerService>(context, listen: false);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Privacy & Security'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: const Text('Stealth Mode SOS'),
                    subtitle: const Text('Silent panic trigger via hardware buttons'),
                    value: triggerService.isStealthModeEnabled,
                    onChanged: (value) {
                      triggerService.setStealthMode(value);
                      setDialogState(() {});
                    },
                    activeColor: AppTheme.primaryColor,
                  ),
                  const Divider(),
                  const Text(
                    'When enabled, hardware triggers (Volume Up + Down) will send a silent SOS without showing any UI or making sound.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CLOSE'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditProfileDialog(BuildContext context, AuthService authService) {
    final user = authService.currentUser;
    final nameController = TextEditingController(text: user?.name ?? '');
    final emailController = TextEditingController(text: user?.email ?? '');
    final phoneController = TextEditingController(text: user?.phone ?? '');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Profile'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Phone',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  keyboardType: TextInputType.phone,
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
              onPressed: () async {
                final updated = UserProfile(
                  id: user?.id ?? '',
                  name: nameController.text.trim(),
                  email: emailController.text.trim(),
                  phone: phoneController.text.trim(),
                  role: user?.role ?? AppConstants.roleCitizen,
                  emergencyContacts: user?.emergencyContacts ?? [],
                  medicalInfo: user?.medicalInfo,
                  createdAt: user?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
                );
                await authService.updateProfile(updated);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Profile updated')),
                  );
                }
              },
              child: const Text('SAVE'),
            ),
          ],
        );
      },
    );
  }

  void _showMedicalInfoDialog(BuildContext context) {
    final storage = OfflineStorageService();
    String bloodType = '';
    String allergies = '';
    String medications = '';
    String conditions = '';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            storage.getSetting('medical_info').then((value) {
              if (value != null && value is String) {
                final data = value.split('||');
                if (data.length >= 4) {
                  bloodType = data[0];
                  allergies = data[1];
                  medications = data[2];
                  conditions = data[3];
                }
              }
            });

            return AlertDialog(
              title: const Text('Medical Info'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: bloodType.isEmpty ? null : bloodType,
                      decoration: const InputDecoration(
                        labelText: 'Blood Type',
                        prefixIcon: Icon(Icons.bloodtype),
                      ),
                      items: ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']
                          .map((type) => DropdownMenuItem(
                                value: type,
                                child: Text(type),
                              ))
                          .toList(),
                      onChanged: (value) => bloodType = value ?? '',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Allergies',
                        prefixIcon: Icon(Icons.warning_amber_outlined),
                        hintText: 'e.g., Penicillin, Peanuts',
                      ),
                      onChanged: (value) => allergies = value,
                      controller: TextEditingController.fromValue(
                        TextEditingValue(text: allergies),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Medications',
                        prefixIcon: Icon(Icons.medication_outlined),
                        hintText: 'e.g., Metformin 500mg',
                      ),
                      onChanged: (value) => medications = value,
                      controller: TextEditingController.fromValue(
                        TextEditingValue(text: medications),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Medical Conditions',
                        prefixIcon: Icon(Icons.health_and_safety_outlined),
                        hintText: 'e.g., Diabetes, Asthma',
                      ),
                      onChanged: (value) => conditions = value,
                      controller: TextEditingController.fromValue(
                        TextEditingValue(text: conditions),
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
                  onPressed: () async {
                    final data = '$bloodType||$allergies||$medications||$conditions';
                    await storage.saveSetting('medical_info', data);
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Medical info saved')),
                      );
                    }
                  },
                  child: const Text('SAVE'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEmergencyContactsDialog(BuildContext context) {
    final storage = OfflineStorageService();
    List<Map<String, String>> contacts = [];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            storage.getSetting('emergency_contacts').then((value) {
              if (value != null && value is String) {
                final decoded = json.decode(value) as List;
                contacts = decoded.map((e) => Map<String, String>.from(e)).toList();
              }
            });

            return AlertDialog(
              title: const Text('Emergency Contacts'),
              content: SizedBox(
                width: double.maxFinite,
                child: contacts.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No emergency contacts added yet.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: contacts.length,
                        itemBuilder: (context, index) {
                          final contact = contacts[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppTheme.primaryColor,
                              child: const Icon(Icons.person, color: Colors.white, size: 20),
                            ),
                            title: Text(contact['name'] ?? ''),
                            subtitle: Text(contact['phone'] ?? ''),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 18),
                                  onPressed: () {
                                    _showAddEditContactDialog(
                                      context,
                                      (updatedContact) {
                                        contacts[index] = updatedContact;
                                        _saveContacts(storage, contacts);
                                        setDialogState(() {});
                                      },
                                      initialData: contact,
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                                  onPressed: () {
                                    contacts.removeAt(index);
                                    _saveContacts(storage, contacts);
                                    setDialogState(() {});
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CLOSE'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    _showAddEditContactDialog(
                      context,
                      (newContact) {
                        contacts.add(newContact);
                        _saveContacts(storage, contacts);
                        setDialogState(() {});
                      },
                    );
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Contact'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAddEditContactDialog(
    BuildContext context,
    void Function(Map<String, String>) onSave, {
    Map<String, String>? initialData,
  }) {
    final nameController = TextEditingController(text: initialData?['name'] ?? '');
    final phoneController = TextEditingController(text: initialData?['phone'] ?? '');

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
                decoration: const InputDecoration(
                  labelText: 'Name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () {
                onSave({
                  'name': nameController.text.trim(),
                  'phone': phoneController.text.trim(),
                });
                Navigator.pop(context);
              },
              child: const Text('SAVE'),
            ),
          ],
        );
      },
    );
  }

  void _saveContacts(OfflineStorageService storage, List<Map<String, String>> contacts) {
    storage.saveSetting('emergency_contacts', json.encode(contacts));
  }
}

class _ProfileOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _ProfileOption(this.icon, this.title, this.onTap);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.primaryColor),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
