CREATE TABLE marketplace_listings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL,
  title TEXT NOT NULL CHECK(char_length(title) BETWEEN 3 AND 140),
  description TEXT NOT NULL CHECK(char_length(description) BETWEEN 10 AND 4000),
  price NUMERIC(12,2) NOT NULL CHECK(price >= 0),
  status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('draft','active','reserved','sold','inactive')),
  city TEXT,
  region_code CHAR(2),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX marketplace_listings_active_region_created_idx ON marketplace_listings(region_code,created_at DESC) WHERE status='active';
CREATE TABLE member_capabilities (
  user_id UUID PRIMARY KEY,
  identity_verified BOOLEAN NOT NULL DEFAULT false,
  auction_seller_eligible BOOLEAN NOT NULL DEFAULT false,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE marketplace_auctions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id UUID NOT NULL UNIQUE REFERENCES marketplace_listings(id),
  seller_id UUID NOT NULL,
  starting_price NUMERIC(12,2) NOT NULL CHECK(starting_price >= 0),
  minimum_increment NUMERIC(12,2) NOT NULL CHECK(minimum_increment > 0),
  starts_at TIMESTAMPTZ NOT NULL,
  ends_at TIMESTAMPTZ NOT NULL CHECK(ends_at > starts_at),
  status TEXT NOT NULL DEFAULT 'scheduled' CHECK(status IN ('scheduled','active','closed','cancelled')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE marketplace_auction_bids (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  auction_id UUID NOT NULL REFERENCES marketplace_auctions(id),
  bidder_id UUID NOT NULL,
  amount NUMERIC(12,2) NOT NULL CHECK(amount > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX marketplace_auction_bids_auction_amount_idx ON marketplace_auction_bids(auction_id,amount DESC,created_at ASC);
