package com.dangeremergence.service;

import com.dangeremergence.model.*;
import com.dangeremergence.repository.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.*;

/**
 * Core business logic for the points/credits monetization system.
 * Manages subscription tiers, points balance, ad-watch earnings,
 * and feature access control.
 */
@Service
public class MonetizationService {

    private static final Logger LOGGER = LoggerFactory.getLogger(MonetizationService.class);

    // Points configuration
    public static final int POINTS_PER_AD = 10;
    public static final int MAX_DAILY_POINTS_FROM_ADS = 100;
    public static final int POINTS_PER_ROUTE_PLAN = 2;
    public static final int POINTS_PER_THREAT_ANALYSIS = 1;
    public static final int POINTS_PER_DIGITAL_TWIN = 5;
    public static final int POINTS_PER_EXTRA_CONTACT = 3;

    // Free tier limits
    public static final int FREE_MAX_EMERGENCY_CONTACTS = 3;
    public static final int FREE_MAX_MESSAGES_PER_DAY = 50;
    public static final int FREE_MAX_INCIDENTS_PER_DAY = 5;

    private final UserSubscriptionRepository subscriptionRepository;
    private final PointTransactionRepository transactionRepository;
    private final AdWatchLogRepository adWatchLogRepository;

    @Autowired
    public MonetizationService(UserSubscriptionRepository subscriptionRepository,
                               PointTransactionRepository transactionRepository,
                               AdWatchLogRepository adWatchLogRepository) {
        this.subscriptionRepository = subscriptionRepository;
        this.transactionRepository = transactionRepository;
        this.adWatchLogRepository = adWatchLogRepository;
    }

    // -----------------------------------------------------------------------
    // Subscription / Tier Management
    // -----------------------------------------------------------------------

    /**
     * Get or create a subscription record for the given user.
     */
    @Transactional
    public UserSubscription getOrCreateSubscription(String userId) {
        return subscriptionRepository.findByUserId(userId)
                .orElseGet(() -> {
                    UserSubscription sub = UserSubscription.builder()
                            .userId(userId)
                            .tier(SubscriptionTier.free)
                            .pointsBalance(0)
                            .pointsEarnedToday(0)
                            .dailyResetDate(LocalDate.now())
                            .autoRenew(true)
                            .build();
                    return subscriptionRepository.save(sub);
                });
    }

    /**
     * Get the current tier for a user.
     */
    public SubscriptionTier getUserTier(String userId) {
        return getOrCreateSubscription(userId).getTier();
    }

    /**
     * Get the current points balance for a user.
     */
    public int getPointsBalance(String userId) {
        return getOrCreateSubscription(userId).getPointsBalance();
    }

    /**
     * Get full monetization status for a user.
     */
    @Transactional(readOnly = true)
    public Map<String, Object> getStatus(String userId) {
        UserSubscription sub = getOrCreateSubscription(userId);
        Map<String, Object> status = new LinkedHashMap<>();
        status.put("tier", sub.getTier().name());
        status.put("pointsBalance", sub.getPointsBalance());
        status.put("pointsEarnedToday", sub.getPointsEarnedToday());
        status.put("maxDailyPoints", MAX_DAILY_POINTS_FROM_ADS);
        status.put("subscriptionStart", sub.getSubscriptionStart());
        status.put("subscriptionEnd", sub.getSubscriptionEnd());
        status.put("autoRenew", sub.isAutoRenew());
        status.put("platform", sub.getPlatform());
        return status;
    }

    // -----------------------------------------------------------------------
    // Points Earning (Ad Watches)
    // -----------------------------------------------------------------------

    /**
     * Record an ad watch and award points to the user.
     * Enforces daily limit on points earned from ads.
     *
     * @return the new points balance, or -1 if daily limit exceeded
     */
    @Transactional
    public int earnPointsFromAd(String userId, String adProvider) {
        UserSubscription sub = getOrCreateSubscription(userId);

        // Reset daily counter if new day
        LocalDate today = LocalDate.now();
        if (!today.equals(sub.getDailyResetDate())) {
            sub.setPointsEarnedToday(0);
            sub.setDailyResetDate(today);
        }

        // Check daily limit
        if (sub.getPointsEarnedToday() + POINTS_PER_AD > MAX_DAILY_POINTS_FROM_ADS) {
            LOGGER.debug("User {} exceeded daily ad points limit", userId);
            return -1;
        }

        // Award points
        sub.setPointsBalance(sub.getPointsBalance() + POINTS_PER_AD);
        sub.setPointsEarnedToday(sub.getPointsEarnedToday() + POINTS_PER_AD);
        subscriptionRepository.save(sub);

        // Log the ad watch
        AdWatchLog log = AdWatchLog.builder()
                .userId(userId)
                .pointsEarned(POINTS_PER_AD)
                .adProvider(adProvider != null ? adProvider : "unknown")
                .build();
        adWatchLogRepository.save(log);

        // Record transaction
        PointTransaction tx = PointTransaction.builder()
                .userId(userId)
                .amount(POINTS_PER_AD)
                .transactionType("ad_watch")
                .build();
        transactionRepository.save(tx);

        LOGGER.debug("User {} earned {} points from ad. Balance: {}", userId, POINTS_PER_AD, sub.getPointsBalance());
        return sub.getPointsBalance();
    }

    // -----------------------------------------------------------------------
    // Points Spending
    // -----------------------------------------------------------------------

    /**
     * Spend points for a feature. Returns true if successful, false if insufficient points.
     */
    @Transactional
    public boolean spendPoints(String userId, int amount, String transactionType, String referenceId) {
        UserSubscription sub = getOrCreateSubscription(userId);

        if (sub.getPointsBalance() < amount) {
            return false;
        }

        sub.setPointsBalance(sub.getPointsBalance() - amount);
        subscriptionRepository.save(sub);

        PointTransaction tx = PointTransaction.builder()
                .userId(userId)
                .amount(-amount)
                .transactionType(transactionType)
                .referenceId(referenceId)
                .build();
        transactionRepository.save(tx);

        LOGGER.debug("User {} spent {} points on {}. Balance: {}", userId, amount, transactionType, sub.getPointsBalance());
        return true;
    }

    // -----------------------------------------------------------------------
    // Feature Access Control
    // -----------------------------------------------------------------------

    /**
     * Check if a user has access to a premium feature.
     * Premium/family subscribers get unlimited access.
     * Free/basic users must have sufficient points.
     *
     * @return Map with "hasAccess" boolean and optional "pointsRequired" / "message"
     */
    public Map<String, Object> checkFeatureAccess(String userId, String feature) {
        SubscriptionTier tier = getUserTier(userId);
        Map<String, Object> result = new LinkedHashMap<>();

        // Premium and family tiers get unlimited access
        if (tier == SubscriptionTier.premium || tier == SubscriptionTier.family) {
            result.put("hasAccess", true);
            result.put("tier", tier.name());
            return result;
        }

        int pointsRequired = getPointsCost(feature);
        if (pointsRequired == 0) {
            // Free feature
            result.put("hasAccess", true);
            result.put("tier", tier.name());
            return result;
        }

        int balance = getPointsBalance(userId);
        if (balance >= pointsRequired) {
            result.put("hasAccess", true);
            result.put("tier", tier.name());
            result.put("pointsRequired", pointsRequired);
            result.put("pointsBalance", balance);
        } else {
            result.put("hasAccess", false);
            result.put("tier", tier.name());
            result.put("pointsRequired", pointsRequired);
            result.put("pointsBalance", balance);
            result.put("message", "Insufficient points. Watch ads or subscribe for unlimited access.");
        }

        return result;
    }

    /**
     * Get the points cost for a specific feature.
     */
    public int getPointsCost(String feature) {
        switch (feature) {
            case "route_plan":
                return POINTS_PER_ROUTE_PLAN;
            case "threat_analysis":
                return POINTS_PER_THREAT_ANALYSIS;
            case "digital_twin":
                return POINTS_PER_DIGITAL_TWIN;
            case "extra_contact":
                return POINTS_PER_EXTRA_CONTACT;
            default:
                return 0;
        }
    }

    // -----------------------------------------------------------------------
    // Subscription Management
    // -----------------------------------------------------------------------

    /**
     * Upgrade a user to a premium subscription.
     * In production, this would verify the platform receipt (Google Play / Apple).
     */
    @Transactional
    public UserSubscription activateSubscription(String userId, SubscriptionTier tier,
                                                  String platform, String platformSubscriptionId,
                                                  int durationMonths) {
        UserSubscription sub = getOrCreateSubscription(userId);
        sub.setTier(tier);
        sub.setPlatform(platform);
        sub.setPlatformSubscriptionId(platformSubscriptionId);
        sub.setPaystackReference(null);
        sub.setSubscriptionStart(LocalDateTime.now());
        sub.setSubscriptionEnd(LocalDateTime.now().plusMonths(durationMonths));
        sub.setAutoRenew(true);
        sub = subscriptionRepository.save(sub);

        // Award subscription bonus points
        int bonusPoints = switch (tier) {
            case premium -> 500;
            case family -> 1000;
            default -> 0;
        };
        if (bonusPoints > 0) {
            sub.setPointsBalance(sub.getPointsBalance() + bonusPoints);
            subscriptionRepository.save(sub);

            PointTransaction tx = PointTransaction.builder()
                    .userId(userId)
                    .amount(bonusPoints)
                    .transactionType("subscription_bonus")
                    .build();
            transactionRepository.save(tx);
        }

        LOGGER.info("User {} activated {} subscription for {} months", userId, tier, durationMonths);
        return sub;
    }

    /**
     * Activate a subscription with a Paystack payment reference.
     * This is called after successful Paystack payment verification (webhook or callback).
     */
    @Transactional
    public UserSubscription activateSubscriptionWithReference(String userId, SubscriptionTier tier,
                                                               String platform, String platformSubscriptionId,
                                                               int durationMonths, String paystackReference) {
        UserSubscription sub = getOrCreateSubscription(userId);
        sub.setTier(tier);
        sub.setPlatform(platform);
        sub.setPlatformSubscriptionId(platformSubscriptionId);
        sub.setPaystackReference(paystackReference);
        sub.setSubscriptionStart(LocalDateTime.now());
        sub.setSubscriptionEnd(LocalDateTime.now().plusMonths(durationMonths));
        sub.setAutoRenew(true);
        sub = subscriptionRepository.save(sub);

        // Award subscription bonus points
        int bonusPoints = switch (tier) {
            case premium -> 500;
            case family -> 1000;
            default -> 0;
        };
        if (bonusPoints > 0) {
            sub.setPointsBalance(sub.getPointsBalance() + bonusPoints);
            subscriptionRepository.save(sub);

            PointTransaction tx = PointTransaction.builder()
                    .userId(userId)
                    .amount(bonusPoints)
                    .transactionType("subscription_bonus")
                    .build();
            transactionRepository.save(tx);
        }

        LOGGER.info("User {} activated {} subscription via Paystack ref {} for {} months",
                userId, tier, paystackReference, durationMonths);
        return sub;
    }

    /**
     * Cancel auto-renewal for a subscription.
     */
    @Transactional
    public void cancelAutoRenew(String userId) {
        subscriptionRepository.findByUserId(userId).ifPresent(sub -> {
            sub.setAutoRenew(false);
            subscriptionRepository.save(sub);
            LOGGER.info("User {} cancelled auto-renewal", userId);
        });
    }

    /**
     * Check if a subscription has expired and downgrade if needed.
     */
    @Transactional
    public void checkAndDowngradeExpired() {
        List<UserSubscription> active = subscriptionRepository.findAll();
        LocalDateTime now = LocalDateTime.now();
        for (UserSubscription sub : active) {
            if (sub.getSubscriptionEnd() != null && now.isAfter(sub.getSubscriptionEnd())) {
                if (sub.getTier() == SubscriptionTier.premium || sub.getTier() == SubscriptionTier.family) {
                    sub.setTier(SubscriptionTier.free);
                    sub.setSubscriptionStart(null);
                    sub.setSubscriptionEnd(null);
                    sub.setPlatform(null);
                    sub.setPlatformSubscriptionId(null);
                    subscriptionRepository.save(sub);
                    LOGGER.info("User {} subscription expired, downgraded to free", sub.getUserId());
                }
            }
        }
    }

    // -----------------------------------------------------------------------
    // Transaction History
    // -----------------------------------------------------------------------

    /**
     * Get point transaction history for a user.
     */
    public List<PointTransaction> getTransactionHistory(String userId) {
        return transactionRepository.findByUserIdOrderByCreatedAtDesc(userId);
    }
}
