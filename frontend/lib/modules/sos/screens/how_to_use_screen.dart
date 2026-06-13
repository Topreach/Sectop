import 'package:flutter/material.dart';
import '../../../core/constants.dart';
import '../../../core/themes.dart';
import '../../../core/localization.dart';

/// Comprehensive "How to Use the Application" guide screen.
class HowToUseScreen extends StatelessWidget {
  const HowToUseScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('how_to_use')),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Welcome
          _sectionCard(
            icon: Icons.waving_hand,
            title: context.tr('welcome_title'),
            description:
                'This guide will help you understand how to use the app effectively '
                'for your safety and to assist others during emergencies.',
          ),
          const SizedBox(height: 16),

          // 1. Getting Started
          _stepCard(
            step: '1',
            title: 'Getting Started',
            icon: Icons.login,
            items: [
              'Download the app from Google Play Store or Apple App Store.',
              'Open the app and grant the required permissions (location, notifications, Bluetooth).',
              'Create an account with your name, email, and phone number, or use "Emergency Access" for one-tap access without registration.',
              'Keep your profile updated with accurate emergency contacts and medical information.',
            ],
          ),
          const SizedBox(height: 12),

          // 2. Sending SOS
          _stepCard(
            step: '2',
            title: 'Sending an SOS Alert',
            icon: Icons.warning_amber_rounded,
            items: [
              'From the Dashboard, tap the large red "SEND SOS" button.',
              'Your current GPS location will be sent to emergency responders and nearby users.',
              'The app will also broadcast your SOS through the mesh network (Bluetooth/Wi-Fi) if internet is unavailable.',
              'You can cancel an accidental SOS within 5 seconds.',
              'In stealth mode, press Volume Up + Volume Down simultaneously to send a silent SOS.',
            ],
          ),
          const SizedBox(height: 12),

          // 3. Dashboard
          _stepCard(
            step: '3',
            title: 'Using the Dashboard',
            icon: Icons.dashboard,
            items: [
              'The Dashboard shows your current safety status and nearby danger zones.',
              'Quick action cards give you one-tap access to: Report Incident, Safe Route, Send Tip-off, and Radio Broadcast.',
              'View active alerts and broadcasts from emergency coordinators.',
              'Check the danger level of your current area (Low / Medium / High / Critical).',
            ],
          ),
          const SizedBox(height: 12),

          // 4. Map & Danger Zones
          _stepCard(
            step: '4',
            title: 'Map & Danger Zones',
            icon: Icons.map,
            items: [
              'The Map tab shows your current location and nearby danger zones.',
              'Red zones indicate high-risk areas. Green zones are safe areas.',
              'Tap on any zone to see details about incidents in that area.',
              'Use the heatmap view to see concentration of recent incidents.',
              'Download offline maps for areas you frequently visit.',
            ],
          ),
          const SizedBox(height: 12),

          // 5. Reporting Incidents
          _stepCard(
            step: '5',
            title: 'Reporting Incidents',
            icon: Icons.report_problem,
            items: [
              'Tap "Report Incident" from the Dashboard or the quick action card.',
              'Select the incident type (Kidnapping, Terrorism, Suspicious Activity, etc.).',
              'Provide a description and your current location.',
              'You can report anonymously if you prefer not to share your identity.',
              'Your report helps warn others and improves danger zone detection.',
            ],
          ),
          const SizedBox(height: 12),

          // 6. Safe Route Planning
          _stepCard(
            step: '6',
            title: 'Safe Route Planning',
            icon: Icons.route,
            items: [
              'Use "Safe Route" to plan a journey that avoids dangerous areas.',
              'Enter your starting point and destination.',
              'The app calculates a route that minimizes exposure to high-risk zones.',
              'You can choose to avoid highways or prefer well-lit roads.',
              'The route is color-coded: green (safe), yellow (caution), red (dangerous).',
            ],
          ),
          const SizedBox(height: 12),

          // 7. Tip-off Channel
          _stepCard(
            step: '7',
            title: 'Sending a Tip-off',
            icon: Icons.tips_and_updates,
            items: [
              'Use "Send Tip-off" to share intelligence information with authorities.',
              'You can submit tips anonymously.',
              'Include location, description, and any supporting details.',
              'Tips are reviewed by coordinators and responders.',
              'High-priority tips may trigger immediate response.',
            ],
          ),
          const SizedBox(height: 12),

          // 8. Radio Broadcasts
          _stepCard(
            step: '8',
            title: 'Radio Broadcasts',
            icon: Icons.radio,
            items: [
              'Emergency coordinators can broadcast messages to all users in a specific area.',
              'Broadcasts may include evacuation orders, safety instructions, or critical alerts.',
              'Radio broadcasts can be targeted by state or local government area (LGA).',
              'Audio broadcasts are automatically generated for accessibility.',
            ],
          ),
          const SizedBox(height: 12),

          // 9. Mesh Network
          _stepCard(
            step: '9',
            title: 'Mesh Network (Offline Communication)',
            icon: Icons.wifi_tethering,
            items: [
              'The mesh network allows devices to communicate directly via Bluetooth and Wi-Fi.',
              'This works even when cellular networks and internet are down.',
              'Enable mesh networking in Settings to stay connected with nearby users.',
              'Messages are automatically synced when internet connectivity is restored.',
              'The mesh network uses end-to-end encryption for security.',
            ],
          ),
          const SizedBox(height: 12),

          // 10. Messages & Inbox
          _stepCard(
            step: '10',
            title: 'Messages & Inbox',
            icon: Icons.inbox,
            items: [
              'The Inbox tab shows messages from responders and system alerts.',
              'Messages are stored offline and synced when connectivity is available.',
              'You can send messages to other users and emergency responders.',
              'Critical alerts are highlighted and shown at the top of your inbox.',
            ],
          ),
          const SizedBox(height: 12),

          // 11. Profile & Settings
          _stepCard(
            step: '11',
            title: 'Profile & Settings',
            icon: Icons.settings,
            items: [
              'Keep your medical information up to date in the Profile tab.',
              'Add emergency contacts who will be notified during an SOS.',
              'Configure notifications, theme, and data usage in Settings.',
              'Enable stealth mode for silent SOS triggering via hardware buttons.',
              'Manage your account: update profile, change password, or delete account.',
            ],
          ),
          const SizedBox(height: 12),

          // 12. Account & Privacy
          _stepCard(
            step: '12',
            title: 'Account & Privacy',
            icon: Icons.security,
            items: [
              'Your data is encrypted both in transit and at rest.',
              'You can request account deletion at any time from Settings.',
              'Account deletion has a 30-day grace period to change your mind.',
              'If you forget your password, use the "Forgot Password" link on the login screen.',
              'For support, contact us at ${AppConstants.supportEmail}.',
            ],
          ),
          const SizedBox(height: 24),

          // Footer
          Center(
            child: Text(
              'Sectop v${AppConstants.appVersion}',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: AppTheme.primaryColor,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepCard({
    required String step,
    required String title,
    required IconData icon,
    required List<String> items,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: AppTheme.primaryColor,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      step,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Icon(icon, color: AppTheme.primaryColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(color: AppTheme.primaryColor)),
                    Expanded(
                      child: Text(
                        item,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
