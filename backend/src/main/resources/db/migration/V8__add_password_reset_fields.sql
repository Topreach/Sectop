ALTER TABLE users
    ADD COLUMN password_reset_token VARCHAR(36) NULL,
    ADD COLUMN password_reset_token_expiry TIMESTAMP NULL;
