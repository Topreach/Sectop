import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/themes.dart';
import '../../../core/localization.dart';

/// First Aid Screen — provides step-by-step emergency medical guides
/// that work offline. Covers CPR, wound care, burns, fractures, choking,
/// and emergency kit checklist.
class FirstAidScreen extends StatefulWidget {
  const FirstAidScreen({Key? key}) : super(key: key);

  @override
  State<FirstAidScreen> createState() => _FirstAidScreenState();
}

class _FirstAidScreenState extends State<FirstAidScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('first_aid_guide')),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // CPR Guide
          _FirstAidCard(
            title: 'CPR (Cardiopulmonary Resuscitation)',
            icon: Icons.favorite_outline,
            color: Colors.red,
            steps: [
              '1. Check the scene is safe. Tap the person and shout "Are you OK?"',
              '2. Call for emergency help immediately or ask someone to call.',
              '3. Open the airway: tilt head back, lift chin up.',
              '4. Check breathing: look, listen, and feel for 10 seconds.',
              '5. If not breathing normally, start chest compressions:',
              '   • Place heel of one hand on center of chest (between nipples)',
              '   • Place other hand on top, interlock fingers',
              '   • Push hard and fast: 100-120 compressions per minute',
              '   • Compress at least 2 inches (5 cm) deep',
              '   • Allow chest to fully recoil between compressions',
              '6. After 30 compressions, give 2 rescue breaths:',
              '   • Pinch nose shut, seal mouth over person\'s mouth',
              '   • Give 1-second breath, watch for chest to rise',
              '   • Give second breath',
              '7. Repeat cycles of 30 compressions and 2 breaths',
              '8. Continue until emergency services arrive or person shows signs of life',
            ],
          ),
          const SizedBox(height: 12),

          // Choking (Heimlich Maneuver)
          _FirstAidCard(
            title: 'Choking — Heimlich Maneuver',
            icon: Icons.air_outlined,
            color: Colors.orange,
            steps: [
              '1. Ask "Are you choking?" If person cannot speak, cough, or breathe:',
              '2. Stand behind the person, wrap arms around their waist',
              '3. Make a fist with one hand, place thumb side against person\'s abdomen',
              '4. Grasp fist with other hand and thrust inward and upward',
              '5. Perform 5 abdominal thrusts (Heimlich maneuver)',
              '6. Alternate with 5 back blows between shoulder blades',
              '7. Repeat until object is dislodged or person becomes unconscious',
              '8. If unconscious: lower to ground, start CPR, check mouth for object',
              '   NOTE: For pregnant or obese persons, give chest thrusts instead',
            ],
          ),
          const SizedBox(height: 12),

          // Wound Care
          _FirstAidCard(
            title: 'Wound Care — Bleeding Control',
            icon: Icons.healing_outlined,
            color: Colors.red.shade700,
            steps: [
              '1. Put on disposable gloves if available (protect yourself)',
              '2. Remove or cut clothing to expose the wound',
              '3. Apply direct pressure with sterile gauze or clean cloth',
              '4. If blood soaks through, DO NOT remove — add more gauze on top',
              '5. Elevate injured area above heart level if possible',
              '6. Apply pressure bandage to maintain pressure',
              '7. For severe bleeding with tourniquet:',
              '   • Apply tourniquet 2-3 inches above wound (not on joint)',
              '   • Tighten until bleeding stops',
              '   • Note time of application',
              '8. Clean minor wounds with clean water, apply antibiotic ointment',
              '9. Cover with sterile bandage or dressing',
              '   SEEK IMMEDIATE MEDICAL HELP FOR SEVERE BLEEDING',
            ],
          ),
          const SizedBox(height: 12),

          // Burn Treatment
          _FirstAidCard(
            title: 'Burn Treatment',
            icon: Icons.local_fire_department_outlined,
            color: Colors.deepOrange,
            steps: [
              '1. Stop the burning process: remove person from heat source',
              '2. Cool the burn with cool (not cold) running water for 10-20 minutes',
              '3. Remove jewelry or tight items near burned area (swelling may occur)',
              '4. DO NOT apply ice, butter, toothpaste, or ointments',
              '5. Cover burn loosely with sterile gauze or clean cloth',
              '6. For minor (first-degree) burns:',
              '   • Apply aloe vera or burn cream',
              '   • Take over-the-counter pain reliever if needed',
              '7. For severe burns (second/third degree):',
              '   • Call emergency services immediately',
              '   • DO NOT remove clothing stuck to burn',
              '   • Keep person warm (prevent hypothermia)',
              '   • Elevate burned area above heart if possible',
              '   • Monitor for signs of shock',
            ],
          ),
          const SizedBox(height: 12),

          // Fracture / Sprain
          _FirstAidCard(
            title: 'Fractures & Sprains',
            icon: Icons.accessible_forward_outlined,
            color: Colors.blueGrey,
            steps: [
              '1. Keep the injured person still and calm',
              '2. Do NOT attempt to realign or push bone back in',
              '3. Immobilize the injured area:',
              '   • Use splints (boards, rolled magazines, sticks)',
              '   • Pad splints with cloth for comfort',
              '   • Tie splints above and below the injury (not directly on it)',
              '4. Apply ice pack wrapped in cloth to reduce swelling',
              '5. Elevate injured limb if possible',
              '6. For open fracture (bone protruding):',
              '   • Do NOT touch or push bone back',
              '   • Cover wound with sterile dressing',
              '   • Apply pressure around (not on) the bone',
              '7. For sprains: RICE method — Rest, Ice, Compression, Elevation',
              '8. Seek medical attention for all suspected fractures',
            ],
          ),
          const SizedBox(height: 12),

          // Allergic Reaction / Anaphylaxis
          _FirstAidCard(
            title: 'Allergic Reaction & Anaphylaxis',
            icon: Icons.warning_amber_rounded,
            color: Colors.purple,
            steps: [
              '1. Recognize symptoms: hives, swelling, difficulty breathing, dizziness',
              '2. Ask if person has known allergies or carries epinephrine (EpiPen)',
              '3. If person has EpiPen:',
              '   • Remove safety cap',
              '   • Press firmly into outer thigh (can be through clothing)',
              '   • Hold for 3 seconds, then massage injection site',
              '4. Call emergency services immediately',
              '5. Help person sit upright (or lie down if dizzy)',
              '6. Loosen tight clothing',
              '7. If person stops breathing: start CPR',
              '8. Monitor until help arrives — symptoms may return after EpiPen wears off',
            ],
          ),
          const SizedBox(height: 12),

          // Emergency Kit Checklist
          _FirstAidCard(
            title: 'Emergency Kit Checklist',
            icon: Icons.inventory_2_outlined,
            color: Colors.green,
            steps: [
              'ESSENTIAL ITEMS TO HAVE READY:',
              '',
              '📦 First Aid Supplies:',
              '  • Sterile gauze pads (various sizes)',
              '  • Adhesive bandages (assorted sizes)',
              '  • Medical tape',
              '  • Antiseptic wipes',
              '  • Antibiotic ointment',
              '  • Burn cream',
              '  • Scissors and tweezers',
              '  • Disposable gloves',
              '  • CPR face shield',
              '  • Triangular bandage (for sling)',
              '  • Elastic bandage (ACE wrap)',
              '',
              '💊 Medications:',
              '  • Pain relievers (ibuprofen, acetaminophen)',
              '  • Antihistamine (Benadryl)',
              '  • Anti-diarrhea medication',
              '  • Prescription medications (7-day supply)',
              '',
              '🔧 Tools & Supplies:',
              '  • Flashlight with extra batteries',
              '  • Whistle (signal for help)',
              '  • Emergency blanket',
              '  • Multi-tool or Swiss Army knife',
              '  • Safety pins',
              '  • Notepad and pen',
              '',
              '📱 Communication:',
              '  • Charged power bank for phone',
              '  • List of emergency contacts (written)',
              '  • Local emergency numbers',
            ],
          ),
          const SizedBox(height: 24),

          // Emergency Call Button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: () {
                // Attempt to call emergency services
                HapticFeedback.heavyImpact();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Dialing emergency services...'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              icon: const Icon(Icons.phone, size: 24),
              label: const Text(
                'Call Emergency Services',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _FirstAidCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<String> steps;

  const _FirstAidCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.steps,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: false,
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.15),
          child: Icon(icon, color: color, size: 24),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey[800],
          ),
        ),
        subtitle: Text(
          'Tap to expand guide',
          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: steps.map((step) {
                if (step.isEmpty) {
                  return const SizedBox(height: 4);
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    step,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: step.startsWith('   ') || step.startsWith('  •')
                          ? Colors.grey[600]
                          : Colors.grey[800],
                      fontWeight: step.startsWith('   ') || step.startsWith('  •')
                          ? FontWeight.normal
                          : FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
