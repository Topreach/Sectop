-- V10: Add evidence table for photo/video/audio evidence storage
-- Supports offline-first sync with base64 content storage
-- PostgreSQL version (adapted from MySQL original)

CREATE TABLE IF NOT EXISTS evidence (
    id          VARCHAR(64)     PRIMARY KEY,
    parent_id   VARCHAR(64)     NOT NULL,
    parent_type VARCHAR(16)     NOT NULL,
    evidence_type VARCHAR(16)   NOT NULL,
    file_name   VARCHAR(255),
    mime_type   VARCHAR(64),
    size_bytes  BIGINT,
    file_content TEXT,
    file_url    VARCHAR(1024),
    latitude    DOUBLE PRECISION,
    longitude   DOUBLE PRECISION,
    captured_at TIMESTAMP       NOT NULL,
    created_at  TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for query performance
CREATE INDEX IF NOT EXISTS idx_evidence_parent_id ON evidence(parent_id);
CREATE INDEX IF NOT EXISTS idx_evidence_parent_type ON evidence(parent_type);
CREATE INDEX IF NOT EXISTS idx_evidence_type ON evidence(evidence_type);
CREATE INDEX IF NOT EXISTS idx_evidence_captured_at ON evidence(captured_at);
