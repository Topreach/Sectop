import 'package:flutter/material.dart';
import '../../../core/constants.dart';
import '../../../core/themes.dart';

/// Screen displaying the app's Privacy Policy (required for Play Store / App Store).
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Privacy Policy'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(
            'Privacy Policy',
            'Last updated: January 2025',
            isTitle: true,
          ),
          const SizedBox(height: 24),

          _section(
            '1. Information We Collect',
            'We collect the following types of information to provide emergency response services:\n\n'
            '• Personal Information: Name, email address, phone number, and emergency contacts you provide during registration.\n'
            '• Location Data: Real-time GPS location when you activate SOS mode or report incidents. Location data is critical for emergency response.\n'
            '• Device Information: Device model, operating system version, and unique device identifiers for mesh networking.\n'
            '• Incident Reports: Details of incidents you report, including descriptions, photos, and location data.\n'
            '• Mesh Network Data: Bluetooth and Wi-Fi peer information for offline communication.',
          ),
          const SizedBox(height: 16),

          _section(
            '2. How We Use Your Information',
            'Your information is used exclusively for:\n\n'
            '• Emergency Response: Sending SOS alerts to responders and coordinating rescue efforts.\n'
            '• Danger Zone Mapping: Aggregating incident reports to identify and warn about dangerous areas.\n'
            '• Communication: Enabling peer-to-peer messaging through mesh networks when cellular networks are unavailable.\n'
            '• Service Improvement: Analyzing anonymized data to improve threat detection and response times.\n'
            '• Legal Compliance: Complying with applicable laws and regulations in Nigeria.',
          ),
          const SizedBox(height: 16),

          _section(
            '3. Data Sharing and Disclosure',
            'We do not sell your personal information. We may share data:\n\n'
            '• With Emergency Responders: Your location and incident details are shared with authorized responders during emergencies.\n'
            '• With Law Enforcement: When required by law or to prevent imminent harm.\n'
            '• With Service Providers: Third-party services that help us operate (cloud hosting, push notifications) under strict data processing agreements.',
          ),
          const SizedBox(height: 16),

          _section(
            '4. Covert SOS Mode',
            'Covert SOS Mode is a privacy feature that allows you to send emergency alerts '
            'discreetly. When enabled:\n\n'
            '• SOS alerts are sent ONLY to your designated emergency contacts and verified '
            'responders — they are NOT broadcast publicly to nearby users.\n'
            '• The location tracking notification uses a discreet title ("Location Service '
            'Active") instead of "SOS Active — Tracking Location".\n'
            '• Notification sounds and vibrations are suppressed on your device.\n'
            '• A configurable "safe word" can be typed anywhere in the app to immediately '
            'lock the screen.\n\n'
            'This feature requires your explicit consent before activation. You can enable '
            'or disable it at any time in Settings. Covert SOS Mode is designed for '
            'situations where you need to alert your trusted contacts without drawing '
            'attention. It is NOT a hidden or disguised feature — it is clearly documented '
            'in this policy and requires your informed consent.',
          ),
          const SizedBox(height: 16),

          _section(
            '5. Data Retention',
            '• Account Data: Retained until you request account deletion.\n'
            '• Location Data: Real-time location is not stored permanently. Aggregated location patterns may be retained for danger zone analysis.\n'
            '• Incident Reports: Retained for safety analysis and legal compliance.\n'
            '• Deletion: Upon account deletion, personal data is anonymized within 30 days.',
          ),
          const SizedBox(height: 16),

          _section(
            '6. Your Rights',
            'You have the right to:\n\n'
            '• Access your personal data.\n'
            '• Request correction of inaccurate data.\n'
            '• Request deletion of your account and associated data.\n'
            '• Withdraw consent for data processing.\n'
            '• Export your data in a portable format.\n\n'
            'To exercise these rights, contact us at ${AppConstants.supportEmail}.',
          ),
          const SizedBox(height: 16),

          _section(
            '7. Data Security',
            'We implement industry-standard security measures:\n\n'
            '• End-to-end encryption for mesh network communications.\n'
            '• TLS 1.2+ for all server communications.\n'
            '• Biometric authentication support on compatible devices.\n'
            '• Local data encryption on device storage.\n'
            '• Regular security audits and penetration testing.',
          ),
          const SizedBox(height: 16),

          _section(
            '8. Children\'s Privacy',
            'Our service is not intended for children under 13. We do not knowingly collect data from children under 13. If you believe a child has provided us with personal data, please contact us immediately.',
          ),
          const SizedBox(height: 16),

          _section(
            '9. Changes to This Policy',
            'We may update this privacy policy from time to time. We will notify you of any changes by posting the new policy on this page and updating the "Last updated" date.',
          ),
          const SizedBox(height: 16),

          _section(
            '10. Contact Us',
            'If you have questions about this Privacy Policy, please contact us:\n\n'
            '• Email: ${AppConstants.supportEmail}\n'
            '• App: Use the "Contact Support" option in Help & Support',
          ),
          const SizedBox(height: 32),

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

  Widget _section(String title, String body, {bool isTitle = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: isTitle ? 24 : 18,
            fontWeight: isTitle ? FontWeight.bold : FontWeight.w600,
            color: isTitle ? AppTheme.primaryColor : null,
          ),
        ),
        if (!isTitle) ...[
          const SizedBox(height: 8),
          Text(
            body,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }
}
