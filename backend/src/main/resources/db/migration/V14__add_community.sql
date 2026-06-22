-- Danger Emergence System - Community Section
-- Flyway Migration V14
-- Adds tables for community posts, likes, comments, favorites, and shares

CREATE TABLE IF NOT EXISTS community_posts (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(36) REFERENCES users(id),
    caption TEXT,
    media_url VARCHAR(512) NOT NULL,
    media_type VARCHAR(20) NOT NULL DEFAULT 'image',
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    location_name VARCHAR(255),
    is_anonymous BOOLEAN DEFAULT false,
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS community_likes (
    id VARCHAR(36) PRIMARY KEY,
    post_id VARCHAR(36) REFERENCES community_posts(id) ON DELETE CASCADE,
    user_id VARCHAR(36) REFERENCES users(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(post_id, user_id)
);

CREATE TABLE IF NOT EXISTS community_comments (
    id VARCHAR(36) PRIMARY KEY,
    post_id VARCHAR(36) REFERENCES community_posts(id) ON DELETE CASCADE,
    user_id VARCHAR(36) REFERENCES users(id),
    content TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS community_favorites (
    id VARCHAR(36) PRIMARY KEY,
    post_id VARCHAR(36) REFERENCES community_posts(id) ON DELETE CASCADE,
    user_id VARCHAR(36) REFERENCES users(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(post_id, user_id)
);

CREATE TABLE IF NOT EXISTS community_shares (
    id VARCHAR(36) PRIMARY KEY,
    post_id VARCHAR(36) REFERENCES community_posts(id) ON DELETE CASCADE,
    user_id VARCHAR(36) REFERENCES users(id),
    platform VARCHAR(50) DEFAULT 'internal',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_community_posts_status_created ON community_posts(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_community_posts_user_id ON community_posts(user_id);
CREATE INDEX IF NOT EXISTS idx_community_likes_post_id ON community_likes(post_id);
CREATE INDEX IF NOT EXISTS idx_community_comments_post_id ON community_comments(post_id);
CREATE INDEX IF NOT EXISTS idx_community_favorites_user_id ON community_favorites(user_id);
CREATE INDEX IF NOT EXISTS idx_community_shares_post_id ON community_shares(post_id);
