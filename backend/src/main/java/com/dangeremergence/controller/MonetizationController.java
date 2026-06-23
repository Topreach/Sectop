package com.dangeremergence.controller;

import com.dangeremergence.model.PointTransaction;
import com.dangeremergence.model.SubscriptionTier;
import com.dangeremergence.model.UserSubscription;
import com.dangeremergence.service.MonetizationService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.security.Principal;
import java.util.List;
import java.util.Map;

/**
 * REST controller for the points/credits monetization system.
 * All endpoints require authentication.
 * <p>
 * Base path: /api/v1/monetization
 */
@RestController
@RequestMapping("/api/v1/monetization")
public class MonetizationController {

    private static final Logger LOGGER = LoggerFactory.getLogger(MonetizationController.class);

    private final MonetizationService monetizationService;

    @Autowired
    public MonetizationController(MonetizationService monetizationService) {
        this.monetizationService = monetizationService;
    }

    /**
     * Get the current monetization status for the authenticated user.
     * Returns tier, points balance, daily limits, and subscription info.
     */
    @GetMapping("/status")
    public ResponseEntity<Map<String, Object>> getStatus(Principal principal) {
        String userId = principal.getName();
        Map<String, Object> status = monetizationService.getStatus(userId);
        return ResponseEntity.ok(status);
    }

    /**
     * Record an ad watch and earn points.
     * Body: { "adProvider": "admob" }
     * Returns the new points balance, or -1 if daily limit exceeded.
     */
    @PostMapping("/earn-from-ad")
    public ResponseEntity<Map<String, Object>> earnFromAd(Principal principal,
                                                           @RequestBody Map<String, String> body) {
        String userId = principal.getName();
        String adProvider = body.getOrDefault("adProvider", "unknown");

        int newBalance = monetizationService.earnPointsFromAd(userId, adProvider);

        if (newBalance == -1) {
            return ResponseEntity.ok(Map.of(
                    "success", false,
                    "message", "Daily ad points limit reached",
                    "maxDailyPoints", MonetizationService.MAX_DAILY_POINTS_FROM_ADS
            ));
        }

        return ResponseEntity.ok(Map.of(
                "success", true,
                "pointsEarned", MonetizationService.POINTS_PER_AD,
                "newBalance", newBalance
        ));
    }

    /**
     * Activate a subscription for the authenticated user.
     * Body: {
     *   "tier": "premium" | "family",
     *   "platform": "google_play" | "apple_app_store",
     *   "platformSubscriptionId": "abc123",
     *   "durationMonths": 1 | 12
     * }
     */
    @PostMapping("/subscribe")
    public ResponseEntity<Map<String, Object>> subscribe(Principal principal,
                                                          @RequestBody Map<String, Object> body) {
        String userId = principal.getName();

        String tierStr = (String) body.get("tier");
        String platform = (String) body.get("platform");
        String platformSubscriptionId = (String) body.get("platformSubscriptionId");
        int durationMonths = body.containsKey("durationMonths")
                ? ((Number) body.get("durationMonths")).intValue()
                : 1;

        SubscriptionTier tier;
        try {
            tier = SubscriptionTier.valueOf(tierStr);
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of(
                    "success", false,
                    "message", "Invalid tier. Must be 'premium' or 'family'."
            ));
        }

        if (tier == SubscriptionTier.free || tier == SubscriptionTier.basic) {
            return ResponseEntity.badRequest().body(Map.of(
                    "success", false,
                    "message", "Cannot subscribe to free or basic tier. Choose 'premium' or 'family'."
            ));
        }

        UserSubscription sub = monetizationService.activateSubscription(
                userId, tier, platform, platformSubscriptionId, durationMonths);

        return ResponseEntity.ok(Map.of(
                "success", true,
                "message", "Subscription activated successfully",
                "tier", sub.getTier().name(),
                "subscriptionStart", sub.getSubscriptionStart(),
                "subscriptionEnd", sub.getSubscriptionEnd(),
                "pointsBalance", sub.getPointsBalance()
        ));
    }

    /**
     * Cancel auto-renewal for the current subscription.
     */
    @PostMapping("/cancel-subscription")
    public ResponseEntity<Map<String, Object>> cancelSubscription(Principal principal) {
        String userId = principal.getName();
        monetizationService.cancelAutoRenew(userId);
        return ResponseEntity.ok(Map.of(
                "success", true,
                "message", "Auto-renewal cancelled. Subscription will remain active until the end of the current period."
        ));
    }

    /**
     * Verify a platform purchase receipt.
     * In production, this would validate with Google Play / Apple App Store.
     * Body: {
     *   "platform": "google_play" | "apple_app_store",
     *   "receipt": "base64-encoded-receipt",
     *   "productId": "monthly_premium"
     * }
     */
    @PostMapping("/verify-purchase")
    public ResponseEntity<Map<String, Object>> verifyPurchase(Principal principal,
                                                               @RequestBody Map<String, String> body) {
        String userId = principal.getName();
        String platform = body.get("platform");
        String receipt = body.get("receipt");
        String productId = body.get("productId");

        if (platform == null || receipt == null || productId == null) {
            return ResponseEntity.badRequest().body(Map.of(
                    "success", false,
                    "message", "Missing required fields: platform, receipt, productId"
            ));
        }

        // Stub: In production, validate with platform SDK
        LOGGER.info("Purchase verification stub for user {} on {} product {}", userId, platform, productId);

        return ResponseEntity.ok(Map.of(
                "success", true,
                "message", "Purchase verified successfully",
                "platform", platform,
                "productId", productId
        ));
    }

    /**
     * Get point transaction history for the authenticated user.
     */
    @GetMapping("/transactions")
    public ResponseEntity<List<PointTransaction>> getTransactions(Principal principal) {
        String userId = principal.getName();
        List<PointTransaction> transactions = monetizationService.getTransactionHistory(userId);
        return ResponseEntity.ok(transactions);
    }

    /**
     * Check if the user has access to a specific feature.
     * Query param: feature (route_plan, threat_analysis, digital_twin, extra_contact)
     */
    @GetMapping("/check-access")
    public ResponseEntity<Map<String, Object>> checkAccess(Principal principal,
                                                            @RequestParam String feature) {
        String userId = principal.getName();
        Map<String, Object> result = monetizationService.checkFeatureAccess(userId, feature);
        return ResponseEntity.ok(result);
    }

    /**
     * Spend points for a feature.
     * Body: {
     *   "feature": "route_plan",
     *   "referenceId": "optional-reference-id"
     * }
     */
    @PostMapping("/spend-points")
    public ResponseEntity<Map<String, Object>> spendPoints(Principal principal,
                                                            @RequestBody Map<String, String> body) {
        String userId = principal.getName();
        String feature = body.get("feature");
        String referenceId = body.get("referenceId");

        if (feature == null) {
            return ResponseEntity.badRequest().body(Map.of(
                    "success", false,
                    "message", "Missing required field: feature"
            ));
        }

        int cost = monetizationService.getPointsCost(feature);
        if (cost == 0) {
            return ResponseEntity.ok(Map.of(
                    "success", true,
                    "message", "Feature is free, no points needed",
                    "feature", feature
            ));
        }

        boolean spent = monetizationService.spendPoints(userId, cost, feature, referenceId);
        if (spent) {
            return ResponseEntity.ok(Map.of(
                    "success", true,
                    "message", "Points spent successfully",
                    "pointsSpent", cost,
                    "newBalance", monetizationService.getPointsBalance(userId)
            ));
        } else {
            return ResponseEntity.ok(Map.of(
                    "success", false,
                    "message", "Insufficient points. Watch ads or subscribe for unlimited access.",
                    "pointsRequired", cost,
                    "pointsBalance", monetizationService.getPointsBalance(userId)
            ));
        }
    }

    /**
     * Get the points cost for all features.
     */
    @GetMapping("/costs")
    public ResponseEntity<Map<String, Object>> getCosts() {
        return ResponseEntity.ok(Map.of(
                "route_plan", MonetizationService.POINTS_PER_ROUTE_PLAN,
                "threat_analysis", MonetizationService.POINTS_PER_THREAT_ANALYSIS,
                "digital_twin", MonetizationService.POINTS_PER_DIGITAL_TWIN,
                "extra_contact", MonetizationService.POINTS_PER_EXTRA_CONTACT,
                "pointsPerAd", MonetizationService.POINTS_PER_AD,
                "maxDailyPointsFromAds", MonetizationService.MAX_DAILY_POINTS_FROM_ADS
        ));
    }

    /**
     * Get subscription plan details and pricing.
     */
    @GetMapping("/plans")
    public ResponseEntity<List<Map<String, Object>>> getPlans() {
        List<Map<String, Object>> plans = List.of(
                Map.of(
                        "id", "free",
                        "name", "Free",
                        "price", 0,
                        "currency", "NGN",
                        "period", "none",
                        "features", List.of(
                                "3 emergency contacts",
                                "50 messages/day",
                                "5 incidents/day",
                                "Read-only community feed",
                                "SOS alerts (always free)"
                        )
                ),
                Map.of(
                        "id", "basic",
                        "name", "Basic",
                        "price", 0,
                        "currency", "NGN",
                        "period", "none",
                        "description", "Watch ads to earn points and unlock features",
                        "features", List.of(
                                "Earn 10 points per rewarded ad",
                                "Up to 100 points/day from ads",
                                "Spend points on premium features",
                                "All free tier features"
                        )
                ),
                Map.of(
                        "id", "premium",
                        "name", "Premium",
                        "price", 1500,
                        "currency", "NGN",
                        "period", "monthly",
                        "annualPrice", 12000,
                        "annualPeriod", "yearly",
                        "features", List.of(
                                "Unlimited access to all features",
                                "No ads",
                                "500 bonus points on signup",
                                "Unlimited emergency contacts",
                                "Unlimited messages",
                                "Route planning & threat analysis",
                                "Digital twin access",
                                "Priority support"
                        )
                ),
                Map.of(
                        "id", "family",
                        "name", "Family",
                        "price", 2500,
                        "currency", "NGN",
                        "period", "monthly",
                        "features", List.of(
                                "Everything in Premium",
                                "Up to 5 family members",
                                "1000 bonus points on signup",
                                "Family dashboard",
                                "Shared emergency contacts"
                        )
                )
        );
        return ResponseEntity.ok(plans);
    }
}
