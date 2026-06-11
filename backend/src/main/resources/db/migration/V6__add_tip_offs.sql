-- Danger Emergence System - Tip-off / Intelligence Channel
-- Flyway Migration V6

CREATE TABLE IF NOT EXISTS tip_offs (
    id VARCHAR(36) PRIMARY KEY,
    tip_type VARCHAR(50) NOT NULL,
    description TEXT NOT NULL,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    accuracy DOUBLE PRECISION,
    state VARCHAR(50),
    lga VARCHAR(50),
    occurred_at TIMESTAMP,
    target_description TEXT,
    suspect_description TEXT,
    threat_score INTEGER DEFAULT 0,
    is_anonymous BOOLEAN DEFAULT true,
    reporter_id VARCHAR(36) REFERENCES users(id),
    status VARCHAR(20) DEFAULT 'pending',
    reviewed_by VARCHAR(36) REFERENCES users(id),
    review_notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_tip_offs_status ON tip_offs(status);
CREATE INDEX IF NOT EXISTS idx_tip_offs_threat ON tip_offs(threat_score DESC);
CREATE INDEX IF NOT EXISTS idx_tip_offs_location ON tip_offs(latitude, longitude);
CREATE INDEX IF NOT EXISTS idx_tip_offs_created ON tip_offs(created_at DESC);
