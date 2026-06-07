import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/service_health.dart';

/// A persistent banner that appears when application services are degraded.
///
/// Shows at the top of the screen (below the AppBar) when one or more
/// services have failed to initialize or are operating in fallback mode.
///
/// Color coding:
/// - Yellow/Amber: One or more services in degraded fallback mode
/// - Red: One or more services completely unavailable
/// - Dark Red: Security compromise detected
class DegradedModeBanner extends StatelessWidget {
  const DegradedModeBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ServiceHealthNotifier>(
      builder: (context, health, _) {
        if (!health.hasDegradation) return const SizedBox.shrink();

        return _DegradedBannerContent(health: health);
      },
    );
  }
}

class _DegradedBannerContent extends StatefulWidget {
  final ServiceHealthNotifier health;

  const _DegradedBannerContent({required this.health});

  @override
  State<_DegradedBannerContent> createState() => _DegradedBannerContentState();
}

class _DegradedBannerContentState extends State<_DegradedBannerContent>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  bool _isVisible = true;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));
    _slideController.forward();
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  void _dismiss() {
    _slideController.reverse().then((_) {
      if (mounted) setState(() => _isVisible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVisible) return const SizedBox.shrink();

    final health = widget.health;
    final degradation = health.worstDegradation;

    // Determine colors based on severity
    final Color bgColor;
    final Color textColor;
    final IconData icon;
    final String title;
    final String subtitle;

    switch (degradation) {
      case ServiceDegradation.compromised:
        bgColor = Colors.deepOrange.shade900;
        textColor = Colors.white;
        icon = Icons.shield;
        title = 'Security Compromise Detected';
        subtitle = health.summary;
      case ServiceDegradation.unavailable:
        bgColor = Colors.red.shade700;
        textColor = Colors.white;
        icon = Icons.error_outline;
        title = 'Some Services Unavailable';
        subtitle = health.summary;
      case ServiceDegradation.degraded:
        bgColor = Colors.amber.shade700;
        textColor = Colors.black87;
        icon = Icons.warning_amber_rounded;
        title = 'Degraded Mode';
        subtitle = health.summary;
      case ServiceDegradation.none:
        return const SizedBox.shrink();
    }

    return SlideTransition(
      position: _slideAnimation,
      child: Material(
        type: MaterialType.canvas,
        elevation: 4,
        child: Container(
          width: double.infinity,
          color: bgColor,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(icon, color: textColor, size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: textColor.withOpacity(0.9),
                        fontSize: 11,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: _dismiss,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.close,
                    color: textColor.withOpacity(0.7),
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A full-screen overlay shown when a critical error occurs that prevents
/// normal app operation. Shows an error message and a retry button.
class CriticalErrorOverlay extends StatelessWidget {
  final String error;
  final String? details;
  final VoidCallback? onRetry;

  const CriticalErrorOverlay({
    super.key,
    required this.error,
    this.details,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      type: MaterialType.canvas,
      child: Container(
        color: theme.colorScheme.errorContainer,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(height: 16),
                Text(
                  'Critical Error',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
                if (details != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    details!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer
                          .withOpacity(0.8),
                    ),
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (onRetry != null) ...[
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.error,
                      foregroundColor: theme.colorScheme.onError,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
