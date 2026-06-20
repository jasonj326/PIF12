import React from 'react';
import { createRoot } from 'react-dom/client';
import { PrivyProvider } from '@privy-io/react-auth';
import { PRIVY_APP_ID } from './config.js';
import App from './App.jsx';

createRoot(document.getElementById('root')).render(
  <PrivyProvider
    appId={PRIVY_APP_ID}
    config={{
      // 'email' and 'google' work with Privy's default credentials (zero setup);
      // email OTP also dodges Google's in-app-browser limitation. 'line' and
      // 'apple' each require your OWN OAuth credentials configured in the Privy
      // dashboard first (LINE channel / Apple Developer account) — only add them
      // back here AFTER that's live, or the login modal fails to render.
      loginMethods: ['email', 'google', 'wallet'],
      appearance: { theme: 'dark', accentColor: '#d4af6a' },
      embeddedWallets: { createOnLogin: 'users-without-wallets' },
    }}
  >
    <App />
  </PrivyProvider>
);
