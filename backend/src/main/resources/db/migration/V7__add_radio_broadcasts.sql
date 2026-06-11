-- Danger Emergence System - Emergency Broadcast Radio Integration
-- Flyway Migration V7

CREATE TABLE IF NOT EXISTS radio_broadcasts (
    id VARCHAR(36) PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    language VARCHAR(20) DEFAULT 'en',
    severity VARCHAR(20) NOT NULL DEFAULT 'urgent',
    broadcast_type VARCHAR(50) NOT NULL DEFAULT 'emergency',
    target_frequency DOUBLE PRECISION,
    target_state VARCHAR(50),
    target_lga VARCHAR(50),
    audio_duration_seconds INTEGER,
    audio_file_url TEXT,
    tts_voice VARCHAR(50) DEFAULT 'default',
    is_anonymous BOOLEAN DEFAULT false,
    created_by VARCHAR(36) REFERENCES users(id),
    status VARCHAR(20) DEFAULT 'pending',
    broadcast_count INTEGER DEFAULT 0,
    last_broadcast_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_radio_broadcasts_status ON radio_broadcasts(status);
CREATE INDEX IF NOT EXISTS idx_radio_broadcasts_created ON radio_broadcasts(created_at DESC);
