import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../shared/services/backend_api.dart';

/// Service for interacting with the monetization backend API.
/// Handles subscription status, points earning/spending, and feature access checks.
class MonetizationService {
  static final MonetizationService _instance = MonetizationService._();
  factory MonetizationService() => _instance;
  MonetizationService._();

  final BackendApi _api = BackendApi();

  // ---------------------------------------------------------------------------
  // Status
  // ---------------------------------------------------------------------------

  /// Get the current monetization status (tier, points, subscription info).
  Future<Map<String, dynamic>> getStatus() async {
    try {
      return await _api.get('/monetization/status');
    } catch (e) {
      debugPrint('MonetizationService.getStatus error: $e');
      return {
        'tier': 'free',
        'pointsBalance': 0,
        'pointsEarnedToday': 0,
        'maxDailyPoints': 100,
        'subscriptionStart': null,
        'subscriptionEnd': null,
        'autoRenew': true,
        'platform': null,
      };
    }
  }

  // ---------------------------------------------------------------------------
  // Points Earning
  // ---------------------------------------------------------------------------

  /// Record an ad watch and earn points.
  /// Returns the new balance, or -1 if daily limit exceeded.
  Future<int> earnPointsFromAd({String adProvider = 'admob'}) async {
    try {
      final result = await _api.post('/monetization/earn-from-ad', body: {
        'adProvider': adProvider,
      });
      if (result['success'] == true) {
        return (result['newBalance'] as num).toInt();
      }
      return -1;
    } catch (e) {
      debugPrint('MonetizationService.earnPointsFromAd error: $e');
      return -1;
    }
  }

  // ---------------------------------------------------------------------------
  // Subscription
  // ---------------------------------------------------------------------------

  /// Activate a subscription.
  Future<Map<String, dynamic>> subscribe({
    required String tier,
    required String platform,
    required String platformSubscriptionId,
    int durationMonths = 1,
  }) async {
    try {
      return await _api.post('/monetization/subscribe', body: {
        'tier': tier,
        'platform': platform,
        'platformSubscriptionId': platformSubscriptionId,
        'durationMonths': durationMonths,
      });
    } catch (e) {
      debugPrint('MonetizationService.subscribe error: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  /// Cancel auto-renewal for the current subscription.
  Future<Map<String, dynamic>> cancelSubscription() async {
    try {
      return await _api.post('/monetization/cancel-subscription');
    } catch (e) {
      debugPrint('MonetizationService.cancelSubscription error: $e');
      return {'success': false, 'message': 'Failed to cancel subscription'};
    }
  }

  /// Verify a platform purchase receipt.
  Future<Map<String, dynamic>> verifyPurchase({
    required String platform,
    required String receipt,
    required String productId,
  }) async {
    try {
      return await _api.post('/monetization/verify-purchase', body: {
        'platform': platform,
        'receipt': receipt,
        'productId': productId,
      });
    } catch (e) {
      debugPrint('MonetizationService.verifyPurchase error: $e');
      return {'success': false, 'message': 'Purchase verification failed'};
    }
  }

  // ---------------------------------------------------------------------------
  // Transactions
  // ---------------------------------------------------------------------------

  /// Get point transaction history.
  Future<List<Map<String, dynamic>>> getTransactions() async {
    try {
      final result = await _api.get('/monetization/transactions');
      // The API returns a list wrapped in {'data': [...]}
      if (result.containsKey('data') && result['data'] is List) {
        return (result['data'] as List).cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      debugPrint('MonetizationService.getTransactions error: $e');
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Feature Access
  // ---------------------------------------------------------------------------

  /// Check if the user has access to a specific feature.
  Future<Map<String, dynamic>> checkAccess(String feature) async {
    try {
      return await _api.get('/monetization/check-access?feature=$feature');
    } catch (e) {
      debugPrint('MonetizationService.checkAccess error: $e');
      return {'hasAccess': true, 'tier': 'free'};
    }
  }

  /// Spend points for a feature.
  Future<Map<String, dynamic>> spendPoints({
    required String feature,
    String? referenceId,
  }) async {
    try {
      final body = <String, dynamic>{'feature': feature};
      if (referenceId != null) body['referenceId'] = referenceId;
      return await _api.post('/monetization/spend-points', body: body);
    } catch (e) {
      debugPrint('MonetizationService.spendPoints error: $e');
      return {'success': false, 'message': 'Failed to spend points'};
    }
  }

  // ---------------------------------------------------------------------------
  // Costs & Plans
  // ---------------------------------------------------------------------------

  /// Get the points cost for all features.
  Future<Map<String, dynamic>> getCosts() async {
    try {
      return await _api.get('/monetization/costs');
    } catch (e) {
      debugPrint('MonetizationService.getCosts error: $e');
      return {
        'route_plan': 2,
        'threat_analysis': 1,
        'digital_twin': 5,
        'extra_contact': 3,
        'pointsPerAd': 10,
        'maxDailyPointsFromAds': 100,
      };
    }
  }

  /// Get subscription plan details and pricing.
  Future<List<Map<String, dynamic>>> getPlans() async {
    try {
      final result = await _api.get('/monetization/plans');
      if (result.containsKey('data') && result['data'] is List) {
        return (result['data'] as List).cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      debugPrint('MonetizationService.getPlans error: $e');
      return [];
    }
  }
}
