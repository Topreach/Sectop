-- Danger Emergence System - Initial Schema
-- Flyway Migration V1

CREATE TABLE IF NOT EXISTS users (
    id VARCHAR(36) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    phone VARCHAR(50) UNIQUE,
    role VARCHAR(50) NOT NULL DEFAULT 'citizen',
    password_hash VARCHAR(512) NOT NULL,
    public_key TEXT,
    emergency_contacts TEXT,
    medical_info TEXT,
    last_seen TIMESTAMP,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS messages (
    id VARCHAR(36) PRIMARY KEY,
    sender_id VARCHAR(36) REFERENCES users(id),
    receiver_id VARCHAR(36) REFERENCES users(id),
    content TEXT NOT NULL,
    message_type VARCHAR(50) NOT NULL DEFAULT 'text',
    priority INTEGER DEFAULT 0,
    status VARCHAR(50) NOT NULL DEFAULT 'pending',
    sync_state VARCHAR(50) NOT NULL DEFAULT 'offline',
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    delivered_at TIMESTAMP,
    read_at TIMESTAMP,
    expires_at TIMESTAMP
);

CREATE TABLE IF NOT EXISTS sos_alerts (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(36) REFERENCES users(id),
    alert_type VARCHAR(100) NOT NULL,
    description TEXT,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    accuracy DOUBLE PRECISION,
    priority INTEGER DEFAULT 1,
    status VARCHAR(50) NOT NULL DEFAULT 'active',
    mesh_relayed BOOLEAN DEFAULT false,
    acknowledged_by TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    resolved_at TIMESTAMP
);

CREATE TABLE IF NOT EXISTS zones (
    id VARCHAR(36) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    type VARCHAR(50) NOT NULL,
    description TEXT,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    radius DOUBLE PRECISION,
    geometry TEXT,
    severity VARCHAR(50),
    status VARCHAR(50) NOT NULL DEFAULT 'active',
    created_by VARCHAR(36) REFERENCES users(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_messages_sender ON messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_messages_receiver ON messages(receiver_id);
CREATE INDEX IF NOT EXISTS idx_messages_status ON messages(status);
CREATE INDEX IF NOT EXISTS idx_messages_sync_state ON messages(sync_state);
CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages(created_at);
CREATE INDEX IF NOT EXISTS idx_messages_priority ON messages(priority);

CREATE INDEX IF NOT EXISTS idx_sos_alerts_user ON sos_alerts(user_id);
CREATE INDEX IF NOT EXISTS idx_sos_alerts_status ON sos_alerts(status);
CREATE INDEX IF NOT EXISTS idx_sos_alerts_location ON sos_alerts(latitude, longitude);
CREATE INDEX IF NOT EXISTS idx_sos_alerts_created_at ON sos_alerts(created_at);

CREATE INDEX IF NOT EXISTS idx_zones_type ON zones(type);
CREATE INDEX IF NOT EXISTS idx_zones_status ON zones(status);
CREATE INDEX IF NOT EXISTS idx_zones_location ON zones(latitude, longitude);
CREATE INDEX IF NOT EXISTS idx_zones_created_at ON zones(created_at);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);
CREATE INDEX IF NOT EXISTS idx_users_last_seen ON users(last_seen);
CREATE INDEX IF NOT EXISTS idx_users_id ON users(id);
CREATE INDEX IF NOT EXISTS idx_users_created_at ON users(created_at);

-- Composite indexes for common query patterns
CREATE INDEX IF NOT EXISTS idx_messages_sender_created ON messages(sender_id, created_at);
CREATE INDEX IF NOT EXISTS idx_messages_receiver_created ON messages(receiver_id, created_at);
CREATE INDEX IF NOT EXISTS idx_messages_status_created ON messages(status, created_at);
CREATE INDEX IF NOT EXISTS idx_sos_alerts_user_created ON sos_alerts(user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_sos_alerts_status_created ON sos_alerts(status, created_at);
CREATE INDEX IF NOT EXISTS idx_zones_type_status ON zones(type, status);
CREATE INDEX IF NOT EXISTS idx_zones_location_active ON zones(latitude, longitude) WHERE status = 'active';
