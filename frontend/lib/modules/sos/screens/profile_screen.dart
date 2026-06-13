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
import '../../../core/localization.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('profile')),
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
              authService.currentUser?.name ?? context.tr('emergency_user'),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              authService.currentUser?.email ?? context.tr('offline_mode'),
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            _ProfileOption(Icons.person_outline, context.tr('edit_profile'), () {
              _showEditProfileDialog(context, authService);
            }),
            _ProfileOption(Icons.medical_services_outlined, context.tr('medical_info'), () {
              _showMedicalInfoDialog(context);
            }),
            _ProfileOption(Icons.contacts_outlined, context.tr('emergency_contacts'), () {
              _showEmergencyContactsDialog(context);
            }),
            _ProfileOption(Icons.shield_outlined, context.tr('privacy_security'), () {
              _showPrivacySecurityDialog(context);
            }),
            _ProfileOption(Icons.info_outline, context.tr('about'), () {
              _showAboutDialog(context);
            }),
            const Divider(height: 24),
            _ProfileOption(Icons.settings_outlined, context.tr('settings'), () {
              Navigator.of(context).pushNamed(AppRoutes.settings);
            }),
            _ProfileOption(Icons.delete_outline, context.tr('delete_local_data'), () {
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
        Text(
          context.tr('app_description'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () {
            debugPrint('Opening Privacy Policy...');
          },
          child: Text(context.tr('read_privacy_policy')),
        ),
      ],
    );
  }

  void _showDeleteLocalDataDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('delete_local_data_title')),
        content: Text(
          context.tr('delete_local_data_description'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.tr('cancel')),
          ),
          TextButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (ctx.mounted) {
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.tr('local_data_deleted'))),
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(context.tr('delete')),
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
              title: Text(context.tr('privacy_security_title')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: Text(context.tr('stealth_mode_sos')),
                    subtitle: Text(context.tr('silent_panic_trigger')),
                    value: triggerService.isStealthModeEnabled,
                    onChanged: (value) {
                      triggerService.setStealthMode(value);
                      setDialogState(() {});
                    },
                    activeColor: AppTheme.primaryColor,
                  ),
                  const Divider(),
                  Text(
                    context.tr('stealth_mode_description'),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.tr('close_action')),
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
          title: Text(context.tr('edit_profile_title')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: context.tr('full_name'),
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailController,
                  decoration: InputDecoration(
                    labelText: context.tr('email_address'),
                    prefixIcon: const Icon(Icons.email_outlined),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  decoration: InputDecoration(
                    labelText: context.tr('phone_number'),
                    prefixIcon: const Icon(Icons.phone_outlined),
                  ),
                  keyboardType: TextInputType.phone,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr('cancel_action')),
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
                    SnackBar(content: Text(context.tr('profile_updated'))),
                  );
                }
              },
              child: Text(context.tr('save_action')),
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
              title: Text(context.tr('medical_info_title')),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: bloodType.isEmpty ? null : bloodType,
                      decoration: InputDecoration(
                        labelText: context.tr('blood_type'),
                        prefixIcon: const Icon(Icons.bloodtype),
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
                      decoration: InputDecoration(
                        labelText: context.tr('allergies'),
                        prefixIcon: const Icon(Icons.warning_amber_outlined),
                        hintText: context.tr('allergies_hint'),
                      ),
                      onChanged: (value) => allergies = value,
                      controller: TextEditingController.fromValue(
                        TextEditingValue(text: allergies),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: InputDecoration(
                        labelText: context.tr('medications'),
                        prefixIcon: const Icon(Icons.medication_outlined),
                        hintText: context.tr('medications_hint'),
                      ),
                      onChanged: (value) => medications = value,
                      controller: TextEditingController.fromValue(
                        TextEditingValue(text: medications),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: InputDecoration(
                        labelText: context.tr('medical_conditions'),
                        prefixIcon: const Icon(Icons.health_and_safety_outlined),
                        hintText: context.tr('conditions_hint'),
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
                  child: Text(context.tr('cancel_action')),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final data = '$bloodType||$allergies||$medications||$conditions';
                    await storage.saveSetting('medical_info', data);
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(context.tr('medical_info_saved'))),
                      );
                    }
                  },
                  child: Text(context.tr('save_action')),
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
              title: Text(context.tr('emergency_contacts_title')),
              content: SizedBox(
                width: double.maxFinite,
                child: contacts.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          context.tr('no_emergency_contacts'),
                          style: const TextStyle(color: Colors.grey),
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
                  child: Text(context.tr('close_action')),
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
                  label: Text(context.tr('add_contact_title')),
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
          title: Text(initialData != null ? context.tr('edit_contact') : context.tr('add_contact_title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: context.tr('full_name'),
                  prefixIcon: const Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                decoration: InputDecoration(
                  labelText: context.tr('phone_number'),
                  prefixIcon: const Icon(Icons.phone_outlined),
                ),
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr('cancel_action')),
            ),
            ElevatedButton(
              onPressed: () {
                onSave({
                  'name': nameController.text.trim(),
                  'phone': phoneController.text.trim(),
                });
                Navigator.pop(context);
              },
              child: Text(context.tr('save_action')),
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
