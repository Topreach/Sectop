import 'package:flutter/material.dart';
import '../../../core/themes.dart';
import '../services/monetization_service.dart';

/// A reusable widget that displays the user's points balance and subscription tier.
/// Can be used in app bars, dashboards, or settings screens.
class PointsBalanceWidget extends StatefulWidget {
  final bool compact;
  final VoidCallback? onTap;

  const PointsBalanceWidget({
    Key? key,
    this.compact = false,
    this.onTap,
  }) : super(key: key);

  @override
  State<PointsBalanceWidget> createState() => _PointsBalanceWidgetState();
}

class _PointsBalanceWidgetState extends State<PointsBalanceWidget> {
  final MonetizationService _monetizationService = MonetizationService();
  Map<String, dynamic> _status = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final status = await _monetizationService.getStatus();
    if (mounted) {
      setState(() {
        _status = status;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return widget.compact
          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
          : const Padding(
              padding: EdgeInsets.all(8.0),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            );
    }

    final tier = _status['tier'] as String? ?? 'free';
    final pointsBalance = _status['pointsBalance'] as int? ?? 0;
    final isPremium = tier == 'premium' || tier == 'family';

    if (widget.compact) {
      // Compact version for app bar
      return GestureDetector(
        onTap: widget.onTap ?? () => _showPointsDialog(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isPremium ? AppTheme.primaryColor.withOpacity(0.2) : Colors.grey.withOpacity(0.2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isPremium ? Icons.stars_rounded : Icons.monetization_on_outlined,
                size: 16,
                color: isPremium ? AppTheme.primaryColor : Colors.amber.shade700,
              ),
              const SizedBox(width: 4),
              Text(
                isPremium ? '∞' : '$pointsBalance',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isPremium ? AppTheme.primaryColor : Colors.amber.shade700,
                ),
              ),
              if (isPremium) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    tier.toUpperCase(),
                    style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // Full version for dashboard cards
    return GestureDetector(
      onTap: widget.onTap ?? () => _showPointsDialog(context),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isPremium ? AppTheme.primaryColor.withOpacity(0.1) : Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isPremium ? Icons.workspace_premium : Icons.monetization_on,
                  color: isPremium ? AppTheme.primaryColor : Colors.amber.shade700,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPremium ? 'Unlimited Access' : 'Points Balance',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isPremium ? 'Premium • No ads' : '$pointsBalance pts available',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              if (!isPremium)
                TextButton(
                  onPressed: () => _showPointsDialog(context),
                  child: const Text('Earn More'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPointsDialog(BuildContext context) {
    final tier = _status['tier'] as String? ?? 'free';
    final pointsBalance = _status['pointsBalance'] as int? ?? 0;
    final pointsEarnedToday = _status['pointsEarnedToday'] as int? ?? 0;
    final maxDailyPoints = _status['maxDailyPoints'] as int? ?? 100;
    final isPremium = tier == 'premium' || tier == 'family';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isPremium ? Icons.workspace_premium : Icons.monetization_on,
              color: isPremium ? AppTheme.primaryColor : Colors.amber.shade700,
            ),
            const SizedBox(width: 8),
            Text(isPremium ? 'Premium Account' : 'Points & Credits'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow('Tier', tier.toUpperCase()),
            if (isPremium) ...[
              _infoRow('Status', 'Unlimited Access'),
              _infoRow('Ads', 'Ad-free experience'),
            ] else ...[
              _infoRow('Points Balance', pointsBalance.toString()),
              _infoRow('Earned Today', '$pointsEarnedToday / $maxDailyPoints'),
              const SizedBox(height: 12),
              const Text(
                'Watch rewarded ads to earn 10 points each.\n'
                'Spend points on route planning, threat analysis, and more.\n'
                'Or subscribe for unlimited access!',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          if (!isPremium)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                // Navigate to earn/subscribe screen
                Navigator.pushNamed(context, '/monetization');
              },
              child: const Text('Earn Points'),
            ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
