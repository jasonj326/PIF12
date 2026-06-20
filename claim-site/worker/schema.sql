-- PIF12 claim-site D1 schema
--
-- Privacy rule (PIF12 hard rule): the database must not hold a persistent
-- "person = 0x address" mapping. So:
--   - A SINGLE link may carry a personal label/message (e.g. "阿哲") BEFORE it is
--     claimed — at that point no address is attached, so it is not a mapping.
--   - On a successful single-link claim, label + message were CLEARED by default
--     (anonymous record). As of 2026-06-20 RETAIN_SINGLE_LABELS=true (Jason's
--     explicit decision): they are KEPT, so message <-> claiming-wallet persists
--     for the gift ledger + recipient gallery. This consciously relaxes the
--     no-mapping rule; Jason accepted the trade-off.
--   - A GROUP link's label ("六月 Solidity 班") and message are collective and map
--     to many addresses, so they are never a 1:1 identity mapping — kept as-is.

CREATE TABLE IF NOT EXISTS claim_links (
  token       TEXT PRIMARY KEY,         -- crypto-random, unguessable (32 bytes hex)
  year        INTEGER NOT NULL,         -- zodiac year number (1 = Horse 2026)
  lang        TEXT NOT NULL DEFAULT 'zh',  -- claim-page default language: 'zh' | 'en' | 'ja'
  kind        TEXT NOT NULL DEFAULT 'single',  -- 'single' | 'group'
  max_uses    INTEGER,                  -- single = 1; group = N, or NULL = unlimited
  use_count   INTEGER NOT NULL DEFAULT 0,
  message     TEXT,                     -- thank-you text shown on the claim page
  label       TEXT,                     -- admin-only reference (NOT shown to claimant)
  created_at  INTEGER NOT NULL,         -- unix seconds
  expires_at  INTEGER,                  -- NULL = no expiry
  revoked_at  INTEGER,                  -- manual revoke / "close after class"
  used_at     INTEGER,                  -- single: set on the one claim; group: set when exhausted
  tx_hash     TEXT                      -- single-link mint tx (group txs live in claims)
);

CREATE TABLE IF NOT EXISTS claims (
  address       TEXT NOT NULL,
  year          INTEGER NOT NULL,
  privy_user_id TEXT,
  link_token    TEXT,                   -- not a FK label-join: see privacy rule above
  tx_hash       TEXT,
  claimed_at    INTEGER NOT NULL,
  PRIMARY KEY (address, year)
);

-- Duplicate-account guard: one claim per Privy account per year (social-layer backup).
CREATE UNIQUE INDEX IF NOT EXISTS idx_claims_privy_year
  ON claims (privy_user_id, year) WHERE privy_user_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_links_created ON claim_links (created_at);
