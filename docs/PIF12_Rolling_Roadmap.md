# PIF12 滾動式三年 Roadmap（Rolling 3-Year）

> ⚠️ Authorship 注記：本文由 Claude session（2026-06-11）撰寫/改寫，Jason 核可方向但用詞選材為 Claude 的，引述時標 provenance。

**版本**：1.0（2026-06-11，lightweight Y1 pivot 定案版）
**規劃哲學**：滾動式三年制——Y1–Y3 具體規劃、**每年更新一次**；Y4–Y12 只保留方向，不做承諾式年表。取代原《PIF12_12Year_Roadmap.md》（已加 superseded banner 存檔為初始願景）。
**鏈**：Ethereum L1（已定案）。**北極星**：記錄感恩、簡單、好玩。
**名詞對照**：合約內 `Curator` = 小太陽（ZH）= Lightkeeper（EN）；星星（ZH）= Star（EN）= pSBT。「12」指 12 年 / 12 款生肖設計——**不是 12 人上限**。

---

## 生肖年對照表

| 年次 | 西元 | 生肖 | 規劃狀態 |
|------|------|------|---------|
| Y1 | 2026 | 馬 Horse | **領取年**（具體規劃，本文 §Y1） |
| Y2 | 2027 | 羊 Goat | **兩層啟動**（具體規劃，本文 §Y2） |
| Y3 | 2028 | 猴 Monkey | **多簽遷移**（具體規劃，本文 §Y3） |
| Y4 | 2029 | 雞 Rooster | TBC（方向性） |
| Y5 | 2030 | 狗 Dog | TBC |
| Y6 | 2031 | 豬 Pig | TBC |
| Y7 | 2032 | 鼠 Rat | TBC |
| Y8 | 2033 | 牛 Ox | TBC |
| Y9 | 2034 | 虎 Tiger | TBC |
| Y10 | 2035 | 兔 Rabbit | TBC |
| Y11 | 2036 | 龍 Dragon | TBC |
| Y12 | 2037 | 蛇 Snake | TBC |

## 五大管理領域

- **(A) 程式碼** — 智能合約、前端、腳本
- **(B) 行銷與宣傳** — 網站、社群媒體、活動、品牌
- **(C) 圖檔與視覺資產** — 年度生肖款設計、IPFS metadata、品牌素材
- **(D) 上鏈與管理權** — 合約操作、admin 金鑰（Y1–Y2 發起人 EOA、Y3 起社群多簽）、IPFS、鏈上狀態
- **(E) 社群經營** — 成員關係、治理、線下活動、文化建設

---

## Y1 — 2026 馬年：領取年

**主題：「一個人的出發」**——刻意的輕量起步。

### 範圍（in scope）

- **6/21 上線**：馬年 SBT 無上限開領（每年一「款」生肖設計，馬年是第一款）
- **Claim 閘門 = link 制、不限量產生**：一次性、crypto-random 不可猜的 claim link；可設過期（TTL）；可手動撤銷。**不是開放式 claim 頁**——「無上限」指對「真實與發起人交會過的人」不限量產生 link；sybil 防護是社交的，不是技術的
- **鑄造 = 後端 relay 代鑄**（GAME_ROLE relayer 呼叫 `mintCuratorToken`）：使用者只提供地址，**不簽任何交易、不付 gas**（Privy：Google/email 生成錢包，或連外部錢包）
- **Landing Page 更新**（V8 敘事，zh + en；Webb 部署）

### 明確不做（out of scope）

- ❌ 星星 / pSBT 發行——`issuanceEnabled` 部署即 false，整年維持 false
- ❌ 多簽（Safe）——Y3 才建
- ❌ Paymaster / meta-tx——Y2 才建

### 管理權與安全

- **admin = 發起人單一 EOA**（部署時參數，非合約變更；合約 v1.0.0 不動）。此金鑰可執行 UUPS 升級、pause、預設模式錢包恢復
- **金鑰紀律**：硬體錢包 + 經還原測試的離線備份；熱操作最小化；**遺失視同被盜等級事件處理**
- **安全狀態**：內部測試 + 安全審視（48 個 Foundry 測試全過）。**未經外部安全審查**——Y1 鏈上功能面窄（只有 relay 代鑄 + soulbound；發行程式碼以 `issuanceEnabled` 閘門關閉），外部審查錨定在 Y2 開啟發行之前（見 §Y2）
- **恢復機制**：三種模式（發起人預設 / Guardian 雙守護 / 獨狼）**合約內建、上線即全部生效**；預設模式零設定自動適用。後補的只是「切換模式的 UI」——在那之前，成員可隨時請發起人協助切換

### Y1 里程碑（質性指標）

- [ ] 合約部署 Ethereum L1 + Etherscan verify
- [ ] Claim 流程端到端跑通：link → Privy 錢包 → relay 代鑄 → 錢包看到馬年 SBT
- [ ] Landing Page V8 上線（zh + en）
- [ ] Admin EOA 離線備份完成且經還原演練驗證

> **誠實注記（馬年成員與星星）**：合約規定的發星窗口是「該生肖年農曆年底」與「領取後第 100 天」取較晚者。Y2 開啟發行旗標時，**馬年成員的窗口已屆滿——Y1 成員不會發星星**，星星從 Y2（羊年）cohort 開始。不做窗口延長的特例。星座隱喻以 12 年願景存續（未來式：「從第二年起」）。

---

## Y2 — 2027 羊年：兩層結構啟動

**主題：SBT + pSBT 兩層開始**——羊年小太陽（Lightkeeper）把光傳下去，發出第一批星星（Star，pSBT）。

### 工程 backlog（承《PIF12_Claim_Roadmap.md》§6，原 Stage 2）

- **Gasless 架構拍板（2027 上半年決定）**：(A) ERC-2771 meta-tx（forwarder + relayer）vs (B) ERC-4337 帳戶抽象（Privy smart wallet + Pimlico paymaster）——合約兩者皆相容，不需改合約
- IPFS pin（自訂圖片 + metadata；Pinata / web3.storage）
- `/issue` 發星頁（沿用 Y1 claim 棧：同一 Privy session，`isCurator` gate）
- Paymaster 預算池建置 + 監控（gasless 是目標，不是保證）
- **外部安全審查：錨定在開啟發行之前**——審查完成後，才由 admin（屆時仍為發起人 EOA，Y3 才升級多簽）執行 `setIssuanceEnabled(true)`

### 小太陽指南（濃縮版）

> Provenance：本節濃縮自 Claude 撰寫的《小太陽指南》（`website/PIF12_Curator_Guide.html`，2026-05-28）；原檔退役，Y2 設計參數以本節為準。

**參數表**

| 參數 | 值 |
|------|-----|
| 每位小太陽可發星星總量 | 50 顆 |
| 每位受贈者 | 最多 1 顆 |
| 發行截止 | max（該生肖年農曆年底，領取後第 100 天） |
| Gas | Paymaster 代付（目標） |

**發行 UX 大綱**（沿用 Y1 claim 棧）

- Privy 登入（Google/email → embedded wallet，或外部錢包）——與 claim 同一 session
- 前端讀 `isCurator` 解鎖發星按鈕；顯示剩餘 quota 與截止倒數（`getProfile` / `curatorIssuanceDeadline`）
- 選受贈者（一次性邀請 link 或直接填地址）→ 選圖（IPFS pin）→ 寫贈言 → 確認送出（meta-tx，Paymaster 付 gas）
- 幕後呼叫 `issuePersonalSBT()`，以小太陽本人的錢包身分發出

**設計約束**

- **贈言永久公開上鏈、不可刪**——發行 UI 必須在確認前明確警告
- **兩層即停**：星星持有者不能再往下發星星
- **星星從 Y2 cohort 開始**（見 Y1 誠實注記）
- **心法：慎選不衝量**——星星是信，不是空投；50 顆不是 KPI

**恢復機制**（合約自 Y1 上線即內建，Y2 補切換 UI）

- 三模式：**發起人預設**（admin 協助恢復；admin Y1–Y2 為發起人 EOA，Y3 起為多簽）／ **Guardian 雙守護**（兩位 PIF12 網路內成員共同恢復）／ **獨狼**（放棄任何恢復路徑）
- 任何恢復模式變更有 **48 小時 timelock**
- （選配）互助計數：記「幫過幾個不同的人」——**計人不計次、無分數無排行榜**；若 Y2 範圍吃緊，此項最先順延 Y3+

### Y2 里程碑（質性指標）

- [ ] 外部安全審查完成
- [ ] `setIssuanceEnabled(true)` 上鏈（審查後）
- [ ] 第一顆星星由羊年小太陽發出

---

## Y3 — 2028 猴年：管理權交給多簽

**主題：核心成員浮現，發起人交出單一金鑰。**

- 核心成員確認（社群經營 2 年後自然浮現的名單）
- 建立 Safe 多簽，**owner 含核心成員**
- 遷移程序（不需修改合約）：`grantRole` 給 Safe → 驗證 Safe 可實際操作（setYearWindow / pause 演練）→ EOA `renounceRole` 撤出
- 多簽演練：pause/unpause、模擬一次預設模式恢復、UUPS 升級流程 dry-run

### Y3 里程碑（質性指標）

- [ ] admin 不再是任何單一 EOA
- [ ] Safe 完成至少一次真實管理操作（如年度 `setYearWindow`）

---

## Y4–Y12：方向性（TBC）

每年一款生肖 SBT 持續發行（12 年 12 款收齊一輪迴）；治理逐步去中心化——多簽 owner 擴大、年度決策權移轉社群、發起人從執行者退為參與者；Republic Labs 種子——12 年實驗收尾時由社群決定：自然封存、演進為 Republic Labs、或開放框架供他人複製。具體規劃**每年滾動更新本文時才寫**，不預先承諾。

---

## 年度常態任務（每年重複）

- **(A) 程式碼**：依賴安全檢查（OZ 版本）／合約升級年度評估／前端與網站維護／repo 整理
- **(B) 行銷**：新年度生肖款發布公告／年度回顧文／Landing Page 更新（當年主題）
- **(C) 視覺**：新年度生肖款設計／metadata JSON 製作與 IPFS 上傳／社群素材更新
- **(D) 上鏈與管理權**：年度 `setYearWindow` + 開領新生肖款／**管理權健檢**（Y1–Y2：EOA 離線備份還原演練；Y3 起：Safe owner 與門檻檢視）／IPFS pin 健檢／鏈上操作紀錄存檔／gas 費紀錄
- **(E) 社群**：年度聚會（至少一次）／成員 check-in／年度計畫討論／文化紀錄（故事、里程碑）

---

## 治理演進表

| 年次 | 管理權 | 說明 |
|------|--------|------|
| Y1–Y2 | **發起人單一 EOA** | 刻意輕量起步；硬體錢包 + 離線備份紀律；無多簽 |
| Y3+ | **社群多簽（Safe，owner 含核心成員）** | `grantRole` → 驗證 → `renounceRole`，不需修改合約 |
| Y4+ | TBC | owner 組成與門檻隨社群演進滾動決定 |

### 單一 EOA 揭露

「Y1–Y2 期間，合約管理權（升級、暫停、預設錢包恢復）由發起人的單一錢包持有——這是刻意的輕量起步，不是疏忽。隨核心成員浮現（預計 Y3，2028 猴年），管理權將遷移至含社群成員的多簽錢包；此遷移不需修改合約。在此之前，任何成員都可以隨時把自己的恢復模式改為 Guardian（雙守護人）或獨狼模式，收回這份信任。」

---

## 風險與應變

| 風險 | 影響 | 應變 |
|------|------|------|
| **Y1–Y2 單一 EOA admin 金鑰遺失／被盜** | 金鑰之上沒有「admin 的 admin」——**遺失即恢復／升級／暫停權永久報廢**；被盜即 UUPS 升級權與即時恢復權落入他人之手 | 硬體錢包＋經還原測試的離線備份；熱操作最小化；遺失視同被盜等級處理；**Y3 遷移多簽 = 此風險的退場條件** |
| 發起人無法繼續主導 | 項目停滯 | Y1–Y2 敞口最大（單一 EOA）；成員可隨時自改 Guardian／獨狼模式自保；Y3 多簽後社群可接手 |
| 合約漏洞被利用 | 身分／狀態損失 | `pause()` 緊急凍結 + UUPS 升級修復；Y2 開發行前完成外部安全審查 |
| Relay 錢包（GAME_ROLE）被盜 | 亂鑄馬年 SBT | admin（Y1 為發起人 EOA）隨時 `revokeRole(GAME_ROLE)`；誤鑄可 burn 回收 |
| IPFS 內容遺失 | metadata 不可讀 | 多重 pin（Pinata＋本地備份＋web3.storage） |
| Ethereum L1 重大環境變動 | 成本／可用性受影響 | 合約可升級（UUPS）；屆時評估因應（鏈選擇已定案，不輕易重開） |

---

## 附錄：關鍵地址紀錄簿

> 部署後填入，此區塊應離線備份。

```
Admin EOA（發起人，Y1–Y2）:   0x___________________________________
Safe 多簽地址（Y3 填入）:      0x___________________________________
Implementation:               0x___________________________________
Proxy（主合約）:               0x___________________________________
Trusted Forwarder:            0x0…0（Y1 不用；Y2 隨 gasless 架構拍板）
Relayer 地址（GAME_ROLE，Worker 直簽）: 0x___________________________________
IPFS Metadata CID:            ___________________________________

Year 1（馬）Token ID: 1
Year 2（羊）Token ID: 2
Year 3（猴）Token ID: 3
...（以此類推）
```

---

*「每一個善行都是一顆星。我們一起畫出一個星座。」——12 年願景，從第二年起逐年成形。*
*— PIF12*
