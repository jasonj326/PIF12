// PIF12 claim API — Cloudflare Worker + D1
//
// Endpoints
//   GET  /api/link/:token        link validity + thank-you message (no inventory leak)
//   POST /api/claim              { token, address } + Privy access token in Authorization
//   POST /api/admin/links        { kind, count, year, ttlHours, maxUses, message, label }
//   POST /api/admin/revoke       { token }            close a link / "課後關閉"
//   GET  /api/admin/links        recent links overview
//
// Link kinds
//   single  one recipient, max_uses = 1, may carry a personal message.
//   group   a class / club; one shared link, max_uses = N (or unlimited until
//           revoked or expired). Each WALLET still gets at most one token — the
//           contract's isCurator guard enforces one-per-address regardless.
//
// Design notes
// - Consumption is ATOMIC (conditional UPDATE) and happens BEFORE the relay call,
//   so a double-submit can never double-mint; on relay failure it is rolled back.
// - Relay = direct signing in the Worker (viem); GAME_ROLE key in a Worker secret
//   (decided 2026-06-12 after OZ Defender's sunset). GAME_ROLE is mint-only and
//   admin-revocable, so a hot key with minimal gas is a proportionate Y1 risk.
// - Privacy: see ../schema.sql. Single-link label/message are cleared on claim.

import { createWalletClient, http as viemHttp, parseAbi } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { mainnet, sepolia } from 'viem/chains';

const SEL_IS_CURATOR = '0x6c7b79d4'; // cast sig "isCurator(address)"
const NEXUS_ABI = parseAbi(['function mintCuratorToken(address to, uint8 yearNumber)']);

// Single-link label/message retention after claim.
// Was false (clear on claim — the DB then held no "message <-> address" link, the
// original PIF12 privacy posture). Set TRUE on 2026-06-20 by Jason's explicit
// decision: retain so a gift's message persists keyed to the claiming wallet,
// enabling (a) reconstructing each gift years later and (b) a recipient gallery
// where a holder logs in and re-reads each year's message. This consciously
// relaxes the "no person<->address on the server" rule for single-link messages.
const RETAIN_SINGLE_LABELS = true;

export default {
  async fetch(request, env) {
    const { pathname } = new URL(request.url);
    const origin = request.headers.get('Origin');
    const wrap = (res) => cors(env, res, origin);
    if (request.method === 'OPTIONS') return wrap(new Response(null, { status: 204 }));

    try {
      if (request.method === 'GET' && pathname.startsWith('/api/link/')) {
        return wrap(await handleLinkCheck(env, pathname.split('/').pop()));
      }
      if (request.method === 'POST' && pathname === '/api/claim') {
        return wrap(await handleClaim(env, request));
      }
      if (pathname.startsWith('/api/admin/')) {
        const denied = requireAdmin(env, request);
        if (denied) return wrap(denied);
        if (request.method === 'POST' && pathname === '/api/admin/links') return wrap(await handleAdminCreateLinks(env, request));
        if (request.method === 'POST' && pathname === '/api/admin/revoke') return wrap(await handleAdminRevoke(env, request));
        if (request.method === 'GET' && pathname === '/api/admin/links') return wrap(await handleAdminListLinks(env));
      }
      return wrap(json({ error: 'not_found' }, 404));
    } catch (err) {
      console.error('unhandled', err.stack || err.message);
      return wrap(json({ error: 'internal' }, 500));
    }
  },
};

// ---------- public: link validity ----------

async function handleLinkCheck(env, token) {
  if (!isHexToken(token)) return json({ valid: false, reason: 'invalid' });
  const row = await env.DB.prepare(
    'SELECT year, lang, kind, max_uses, use_count, message, tx_hash, expires_at, revoked_at, used_at FROM claim_links WHERE token = ?'
  ).bind(token).first();

  if (!row) return json({ valid: false, reason: 'invalid' });
  if (row.revoked_at) return json({ valid: false, reason: 'revoked' });
  if (row.expires_at && now() > row.expires_at) return json({ valid: false, reason: 'expired' });
  if (isExhausted(row)) {
    // Re-download: a used SINGLE link can still surface its keepsake data so the
    // recipient — who already holds this secret token — can download it again
    // (e.g. they forgot to save it the first time). No re-mint happens here.
    if (row.kind === 'single' && row.tx_hash) {
      const claim = await env.DB.prepare(
        'SELECT address, claimed_at FROM claims WHERE link_token = ? AND year = ? LIMIT 1'
      ).bind(token, row.year).first();
      if (claim) {
        return json({ valid: false, reason: 'used', redownload: {
          address: claim.address, txHash: row.tx_hash, message: row.message || null,
          year: row.year, lang: row.lang || 'zh', claimedAt: claim.claimed_at,
        } });
      }
    }
    return json({ valid: false, reason: 'used' });
  }
  return json({ valid: true, year: row.year, lang: row.lang || 'zh', kind: row.kind, message: row.message || null });
}

// ---------- public: claim ----------

async function handleClaim(env, request) {
  const body = await request.json().catch(() => null);
  if (!body || !isHexToken(body.token) || !isAddress(body.address)) return json({ error: 'bad_request' }, 400);
  const { token } = body;
  const address = body.address.toLowerCase();

  // 1. Verify the caller is a logged-in Privy user (defense in depth; the link is
  //    the primary authorization).
  const privyUserId = await verifyPrivyToken(env, request.headers.get('Authorization'));
  if (!privyUserId) return json({ error: 'auth_required' }, 401);

  // 2. Validate link state (friendly errors before consuming anything).
  const link = await env.DB.prepare(
    'SELECT year, kind, max_uses, use_count, expires_at, revoked_at, used_at FROM claim_links WHERE token = ?'
  ).bind(token).first();
  if (!link) return json({ error: 'link_invalid' }, 400);
  if (link.revoked_at) return json({ error: 'link_revoked' }, 400);
  if (link.expires_at && now() > link.expires_at) return json({ error: 'link_expired' }, 400);
  if (isExhausted(link)) return json({ error: 'link_used' }, 400);

  // 3. Duplicate guards before touching the chain.
  const dup = await env.DB.prepare(
    'SELECT 1 FROM claims WHERE (address = ? OR privy_user_id = ?) AND year = ?'
  ).bind(address, privyUserId, link.year).first();
  if (dup) return json({ error: 'already_claimed' }, 409);
  if (await isCuratorOnChain(env, address)) return json({ error: 'already_member' }, 409);

  // 4. Atomically take a slot BEFORE relaying (no double-mint window).
  const consumed = await takeSlot(env, token);
  if (!consumed) return json({ error: 'link_used' }, 409); // lost the race / just exhausted

  // 5. Relay mint: the Worker signs with the GAME_ROLE key and broadcasts.
  let txHash;
  try {
    txHash = await relayMint(env, address, link.year);
  } catch (err) {
    console.error('relay failed', err.message);
    await releaseSlot(env, token); // give the slot back so they can retry
    return json({ error: 'mint_failed_retry' }, 502);
  }

  // 6. Record the claim. Single-link personal label/message are cleared (privacy).
  const stmts = [
    env.DB.prepare(
      'INSERT INTO claims (address, year, privy_user_id, link_token, tx_hash, claimed_at) VALUES (?, ?, ?, ?, ?, ?)'
    ).bind(address, link.year, privyUserId, token, txHash, now()),
  ];
  if (link.kind === 'single') {
    stmts.push(
      RETAIN_SINGLE_LABELS
        ? env.DB.prepare('UPDATE claim_links SET tx_hash = ? WHERE token = ?').bind(txHash, token)
        : env.DB.prepare('UPDATE claim_links SET tx_hash = ?, message = NULL, label = NULL WHERE token = ?').bind(txHash, token)
    );
  }
  await env.DB.batch(stmts);

  return json({ ok: true, txHash, year: link.year });
}

// A link is exhausted when its slots are full. single: used_at set. group:
// use_count >= max_uses (NULL max_uses = unlimited, never exhausted by count).
function isExhausted(row) {
  if (row.kind === 'group') return row.max_uses != null && row.use_count >= row.max_uses;
  return row.used_at != null;
}

async function takeSlot(env, token) {
  // single: claim the one slot. group: increment under the cap, atomically.
  const res = await env.DB.prepare(
    "UPDATE claim_links SET use_count = use_count + 1, used_at = CASE WHEN kind = 'single' THEN ?1 " +
    "WHEN max_uses IS NOT NULL AND use_count + 1 >= max_uses THEN ?1 ELSE used_at END " +
    'WHERE token = ?2 AND revoked_at IS NULL AND (expires_at IS NULL OR expires_at > ?1) ' +
    "AND (used_at IS NULL) AND (max_uses IS NULL OR use_count < max_uses)"
  ).bind(now(), token).run();
  return res.meta && res.meta.changes === 1;
}

async function releaseSlot(env, token) {
  await env.DB.prepare(
    'UPDATE claim_links SET use_count = MAX(0, use_count - 1), used_at = NULL WHERE token = ?'
  ).bind(token).run();
}

// ---------- admin ----------

function requireAdmin(env, request) {
  const auth = request.headers.get('Authorization') || '';
  if (!env.ADMIN_TOKEN || auth !== 'Bearer ' + env.ADMIN_TOKEN) return json({ error: 'forbidden' }, 403);
  return null;
}

async function handleAdminCreateLinks(env, request) {
  const body = await request.json().catch(() => ({}));
  const kind = body.kind === 'group' ? 'group' : 'single';
  const year = body.year || Number(env.CURRENT_YEAR);
  const lang = ['zh', 'en', 'ja'].includes(body.lang) ? body.lang : 'zh';
  const ttlHours = body.ttlHours === 0 ? null : (body.ttlHours || 72);
  const createdAt = now();
  const expiresAt = ttlHours ? createdAt + ttlHours * 3600 : null;
  const message = (body.message || '').slice(0, 500) || null;
  const label = (body.label || '').slice(0, 120) || null;

  const links = [];
  const stmts = [];
  const mk = (maxUses) => {
    const token = randomToken();
    links.push('https://claim.jasonjlai.net/?t=' + token);
    stmts.push(env.DB.prepare(
      'INSERT INTO claim_links (token, year, lang, kind, max_uses, message, label, created_at, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)'
    ).bind(token, year, lang, kind, maxUses, message, label, createdAt, expiresAt));
  };

  if (kind === 'group') {
    // One shared link for the whole group. maxUses null = unlimited until closed.
    const maxUses = body.maxUses ? Math.min(Math.max(1, body.maxUses), 1000) : null;
    mk(maxUses);
  } else {
    // One or more single-use links (count > 1 = a batch of identical personal links).
    const count = Math.min(Math.max(1, body.count || 1), 100);
    for (let i = 0; i < count; i++) mk(1);
  }

  await env.DB.batch(stmts);
  return json({ ok: true, kind, year, lang, expiresAt, links });
}

async function handleAdminRevoke(env, request) {
  const body = await request.json().catch(() => ({}));
  if (!isHexToken(body.token)) return json({ error: 'bad_request' }, 400);
  // Revoke works for unused single links AND active group links ("課後關閉").
  const res = await env.DB.prepare(
    'UPDATE claim_links SET revoked_at = ? WHERE token = ? AND revoked_at IS NULL'
  ).bind(now(), body.token).run();
  return json({ ok: true, revoked: res.meta.changes === 1 });
}

async function handleAdminListLinks(env) {
  const { results } = await env.DB.prepare(
    'SELECT token, year, lang, kind, max_uses, use_count, label, message, created_at, expires_at, revoked_at, used_at, tx_hash ' +
    'FROM claim_links ORDER BY created_at DESC LIMIT 200'
  ).all();
  return json({ links: results });
}

// ---------- chain + relay helpers ----------

async function isCuratorOnChain(env, address) {
  if (!env.RPC_URL || env.CONTRACT_ADDRESS === 'TBD') return false; // pre-deploy dev mode
  const data = SEL_IS_CURATOR + address.slice(2).padStart(64, '0');
  const res = await fetch(env.RPC_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'eth_call', params: [{ to: env.CONTRACT_ADDRESS, data }, 'latest'] }),
  });
  const out = await res.json();
  return out.result && BigInt(out.result) === 1n;
}

async function relayMint(env, address, year) {
  const account = privateKeyToAccount(env.RELAYER_PRIVATE_KEY);
  const client = createWalletClient({
    account,
    chain: env.CHAIN_ID === '11155111' ? sepolia : mainnet,
    transport: viemHttp(env.RPC_URL),
  });
  return await client.writeContract({
    address: env.CONTRACT_ADDRESS,
    abi: NEXUS_ABI,
    functionName: 'mintCuratorToken',
    args: [address, Number(year)],
  });
}

// ---------- Privy access-token verification (ES256 via JWKS) ----------

let jwksCache = { keys: null, fetchedAt: 0 };

async function verifyPrivyToken(env, authHeader) {
  if (!authHeader || !authHeader.startsWith('Bearer ')) return null;
  const parts = authHeader.slice(7).split('.');
  if (parts.length !== 3) return null;

  try {
    const header = JSON.parse(atob(b64url(parts[0])));
    const payload = JSON.parse(atob(b64url(parts[1])));

    if (payload.aud !== env.PRIVY_APP_ID) return null;
    if (payload.iss !== 'privy.io') return null;
    if (payload.exp && now() > payload.exp) return null;

    if (!jwksCache.keys || now() - jwksCache.fetchedAt > 3600) {
      const res = await fetch('https://auth.privy.io/api/v1/apps/' + env.PRIVY_APP_ID + '/jwks.json');
      jwksCache = { keys: (await res.json()).keys, fetchedAt: now() };
    }
    const jwk = jwksCache.keys.find((k) => k.kid === header.kid) || jwksCache.keys[0];
    if (!jwk) return null;

    const key = await crypto.subtle.importKey('jwk', jwk, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['verify']);
    const sig = Uint8Array.from(atob(b64url(parts[2])), (c) => c.charCodeAt(0));
    const data = new TextEncoder().encode(parts[0] + '.' + parts[1]);
    const valid = await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, key, sig, data);
    return valid ? payload.sub : null; // did:privy:...
  } catch {
    return null;
  }
}

// ---------- small utils ----------

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), { status, headers: { 'Content-Type': 'application/json' } });
}

function cors(env, res, origin) {
  // Reflect the caller's origin: the claim page (ALLOWED_ORIGIN) and the local
  // admin tool both need access. Auth is by unguessable link token / admin
  // bearer token, not cookies — so reflecting origin is safe for this app.
  const allow = origin || env.ALLOWED_ORIGIN || '*';
  const h = new Headers(res.headers);
  h.set('Access-Control-Allow-Origin', allow);
  h.set('Vary', 'Origin');
  h.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  h.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  return new Response(res.body, { status: res.status, headers: h });
}

function now() { return Math.floor(Date.now() / 1000); }

function randomToken() {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return [...bytes].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function isHexToken(t) { return typeof t === 'string' && /^[0-9a-f]{64}$/.test(t); }
function isAddress(a) { return typeof a === 'string' && /^0x[0-9a-fA-F]{40}$/.test(a); }
function b64url(s) { return s.replace(/-/g, '+').replace(/_/g, '/'); }
