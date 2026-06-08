-- Danger Emergence System - Add missing SOS Alert columns
-- Flyway Migration V3
-- Adds state, lga, and is_silent columns that were missing from V1

ALTER TABLE sos_alerts
    ADD COLUMN IF NOT EXISTS state VARCHAR(50),
    ADD COLUMN IF NOT EXISTS lga VARCHAR(50),
    ADD COLUMN IF NOT EXISTS is_silent BOOLEAN DEFAULT false;

-- Add indexes for the new columns for query performance
CREATE INDEX IF NOT EXISTS idx_sos_alerts_state ON sos_alerts(state);
CREATE INDEX IF NOT EXISTS idx_sos_alerts_lga ON sos_alerts(lga);
CREATE INDEX IF NOT EXISTS idx_sos_alerts_state_lga ON sos_alerts(state, lga);
