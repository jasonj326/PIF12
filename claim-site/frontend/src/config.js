// Build-time config — set in .env / CF Pages env vars (VITE_ prefix).
export const PRIVY_APP_ID = import.meta.env.VITE_PRIVY_APP_ID || 'TBD';
export const API_BASE = import.meta.env.VITE_API_BASE || 'https://pif12-claim-api.workers.dev';
export const ETHERSCAN = 'https://etherscan.io/tx/';
