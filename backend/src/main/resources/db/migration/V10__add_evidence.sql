-- V10: Add evidence table for photo/video/audio evidence storage
-- Supports offline-first sync with base64 content storage

CREATE TABLE evidence (
    id          VARCHAR(64)     PRIMARY KEY,
    parent_id   VARCHAR(64)     NOT NULL,
    parent_type VARCHAR(16)     NOT NULL COMMENT 'alert, incident, or tip',
    evidence_type VARCHAR(16)   NOT NULL COMMENT 'photo, video, or audio',
    file_name   VARCHAR(255),
    mime_type   VARCHAR(64),
    size_bytes  BIGINT,
    file_content MEDIUMTEXT     COMMENT 'Base64-encoded file content for offline-first sync',
    file_url    VARCHAR(1024)   COMMENT 'URL if stored externally (S3/MinIO)',
    latitude    DOUBLE,
    longitude   DOUBLE,
    captured_at DATETIME        NOT NULL,
    created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,

    INDEX idx_evidence_parent_id (parent_id),
    INDEX idx_evidence_parent_type (parent_type),
    INDEX idx_evidence_type (evidence_type),
    INDEX idx_evidence_captured_at (captured_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
