ALTER TABLE users
    ADD COLUMN deleted_at TIMESTAMP NULL,
    ADD COLUMN deletion_requested_at TIMESTAMP NULL;
