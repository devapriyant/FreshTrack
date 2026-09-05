-- FreshTrack Email OTP Authentication & Verification Migration
-- All security and OTP timestamps use TIMESTAMPTZ for unambiguous time handling

-- 1. Extend users table for verification tracking
ALTER TABLE users
ADD COLUMN IF NOT EXISTS email_verified BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE users
ADD COLUMN IF NOT EXISTS email_verified_at TIMESTAMPTZ NULL;

-- 2. Create pending_registrations table
-- Holds unverified registrations so unverified accounts never touch or pollute the users table
CREATE TABLE IF NOT EXISTS pending_registrations (
    id UUID PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_pending_reg_email
ON pending_registrations(email);

-- 3. Create email_otp_challenges table
-- Stores bcrypt-hashed 6-digit OTP challenges with rate/attempt limits
CREATE TABLE IF NOT EXISTS email_otp_challenges (
    id UUID PRIMARY KEY,
    user_id INTEGER NULL,
    pending_registration_id UUID NULL,
    email VARCHAR(255) NOT NULL,
    purpose VARCHAR(20) NOT NULL,
    otp_hash VARCHAR(255) NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    max_attempts INTEGER NOT NULL DEFAULT 5,
    consumed_at TIMESTAMPTZ NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_sent_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT valid_otp_purpose
      CHECK (purpose IN ('register', 'login', 'verify_email')),

    CONSTRAINT fk_otp_user
      FOREIGN KEY (user_id)
      REFERENCES users(id)
      ON DELETE CASCADE,

    CONSTRAINT fk_otp_pending_registration
      FOREIGN KEY (pending_registration_id)
      REFERENCES pending_registrations(id)
      ON DELETE SET NULL
);

-- 4. Create indexes for fast challenge lookup, purpose checks, and cleanup
CREATE INDEX IF NOT EXISTS idx_otp_email_purpose
ON email_otp_challenges(email, purpose);

CREATE INDEX IF NOT EXISTS idx_otp_expires_at
ON email_otp_challenges(expires_at);

CREATE INDEX IF NOT EXISTS idx_otp_user_id
ON email_otp_challenges(user_id);

CREATE INDEX IF NOT EXISTS idx_otp_pending_reg_id
ON email_otp_challenges(pending_registration_id);
