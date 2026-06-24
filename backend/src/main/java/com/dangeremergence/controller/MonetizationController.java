package com.dangeremergence.controller;

import com.dangeremergence.model.PointTransaction;
import com.dangeremergence.model.SubscriptionTier;
import com.dangeremergence.model.UserSubscription;
import com.dangeremergence.service.MonetizationService;
import com.dangeremergence.service.PaystackService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.security.Principal;
import java.util.HashMap;
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
    private final PaystackService paystackService;

    @Autowired
    public MonetizationController(MonetizationService monetizationService,
                                  PaystackService paystackService) {
        this.monetizationService = monetizationService;
        this.paystackService = paystackService;
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
     * Initialize a Paystack payment for a subscription.
     * Body: {
     *   "tier": "premium" | "family",
     *   "durationMonths": 1 | 12,
     *   "email": "user@example.com"
     * }
     * Returns the Paystack authorization URL for the user to complete payment.
     */
    @PostMapping("/initialize-payment")
    public ResponseEntity<Map<String, Object>> initializePayment(Principal principal,
                                                                  @RequestBody Map<String, Object> body) {
        String userId = principal.getName();

        String tierStr = (String) body.get("tier");
        String email = (String) body.get("email");
        int durationMonths = body.containsKey("durationMonths")
                ? ((Number) body.get("durationMonths")).intValue()
                : 1;

        if (tierStr == null || email == null) {
            return ResponseEntity.badRequest().body(Map.of(
                    "success", false,
                    "message", "Missing required fields: tier, email"
            ));
        }

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

        if (!paystackService.isConfigured()) {
            return ResponseEntity.ok(Map.of(
                    "success", false,
                    "message", "Payment gateway is not configured. Please contact support.",
                    "requiresConfiguration", true
            ));
        }

        // Calculate amount in kobo (e.g., ₦1,500 = 150000 kobo)
        int amountInKobo = PaystackService.getAmountInKobo(tier, durationMonths);

        // Attach metadata for webhook processing
        Map<String, Object> metadata = new HashMap<>();
        metadata.put("userId", userId);
        metadata.put("tier", tier.name());
        metadata.put("durationMonths", durationMonths);
        metadata.put("productId", PaystackService.getProductId(tier, durationMonths));

        Map<String, Object> result = paystackService.initializeTransaction(email, amountInKobo, metadata);

        if (result.containsKey("error")) {
            return ResponseEntity.ok(Map.of(
                    "success", false,
                    "message", result.get("error")
            ));
        }

        result.put("success", true);
        result.put("tier", tier.name());
        result.put("durationMonths", durationMonths);
        result.put("amount", amountInKobo / 100); // Return amount in Naira for display
        result.put("currency", "NGN");

        return ResponseEntity.ok(result);
    }

    /**
     * Paystack webhook endpoint.
     * Paystack sends POST requests to this URL for payment events.
     * This endpoint is PUBLIC (no auth) because Paystack signs requests.
     * <p>
     * IMPORTANT: Configure this URL in your Paystack dashboard:
     * Settings -> Webhooks -> Add Webhook URL
     * URL: https://sectop.resultscaleai.com/api/v1/monetization/paystack-webhook
     */
    @PostMapping("/paystack-webhook")
    public ResponseEntity<Map<String, Object>> paystackWebhook(
            @RequestHeader(value = "x-paystack-signature", required = false) String signature,
            @RequestBody String rawBody) {

        // Validate webhook signature
        if (signature == null || !paystackService.validateWebhookSignature(signature, rawBody)) {
            LOGGER.warn("Invalid Paystack webhook signature received");
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of(
                    "status", "error",
                    "message", "Invalid signature"
            ));
        }

        try {
            com.fasterxml.jackson.databind.ObjectMapper mapper = new com.fasterxml.jackson.databind.ObjectMapper();
            com.fasterxml.jackson.databind.JsonNode event = mapper.readTree(rawBody);

            String eventType = event.has("event") ? event.get("event").asText() : "";

            LOGGER.info("Received Paystack webhook event: {}", eventType);

            if ("charge.success".equals(eventType)) {
                com.fasterxml.jackson.databind.JsonNode data = event.get("data");
                String reference = data.has("reference") ? data.get("reference").asText() : "";
                String status = data.has("status") ? data.get("status").asText() : "";
                String paidAt = data.has("paid_at") && !data.get("paid_at").isNull()
                        ? data.get("paid_at").asText() : "";

                // Extract metadata
                String userId = "";
                String tier = "";
                int durationMonths = 1;

                if (data.has("metadata") && !data.get("metadata").isNull()) {
                    com.fasterxml.jackson.databind.JsonNode metadata = data.get("metadata");
                    userId = metadata.has("userId") ? metadata.get("userId").asText() : "";
                    tier = metadata.has("tier") ? metadata.get("tier").asText() : "";
                    durationMonths = metadata.has("durationMonths") ? metadata.get("durationMonths").asInt() : 1;
                }

                if ("success".equals(status) && !userId.isEmpty() && !tier.isEmpty()) {
                    try {
                        SubscriptionTier subscriptionTier = SubscriptionTier.valueOf(tier);
                        monetizationService.activateSubscriptionWithReference(
                                userId, subscriptionTier, "paystack", reference, durationMonths, reference);
                        LOGGER.info("Subscription activated via Paystack webhook for user {} tier {} ref {}",
                                userId, tier, reference);
                    } catch (Exception e) {
                        LOGGER.error("Failed to activate subscription from webhook", e);
                    }
                } else {
                    LOGGER.warn("Paystack charge.success but missing data: status={}, userId={}, tier={}",
                            status, userId, tier);
                }
            }

            // Always return 200 to acknowledge receipt
            return ResponseEntity.ok(Map.of("status", "success"));

        } catch (Exception e) {
            LOGGER.error("Failed to process Paystack webhook", e);
            return ResponseEntity.ok(Map.of("status", "error", "message", e.getMessage()));
        }
    }

    /**
     * Verify a Paystack payment after the user returns from the Paystack checkout page.
     * The frontend calls this with the reference from the URL callback.
     * Query param: reference (the Paystack transaction reference)
     */
    @GetMapping("/verify-paystack-payment")
    public ResponseEntity<Map<String, Object>> verifyPaystackPayment(Principal principal,
                                                                      @RequestParam String reference) {
        String userId = principal.getName();

        if (reference == null || reference.isBlank()) {
            return ResponseEntity.badRequest().body(Map.of(
                    "success", false,
                    "message", "Missing reference parameter"
            ));
        }

        Map<String, Object> verification = paystackService.verifyTransaction(reference);

        if (verification.containsKey("error")) {
            return ResponseEntity.ok(Map.of(
                    "success", false,
                    "message", verification.get("error")
            ));
        }

        String paymentStatus = (String) verification.get("status");
        if (!"success".equals(paymentStatus)) {
            return ResponseEntity.ok(Map.of(
                    "success", false,
                    "message", "Payment was not successful. Status: " + paymentStatus,
                    "paymentStatus", paymentStatus
            ));
        }

        // Extract tier and duration from metadata (already attached during init)
        String tier = (String) verification.getOrDefault("tier", "premium");
        int durationMonths = (int) verification.getOrDefault("durationMonths", 1);

        SubscriptionTier subscriptionTier;
        try {
            subscriptionTier = SubscriptionTier.valueOf(tier);
        } catch (IllegalArgumentException e) {
            return ResponseEntity.ok(Map.of(
                    "success", false,
                    "message", "Invalid tier in payment metadata"
            ));
        }

        // Activate the subscription
        UserSubscription sub = monetizationService.activateSubscriptionWithReference(
                userId, subscriptionTier, "paystack", reference, durationMonths, reference);

        return ResponseEntity.ok(Map.of(
                "success", true,
                "message", "Payment verified and subscription activated successfully",
                "tier", sub.getTier().name(),
                "subscriptionStart", sub.getSubscriptionStart(),
                "subscriptionEnd", sub.getSubscriptionEnd(),
                "pointsBalance", sub.getPointsBalance()
        ));
    }

    /**
     * Activate a subscription for the authenticated user.
     * Body: {
     *   "tier": "premium" | "family",
     *   "platform": "google_play" | "apple_app_store" | "paystack",
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

        // For Paystack payments, the subscription is activated via webhook or verify-paystack-payment
        // This endpoint is for Google Play / Apple App Store direct activation
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
                        "paystackProductId", "PREMIUM_MONTHLY",
                        "paystackAnnualProductId", "PREMIUM_ANNUAL",
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
                        "paystackProductId", "FAMILY_MONTHLY",
                        "paystackAnnualProductId", "FAMILY_ANNUAL",
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
