import React, { useEffect, useMemo, useRef, useState } from 'react';
import { usePrivy, useWallets } from '@privy-io/react-auth';
import { API_BASE, ETHERSCAN } from './config.js';
import { T, LANGS, pickInitialLang } from './i18n.js';
import QRCode from 'qrcode';

// Claim flow: link check -> Privy login -> confirm address -> relay mint.
// The user never signs a transaction and never pays gas (backend relay).
// UI is trilingual (中/EN/日); default comes from ?lang=, then the link's
// admin-set language, then the browser, then Chinese.

const OMAMORI_IMG = 'https://ipfs.io/ipfs/bafybeihpmwj5ekxbqzxrqbksc2css36tk3m23t32rxmaxdbs6buo2x2ck4';

// Load the omamori WITHOUT tainting the canvas: fetch it as a blob first (ipfs.io
// serves CORS *), so the composited canvas stays exportable via toBlob. Fall back
// to a crossOrigin <img> if fetch is blocked.
async function loadKeepsakeImage(url) {
  try {
    const res = await fetch(url, { mode: 'cors' });
    if (!res.ok) throw new Error('fetch failed');
    return await createImageBitmap(await res.blob());
  } catch {
    return await new Promise((resolve, reject) => {
      const img = new Image();
      img.crossOrigin = 'anonymous';
      img.onload = () => resolve(img);
      img.onerror = reject;
      img.src = url;
    });
  }
}

function roundRect(ctx, x, y, w, h, r) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

// Centered, wrapped text (handles CJK with no spaces). Returns y below last line.
function drawWrapped(ctx, text, cx, y, maxW, lineH) {
  const lines = [];
  let cur = '';
  for (const ch of String(text)) {
    if (ch === '\n') { lines.push(cur); cur = ''; continue; }
    if (ctx.measureText(cur + ch).width > maxW && cur) { lines.push(cur); cur = ch; }
    else cur += ch;
  }
  if (cur) lines.push(cur);
  for (const ln of lines) { ctx.fillText(ln, cx, y); y += lineH; }
  return y;
}

function triggerDownload(blob, name) {
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = name;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}

export default function App() {
  const { ready, authenticated, login, logout, getAccessToken, exportWallet } = usePrivy();
  const { wallets } = useWallets();

  const token = useMemo(
    () => new URLSearchParams(window.location.search).get('t') || '',
    []
  );
  const urlLang = useMemo(
    () => new URLSearchParams(window.location.search).get('lang'),
    []
  );

  const [lang, setLang] = useState(() => pickInitialLang(urlLang, null));
  const langTouched = useRef(false);
  const t = T[lang];

  // phases: checking | bad-link | need-login | ready | claiming | done | error
  const [phase, setPhase] = useState('checking');
  const [reason, setReason] = useState('');
  const [message, setMessage] = useState(null); // personal/collective thank-you note
  const [txHash, setTxHash] = useState('');
  const [errKey, setErrKey] = useState('');
  const [ksBusy, setKsBusy] = useState(false);

  function chooseLang(code) { langTouched.current = true; setLang(code); }

  // 1. Link validity gate (also carries the admin-set default language).
  useEffect(() => {
    if (!token) { setPhase('bad-link'); setReason('invalid'); return; }
    fetch(API_BASE + '/api/link/' + token)
      .then((r) => r.json())
      .then((out) => {
        if (out.valid) {
          setMessage(out.message || null);
          if (!urlLang && !langTouched.current && out.lang) setLang(pickInitialLang(null, out.lang));
          setPhase('need-login');
        } else {
          setReason(out.reason || 'invalid');
          setPhase('bad-link');
        }
      })
      .catch(() => { setReason('invalid'); setPhase('bad-link'); });
  }, [token, urlLang]);

  useEffect(() => {
    if (phase === 'need-login' && ready && authenticated) setPhase('ready');
    if (phase === 'ready' && ready && !authenticated) setPhase('need-login');
  }, [phase, ready, authenticated]);

  // Receiving address: prefer the embedded wallet (created on login);
  // otherwise the first connected external wallet (WalletConnect / injected).
  const wallet = useMemo(() => {
    if (!wallets.length) return null;
    return wallets.find((w) => w.walletClientType === 'privy') || wallets[0];
  }, [wallets]);

  // Embedded (Privy-managed) wallet: created from email/social login. These
  // users get the security notice + key-export link; external wallet users
  // (WalletConnect / injected) already self-custody and manage their own keys.
  const isEmbedded = wallet?.walletClientType === 'privy';

  async function claim() {
    if (!wallet) return;
    setPhase('claiming');
    try {
      const accessToken = await getAccessToken();
      const res = await fetch(API_BASE + '/api/claim', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + accessToken },
        body: JSON.stringify({ token, address: wallet.address }),
      });
      const out = await res.json();
      if (out.ok) { setTxHash(out.txHash); setPhase('done'); }
      else { setErrKey(out.error || 'mint_failed_retry'); setPhase('error'); }
    } catch {
      setErrKey('mint_failed_retry');
      setPhase('error');
    }
  }

  // One-click keepsake: composite the omamori + receipt into a single PNG so the
  // recipient can save the whole thing, not just screenshot it. Falls back to the
  // raw art if the canvas can't be exported (e.g. CORS image load fails).
  async function downloadKeepsake() {
    if (ksBusy) return;
    setKsBusy(true);
    try {
      const today = new Date().toISOString().slice(0, 10);
      const shortAddr = wallet ? wallet.address.slice(0, 6) + '…' + wallet.address.slice(-4) : '';
      const W = 640, H = 880, S = 2;
      const cv = document.createElement('canvas');
      cv.width = W * S; cv.height = H * S;
      const ctx = cv.getContext('2d');
      ctx.scale(S, S);
      const sans = '-apple-system, "PingFang TC", "Noto Sans TC", sans-serif';
      const serif = 'Georgia, "Songti TC", "Noto Serif TC", serif';
      ctx.fillStyle = '#0b0e14'; ctx.fillRect(0, 0, W, H);
      ctx.fillStyle = 'rgba(212,175,106,0.5)';
      for (const [sx, sy] of [[70, 90], [560, 70], [120, 770], [540, 800], [92, 430], [580, 450], [300, 46], [330, 836]]) {
        ctx.beginPath(); ctx.arc(sx, sy, 1.4, 0, 7); ctx.fill();
      }
      roundRect(ctx, 28, 28, W - 56, H - 56, 22);
      ctx.fillStyle = '#141823'; ctx.fill();
      ctx.strokeStyle = 'rgba(212,175,106,0.30)'; ctx.lineWidth = 1.5; ctx.stroke();
      ctx.textAlign = 'center';
      ctx.fillStyle = '#d4af6a'; ctx.font = '600 15px ' + sans;
      ctx.fillText('PIF12', W / 2, 74);
      const img = await loadKeepsakeImage(OMAMORI_IMG);
      const isz = 300, ix = (W - isz) / 2, iy = 102;
      ctx.save(); roundRect(ctx, ix, iy, isz, isz, 14); ctx.clip();
      ctx.drawImage(img, ix, iy, isz, isz);
      ctx.restore();
      ctx.fillStyle = '#d4af6a'; ctx.font = '600 23px ' + sans;
      ctx.fillText(t.tokenName, W / 2, iy + isz + 48);
      ctx.fillStyle = '#9a968d'; ctx.font = '13px ' + sans;
      ctx.fillText(t.tokenSub, W / 2, iy + isz + 72);
      let y = iy + isz + 112;
      if (message) {
        ctx.fillStyle = '#e8e6e1'; ctx.font = 'italic 17px ' + serif;
        y = drawWrapped(ctx, '「' + message + '」', W / 2, y, W - 150, 28) + 16;
      }
      ctx.fillStyle = '#9a968d'; ctx.font = '13px ' + sans;
      ctx.fillText(t.metaHold + '  ' + shortAddr, W / 2, y); y += 24;
      ctx.fillText(t.metaDate + '  ' + today + '   ·   ' + t.metaKindVal, W / 2, y);
      // tx QR (BUNDLED qrcode lib — no CDN dependency, so it can't fail the way
      // the admin console's CDN-loaded QR does) makes the saved keepsake
      // independently scannable to verify the mint on Etherscan.
      if (txHash) {
        try {
          const qc = document.createElement('canvas');
          await QRCode.toCanvas(qc, ETHERSCAN + txHash, { width: 132, margin: 2, color: { dark: '#1a1505', light: '#efe7d2' } });
          const qsz = 124, qx = (W - qsz) / 2, qy = Math.max(y + 30, H - 224);
          ctx.drawImage(qc, qx, qy, qsz, qsz);
          ctx.fillStyle = 'rgba(212,175,106,0.78)'; ctx.font = '12px ' + sans;
          ctx.fillText(t.keepsakeVerify, W / 2, qy + qsz + 26);
        } catch { /* QR is optional — the keepsake stays valid without it */ }
      } else {
        ctx.fillStyle = 'rgba(212,175,106,0.7)'; ctx.font = '12px ' + sans;
        ctx.fillText(t.keepsakeVerify, W / 2, H - 52);
      }
      const blob = await new Promise((r) => cv.toBlob(r, 'image/png'));
      if (!blob) throw new Error('no blob');
      triggerDownload(blob, 'PIF12-Horse-omamori-2026.png');
    } catch {
      window.open(OMAMORI_IMG, '_blank', 'noopener'); // fallback: at least the art
    } finally {
      setKsBusy(false);
    }
  }

  const cardProps = { lang, onLang: chooseLang };

  // ---------- render ----------

  if (phase === 'checking' || !ready) {
    return <Card {...cardProps} title={t.checking} />;
  }

  if (phase === 'bad-link') {
    // No/invalid token = a public visitor with no personal link: greet warmly
    // (PIF12 is claimed by invite) instead of a cold error. A used/expired/
    // revoked link still gets an honest, un-alarming line, then the same invite.
    const isInvalid = reason === 'invalid';
    // Route the "About PIF12" link to the landing in the reader's language:
    // zh → the Chinese landing; en/ja → the English landing (no Japanese landing).
    const pif12Url = lang === 'zh' ? 'https://jasonjlai.net/zh/PIF12/' : 'https://jasonjlai.net/PIF12/';
    return (
      <Card {...cardProps} title={isInvalid ? t.welcomeTitle : t.linkUnavailable}>
        {!isInvalid && <p className="muted">{t['reason_' + reason] || t.reason_invalid}</p>}
        <p>{t.welcomeBody}</p>
        <div className="invite-links">
          <a href={pif12Url} target="_blank" rel="noreferrer">{t.welcomeReadDocs} →</a>
          <a href="https://jasonjlai.net/qualia" target="_blank" rel="noreferrer">{t.welcomeChatLia} →</a>
          <a href="mailto:hello@jasonjlai.net?subject=PIF12%20catch-up">{t.welcomeReconnect} →</a>
        </div>
      </Card>
    );
  }

  if (phase === 'need-login') {
    return (
      <Card {...cardProps} title={t.claimTitle}>
        {message && (
          <div className="note">
            <div className="note-label">{t.noteLabel}</div>
            <div className="note-body">{message}</div>
          </div>
        )}
        <p>{t.intro1}</p>
        <p className="muted">{t.intro2}</p>
        <button onClick={login}>{t.signIn}</button>
      </Card>
    );
  }

  if (phase === 'ready' || phase === 'claiming') {
    return (
      <Card {...cardProps} title={t.lastStep}>
        <p>{t.addrStored}</p>
        <div className="addr">{wallet ? wallet.address : t.preparing}</div>
        <p className="muted">{t.addrReassure}</p>
        {isEmbedded && (
          <div className="note">
            <div className="note-label">{t.secTitle}</div>
            <ul className="seclist">
              <li>{t.secSoulbound}</li>
              <li>{t.sec2fa}</li>
              <li>{t.secExport}</li>
            </ul>
          </div>
        )}
        <button onClick={claim} disabled={!wallet || phase === 'claiming'}>
          {phase === 'claiming' ? t.minting : t.claim}
        </button>
        <p className="muted" style={{ marginTop: 12 }}>
          <a href="#" onClick={(e) => { e.preventDefault(); logout(); }}>{t.switchAccount}</a>
        </p>
      </Card>
    );
  }

  if (phase === 'done') {
    const today = new Date().toISOString().slice(0, 10);
    const shortAddr = wallet ? wallet.address.slice(0, 6) + '…' + wallet.address.slice(-4) : '';
    return (
      <Card {...cardProps} title={t.litTitle}>
        <div className="receipt">
          <div className="receipt-emblem">
            <img
              className="receipt-omamori"
              src={OMAMORI_IMG}
              alt={t.tokenName}
              onError={(e) => { e.currentTarget.style.display = 'none'; e.currentTarget.parentElement.textContent = '馬'; }}
            />
          </div>
          <div className="receipt-title">{t.tokenName}</div>
          <div className="receipt-sub">{t.tokenSub}</div>
          {message && <div className="receipt-msg">{message}</div>}
          <div className="receipt-meta">
            <div><span>{t.metaHold}</span><b>{shortAddr}</b></div>
            <div><span>{t.metaDate}</span><b>{today}</b></div>
            <div><span>{t.metaKind}</span><b>{t.metaKindVal}</b></div>
          </div>
          <a className="receipt-link" href={ETHERSCAN + txHash} target="_blank" rel="noreferrer">{t.viewTx}</a>
        </div>
        <button onClick={downloadKeepsake} disabled={ksBusy}>
          {ksBusy ? t.preparingKeepsake : t.downloadKeepsake}
        </button>
        <p className="muted" style={{ marginTop: 12 }}>{t.welcome}<br />{t.screenshot}</p>
        {isEmbedded && (
          <p className="muted" style={{ marginTop: 12 }}>
            <a href="#" onClick={(e) => { e.preventDefault(); exportWallet({ address: wallet.address }); }}>{t.exportKey}</a>
          </p>
        )}
      </Card>
    );
  }

  // error
  const retriable = errKey === 'mint_failed_retry';
  return (
    <Card {...cardProps} title={t.hiccup}>
      <p className="error">{t['err_' + errKey] || t.err_mint_failed_retry}</p>
      {retriable && <button onClick={() => setPhase('ready')}>{t.tryAgain}</button>}
    </Card>
  );
}

function Card({ lang, onLang, title, children }) {
  return (
    <div className="card">
      <div className="langbar">
        {LANGS.map((l) => (
          <button
            key={l.code}
            className={'langbtn' + (l.code === lang ? ' on' : '')}
            onClick={() => onLang(l.code)}
            aria-pressed={l.code === lang}
          >
            {l.label}
          </button>
        ))}
      </div>
      {title && <h1>{title}</h1>}
      {children}
    </div>
  );
}
