-- 001_initial_schema.sql
-- Baseline schema for FreshTrack users and food items

CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS food_items (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    food_name VARCHAR(150) NOT NULL,
    category VARCHAR(100),
    quantity INTEGER NOT NULL DEFAULT 1,
    purchase_date DATE,
    expiry_date DATE NOT NULL,
    storage_location VARCHAR(50),
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    notes TEXT,
    created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_food_user
        FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_food_items_user_id
ON food_items(user_id);

CREATE INDEX IF NOT EXISTS idx_food_items_active_expiry
ON food_items(user_id, expiry_date)
WHERE status = 'active';
