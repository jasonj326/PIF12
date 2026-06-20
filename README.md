# 🌌 PIF12 — Pay It Forward, 12-Year Legacy

> *A 12-year on-chain social experiment that turns gratitude into a verifiable, soulbound legacy.*

![Version](https://img.shields.io/badge/version-v1.0.0-C9A96E?style=flat-square)
![Network](https://img.shields.io/badge/network-Ethereum-3C3C3D?style=flat-square&logo=ethereum)
![Standard](https://img.shields.io/badge/standard-ERC--1155%20Soulbound-success?style=flat-square)
![License](https://img.shields.io/badge/license-GPL--3.0-blue?style=flat-square)
![Tests](https://img.shields.io/badge/foundry%20tests-48%20passing-brightgreen?style=flat-square)
![Solidity](https://img.shields.io/badge/solidity-0.8.28-363636?style=flat-square&logo=solidity)

**[English](#-english) · [繁體中文](#-繁體中文)**

> *"Every act of kindness is a star. Together, we are drawing a constellation."*

---

## 🇺🇸 English

**PIF12** is a 12-year community experiment on **Ethereum**. It starts as a solo initiative — in Year 1 (2026, the Horse year), anyone whose path has crossed the founder's can claim the Horse-year token, unlimited and by personal link — and the long-term vision is to evolve into a decentralized **Republic Labs** by the end of the twelve-year journey.

We rely, every day, on the labor of countless people we'll never meet. It is through mutual support that connection is forged — and from connection, a real community and a sense of belonging are born. Here, we find joy in helping others and feel no shame in asking for help. Even when we cannot repay a kindness directly, we pass that gratitude forward to someone else.

PIF12 v1.0.0 removes every numeric score (the earlier "karma" and "blessing value" designs were never deployed). There is no leaderboard — only a record of the people you've touched and who've touched you.

### ✨ Core Mechanisms

- **🪪 Soulbound Tokens (SBT)** — non-transferable ERC-1155 identity. A token follows the person; it can't be bought, sold, or traded.
- **🕸️ Curator Network** — a two-layer trust constellation. The Initiator mints a zodiac-year token to a **Lightkeeper** (小太陽); each Lightkeeper who holds an SBT may issue a customized **Star** (星星, a pSBT) to someone they admire, appreciate, or wish to thank. The network stops at two layers. *Phasing:* Year 1 (2026, Horse) issues only the zodiac-year SBT — unlimited, by personal claim link. Star issuance begins with the Year 2 cohort (2027, Goat), gated on-chain by the `issuanceEnabled` flag (deployed off); Year 1 holders' issuance window will have lapsed by then, so the constellation starts being drawn from Year 2.
- **🤝 Unique-People Counting** — every SBT and pSBT holder can see two on-chain counters: how many *distinct* people you've helped (`peopleHelped`) and how many *distinct* people have helped you (`peopleHelpedBy`). Help is co-attested: the giver records it, the recipient confirms.
- **🛟 Social Recovery (3 modes)** — recoverable by the Initiator by default (a single founder wallet in the early years; planned upgrade to a multisig as core members emerge, around Year 3); a member may opt out to two designated guardians (dual-approval + timelock) or to *Lone Wolf* (no recovery, full self-sovereignty). All three modes are built into the contract and live at launch — the default applies with zero setup (the mode-switching UI ships later; until then, ask the founder).
- **⛽ Gasless** — ERC-2771 meta-transactions + Paymaster. The aim is a gas-free experience — **a hope, not a guarantee**: when the network isn't congested and the budget allows, participants can avoid gas fees. We'd rather under-promise than over-commit.

### 🗓 Roadmap — rolling three years

We plan firmly one year out, directionally three ([full roadmap](./docs/PIF12_Rolling_Roadmap.md)):

- **Year 1 · 2026 Horse — Claim.** Open, unlimited claiming of the Horse-year SBT by personal link; gasless for the claimer via backend relay mint.
- **Year 2 · 2027 Goat — Stars.** The two-layer constellation begins: Lightkeepers issue Stars (pSBT). Gasless meta-transactions + Paymaster are built, and an external security review is anchored before issuance is switched on.
- **Year 3 · 2028 Monkey — Multisig.** As core members emerge, administration migrates from the founder's single wallet to a community multisig (grant role, then renounce — no contract change).
- **Years 4–12** — directional only; written down one year at a time.

### 🛠 Tech Stack

| Category | Technology |
| :--- | :--- |
| Network | Ethereum L1 |
| Standard | ERC-1155 (Soulbound) |
| Architecture | UUPS Upgradeable Proxy |
| Gasless | ERC-2771 + Paymaster |
| Dependencies | OpenZeppelin Contracts (Upgradeable) v5 |
| Tooling | Foundry (forge / cast) |

### 🧪 Build & Test

```bash
git clone https://github.com/jasonj326/PIF12.git
cd PIF12
forge install foundry-rs/forge-std \
  OpenZeppelin/openzeppelin-contracts-upgradeable@v5.1.0 \
  OpenZeppelin/openzeppelin-contracts@v5.1.0
forge test            # 48 tests
forge build --sizes   # bytecode under the EIP-170 24 KB limit
```

### 📚 Documentation

- **Whitepaper:** [English](./docs/whitepaper/PIF12_Whitepaper_en.md) · 繁體中文（撰寫中）
- **Roadmap:** [rolling 3-year roadmap](./docs/PIF12_Rolling_Roadmap.md) — includes the Lightkeeper guide (Star issuance begins Year 2)
- **License:** [GPL-3.0-or-later](./LICENSE)

### 📍 Status

- **Version:** v1.0.0 (`PIF12Nexus`)
- **Stage:** pre-mainnet
- **Quality:** internal testing + security-reviewed (48 Foundry tests, Slither static analysis); an external security review is anchored **before Star issuance is enabled in Year 2** — Year 1's on-chain surface is deliberately narrow (relay mint + soulbound only)
- **Governance:** in Years 1–2, contract administration (upgrades, pause, default-wallet recovery) is held by a single founder wallet — a deliberate lightweight start, disclosed here rather than discovered later. It migrates to a community multisig as core members emerge (target Year 3; no contract change required). Until then, any member may opt out of founder-default recovery into Guardian or Lone Wolf mode at any time.
- **Mainnet proxy:** `TBD`

---

## 🇹🇼 繁體中文

**PIF12** 是一個部署在 **Ethereum** 上的 12 年社群實驗。第一年由我自己發起：2026 馬年，凡與我的人生有過真實交集的人，都能憑專屬連結領取馬年 token——開放領取、不設名額；長期目標是十二年後自然演進成分散式的**共和實驗室（Republic Labs）**。

因為我們明白，一日所需，百工斯為備。正因為互助，才有連結；因為連結，才有社群與歸屬。在這裡，我們助人為樂，也不恥於求助於人。即使受恩於人無以回報，我們也將這份感激，轉化為對另一個人的幫助——把善傳下去。

PIF12 v1.0.0 **移除了一切數值分數**（更早的「karma 業力」與「blessing value 福報」設計從未上線）。這裡沒有排行榜——只有一份「你觸碰過誰、誰觸碰過你」的紀錄。

### ✨ 核心機制

- **🪪 靈魂綁定身分（SBT）** — 不可轉讓的 ERC-1155 身分。token 跟著人走，不能買賣、不能轉讓。
- **🕸️ Curator Network（信任星座）** — 兩層信任網路。發起人發行生肖年 token 給**小太陽（Lightkeeper）**；持有 SBT 的每位小太陽，可再發客製化的**星星（Star，pSBT）**給敬佩、欣賞、感謝的人。網路止於兩層。*分期：*第一年（2026 馬年）僅發行生肖年 SBT——不限量、憑專屬連結領取；星星發行自第二年隊伍（2027 羊年）啟動，鏈上由 `issuanceEnabled` 旗標把關（部署即關閉）。屆時第一年持有者的發行窗口已自然屆滿——星座，從第二年開始畫起。
- **🤝 唯一人數計算** — 每個 SBT & pSBT holder 在區塊鏈上都看得到兩個計數：你幫過幾個*不同的*人（`peopleHelped`）、幾個*不同的*人幫過你（`peopleHelpedBy`）。互助需雙方確認：給予者記錄、受助者確認。
- **🛟 社會恢復（三模式）** — 預設由發起人守護（初期為發起人單一錢包；待核心成員浮現——預計第三年——升級為多簽）；成員可自行改為指定兩位 guardian（雙簽 + 時間鎖），或「孤狼模式」（無人能恢復，完全自治）。三種模式都已寫進合約、上線即生效——預設模式零設定自動套用（切換模式的介面稍後推出，期間可請發起人協助）。
- **⛽ Gasless** — ERC-2771 meta-transaction + Paymaster。目標是全程免 gas，但**這是期望、不是保證**：在以太鏈不塞車、且財務/預算許可時，參與者理論上可以免 gas fee。寧可保守，也不過度承諾。

### 🗓 Roadmap — 滾動式三年

一年定案、三年定向（[完整路線圖](./docs/PIF12_Rolling_Roadmap.md)）：

- **第一年 · 2026 馬年 — 領取。** 馬年 SBT 憑專屬連結開放領取、不設名額；由後端 relay 代為 mint，領取者免 gas。
- **第二年 · 2027 羊年 — 星星。** 兩層星座啟動：小太陽開始發星星（pSBT）。建置 gasless meta-transaction + Paymaster；外部安全審查錨定在發行啟用之前。
- **第三年 · 2028 猴年 — 多簽。** 核心成員浮現後，管理權自發起人單一錢包遷移至社群多簽（grantRole 後 renounceRole——無需修改合約）。
- **第四～十二年** — 僅定方向，一年一年寫實。

### 🛠 技術架構

| 類別 | 使用技術 |
| :--- | :--- |
| 部署網路 | Ethereum L1 |
| 代幣標準 | ERC-1155（Soulbound） |
| 升級架構 | UUPS 可升級代理合約 |
| Gasless | ERC-2771 + Paymaster |
| 依賴套件 | OpenZeppelin Contracts (Upgradeable) v5 |
| 開發工具 | Foundry (forge / cast) |

### 🧪 建置與測試

```bash
git clone https://github.com/jasonj326/PIF12.git
cd PIF12
forge install foundry-rs/forge-std \
  OpenZeppelin/openzeppelin-contracts-upgradeable@v5.1.0 \
  OpenZeppelin/openzeppelin-contracts@v5.1.0
forge test            # 48 個測試
forge build --sizes   # bytecode 在 EIP-170 的 24 KB 上限內
```

### 📚 文件

- **白皮書：** [English](./docs/whitepaper/PIF12_Whitepaper_en.md) · 繁體中文（撰寫中）
- **Roadmap：** [滾動式三年路線圖](./docs/PIF12_Rolling_Roadmap.md)（含小太陽指南；星星發行自第二年開始）
- **授權：** [GPL-3.0-or-later](./LICENSE)

### 📍 狀態

- **版本：** v1.0.0（`PIF12Nexus`）
- **階段：** 主網前（pre-mainnet）
- **品質：** 內部測試 + security review（48 個 Foundry 測試、Slither 靜態分析）；外部安全審查錨定在**第二年星星發行啟用之前**——第一年的鏈上介面刻意收窄（僅 relay mint + soulbound）
- **治理：** 第一、二年期間，合約管理權（升級、暫停、預設錢包恢復）由發起人的單一錢包持有——這是刻意的輕量起步，先講明、不藏著。隨核心成員浮現（預計第三年，2028 猴年），管理權將遷移至含社群成員的多簽錢包；此遷移不需修改合約。在此之前，任何成員都可以隨時把自己的恢復模式改為 Guardian（雙守護人）或孤狼模式，收回這份信任。
- **主網 Proxy：** `TBD`

---

*北極星不發熱，它指路。*

📝 Licensed under **[GPL-3.0-or-later](./LICENSE)** · 📄 Docs CC BY-SA 4.0 · © 2026 Jason J. Lai
