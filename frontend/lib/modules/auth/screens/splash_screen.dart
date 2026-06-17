import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/constants.dart';
import '../../../core/routes.dart';
import '../../../core/themes.dart';
import '../../../shared/services/covert_mode_manager.dart';
import '../services/auth_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.elasticOut),
    );
    _animationController.forward();
    _checkAppStatus();
  }

  Future<void> _checkAppStatus() async {
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;

    // 1. Check permissions first (Proactive Permission UX)
    final locationStatus = await Permission.location.status;
    final bluetoothStatus = await Permission.bluetoothScan.status;

    if (!mounted) return;

    // If critical permissions aren't granted, go to PermissionScreen
    if (!locationStatus.isGranted || !bluetoothStatus.isGranted) {
      Navigator.of(context).pushReplacementNamed(AppRoutes.permissions);
      return;
    }

    // 2. Check Authentication
    final authService = context.read<AuthService>();
    final isLoggedIn = authService.isAuthenticated;

    if (!mounted) return;

    if (isLoggedIn) {
      // 3. Show Covert Mode info on first launch (one-time informational prompt)
      final covertMode = CovertModeManager();
      await covertMode.initialize();
      if (!mounted) return;

      if (!covertMode.consentGiven) {
        await _showCovertModeInfoDialog();
        if (!mounted) return;
      }

      Navigator.of(context).pushReplacementNamed(AppRoutes.dashboard);
    } else {
      Navigator.of(context).pushReplacementNamed(AppRoutes.login);
    }
  }

  /// Shows a one-time informational dialog about Covert SOS Mode on first launch.
  /// This is a non-blocking notification — the user can dismiss it and proceed.
  /// Consent is obtained later when the user actually tries to enable the feature
  /// in Settings.
  Future<void> _showCovertModeInfoDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.visibility_off, color: AppTheme.primaryColor, size: 24),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Privacy Feature Available', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Sectop includes a Covert SOS Mode — a privacy feature '
                'that lets you send emergency alerts discreetly.',
                style: TextStyle(fontSize: 14),
              ),
              SizedBox(height: 16),
              Text(
                'When enabled:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              SizedBox(height: 8),
              Text('• SOS alerts go ONLY to your emergency contacts'),
              Text('• Alerts are NOT broadcast to nearby users'),
              Text('• Notification sounds are suppressed on your device'),
              Text('• Location tracking uses a discreet notification title'),
              SizedBox(height: 16),
              Text(
                'You can enable this feature anytime in Settings > Covert SOS Mode. '
                'Your explicit consent is required before activation.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: TextButton.styleFrom(foregroundColor: AppTheme.primaryColor),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primaryColor,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    size: 64,
                    color: Color(0xFFE53935),
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'DANGER\nEMERGENCE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 4,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Emergency Response System',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.8),
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 48),
                SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.white.withOpacity(0.8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
