# PIF12: Pay It Forward — A 12-Year On-Chain Social Experiment

**「PIF12：善的循環 — 十二年鏈上社會實驗」**

---

## Executive Summary

PIF12 is a Web3 social experiment launched on the Base blockchain. It transforms the ancient Eastern ritual of blessing charms (Omamori — 御守) into annual non-transferable digital tokens that connect brilliant people across the globe for 12 years.

This is not a cryptocurrency project. There is no token sale, no speculation, and no financial incentives. Instead, PIF12 builds a **constellation of trust** — a community of 12 core members who each year receive a new soulbound token (SBT) representing their membership in an evolving social contract. The project is created and led by Jason J. Lai.

The simple idea: if you commit to an annual gathering and earn trust within a community, you become eligible for recovery support in personal crisis. Simultaneously, you join a 12-year experiment in decentralized coordination that may evolve into a global "Republic Labs" — a network of trusted humans bound by shared values, not shared tokens.

**Our north star:** *Every act of kindness is a star. Together, we are drawing a constellation.*

---

## 1. Vision & Philosophy

### The Problem We Address

Modern society struggles with loneliness despite constant digital connection. Web3 promises decentralization but often defaults to financialization — turning everything into a transaction. We believe there's a third way: **technology in service of authentic human relationship**.

PIF12 asks: What if we used blockchain not for wealth redistribution, but for **trust codification**? What if the rarest asset — membership in a genuine community — became the foundation of mutual aid?

### The Omamori Concept

An Omamori (御守) is a Japanese charm believed to bring blessings, protection, or good fortune. Traditionally purchased at shrines, each charm represents an intention — a prayer for health, love, or wisdom.

PIF12 reimagines this ritual for the digital age. Each year, members receive a new Omamori — a soulbound token that:
- Cannot be bought, sold, or transferred
- Proves membership in a verified community
- Entitles you to social recovery support in personal hardship
- Represents one year of the 12-year commitment

This token is **proof of presence**, not proof of wealth.

### The 12-Year Commitment

Why 12 years? This duration aligns with:
- The Asian zodiac cycle (12 animal years)
- Historical significance in relationship-building research
- The time needed to form genuine, decentralized institutions
- A human lifetime milestone (a child becomes an adult)

After 12 years, the experiment concludes. Members will have earned:
- 12 distinct annual Omamori tokens
- Deep relationships with 11 other core members
- A proven track record of community governance
- A blueprint for decentralized social coordination

Then comes the real test: Can this constellation become self-governing without its founder?

---

## 2. Core Commitments (明示承諾)

### Annual Omamori Token

Every January, a new soulbound token is minted on the Base blockchain. The token ID increments with each year (Year 1, Year 2, etc.), but all exist within a single ERC-1155 smart contract. The first Omamori (2026) represents the "Year of the Horse" — a symbolic start to this 12-year cycle.

**Key properties:**
- **Non-transferable:** Cannot be sold, gifted, or lost. Only you can hold your own Omamori.
- **Verifiable:** Every token can be audited on the blockchain.
- **Annual:** A new token is minted each January, requiring active participation to claim.
- **Designed by community:** From Year 2 onward, members help design the visual appearance and narrative of each year's Omamori.

### Physical Gathering (年次集合)

At minimum, one annual in-person event brings core members together. This is non-negotiable. A social experiment with no humans in the same room is not a social experiment.

These gatherings serve multiple purposes:
- **Trust-building:** Meeting in person creates bonds that digital communication cannot replicate.
- **Karma settlement:** Major life updates and mutual support are discussed face-to-face.
- **Collective decision-making:** Major project decisions are made by consensus among present members.
- **Ritual:** The gathering itself becomes part of the collective memory, strengthening the community's identity.

Location rotates among members' home regions. By Year 12, members will have traveled to diverse parts of the world, expanding their perspective and network.

### Open Source & Transparency

All smart contract code is published under the MIT license on GitHub:
**https://github.com/jasonj326/PIF12/**

This ensures:
- **Auditability:** Any developer can inspect the code for security or fairness.
- **Permanence:** The code exists in the public domain. No legal threats can erase it.
- **Composability:** Future projects can fork or build upon PIF12's architecture.
- **Trust:** We have nothing to hide.

The smart contracts have been audited. Any findings and remediations are public.

### Community First, Speculation Never

PIF12 will never:
- Conduct an ICO or token sale
- Create investor classes or governance token holders
- Promise financial returns
- Speculate on token price or market value
- Offer referral bonuses or monetary incentives
- Sell user data

The Omamori tokens have **zero commercial value by design**. They cannot be listed on exchanges. Their only value is social: membership in a community of trusted humans.

This radical commitment to non-financial coordination is PIF12's defining feature.

---

## 3. Technical Architecture

### Blockchain & Infrastructure

**Chain:** Base (Ethereum Layer 2)
- **Why Base?** Low transaction costs, high security through Ethereum's settlement layer, growing ecosystem aligned with Coinbase's vision of accessible crypto.
- **Finality:** Transactions are final within minutes, suitable for both financial and social applications.

### Smart Contract Design

**ERC-1155 Token Standard:**
The smart contract uses ERC-1155, which allows a single contract to manage multiple token types. Each year's Omamori is a different token ID:
- Token ID 1 = Year 1 (2026) Omamori
- Token ID 2 = Year 2 (2027) Omamori
- etc.

This design is more efficient than deploying separate contracts each year and creates a unified "collector's experience" for members.

**UUPS Upgradeable Proxy:**
The contract uses the Universal Upgradeable Proxy Standard (UUPS), allowing future improvements without migration or loss of token history. All upgrades require a timelock mechanism — changes are announced 48 hours before execution, giving community time to respond.

**Non-Transferability:**
Omamori tokens are **soulbound** — they cannot be transferred, sold, or burned. Each member's wallet holds the tokens they earned. If a member leaves the project, they retain their historical Omamori as proof of their participation.

### Karma Ledger (道徳台帳)

The Karma Ledger is an on-chain integer (ranging from -100,000 to +100,000) tracking each member's moral credit and debt within the community.

**How Karma Works:**

Members earn positive karma by:
- Mentoring other community members
- Organizing social events or content
- Performing acts of radical transparency
- Contributing knowledge, art, or labor

Members incur negative karma by:
- Breaking community commitments
- Violating trust
- Acting deceptively

Karma is **not a punishment system** — it's a ledger of generosity. A member with -50,000 karma may have experienced hardship and received massive support; a member with +50,000 karma has given freely. Neither is "better."

**The Reincarnation Tax:**
To prevent karma from becoming a status game, every year it resets partially. This ensures that past generosity doesn't create permanent hierarchies and that redemption is always possible.

**Why Non-Zero-Sum?**
Traditional games have winners and losers. Karma in PIF12 is designed so that **collective generosity increases the total karma in the system**. One member helping three others creates +3 karma (not -1). This shifts the game from competition to cooperation.

### Social Recovery Mechanism (社會復興)

Imagine your laptop is stolen, and your Ethereum seed phrase goes with it. In traditional finance, you might lose everything. In Web3, most people resort to using centralized custodians (defeating the purpose of decentralization).

PIF12 offers a third option: **human-based recovery**.

**How it works:**
1. Each member designates two "Guardians" from within the community.
2. If you lose access to your wallet, you can initiate a recovery request.
3. Both Guardians must approve and sign a recovery authorization.
4. After a 7-day timelock, the recovery is executed, and a new wallet is authorized.
5. The old wallet's admin access is revoked, but the token history remains.

**Why this matters:**
- **Decentralized:** No single company or third party controls recovery.
- **Human:** Guardians are people you know and trust, not algorithms.
- **Safe:** The timelock ensures attackers can't instantaneously drain accounts.
- **Relationship-based:** Encourages genuine friendships and mutual interdependence.

**Lone Wolf Mode (狼爺モード):**
Some members may refuse the social recovery option, preferring absolute sovereignty. By enabling Lone Wolf Mode, a member permanently opts out of admin recovery. If they lose their keys, they lose their account — but no one, including Jason, can ever take it.

This escape hatch is crucial for true decentralization.

### Gasless Transactions (無料取引)

PIF12 uses ERC-2771 meta-transactions to enable gasless claims. Members don't need ETH in their wallet to claim annual Omamori. A service provider pays the gas costs; this cost is absorbed by the community's operational budget.

**Why gasless?**
- Lowers barriers to entry for international members with limited crypto experience
- Eliminates friction in annual token claiming
- Maintains Web3 security without requiring each member to be a gas expert

---

## 4. Three-Year Rolling Roadmap (2026–2028)

### Year 1 (2026) — Genesis 🐴

**Q1 2026: Smart Contract Deployment**
- Deploy PIF12 contract on Base mainnet
- Complete security audit; publish audit report publicly
- Set up governance structure and emergency pause mechanism

**Q2 2026: Community Formation**
- Mint first "Year of the Horse" Omamori (Token ID: 1)
- Distribute to 12 core founding members
- Announce community membership publicly; invite broader participation in future years
- Launch claimer website (WalletConnect + Privy integration for seamless onboarding)

**Q3 2026: First Gathering**
- Host inaugural in-person gathering (location TBD, likely Southeast Asia or North America)
- Establish annual gathering cadence and rotating location model
- Formalize Guardian pairings and recovery settings

**Q4 2026: Foundation**
- Deploy Karma Ledger and begin tracking community interactions
- Create transparency reports on contract activity
- Publish Year 1 retrospective and learnings

### Year 2 (2027) — Growth 🐍

**Q1 2027: Token Generation**
- Mint Year 2 Omamori (Token ID: 2)
- Implement gasless claiming for all returning members

**Q2 2027: Karma dApp Launch**
- Launch interactive dApp showing member Karma scores and contributions
- Enable on-chain logging of community activities (mentoring, events, contributions)
- Begin co-design process for Year 3 Omamori visual design

**Q3 2027: Organic Expansion**
- Accept 3–4 new members into the core circle (raising from 12 to 15–16)
- Host second annual gathering; rotate to new geographic region
- Publish detailed governance documentation

**Q4 2027: Maturation**
- Evaluate contract stability and performance
- Publish Year 2 impact report and audit updates

### Year 3 (2028) — Maturity ⭐

**Q1 2028: Token Generation**
- Mint Year 3 Omamori (Token ID: 3)
- Reflect on lessons from first three years

**Q2 2028: Social Recovery Activation**
- Deploy full Social Recovery feature
- Conduct live recovery drills (simulated scenarios to test process)

**Q3 2028: Governance Evolution**
- Launch formal co-governance structure
- Establish decision-making process for Years 4–12
- Host third annual gathering with expanded international cohort

**Q4 2028: Legacy Planning**
- Begin succession planning for community leadership
- Document "Republic Labs" governance model
- Publish long-term vision for decentralization

---

## 5. The 12-Year Vision (2026–2037)

### Phases of the Constellation

#### Phase 1: Foundation & Trust (Years 1–3)
- A small circle of 12–16 brilliant humans form deep bonds.
- The Omamori ritual becomes sacred within the community.
- Social recovery is tested and proven reliable.
- The annual gathering becomes a highlight of each member's year.

#### Phase 2: Organic Growth (Years 4–6)
- Karma deepens as the community shares more lived experience.
- Members begin public speaking and writing about PIF12.
- Spin-off projects emerge from members' collaborations.
- The network expands to 20–25 core members.

#### Phase 3: Community Governance (Years 7–9)
- Formal governance structures emerge, designed and voted on by members.
- Decisions about changes to the contract are made by consensus.
- New members are admitted only with 90% community approval.
- The annual gathering alternates between regions, with planning led by local members.

#### Phase 4: Legacy & Completion (Years 10–12)
- Members reflect on their 12-year journey together.
- A decision point: Does the project continue indefinitely, or does it conclude as planned?
- If concluded, the final Omamori (Year 12) becomes the capstone.
- A "Graduation" gathering celebrates the completion of the cycle.

### The Vision: From Experiment to Institution

By Year 12, PIF12 will have demonstrated that:
- **Decentralized trust is possible.** A community of 20–30 humans can self-govern without CEO or board.
- **Technology serves humans.** Blockchain can encode relationships, not just transactions.
- **Beauty is in simplicity.** One rule (annual commitment), one token, one gathering, one community.

This model — "Republic Labs" — can then be:
- **Replicated:** Other founders can launch their own 12-year cycles with different values.
- **Connected:** Multiple Republic Labs can interoperate, creating a global network of trusted communities.
- **Evolved:** Technology and governance improve with each iteration.

The dream: In 2050, humans say, "I'm part of a Republic Lab" the way we say "I'm part of a family" today.

---

## 6. Game Theory & Economics

### Why Karma Is Non-Zero-Sum

In traditional economic models, wealth is zero-sum: your gain is my loss. This creates competition and hoarding.

Karma in PIF12 is explicitly non-zero-sum. When you mentor a member, both your karma and theirs increase. The total system karma grows. This aligns incentives toward cooperation.

**The Reincarnation Tax:** To prevent permanent inequality, each member's karma resets by 20% every year. This means:
- A member who gave generously (high positive karma) resets but retains most of their "generous" status.
- A member who struggled (negative karma) gets a fresh start — redemption is always possible.
- No one becomes an untouchable saint; no one is permanently shamed.

### Why Soulbound Tokens Matter

**Transferable tokens** (like traditional cryptocurrencies) create speculation. If an Omamori could be bought and sold, wealthy people would buy all the Year 1 tokens, reducing them to luxury collectibles.

**Soulbound tokens** encode identity, not wealth. Your Omamori proves you *were here, you showed up, you're part of us*. This cannot be purchased. It can only be earned.

This is why artists, writers, and creators love soulbounds — they represent genuine achievement, not cash.

### Why Social Recovery Replaces Seed Phrases

Asking humans to memorize 12-word seed phrases and store them safely is a failure of design. It's asking users to be security experts.

Social recovery acknowledges reality: **humans are better at remembering faces and relationships than random words.**

By encoding recovery in trusted relationships, we:
- Lower the barrier to genuine decentralization
- Create mutual interdependence (which strengthens communities)
- Admit that humans need humans

### The Economics of No Economics

PIF12 has zero tokenomics, no token sale, and no venture capital funding. How is it funded?

**Year 1–2:** Jason covers basic costs (domain, smart contract deployment, gatherings).

**Year 3+:** The community collectively funds operations through voluntary contributions. A member who benefits might contribute $500/year; another might contribute $5. Contributions are logged on-chain (via Karma Ledger) but are never mandatory.

This creates a **Gift Economy** — like open-source software. People contribute because they believe in the mission, not for profit.

---

## 7. Safety, Trust & Decentralization

### Smart Contract Audit

PIF12's smart contract has been professionally audited for security vulnerabilities. The audit report is publicly available, including any findings and how they were remediated.

### Emergency Pause Mechanism

If a critical vulnerability is discovered, the contract can be paused, freezing all transactions until a fix is deployed. This power rests with the Guardian multisig (at least 6 of 12 core members).

### Admin Safeguard & Lone Wolf Escape Hatch

Jason, the founder, has admin privileges to manage the contract. However:
- All admin actions are **time-locked** (announced 48 hours before execution).
- Any member can opt into **Lone Wolf Mode**, permanently revoking admin authority over their wallet.
- Eventually (by Year 7), a formal vote can **revoke all admin privileges entirely**, making the contract fully community-governed.

This gradual decentralization ensures early stability while enabling long-term sovereignty.

### Transparency Reports

Every quarter, a transparency report is published:
- Number of members and transactions
- Total Karma ledger state
- Changes to the contract or governance
- Any incidents or disputes and how they were resolved

---

## 8. Membership & Participation

### Who Is Eligible?

Year 1 (2026) is reserved for 12 core founding members, personally invited by Jason. These are humans he knows and trusts deeply.

From Year 2 onward, new members may be admitted with community approval (90% vote threshold). Candidates must:
- Demonstrate alignment with PIF12 values
- Commit to annual gathering attendance
- Consent to social recovery participation
- Be nominated by an existing member

### What Does Membership Mean?

Membership is a **12-year commitment** to:
- Attend at least one annual gathering (or send a compelling explanation)
- Contribute to community decisions and governance
- Practice radical transparency and honesty
- Support other members in hardship (via social recovery or mentorship)

In return, you receive:
- An annual Omamori token (non-transferable, priceless proof of membership)
- Access to a global network of brilliant, trusted humans
- Social recovery support in personal crisis
- A role in evolving decentralized governance

### Resignation & Departure

Members may resign at any time. Upon resignation:
- They retain all historical Omamori (proof of past membership).
- They are removed from the Karma Ledger and social recovery duties.
- They remain part of the community's story forever.

---

## 9. Values & Ethos

### The PIF12 Principles

1. **Transparency First:** If it's not public, it didn't happen. Secrets rot trust.
2. **Humans Over Tech:** Technology exists to serve relationships, not replace them.
3. **Long-term Thinking:** 12 years is our planning horizon. Quarterly earnings are meaningless.
4. **Radical Generosity:** When in doubt, give. The Reincarnation Tax ensures we never run out.
5. **Decentralization Always:** Power flows from the community, never consolidated in one person.
6. **Beauty in Simplicity:** One gathering, one token, one commitment per year. No byzantine rules.

### The Omamori Spirit

An Omamori is more than a token. It's a blessing, a promise, a reminder. It says:
- *I see you.*
- *I trust you.*
- *We are in this together.*
- *For the next 12 years, your struggles are mine; mine are yours.*

This is what PIF12 builds.

---

## 10. Call to Action

### For the Curious

Visit the GitHub repository to read the smart contract code:
**https://github.com/jasonj326/PIF12/**

Join the community conversations. Follow for announcements of the first gathering.

### For the Committed

If you are a founder, artist, writer, thinker, or changemaker who believes in this vision, watch for opportunities to join in Year 2 or beyond. New members are admitted with community consent.

### For the Builders

If you want to launch your own 12-year community or build on PIF12's architecture, the MIT license makes it yours to fork, modify, and evolve.

---

## Closing: The Constellation

The Chinese concept of 善的循環 — "the cycle of goodness" — is central to PIF12. Each act of kindness creates a ripple that strengthens the community. These ripples, overlapping across 12 years, create a constellation.

A constellation is not a single star. It's a pattern of many stars, each shining uniquely, each essential to the whole.

PIF12 is our attempt to draw that constellation on-chain. To prove that humans can coordinate around shared values, not shared profit. To show that decentralization is not a tech problem — it's a relationship problem.

And relationship problems, we believe, have human solutions.

---

**Every act of kindness is a star. Together, we are drawing a constellation.**

---

## Technical References

- **GitHub Repository:** https://github.com/jasonj326/PIF12/
- **Blockchain:** Base (Ethereum Layer 2)
- **Token Standard:** ERC-1155 (with non-transferability)
- **Upgrade Pattern:** UUPS Upgradeable Proxy
- **Meta-Transaction Standard:** ERC-2771
- **License:** MIT

---

**Document Version:** 1.0
**Date:** April 2026
**Created by:** Jason J. Lai
**Community Edited by:** PIF12 Core Members

*This whitepaper is a living document. Corrections and improvements are welcome via GitHub issues or community discussions.*
