-- Phase 3: Notifications & Preferences Migration
-- FreshTrack Expiry Reminder System

-- 1. Create notification_preferences table
CREATE TABLE IF NOT EXISTS notification_preferences (
    user_id INTEGER PRIMARY KEY,
    notifications_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    browser_notifications_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    reminder_days INTEGER[] NOT NULL DEFAULT ARRAY[7, 3, 1, 0],
    timezone VARCHAR(100) NOT NULL DEFAULT 'Asia/Kolkata',
    reminder_hour SMALLINT NOT NULL DEFAULT 9,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_notification_preferences_user
        FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE CASCADE,

    CONSTRAINT valid_reminder_hour
        CHECK (reminder_hour BETWEEN 0 AND 23),

    CONSTRAINT valid_reminder_days
        CHECK (
            cardinality(reminder_days) > 0
            AND reminder_days <@ ARRAY[0, 1, 3, 7]::INTEGER[]
        )
);

-- 2. Create notifications table
CREATE TABLE IF NOT EXISTS notifications (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    food_item_id INTEGER NOT NULL,
    expiry_date DATE NOT NULL,
    reminder_offset_days INTEGER NOT NULL,
    type VARCHAR(30) NOT NULL,
    title VARCHAR(200) NOT NULL,
    message TEXT NOT NULL,
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_notification_user
        FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE CASCADE,

    CONSTRAINT fk_notification_food
        FOREIGN KEY (food_item_id)
        REFERENCES food_items(id)
        ON DELETE CASCADE,

    CONSTRAINT valid_notification_type
        CHECK (type IN (
            'expiring_soon',
            'expires_today',
            'expired'
        )),

    CONSTRAINT unique_food_expiry_reminder
        UNIQUE (
            user_id,
            food_item_id,
            expiry_date,
            reminder_offset_days
        )
);

-- 3. Create indexes for notification lookup and inventory queries
CREATE INDEX IF NOT EXISTS idx_notifications_user_created
ON notifications(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notifications_user_unread
ON notifications(user_id, is_read);

CREATE INDEX IF NOT EXISTS idx_food_items_active_expiry
ON food_items(user_id, expiry_date)
WHERE status = 'active';
