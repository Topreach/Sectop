-- Danger Emergence System - Broadcasts Table
-- Flyway Migration V5
-- Stores mass alert/broadcast messages sent to users in geographic areas

CREATE TABLE IF NOT EXISTS broadcasts (
    id VARCHAR(36) PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    severity VARCHAR(20) NOT NULL,
    broadcast_type VARCHAR(50) NOT NULL,
    target_state VARCHAR(50),
    target_lga VARCHAR(50),
    target_roles VARCHAR(255),
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    radius_km DOUBLE PRECISION,
    created_by VARCHAR(36) REFERENCES users(id),
    is_active BOOLEAN DEFAULT true,
    expires_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for query performance
CREATE INDEX IF NOT EXISTS idx_broadcasts_severity ON broadcasts(severity);
CREATE INDEX IF NOT EXISTS idx_broadcasts_type ON broadcasts(broadcast_type);
CREATE INDEX IF NOT EXISTS idx_broadcasts_target_state ON broadcasts(target_state);
CREATE INDEX IF NOT EXISTS idx_broadcasts_target_lga ON broadcasts(target_lga);
CREATE INDEX IF NOT EXISTS idx_broadcasts_created_at ON broadcasts(created_at);
CREATE INDEX IF NOT EXISTS idx_broadcasts_active ON broadcasts(is_active);
CREATE INDEX IF NOT EXISTS idx_broadcasts_created_by ON broadcasts(created_by);
