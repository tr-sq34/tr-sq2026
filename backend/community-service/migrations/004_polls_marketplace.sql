CREATE TABLE marketplace_listing_projection (listing_id UUID PRIMARY KEY, owner_id UUID NOT NULL, status TEXT NOT NULL CHECK(status IN ('active','inactive')), title TEXT NOT NULL, price NUMERIC(12,2) NOT NULL, updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
ALTER TABLE community_posts ADD COLUMN marketplace_listing_id UUID;
