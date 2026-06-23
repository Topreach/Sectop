import 'package:flutter/material.dart';
import '../../../core/themes.dart';
import '../services/monetization_service.dart';
import '../widgets/points_balance_widget.dart';

/// Main monetization screen showing subscription plans and ad-earning options.
/// Accessible from the dashboard/profile via the /monetization route.
class MonetizationScreen extends StatefulWidget {
  const MonetizationScreen({Key? key}) : super(key: key);

  @override
  State<MonetizationScreen> createState() => _MonetizationScreenState();
}

class _MonetizationScreenState extends State<MonetizationScreen> {
  final MonetizationService _monetizationService = MonetizationService();
  Map<String, dynamic> _status = {};
  List<Map<String, dynamic>> _plans = [];
  bool _loading = true;
  bool _earningPoints = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final results = await Future.wait([
      _monetizationService.getStatus(),
      _monetizationService.getPlans(),
    ]);
    if (mounted) {
      setState(() {
        _status = results[0] as Map<String, dynamic>;
        _plans = results[1] as List<Map<String, dynamic>>;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monetization'),
        actions: [
          PointsBalanceWidget(
            compact: true,
            onTap: () {},
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCurrentStatusCard(),
                    const SizedBox(height: 24),
                    _buildEarnPointsSection(),
                    const SizedBox(height: 24),
                    _buildSubscriptionPlansSection(),
                    const SizedBox(height: 24),
                    _buildTransactionHistorySection(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildCurrentStatusCard() {
    final tier = _status['tier'] as String? ?? 'free';
    final pointsBalance = _status['pointsBalance'] as int? ?? 0;
    final pointsEarnedToday = _status['pointsEarnedToday'] as int? ?? 0;
    final maxDailyPoints = _status['maxDailyPoints'] as int? ?? 100;
    final isPremium = tier == 'premium' || tier == 'family';

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: isPremium
              ? const LinearGradient(
                  colors: [AppTheme.primaryColor, Color(0xFF6A1B9A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isPremium ? 'PREMIUM' : tier.toUpperCase(),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isPremium ? Colors.white : AppTheme.primaryColor,
                    letterSpacing: 1.5,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: isPremium ? Colors.white.withOpacity(0.2) : Colors.amber.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.monetization_on,
                        size: 16,
                        color: isPremium ? Colors.white : Colors.amber.shade700,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isPremium ? 'Unlimited' : '$pointsBalance pts',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isPremium ? Colors.white : Colors.amber.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (!isPremium) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: pointsEarnedToday / maxDailyPoints,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.amber),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Daily ad points: $pointsEarnedToday / $maxDailyPoints',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
            if (isPremium) ...[
              const SizedBox(height: 12),
              Text(
                'Unlimited access to all features • No ads',
                style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.9)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEarnPointsSection() {
    final tier = _status['tier'] as String? ?? 'free';
    final isPremium = tier == 'premium' || tier == 'family';

    if (isPremium) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Earn Points',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Watch rewarded ads to earn 10 points each. Use points to unlock premium features.',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            onPressed: _earningPoints ? null : _watchAd,
            icon: _earningPoints
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.play_circle_fill, size: 28),
            label: Text(_earningPoints ? 'Loading Ad...' : 'Watch Ad to Earn 10 Points'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Quick info row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _quickInfoChip(Icons.map, 'Route\n2 pts'),
            _quickInfoChip(Icons.analytics_outlined, 'Threat\n1 pt'),
            _quickInfoChip(Icons.view_in_ar, 'Digital Twin\n5 pts'),
            _quickInfoChip(Icons.contacts, 'Extra Contact\n3 pts'),
          ],
        ),
      ],
    );
  }

  Widget _quickInfoChip(IconData icon, String label) {
    return Column(
      children: [
        Icon(icon, size: 20, color: AppTheme.primaryColor),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Future<void> _watchAd() async {
    setState(() => _earningPoints = true);

    // In production, this would show a rewarded ad via google_mobile_ads
    // For now, simulate the ad watch
    await Future.delayed(const Duration(seconds: 2));

    final result = await _monetizationService.earnPointsFromAd();

    if (!mounted) return;
    setState(() => _earningPoints = false);

    if (result == -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Daily ad points limit reached! Come back tomorrow.'),
          backgroundColor: Colors.orange,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('+10 points earned! Balance: $result pts'),
          backgroundColor: Colors.green,
        ),
      );
      // Refresh status
      final status = await _monetizationService.getStatus();
      if (mounted) {
        setState(() => _status = status);
      }
    }
  }

  Widget _buildSubscriptionPlansSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Subscription Plans',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Subscribe for unlimited access to all features — no ads, no points needed.',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),
        ..._plans
            .where((p) => p['id'] != 'free' && p['id'] != 'basic')
            .map((plan) => _buildPlanCard(plan)),
      ],
    );
  }

  /// Format price with currency symbol.
  /// For NGN, use the ₦ symbol with no decimal places.
  /// For other currencies, use the currency code with 2 decimal places.
  String _formatPrice(num price, String currency) {
    if (currency == 'NGN') {
      return '₦${price.toStringAsFixed(0)}';
    }
    return '$currency${price.toStringAsFixed(2)}';
  }

  Widget _buildPlanCard(Map<String, dynamic> plan) {
    final planId = plan['id'] as String? ?? '';
    final planName = plan['name'] as String? ?? '';
    final price = plan['price'] as num? ?? 0;
    final currency = plan['currency'] as String? ?? 'USD';
    final period = plan['period'] as String? ?? '';
    final annualPrice = plan['annualPrice'] as num?;
    final features = (plan['features'] as List<dynamic>?)?.cast<String>() ?? [];
    final isPremium = planId == 'premium';
    final isFamily = planId == 'family';

    final currentTier = _status['tier'] as String? ?? 'free';
    final isCurrentPlan = currentTier == planId;

    return Card(
      elevation: isPremium ? 4 : 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isPremium
            ? const BorderSide(color: AppTheme.primaryColor, width: 2)
            : BorderSide.none,
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isFamily ? Icons.people : Icons.workspace_premium,
                          color: AppTheme.primaryColor,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          planName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _formatPrice(price, currency),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                        Text(
                          '/$period',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ],
                ),
                if (annualPrice != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Or ${_formatPrice(annualPrice, currency)}/year (save ${((1 - annualPrice / (price * 12)) * 100).round()}%)',
                    style: TextStyle(fontSize: 12, color: Colors.green.shade700, fontWeight: FontWeight.w500),
                  ),
                ],
                const SizedBox(height: 12),
                ...features.map((f) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, size: 18, color: Colors.green.shade600),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(f, style: const TextStyle(fontSize: 13)),
                          ),
                        ],
                      ),
                    )),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isCurrentPlan
                        ? null
                        : () => _handleSubscribe(planId),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isPremium ? AppTheme.primaryColor : Colors.grey.shade300,
                      foregroundColor: isPremium ? Colors.white : Colors.black87,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      isCurrentPlan ? 'Current Plan' : 'Subscribe',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isPremium)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'RECOMMENDED',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _handleSubscribe(String planId) async {
    // In production, this would initiate Google Play / App Store billing
    // For now, show a confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Subscribe'),
        content: Text('Subscribe to the $planId plan?\n\n'
            'In production, this would open Google Play or App Store billing.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Subscribe'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Stub: In production, verify with platform SDK
      final result = await _monetizationService.subscribe(
        tier: planId,
        platform: 'google_play',
        platformSubscriptionId: 'stub_${planId}_${DateTime.now().millisecondsSinceEpoch}',
        durationMonths: 1,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Subscribed to $planId!'),
            backgroundColor: Colors.green,
          ),
        );
        _loadData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] as String? ?? 'Subscription failed'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildTransactionHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recent Transactions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () => _showTransactionHistory(),
              child: const Text('View All'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _monetizationService.getTransactions(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final transactions = snapshot.data ?? [];
            if (transactions.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 8),
                        Text(
                          'No transactions yet',
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Watch ads or use features to see your transaction history.',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }
            return Column(
              children: transactions.take(5).map((tx) => _buildTransactionTile(tx)).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildTransactionTile(Map<String, dynamic> tx) {
    final amount = (tx['amount'] as num?)?.toInt() ?? 0;
    final type = tx['transactionType'] as String? ?? 'unknown';
    final createdAt = tx['createdAt'] as String? ?? '';

    final isEarned = amount > 0;
    final typeLabel = type.replaceAll('_', ' ');

    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        dense: true,
        leading: Icon(
          isEarned ? Icons.add_circle_outline : Icons.remove_circle_outline,
          color: isEarned ? Colors.green : Colors.red,
        ),
        title: Text(
          typeLabel[0].toUpperCase() + typeLabel.substring(1),
          style: const TextStyle(fontSize: 14),
        ),
        trailing: Text(
          '${isEarned ? '+' : ''}$amount pts',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isEarned ? Colors.green : Colors.red,
          ),
        ),
        subtitle: createdAt.isNotEmpty
            ? Text(
                createdAt.substring(0, 19).replaceAll('T', ' '),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              )
            : null,
      ),
    );
  }

  void _showTransactionHistory() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Transaction History',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _monetizationService.getTransactions(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final transactions = snapshot.data ?? [];
                    if (transactions.isEmpty) {
                      return const Center(child: Text('No transactions'));
                    }
                    return ListView.builder(
                      controller: scrollController,
                      itemCount: transactions.length,
                      itemBuilder: (ctx, i) => _buildTransactionTile(transactions[i]),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
