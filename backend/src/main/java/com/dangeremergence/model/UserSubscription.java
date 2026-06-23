package com.dangeremergence.model;

import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.UUID;

/**
 * Tracks each user's subscription tier, points balance, and subscription period.
 * One record per user (enforced by unique user_id constraint).
 */
@Entity
@Table(name = "user_subscriptions")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class UserSubscription {

    @Id
    @Column(length = 36)
    private String id;

    @Column(name = "user_id", nullable = false, unique = true, length = 36)
    private String userId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    @Builder.Default
    private SubscriptionTier tier = SubscriptionTier.free;

    @Column(name = "points_balance", nullable = false)
    @Builder.Default
    private int pointsBalance = 0;

    @Column(name = "points_earned_today", nullable = false)
    @Builder.Default
    private int pointsEarnedToday = 0;

    @Column(name = "daily_reset_date")
    private LocalDate dailyResetDate;

    @Column(name = "subscription_start")
    private LocalDateTime subscriptionStart;

    @Column(name = "subscription_end")
    private LocalDateTime subscriptionEnd;

    @Column(name = "auto_renew")
    @Builder.Default
    private boolean autoRenew = true;

    @Column(length = 20)
    private String platform; // google_play, apple_app_store

    @Column(name = "platform_subscription_id", length = 255)
    private String platformSubscriptionId;

    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @UpdateTimestamp
    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt;

    @PrePersist
    public void ensureId() {
        if (id == null) {
            id = UUID.randomUUID().toString();
        }
    }
}
