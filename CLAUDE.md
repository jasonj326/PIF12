# CLAUDE.md — PIF12 AI 協作指南

> 本文件定義 Jason 與 Claude 的共同工作規範。

## 專案概述

PIF12 (Pay It Forward — 12-Year Legacy) 是一個部署在 Base 鏈上的 12 年 Web3 社會實驗。
核心機制：SBT（ERC-1155）、Karma Ledger、Social Recovery、Gasless Transactions。
架構：UUPS Upgradeable Proxy + Safe 多簽 (2-of-3)。

## Repo 結構

```
contracts/   → 智能合約 (.sol)
docs/        → 文件（Whitepaper、Audit、Roadmap、Strategy、Deploy Guide）
website/     → Landing Page HTML、Claim Website 計畫
assets/      → 圖檔（壓縮版，原始大檔不入 Git）
marketing/   → Pitch Deck、策略文件
scripts/     → 部署與操作腳本
metadata/    → Token metadata JSON
```

## 安全規範

### 絕對禁止
- 不在對話或檔案中輸入/儲存私鑰、助記詞、seed phrase
- 不記錄「某人 = 0x地址」的對應關係
- 不未經 Jason 確認就執行鏈上交易
- 不把 .env、密鑰檔推上 Git

### 需要 Jason 明確確認
- 部署合約到主網
- 修改 .sol 合約邏輯
- git push 到 GitHub（尤其是 main branch）
- 上傳任何內容到 IPFS（不可逆）
- 修改 Safe 角色設定
- 建立或關閉 GitHub Issues/PR

### 可以自主執行
- 讀取/分析程式碼
- 修改前端 HTML/CSS/JS（本地）
- 整理檔案、目錄結構（本地）
- 撰寫文件、文案
- 在測試網測試（Base Sepolia）
- 建立/更新本地 Git commits

## 語言與風格

- 與 Jason 溝通使用繁體中文
- 程式碼註解使用英文
- 文件可雙語（視受眾而定）
- commit message 使用英文

## 常用指令備忘

```bash
# Git 基本流
git status
git add <file>
git commit -m "message"
git push origin main

# GitHub CLI
gh repo view
gh pr list
gh issue list

# 合約相關
# 部署: 透過 Remix + MetaMask (非 CLI)
# mint: 透過 Safe Transaction Builder 或 Basescan
```

## 關鍵連結

- GitHub Repo: https://github.com/jasonj326/PIF12
- 個人網站 Repo: https://github.com/jasonj326/jasonj326
- Landing Page: https://jasonjlai.net/main-quest/PIF12/
- Base Mainnet Explorer: https://basescan.org
- Safe: https://app.safe.global
