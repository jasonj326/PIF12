# PIF12 部署演練 Checklist（v1.0.0 · Y1 馬年）

> ⚠️ Authorship 注記：本文由 Claude session（2026-06-14）撰寫，Jason 核可方向。
>
> **流程**：先在 **Sepolia 測試網**完整演練一次 → 確認無誤 → **主網（W3, 6/19–21）**正式部署。
> **Y1 config**：admin = 發起人單一 EOA（非多簽）｜`issuanceEnabled` 部署為 **false**｜forwarder = `0x0`（Y1 無 meta-tx）。
> 合約 = `contracts/PIF12Nexus.sol`，UUPS proxy，48 Foundry 測試全過。

---

## 0. 部署前準備（你 = Jason）

| # | 項目 | 取得 | 備註 |
|---|------|------|------|
| 1 | **Deployer 私鑰** | 任一有 ETH 的 EOA | 只付 gas，**不會拿到任何 role** |
| 2 | **Admin EOA 地址** | 你的 admin 錢包（建議 Ledger）| 拿 DEFAULT_ADMIN + UPGRADER + PAUSER |
| 3 | **Relayer 地址** | `cast wallet new` 生成 | 拿 GAME_ROLE（只能 mint）|
| 4 | **Sepolia RPC** | Alchemy | 演練用 |
| 5 | **Mainnet RPC** | Alchemy | 正式用 |
| 6 | **baseURI** | IPFS metadata（`ipfs://CID/{id}.json`）| Y1 可先放暫時 URI，之後 `setURI` 改 |
| 7 | **Etherscan API key** | etherscan.io | `--verify` 用 |

> 🔒 私鑰只在你終端機輸入，**不進檔案 / git / 對話**。Deployer 與 Admin 可同一把，也可分開（分開更乾淨）。

```bash
# 設環境變數（每次開新 terminal 重設；值不寫進檔案）
export ADMIN_ADDR=0x...            # 你的 admin EOA
export GAME_OPERATOR_ADDR=0x...    # relayer 地址
export BASE_URI="ipfs://CID/{id}.json"
export SEPOLIA_RPC="https://eth-sepolia.g.alchemy.com/v2/KEY"
export MAINNET_RPC="https://eth-mainnet.g.alchemy.com/v2/KEY"
export ETHERSCAN_API_KEY=...
read -s DEPLOYER_KEY               # 互動式輸入，不留 history
```

---

## 1. Sepolia 演練（完整跑一次）

```bash
cd /Users/jsl/Documents/Claude/Projects/PIF12

# 部署 impl + proxy + initialize（一次完成）
forge script script/Deploy.s.sol \
  --rpc-url "$SEPOLIA_RPC" --private-key "$DEPLOYER_KEY" \
  --broadcast --verify

# 記下 console 印出的 proxy 地址：
export PROXY=0x...   # 「proxy (USE THIS)」那一行
```

---

## 2. 部署後驗證（read-only，不花 gas）

```bash
# 版號 = 1.0.0
cast call $PROXY "VERSION()(string)" --rpc-url "$SEPOLIA_RPC"

# issuanceEnabled 必須為 false（Y1 發星星關閉）
cast call $PROXY "issuanceEnabled()(bool)" --rpc-url "$SEPOLIA_RPC"

# 角色確認（true / true / true / true / false）
# DEFAULT_ADMIN_ROLE = 0x0000…0000
cast call $PROXY "hasRole(bytes32,address)(bool)" \
  0x0000000000000000000000000000000000000000000000000000000000000000 $ADMIN_ADDR --rpc-url "$SEPOLIA_RPC"
# UPGRADER_ROLE
cast call $PROXY "hasRole(bytes32,address)(bool)" \
  0x189ab7a9244df0848122154315af71fe140f3db0fe014031783b0946b8c9d2e3 $ADMIN_ADDR --rpc-url "$SEPOLIA_RPC"
# PAUSER_ROLE
cast call $PROXY "hasRole(bytes32,address)(bool)" \
  0x65d7a28e3265b37a6474929f336521b332c1681b933f6cb9f3376673440d862a $ADMIN_ADDR --rpc-url "$SEPOLIA_RPC"
# GAME_ROLE → relayer（不是 admin）
cast call $PROXY "hasRole(bytes32,address)(bool)" \
  0x6a64baf327d646d1bca72653e2a075d15fd6ac6d8cbd7f6ee03fc55875e0fa88 $GAME_OPERATOR_ADDR --rpc-url "$SEPOLIA_RPC"
# 反向確認：GAME_ROLE 不能是 admin 那把（應為 false）
cast call $PROXY "hasRole(bytes32,address)(bool)" \
  0x6a64baf327d646d1bca72653e2a075d15fd6ac6d8cbd7f6ee03fc55875e0fa88 $ADMIN_ADDR --rpc-url "$SEPOLIA_RPC"
```

✅ 預期：`VERSION=1.0.0`、`issuanceEnabled=false`、admin 三個 role 都 true、GAME_ROLE 只在 relayer。

---

## 3. 開馬年領取窗口（admin EOA 簽）

```bash
# 算 deadline 時間戳：馬年「農曆」年底 ≈ 2027 春節前一天（2027-02-05）
DEADLINE=$(date -j -f "%Y-%m-%d" "2027-02-06" "+%s")
START=$(date "+%s")    # 現在起即開放（或填國曆 2026 起點）

# setYearWindow(yearNumber=1 馬, startTime, mintDeadline) — admin 簽
cast send $PROXY "setYearWindow(uint8,uint256,uint256)" 1 $START $DEADLINE \
  --rpc-url "$SEPOLIA_RPC" --private-key "$ADMIN_KEY"

# 驗證已開
cast call $PROXY "isYearOpen(uint8)(bool)" 1 --rpc-url "$SEPOLIA_RPC"   # → true
```

---

## 4. 試鑄演練（relayer 簽，鑄給丟棄地址）

```bash
# 用 relayer 鑰匙鑄一枚馬年 token 給隨手生成的測試地址
TEST_ADDR=$(cast wallet new | grep Address | awk '{print $2}')
cast send $PROXY "mintCuratorToken(address,uint8)" $TEST_ADDR 1 \
  --rpc-url "$SEPOLIA_RPC" --private-key "$RELAYER_KEY"

# 確認到帳
cast call $PROXY "balanceOf(address,uint256)(uint256)" $TEST_ADDR 1 --rpc-url "$SEPOLIA_RPC"  # → 1
cast call $PROXY "isCurator(address)(bool)" $TEST_ADDR --rpc-url "$SEPOLIA_RPC"               # → true
# 重鑄應 revert（一人一枚）
cast send $PROXY "mintCuratorToken(address,uint8)" $TEST_ADDR 1 \
  --rpc-url "$SEPOLIA_RPC" --private-key "$RELAYER_KEY"   # → revert AlreadyCurator
```

✅ 這一步同時驗證了 claim 網站後端會走的那條路（relayer 代鑄）。

---

## 5. 串接 claim 網站（Sepolia 端對端）

1. Worker `wrangler.toml`：`CONTRACT_ADDRESS=$PROXY`、`CHAIN_ID=11155111`。
2. Worker secrets：`RELAYER_PRIVATE_KEY` / `RPC_URL`(Sepolia) / `PRIVY_APP_ID` / `ADMIN_TOKEN`。
3. 後台產生一條連結 → 手機/無痕開 → Privy 登入 → 領取 → 確認收據卡 + Etherscan。
4. 測三語、單人 + 群組、各種出錯（連結已用 / 已過期 / 已領過）。

---

## 6. 主網部署（W3 · 6/19–21）

與 Sepolia **完全相同**，差別只有：
- `--rpc-url "$MAINNET_RPC"`、deployer 用主網有 ETH 的錢包。
- relayer 主網地址先充 ~0.05 ETH gas。
- 部署後**立刻**記錄地址（下方第 7 步）。
- `setYearWindow` 用真實窗口；`issuanceEnabled` **維持 false**。

> 🛟 **安全網**：若 claim 網站 W3 沒完工，6/21 可直接用第 4 步的 `mintCuratorToken`（relayer 經 cast / Etherscan「Write Contract」）**手動發第一批小太陽**。deadline 不靠網站綁死。

---

## 7. 記錄地址（部署後立刻）

填進兩個地方：
- `docs/PIF12_Rolling_Roadmap.md` 的「地址紀錄簿」附錄（公開可放合約地址）。
- 你本機的**鑰匙地圖**（私鑰/seed 位置——絕不進 repo）。

```
Implementation : 0x...
Proxy（主合約）: 0x...   ← 對外公布、Etherscan verify、claim 網站用這個
Admin EOA      : 0x...
Relayer        : 0x...
部署 tx        : 0x...
```

---

## 8. 完成判準（Definition of Done）

- [ ] Sepolia 全流程跑通（部署 → 驗證 → setYearWindow → 試鑄 → 網站端對端 → 三語/出錯）
- [ ] 主網部署 + Etherscan verify + 8 項 role/flag 驗證全綠
- [ ] `issuanceEnabled = false` 二次確認
- [ ] 安全網演練過（手動 mint 可行）
- [ ] 地址記錄完成（公開簿 + 私人鑰匙地圖）
- [ ] `git tag v1.0.0`（部署後，需 Jason 同意 push）
