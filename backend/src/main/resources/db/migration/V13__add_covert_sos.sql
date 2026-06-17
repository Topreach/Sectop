-- V13: Add covert SOS support
-- Adds is_covert column to sos_alerts table for covert/stealth mode alerts.
-- Covert alerts are NOT broadcast to public channels — only delivered to
-- emergency contacts and verified responders via private FCM push.

ALTER TABLE sos_alerts
    ADD COLUMN IF NOT EXISTS is_covert BOOLEAN NOT NULL DEFAULT FALSE;

-- Add index for querying covert alerts
CREATE INDEX IF NOT EXISTS idx_sos_alerts_covert ON sos_alerts (is_covert);

-- Add index for querying covert alerts by user
CREATE INDEX IF NOT EXISTS idx_sos_alerts_user_covert ON sos_alerts (user_id, is_covert);

-- Add comment for documentation
COMMENT ON COLUMN sos_alerts.is_covert IS 'If true, alert is only sent to emergency contacts and verified responders — no public broadcast';
