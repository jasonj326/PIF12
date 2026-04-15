# SOP: Contract Deploy（PIF12 合約部署）

> Forge session 的合約部署執行手冊。
> 寫給：未來的 Jason、未來的 Forge session、未來接手的人。
> 原則：**每一步都是不可逆的**——寫得像核彈發射檢查清單那樣嚴謹。

---

## 適用範圍

- **初始部署**：V6 合約首次部署到 Base Mainnet（當前狀態）
- **升級部署**：UUPS proxy 的 implementation 升級（Y2+）
- **不適用**：Base Sepolia 測試部署（那是 dry-run，失敗可重來，不走本 SOP）

---

## Phase 0：部署前強制檢查清單（Pre-flight）

**任何一項未確認，不得進 Phase 1。**

### 0.1 程式碼層

- [ ] 合約版本已 tag（`git tag v6.0.0` + `git push --tags`）
- [ ] `contracts/PIF12.sol` 與當前生產 branch 一致
- [ ] 審計報告 HIGH/MEDIUM/LOW findings 全部逐條比對
- [ ] Base Sepolia 測試部署成功（完整 mint/recover flow 測過）
- [ ] 所有外部 import（OpenZeppelin、ERC-2771）版本鎖定

### 0.2 治理層

- [ ] Safe 多簽錢包已建立（Base Mainnet, 2-of-3）
- [ ] 3 個 signer 地址已確認並由不同設備/人持有
- [ ] Safe threshold 設定正確（2-of-3 非 1-of-3）
- [ ] Jason EOA 已備份 seed（紙本 + 實體保險位置）

### 0.3 資產層

- [ ] IPFS metadata JSON 已寫好（馬年 Omamori）
- [ ] Omamori 圖檔已壓縮並最終確認（`assets/` 下）
- [ ] IPFS pin 服務選定（Pinata / web3.storage / NFT.Storage）
- [ ] Metadata URL 格式驗證（`ipfs://<CID>/0.json` 可解析）

### 0.4 環境層

- [ ] Base Mainnet RPC 確認可用（官方 `https://mainnet.base.org`）
- [ ] MetaMask 已切 Base Mainnet 且地址正確
- [ ] 錢包 ETH 餘額 > 0.05 ETH（預留部署 + 驗證 + 3 次失敗重試 gas）
- [ ] Basescan API key 已準備（用於 verification）
- [ ] 無其他 session 同時在做鏈上操作（避免 nonce 衝突）

### 0.5 人為層

- [ ] 睡眠充足（不要凌晨三點部署不可逆合約）
- [ ] 未喝酒 / 未服藥影響判斷力
- [ ] Jason 親自在場主操作（不遠端遙控、不代理）
- [ ] 手機充飽、網路穩定
- [ ] 有至少 2 小時連續無打擾時段

**全部打勾後才進 Phase 1。**

---

## Phase 1：IPFS Metadata 上傳

1. 最終確認 metadata JSON 內容（`metadata/0.json`）：
   - `name`、`description`、`image`、`attributes`（年份、生肖、編號）
2. 上傳圖檔到 IPFS → 取得 `<image_CID>`
3. 更新 JSON 中 `image` 欄位為 `ipfs://<image_CID>`
4. 上傳 JSON 到 IPFS → 取得 `<metadata_CID>`
5. 驗證：瀏覽器開 `https://ipfs.io/ipfs/<metadata_CID>` 能看到完整 JSON
6. **記錄 CID 到 `PIF12_Engineering_Notes.md`**（不可逆，永久保存）

> ⚠️ IPFS 上傳後**不能改**。這個 CID 永遠綁在 token URI 上。

---

## Phase 2：合約部署（Remix + MetaMask）

**走 Remix Web IDE，不用 Foundry/Hardhat CLI**——UI 操作比腳本可逆誤差小。

1. 開 https://remix.ethereum.org
2. 上傳 `contracts/PIF12.sol` + 所有 OpenZeppelin 依賴
3. Compiler：使用合約裡 pragma 指定版本（不要用 default）
4. 編譯結果與本地 `out/` 對比 bytecode hash
5. Environment：選 "Injected Provider - MetaMask"，確認 Chain ID 為 8453（Base Mainnet）
6. Deploy parameters：
   - 初始 admin：**Jason EOA**（暫時，Phase 5 會轉給 Safe）
   - Trusted forwarder (ERC-2771)：預先決定的 relayer 地址
   - Base URI：Phase 1 的 `ipfs://<metadata_CID>/`
7. **按 Deploy 前最後一次檢查 gas estimate 是否合理**（不要被 gas spike 坑）
8. 確認交易後記錄：
   - Implementation address
   - Proxy address（**這是未來公告的 contract address**）
   - Deploy tx hash

> ⚠️ 部署後**不能關閉瀏覽器**直到 Phase 3 完成。地址丟了可以 Basescan 查，但 compile artifact 丟了 verification 會卡住。

---

## Phase 3：Basescan Verification

1. Basescan 開 proxy address → "Contract" tab → "Verify and Publish"
2. 選 "Solidity (Single file)" 或 "Multi-Part Files"（看編譯方式）
3. 貼上 source code + constructor arguments（ABI-encoded）
4. Compiler version 必須**完全**對上（包括 commit hash）
5. 提交後等待 10-60 秒
6. 看到綠色 ✅ Contract Source Code Verified
7. Proxy pattern verify：額外做「Is this a proxy?」→ Basescan 會自動偵測 implementation

> ⚠️ Verification 失敗不影響合約功能，但沒 verify 的合約社群不會信任。48 小時內必須完成。

---

## Phase 4：初始狀態檢查

在轉移權限前先確認合約活著且行為正確：

1. Basescan → Read Contract：
   - `owner()` 或 `admin()` 回傳 Jason EOA ✅
   - `totalSupply()` = 0 ✅
   - `uri(0)` 回傳正確 IPFS URL ✅
2. Write Contract：**不要在這裡測 mint**——留給 Phase 6

---

## Phase 5：角色轉移（EOA → Safe）

**這是最危險的一步。錯了就永久失去合約控制權。**

1. 再次確認 Safe 地址**本人**能登入 app.safe.global 且看到 2-of-3 threshold
2. Basescan → Write Contract → `transferOwnership(<Safe_address>)` 或等價函式
3. **貼地址前 3 次複誦**地址前 6 碼 + 後 4 碼
4. 交易送出前，錢包彈出確認畫面再確認一次 to/data
5. 交易成功後，**立刻驗證**：
   - `owner()` 回傳 Safe address
   - 用 Jason EOA 嘗試呼叫 admin function → **必須 revert**
6. Safe 介面能看到自己是 owner 並能 propose transaction

> ⚠️ 如果轉錯地址，**合約永久報廢**（除非該地址恰好是另一個你控制的地址）。不要相信 ENS 反解析——永遠用 raw address。

---

## Phase 6：測試 Mint（Safe Transaction Builder）

1. Safe → Apps → Transaction Builder
2. Contract address：PIF12 proxy
3. Function：`mint`（或合約定義的首發函式）
4. Parameters：
   - `to`：Jason 自己的收件地址（**不是 Safe 自己**——SBT 不可轉，會卡死）
   - `tokenId`：0
   - `amount`：1
5. Propose → 2nd signer 簽核 → Execute
6. 交易成功後驗證：
   - Basescan proxy → Read → `balanceOf(Jason, 0)` = 1
   - OpenSea/Basescan NFT viewer 顯示 metadata 正確
   - 嘗試 `safeTransferFrom` → **必須 revert**（SBT 特性驗證）

---

## Phase 7：公告 + 文件更新

1. 通知 Webb 更新 Landing Page（contract address、explorer link、mint 說明）
   - 在 HANDOFF 發 `Forge → Webb` 請求，附：proxy address、metadata CID、explorer URL
2. 更新 `PIF12_Engineering_Notes.md` 記錄完整部署事件
3. 更新 `README.md` 移除 TBC placeholder
4. git commit + tag `v6.0.0-deployed`
5. （選配）寫 LinkedIn / X 公告貼文（走 Lex 合規掃描後發）

---

## Emergency / Rollback

**合約是 UUPS upgradeable，bug 可透過升級修復**（除非 upgrade 權限已 renounce，Y5+ 才會做）。

緊急流程：

| 情境 | 動作 |
|------|------|
| 發現 critical bug 且未被利用 | Safe 2-of-3 執行 `pause()`（若合約有）→ 寫 fix → 部署新 implementation → upgrade |
| Bug 已被利用 | `pause()` → 評估損失 → 公告 → 根據 Roadmap emergency 章節處理 |
| 私鑰外洩（Safe signer 之一）| 立刻移除該 signer + 加新 signer（需其他 2 人簽）→ 所有資產移出 |
| IPFS metadata 損毀 | 重新 pin（多個服務同步 pin）|

詳見 `docs/PIF12_12Year_Roadmap.md` 的風險矩陣。

---

## 本 SOP 的迭代紀律

- 每次部署後**當天**補充：這次遇到什麼 edge case、哪些步驟太囉嗦、哪些步驟太草率
- Y1-Y12 每次升級部署都走本 SOP
- 過時步驟用 `~~刪除線~~` 保留歷史，不直接刪

---

## 狀態（2026-04-15）

**SOP v1.0**。V6 合約尚未執行 Phase 1-7，本 SOP 是 pre-flight 版本，首次部署後會根據實戰補正。
