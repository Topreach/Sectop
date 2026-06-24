-- V17: Add paystack_reference column to user_subscriptions table
-- This stores the Paystack transaction reference for payment verification

ALTER TABLE user_subscriptions
    ADD COLUMN IF NOT EXISTS paystack_reference VARCHAR(100);
