-- Danger Emergence System - Incidents Table
-- Flyway Migration V4
--
-- This table stores crowdsourced incident reports (kidnapping, terrorism,
-- banditry, suspicious activity) with GPS coordinates for heatmap visualization
-- and pattern analysis.

CREATE TABLE IF NOT EXISTS incidents (
    id VARCHAR(36) PRIMARY KEY,
    reporter_id VARCHAR(36) REFERENCES users(id),
    incident_type VARCHAR(100) NOT NULL,
    description TEXT,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    accuracy DOUBLE PRECISION,
    state VARCHAR(50),
    lga VARCHAR(50),
    occurred_at TIMESTAMP NOT NULL,
    severity VARCHAR(20) NOT NULL DEFAULT 'medium',
    is_anonymous BOOLEAN DEFAULT false,
    is_verified BOOLEAN DEFAULT false,
    verified_by VARCHAR(36) REFERENCES users(id),
    status VARCHAR(20) NOT NULL DEFAULT 'reported',
    upvote_count INTEGER DEFAULT 0,
    witness_count INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for spatial queries and filtering
CREATE INDEX IF NOT EXISTS idx_incidents_type ON incidents(incident_type);
CREATE INDEX IF NOT EXISTS idx_incidents_status ON incidents(status);
CREATE INDEX IF NOT EXISTS idx_incidents_severity ON incidents(severity);
CREATE INDEX IF NOT EXISTS idx_incidents_location ON incidents(latitude, longitude);
CREATE INDEX IF NOT EXISTS idx_incidents_occurred_at ON incidents(occurred_at);
CREATE INDEX IF NOT EXISTS idx_incidents_created_at ON incidents(created_at);
CREATE INDEX IF NOT EXISTS idx_incidents_reporter ON incidents(reporter_id);
CREATE INDEX IF NOT EXISTS idx_incidents_state ON incidents(state);
CREATE INDEX IF NOT EXISTS idx_incidents_lga ON incidents(lga);

-- Composite indexes for common query patterns
CREATE INDEX IF NOT EXISTS idx_incidents_type_status ON incidents(incident_type, status);
CREATE INDEX IF NOT EXISTS idx_incidents_status_severity ON incidents(status, severity);
CREATE INDEX IF NOT EXISTS idx_incidents_location_time ON incidents(latitude, longitude, occurred_at);
