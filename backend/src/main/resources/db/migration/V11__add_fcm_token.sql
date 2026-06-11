-- V11: Add FCM push notification token to users table
-- This enables Firebase Cloud Messaging for offline alert delivery

ALTER TABLE users ADD COLUMN IF NOT EXISTS fcm_token VARCHAR(512);

-- Add index for querying users with FCM tokens
CREATE INDEX IF NOT EXISTS idx_users_fcm_token ON users (fcm_token)
    WHERE fcm_token IS NOT NULL AND fcm_token <> '';
