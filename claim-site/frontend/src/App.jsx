import React, { useEffect, useMemo, useRef, useState } from 'react';
import { usePrivy, useWallets } from '@privy-io/react-auth';
import { API_BASE, ETHERSCAN } from './config.js';
import { T, LANGS, pickInitialLang } from './i18n.js';

// Claim flow: link check -> Privy login -> confirm address -> relay mint.
// The user never signs a transaction and never pays gas (backend relay).
// UI is trilingual (中/EN/日); default comes from ?lang=, then the link's
// admin-set language, then the browser, then Chinese.

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

  const cardProps = { lang, onLang: chooseLang };

  // ---------- render ----------

  if (phase === 'checking' || !ready) {
    return <Card {...cardProps} title={t.checking} />;
  }

  if (phase === 'bad-link') {
    return (
      <Card {...cardProps} title={t.linkUnavailable}>
        <p className="error">{t['reason_' + reason] || t.reason_invalid}</p>
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
              src="https://ipfs.io/ipfs/bafybeihpmwj5ekxbqzxrqbksc2css36tk3m23t32rxmaxdbs6buo2x2ck4"
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
        <p className="muted">{t.welcome}<br />{t.screenshot}</p>
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
