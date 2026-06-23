# Monetization Plan: Points/Credits System

## Overview

Users earn **points/credits** to use the app's features. Two ways to earn:

1. **Subscribe** (monthly/yearly) → automatic unlimited points each period
2. **Watch ads** → earn points per ad watched

---

## Feature Tiers

| Feature | Free (0 pts/day) | Basic (earn via ads) | Premium (subscribers) |
|---------|-----------------|---------------------|----------------------|
| SOS Alerts | ✅ Unlimited | ✅ Unlimited | ✅ Unlimited |
| Emergency Contacts | 3 contacts | 10 contacts | Unlimited |
| Safe Route Planning | ❌ Locked | 5 routes/day | Unlimited |
| Threat Analysis | ❌ Locked | 10 analyses/day | Unlimited |
| Community Feed | ✅ Read only | ✅ Full access | ✅ Full access |
| Messaging | 50 msgs/day | 200 msgs/day | Unlimited |
| Incident Reports | 5/day | 20/day | Unlimited |
| Digital Twin Evacuation | ❌ Locked | 2/month | Unlimited |
| Ads | Shown | Reduced | **No ads** |

---

## Points Economy

| Action | Points Cost/Earned |
|--------|-------------------|
| Watch 1 ad (rewarded video) | **Earn 10 points** |
| Safe Route Plan | Cost 2 points |
| Threat Analysis | Cost 1 point |
| Digital Twin Evacuation | Cost 5 points |
| Extra Emergency Contact slot (beyond free limit) | Cost 3 points each |

---

## Subscription Plans

| Plan | Price | Points/Month | Bonus |
|------|-------|-------------|-------|
| Monthly Premium | $2.99/mo | 500 pts + unlimited features | No ads |
| Yearly Premium | $19.99/yr | 6000 pts + unlimited features | No ads, 2 months free |
| Family (up to 5) | $4.99/mo | Unlimited for all members | No ads, shared contacts |

---

## Implementation Plan

### Phase 1: Backend Database Changes

**New table: `user_subscriptions`**
```sql
CREATE TABLE user_subscriptions (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL UNIQUE,
    tier VARCHAR(20) NOT NULL DEFAULT 'free',       -- free, basic, premium, family
    points_balance INT NOT NULL DEFAULT 0,
    points_earned_today INT NOT NULL DEFAULT 0,
    subscription_start TIMESTAMP,
    subscription_end TIMESTAMP,
    auto_renew BOOLEAN DEFAULT TRUE,
    platform VARCHAR(20),                            -- google_play, apple_app_store
    platform_subscription_id VARCHAR(255),
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id)
);
```

**New table: `ad_watch_log`**
```sql
CREATE TABLE ad_watch_log (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL,
    points_earned INT NOT NULL,
    watched_at TIMESTAMP NOT NULL,
    ad_provider VARCHAR(50),                         -- google_admob, etc.
    FOREIGN KEY (user_id) REFERENCES users(id)
);
```

**New table: `point_transactions`**
```sql
CREATE TABLE point_transactions (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL,
    amount INT NOT NULL,                             -- positive = earned, negative = spent
    transaction_type VARCHAR(30) NOT NULL,           -- ad_watch, subscription_bonus, route_plan, threat_analysis, etc.
    reference_id VARCHAR(255),                       -- optional: links to specific feature usage
    created_at TIMESTAMP NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id)
);
```

### Phase 2: Backend New Files

1. **`SubscriptionTier` enum** — `free`, `basic`, `premium`, `family`
2. **`UserSubscription` entity** — maps to `user_subscriptions` table
3. **`UserSubscriptionRepository`** — JPA repository
4. **`PointTransaction` entity** — maps to `point_transactions` table
5. **`PointTransactionRepository`** — JPA repository
6. **`AdWatchLog` entity** — maps to `ad_watch_log` table
7. **`AdWatchLogRepository`** — JPA repository
8. **`MonetizationService`** — core business logic:
   - `getUserTier(userId)` → returns current tier
   - `getPointsBalance(userId)` → returns current points
   - `earnPointsFromAd(userId)` → adds points, logs ad watch
   - `spendPoints(userId, amount, type)` → deducts points if sufficient
   - `hasAccess(userId, feature)` → checks tier + points for feature access
   - `checkAndResetDailyLimit(userId)` → resets daily earned points counter
9. **`MonetizationController`** — REST endpoints:
   - `GET /api/v1/monetization/status` — tier, points, limits
   - `POST /api/v1/monetization/earn-from-ad` — record ad watch, add points
   - `POST /api/v1/monetization/subscribe` — start subscription
   - `POST /api/v1/monetization/cancel-subscription` — cancel auto-renew
   - `POST /api/v1/monetization/verify-purchase` — verify Google Play/Apple receipt

### Phase 3: Frontend New Files

1. **`frontend/lib/modules/monetization/`** — new module directory
2. **`monetization_service.dart`** — service class:
   - `getStatus()` → calls `GET /monetization/status`
   - `earnFromAd()` → calls `POST /monetization/earn-from-ad`
   - `subscribe(planId, platform, receipt)` → calls `POST /monetization/subscribe`
   - `cancelSubscription()` → calls `POST /monetization/cancel-subscription`
   - `hasFeatureAccess(feature)` → checks local cache of tier/points
3. **`subscription_screen.dart`** — subscription plans UI
4. **`points_balance_widget.dart`** — reusable widget showing points + tier badge
5. **`earn_points_screen.dart`** — screen showing "Watch Ad to Earn Points" button
6. **`feature_gate_mixin.dart`** — mixin/widget that wraps features and shows "Premium" lock overlay

### Phase 4: Frontend Integration Points

1. **`pubspec.yaml`** — add `google_mobile_ads` package for AdMob
2. **`constants.dart`** — add:
   - `static const int maxFreeEmergencyContacts = 3`
   - `static const int maxFreeMessagesPerDay = 50`
   - `static const int maxFreeIncidentsPerDay = 5`
   - `static const int pointsPerAd = 10`
   - `static const int pointsPerRoutePlan = 2`
   - `static const int pointsPerThreatAnalysis = 1`
   - `static const int maxDailyPointsFromAds = 100`
3. **Feature gating in existing screens**:
   - `dashboard_screen.dart` — check tier before showing route planning button
   - `emergency_contacts_screen.dart` — enforce max free contacts limit
   - `message_screen.dart` — enforce daily message limit
   - `incident_report_screen.dart` — enforce daily incident limit
   - `threat_analysis_screen.dart` — enforce points cost
   - `route_planning_screen.dart` — enforce points cost
4. **`app_bar_extension.dart`** — add points balance icon in app bar across screens

### Phase 5: Ad Integration (Google AdMob)

1. Add `google_mobile_ads` to `pubspec.yaml`
2. Initialize AdMob in `main.dart`
3. **Rewarded Ads** — full-screen video ads that users watch to earn points
4. **Banner Ads** — shown on community feed and non-critical screens for free users
5. **No ads during SOS** — critical safety feature, never show ads during emergencies

---

## Data Flow Diagrams

### Points Earning Flow
```
User taps "Watch Ad to Earn Points"
  → MonetizationService.earnFromAd()
  → Frontend shows rewarded ad (AdMob)
  → Ad completes → Frontend calls POST /monetization/earn-from-ad
  → Backend MonetizationService:
      1. Check daily limit not exceeded
      2. Add points to user_subscriptions.points_balance
      3. Insert ad_watch_log record
      4. Insert point_transactions record (+10)
  → Response returns new balance
  → UI updates points badge
```

### Feature Access Check Flow
```
User taps "Plan Safe Route"
  → Frontend checks local cache: is user premium? 
     YES → proceed
     NO → check points balance ≥ 2?
       YES → call POST /routes/plan with spend_points=true
              Backend deducts 2 points, returns route
       NO → show "Earn Points" dialog:
              [Watch Ad] [Subscribe] [Cancel]
```

### Subscription Purchase Flow
```
User selects "Monthly Premium $2.99"
  → Google Play Billing / Apple App Store purchase dialog
  → Purchase completed → platform returns receipt token
  → Frontend calls POST /monetization/verify-purchase
     with { platform, receipt, plan_id }
  → Backend verifies receipt with Google/Apple API
  → On success:
      1. Update user_subscriptions tier=premium
      2. Set subscription_start/end dates
      3. Add subscription bonus points
      4. Insert point_transactions record
  → Response returns updated status
  → UI refreshes to show premium features unlocked
```

---

## Migration SQL

```sql
-- V16__add_monetization.sql

CREATE TABLE user_subscriptions (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL UNIQUE,
    tier VARCHAR(20) NOT NULL DEFAULT 'free',
    points_balance INT NOT NULL DEFAULT 0,
    points_earned_today INT NOT NULL DEFAULT 0,
    daily_reset_date DATE,
    subscription_start TIMESTAMP NULL,
    subscription_end TIMESTAMP NULL,
    auto_renew BOOLEAN DEFAULT TRUE,
    platform VARCHAR(20) NULL,
    platform_subscription_id VARCHAR(255) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE point_transactions (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL,
    amount INT NOT NULL,
    transaction_type VARCHAR(30) NOT NULL,
    reference_id VARCHAR(255) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE ad_watch_log (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL,
    points_earned INT NOT NULL,
    ad_provider VARCHAR(50) NULL,
    watched_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX idx_point_transactions_user ON point_transactions(user_id);
CREATE INDEX idx_ad_watch_log_user_date ON ad_watch_log(user_id, watched_at);
CREATE INDEX idx_user_subscriptions_tier ON user_subscriptions(tier);
```
