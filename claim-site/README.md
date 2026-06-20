# PIF12 Claim Site — `claim.jasonjlai.net`

> ⚠️ Authorship 注記：本文件與本目錄程式碼由 Claude session（2026-06-11）撰寫，
> 架構方向經 Jason 拍板（link 制不限量、Privy 三登入、relay 代鑄）。
>
> Y1（2026 馬年）唯一交付：**6/21 上線，讓路有交集的人 gasless 領取馬年 SBT。**

## 架構（一張圖）

```
 Jason（admin 工具/CLI）
   │  產生一次性 claim link（可批次、可設過期）
   ▼
 https://claim.jasonjlai.net/?t=<token>
   │
   ▼
 前端（CF Pages, Vite + React + Privy）
   │  1. GET /api/link/:token   → link 有效？
   │  2. Privy 登入（Apple / Google / WalletConnect）→ 取得收件地址
   │  3. POST /api/claim {token, address} + Privy auth token
   ▼
 Worker（CF Worker + D1）
   │  驗 link（未用/未過期/未撤銷）→ 驗 Privy token →
   │  eth_call isCurator(address) 鏈上預檢（已領過？）→
   │  用 GAME_ROLE 鑰匙（Worker Secret）簽名 mintCuratorToken(address, year)
   ▼
 Alchemy RPC → Ethereum L1 — PIF12Nexus（使用者全程不簽名、不付 gas）
```

> **架構決定（2026-06-12）**：原規劃用 OZ Defender 託管 relayer，但 Defender 已停止新註冊
> （2025-06-30）並將於 **2026-07-01 關閉**。改為 Worker 直簽：GAME_ROLE 私鑰放 CF Worker
> Secret（加密存放、設定後不可讀回）。風險成比例：GAME_ROLE 權限極窄（只能 mint，不能
> 升級/恢復/撤銷），鑰匙若洩漏 admin 一個 revokeRole 即時止血、亂發 token 可 burn——
> 合約當初就是為這個失敗模式設計的。鑰匙只裝 gas 零錢。Y3 升級多簽時再評估自架 OZ Relayer（開源版）。

## 防重複領取——三層設計

| 層 | 擋什麼 | 在哪實作 |
|---|---|---|
| **合約層**（已內建，零工作）| 同一地址領兩次 | `isCurator[to]` + `balanceOf` 雙檢查，鏈上保證 |
| **Link 層**（D1）| 同一連結用兩次、轉傳 | token 一次性：用掉即標 `used_at`；可設 TTL、可手動撤銷 |
| **社交層**（link 制本身）| 同一個人多地址多領 | link 由 Jason 親手發給「路有交集的人」，一人一條；想多領得再跟 Jason 要——社交關係就是 sybil 防線 |

> Jason 原本的想像「開網頁給他 → claim → 手動關後台」由 **TTL + 一次性** 自動化了：
> link 預設 72 小時過期、用掉即失效，不需要手動關。後台保留單條撤銷（revoke）能力。

## 隱私規範（硬性）

- **D1 不存任何個資**：沒有姓名、email、備註欄。專案規範禁止記錄「某人 = 0x地址」的對應。
- link → 人的對應由 Jason **線下自記**（紙本或本地私人筆記），資料庫只有 token 與時間戳。
- Privy 設定為不向我們的後端傳 email；我們只存 Privy user id（不可逆向出身分）防同帳號重複。

## 目錄

```
claim-site/
  README.md            ← 本檔
  frontend/            ← CF Pages（Vite + React + Privy）— 領取頁
  worker/              ← CF Worker API + D1 schema + relay 直簽（viem）
  admin/index.html     ← 後台工具（產生連結 / 單人·群組 / QR / 感謝存底）
```

## 後台工具（`admin/index.html`）

單檔、無 build。**本機開啟即可用**（`open claim-site/admin/index.html`，或 `npx serve claim-site/admin`）。
連線時填 API 位址 + `ADMIN_TOKEN`（存在分頁 sessionStorage，不落地）。

- **單人連結**：max_uses=1、可帶個人化感謝話 → 面對面送一個人。
- **群組／班級連結**：一條共用連結 + 集體感謝話 + 數量上限（可不限）→ 投影片放 QR、課後按「關閉」。合約保證一個錢包只領一枚。
- **存進感謝存底**：把（日期＋標籤＋感謝話＋連結碼）累積在瀏覽器 → 按「匯出 .md」下載**完整一本** → 覆蓋本機 `Archive/PIF12_Gift_Journal.md`（gitignored，**不進公開 Git**）。線上 D1 在領取後會清掉單人連結的感謝話與標籤（隱私規範），這本是你手上的離線回憶。

> ⚠️ admin 工具本身不含密鑰（token 執行時才輸入），可進公開 repo；但**不要部署到公開 claim 網站**——本機跑或放 Cloudflare Access 後面。

## Jason 要準備的憑證（部署前 checklist）

| # | 項目 | 哪裡拿 | 放哪 |
|---|---|---|---|
| 1 | Privy App ID | dashboard.privy.io 建 app（開 Apple + Google + WalletConnect）| 前端 `VITE_PRIVY_APP_ID` + Worker secret `PRIVY_APP_ID` |
| 2 | Relayer 鑰匙（GAME_ROLE）| 本機 `cast wallet new` 生成全新鑰匙對（**私鑰不入檔案/git/對話**，Jason 親手輸入）| Worker secret `RELAYER_PRIVATE_KEY`；**地址**填部署 `initialize` 的 `gameOperator` |
| 3 | Relayer gas | 轉 ~0.05 ETH 到上面的 relayer 地址（之後視用量補充）| 鏈上 |
| 4 | Alchemy RPC URL | alchemy.com 建 app（Mainnet + Sepolia 各一個）| Worker secret `RPC_URL` |
| 5 | Admin bearer token | 自訂亂數（`openssl rand -hex 32`）| Worker secret `ADMIN_TOKEN` |
| 6 | 合約地址 | 部署後 | `wrangler.toml` 的 `CONTRACT_ADDRESS` |
| 7 | D1 database id | `wrangler d1 create pif12-claim` | `wrangler.toml` |
| 8 | DNS CNAME | Webb（已在 HANDOFF 請求）| Cloudflare Pages |

## 部署步驟（需 Jason 確認才執行）

```bash
# 1. D1
cd claim-site/worker
wrangler d1 create pif12-claim          # 把 id 填進 wrangler.toml
wrangler d1 execute pif12-claim --file=schema.sql

# 2. Secrets（互動式輸入，值不留在 shell history）
wrangler secret put ADMIN_TOKEN
wrangler secret put RELAYER_PRIVATE_KEY   # Jason 親手貼，不經過任何檔案或對話
wrangler secret put RPC_URL
wrangler secret put PRIVY_APP_ID

# 3. Worker
wrangler deploy                          # ⚠️ 上線操作，先問 Jason

# 4. 前端
cd ../frontend
npm install && npm run build             # dist/ 上 CF Pages
```

## 產生 claim link（admin）

```bash
curl -X POST https://<worker-url>/api/admin/links \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"count": 5, "year": 1, "ttlHours": 72}'
# 回傳 5 條完整 URL（含 QR 用的 token）。面對面場景：把 URL 轉 QR code 給對方掃。
```

## Y1 範圍外（明確不做）

- ❌ 發星星（pSBT）— Y2 2027
- ❌ Paymaster / EIP-712 meta-tx — Y2（Y1 的 gasless 靠 relay 代鑄，使用者本來就不簽）
- ❌ Recovery 模式切換 UI — 後續版本（三種模式合約皆已內建生效）
- ❌ 多簽 — Y3 2028
