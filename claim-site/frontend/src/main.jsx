import React from 'react';
import { createRoot } from 'react-dom/client';
import { PrivyProvider } from '@privy-io/react-auth';
import { PRIVY_APP_ID } from './config.js';
import App from './App.jsx';

createRoot(document.getElementById('root')).render(
  <PrivyProvider
    appId={PRIVY_APP_ID}
    config={{
      // 'email' and 'google' use Privy's default credentials; email OTP also
      // dodges Google's in-app-browser limitation. 'line' uses Jason's own LINE
      // channel credentials, configured in the Privy dashboard (2026-06-20).
      // 'apple' still needs an Apple Developer account — only add it back here
      // AFTER that's configured, or the login modal fails to render.
      loginMethods: ['email', 'line', 'google', 'wallet'],
      appearance: { theme: 'dark', accentColor: '#d4af6a' },
      embeddedWallets: { createOnLogin: 'users-without-wallets' },
    }}
  >
    <App />
  </PrivyProvider>
);
