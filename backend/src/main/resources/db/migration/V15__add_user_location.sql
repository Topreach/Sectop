-- Danger Emergence System - User Location Fields
-- Flyway Migration V15
-- Adds latitude/longitude columns to users table for geo-fencing
-- and nearby user queries (used by findUsersInArea() query)

ALTER TABLE users ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION;
ALTER TABLE users ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;

-- Add index for geo-spatial queries on active users with FCM tokens
CREATE INDEX IF NOT EXISTS idx_users_location ON users (latitude, longitude)
    WHERE latitude IS NOT NULL AND longitude IS NOT NULL;
