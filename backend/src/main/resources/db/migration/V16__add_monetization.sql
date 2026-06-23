-- Danger Emergence System - Monetization / Points System
-- Flyway Migration V16
-- Adds tables for subscription tiers, points transactions, and ad watch logging.

-- User Subscriptions table
-- One record per user, tracks their tier, points balance, and subscription period
CREATE TABLE IF NOT EXISTS user_subscriptions (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(255) NOT NULL UNIQUE,
    tier VARCHAR(20) NOT NULL DEFAULT 'free',
    points_balance INTEGER NOT NULL DEFAULT 0,
    points_earned_today INTEGER NOT NULL DEFAULT 0,
    daily_reset_date DATE NOT NULL DEFAULT CURRENT_DATE,
    subscription_start TIMESTAMP,
    subscription_end TIMESTAMP,
    auto_renew BOOLEAN NOT NULL DEFAULT TRUE,
    platform VARCHAR(50),
    platform_subscription_id VARCHAR(255),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Index for finding expired subscriptions (used by scheduled downgrade task)
CREATE INDEX IF NOT EXISTS idx_user_subscriptions_end
    ON user_subscriptions (subscription_end)
    WHERE subscription_end IS NOT NULL;

-- Index for daily reset queries
CREATE INDEX IF NOT EXISTS idx_user_subscriptions_daily_reset
    ON user_subscriptions (daily_reset_date);

-- Point Transactions table
-- Audit trail for all points earned and spent
CREATE TABLE IF NOT EXISTS point_transactions (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(255) NOT NULL,
    amount INTEGER NOT NULL,
    transaction_type VARCHAR(50) NOT NULL,
    reference_id VARCHAR(255),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Index for user transaction history queries
CREATE INDEX IF NOT EXISTS idx_point_transactions_user
    ON point_transactions (user_id, created_at DESC);

-- Index for counting transactions by type (e.g., daily ad earnings)
CREATE INDEX IF NOT EXISTS idx_point_transactions_type
    ON point_transactions (user_id, transaction_type, created_at);

-- Ad Watch Log table
-- Logs each ad watch for audit and daily limit enforcement
CREATE TABLE IF NOT EXISTS ad_watch_logs (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(255) NOT NULL,
    points_earned INTEGER NOT NULL DEFAULT 10,
    ad_provider VARCHAR(50) NOT NULL DEFAULT 'unknown',
    watched_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Index for daily ad watch count queries
CREATE INDEX IF NOT EXISTS idx_ad_watch_logs_user_date
    ON ad_watch_logs (user_id, watched_at);
