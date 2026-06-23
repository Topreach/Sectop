import 'package:flutter/material.dart';
import '../../../core/themes.dart';
import '../services/monetization_service.dart';

/// A widget that wraps a child widget and shows a premium lock overlay
/// if the user doesn't have access to the specified feature.
///
/// Usage:
/// ```dart
/// FeatureGate(
///   feature: 'route_plan',
///   child: SafeRouteButton(),
/// )
/// ```
class FeatureGate extends StatefulWidget {
  final String feature;
  final String featureName;
  final Widget child;
  final int? pointsCost;

  const FeatureGate({
    Key? key,
    required this.feature,
    this.featureName = 'this feature',
    required this.child,
    this.pointsCost,
  }) : super(key: key);

  @override
  State<FeatureGate> createState() => _FeatureGateState();
}

class _FeatureGateState extends State<FeatureGate> {
  final MonetizationService _monetizationService = MonetizationService();
  bool _loading = true;
  bool _hasAccess = true;
  String _tier = 'free';
  int _pointsRequired = 0;
  int _pointsBalance = 0;

  @override
  void initState() {
    super.initState();
    _checkAccess();
  }

  Future<void> _checkAccess() async {
    final result = await _monetizationService.checkAccess(widget.feature);
    if (mounted) {
      setState(() {
        _hasAccess = result['hasAccess'] == true;
        _tier = result['tier'] as String? ?? 'free';
        _pointsRequired = (result['pointsRequired'] as num?)?.toInt() ?? widget.pointsCost ?? 0;
        _pointsBalance = (result['pointsBalance'] as num?)?.toInt() ?? 0;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return widget.child;
    }

    if (_hasAccess) {
      return widget.child;
    }

    // Locked feature — show overlay
    return Stack(
      children: [
        // Blurred/disabled child
        Opacity(
          opacity: 0.4,
          child: AbsorbPointer(
            absorbing: true,
            child: widget.child,
          ),
        ),
        // Lock overlay
        Positioned.fill(
          child: GestureDetector(
            onTap: () => _showUpgradeDialog(context),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.black.withOpacity(0.05),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.lock_outline,
                        color: AppTheme.primaryColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Premium Feature',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$_pointsRequired pts or subscribe',
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showUpgradeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Premium Feature'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You need ${_pointsRequired} points to use ${widget.featureName}.',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              'Your balance: $_pointsBalance pts',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            const Text(
              'Options:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            _optionRow(Icons.play_circle_outline, 'Watch ads to earn points'),
            const SizedBox(height: 4),
            _optionRow(Icons.workspace_premium, 'Subscribe for unlimited access'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Not Now'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushNamed(context, '/monetization');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('View Plans'),
          ),
        ],
      ),
    );
  }

  Widget _optionRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.primaryColor),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

/// A mixin that can be used on StatefulWidget states to check feature access.
/// Provides [checkFeatureAccess] and [spendPointsForFeature] methods.
mixin FeatureGateMixin<T extends StatefulWidget> on State<T> {
  final MonetizationService _monetizationService = MonetizationService();

  /// Check if the user has access to a feature.
  /// Shows a dialog if access is denied.
  /// Returns true if the user has access.
  Future<bool> checkFeatureAccess(String feature, String featureName) async {
    final result = await _monetizationService.checkAccess(feature);
    if (result['hasAccess'] == true) {
      return true;
    }

    final pointsRequired = (result['pointsRequired'] as num?)?.toInt() ?? 0;
    final pointsBalance = (result['pointsBalance'] as num?)?.toInt() ?? 0;

    if (!mounted) return false;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Feature Locked'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$featureName requires $pointsRequired points.'),
            const SizedBox(height: 8),
            Text('Your balance: $pointsBalance pts'),
            const SizedBox(height: 16),
            const Text('Watch ads to earn points or subscribe for unlimited access.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushNamed(context, '/monetization');
            },
            child: const Text('Earn Points'),
          ),
        ],
      ),
    );

    return false;
  }

  /// Spend points for a feature. Returns true if successful.
  Future<bool> spendPointsForFeature(String feature, {String? referenceId}) async {
    final result = await _monetizationService.spendPoints(
      feature: feature,
      referenceId: referenceId,
    );
    return result['success'] == true;
  }
}
