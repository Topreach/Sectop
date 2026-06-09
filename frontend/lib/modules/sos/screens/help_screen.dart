import 'package:flutter/material.dart';
import '../../../core/constants.dart';
import '../../../core/themes.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help & Support'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Emergency Numbers
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.phone, color: AppTheme.primaryColor),
                      const SizedBox(width: 8),
                      const Text(
                        'Emergency Numbers',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...AppConstants.sosEmergencyNumbers.map((number) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.phone_in_talk, size: 16, color: Colors.grey),
                            const SizedBox(width: 8),
                            Text(number, style: const TextStyle(fontSize: 16)),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // FAQ Section
          const Text(
            'Frequently Asked Questions',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _FaqTile(
            question: 'How do I send an SOS alert?',
            answer: 'Tap the large red "SEND SOS" button on the home screen. Your current location will be sent to emergency responders and nearby peers via mesh network.',
          ),
          _FaqTile(
            question: 'What is the Mesh Network?',
            answer: 'The mesh network allows devices to communicate directly via Bluetooth and Wi-Fi without internet. It\'s essential for communication when cellular networks are down.',
          ),
          _FaqTile(
            question: 'How does offline mode work?',
            answer: 'The app stores all critical data locally. When internet is unavailable, messages and alerts are queued and automatically synced when connectivity is restored.',
          ),
          _FaqTile(
            question: 'Can I use this without an account?',
            answer: 'Yes, use the "Emergency Access" option on the login screen for one-tap access without registration. Your data will be stored locally.',
          ),
          _FaqTile(
            question: 'How accurate is the location tracking?',
            answer: 'The app uses GPS with high accuracy. Location updates occur every 10 meters. In offline mode, last known location is used.',
          ),
          const SizedBox(height: 16),

          // Usage Guide
          const Text(
            'Quick Usage Guide',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _GuideStep(
            step: '1',
            title: 'Send SOS',
            description: 'Tap the SOS button on the home screen to send an immediate distress signal.',
          ),
          _GuideStep(
            step: '2',
            title: 'View Map',
            description: 'Check the Map tab for nearby danger zones, safe zones, and your current location.',
          ),
          _GuideStep(
            step: '3',
            title: 'Check Messages',
            description: 'Use the Inbox tab to view messages from responders and system alerts.',
          ),
          _GuideStep(
            step: '4',
            title: 'Update Profile',
            description: 'Keep your medical info and emergency contacts up to date in the Profile tab.',
          ),
          _GuideStep(
            step: '5',
            title: 'Stay Connected',
            description: 'Enable mesh networking to stay connected with peers when internet is unavailable.',
          ),
          const SizedBox(height: 24),

          // Contact Support
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Support request submitted. We will get back to you shortly.')),
                );
              },
              icon: const Icon(Icons.support_agent),
              label: const Text('Contact Support'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _FaqTile extends StatefulWidget {
  final String question;
  final String answer;

  const _FaqTile({required this.question, required this.answer});

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.question,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey,
                  ),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 8),
                Text(
                  widget.answer,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GuideStep extends StatelessWidget {
  final String step;
  final String title;
  final String description;

  const _GuideStep({
    required this.step,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
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
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
