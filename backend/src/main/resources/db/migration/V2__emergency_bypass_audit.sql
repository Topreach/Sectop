-- Flyway migration: create emergency_bypass_audit table
CREATE TABLE IF NOT EXISTS emergency_bypass_audit (
  id BIGSERIAL PRIMARY KEY,
  session_id TEXT,
  phone TEXT,
  client_ip TEXT,
  method TEXT,
  success BOOLEAN NOT NULL DEFAULT false,
  token_issued BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT now()
);
