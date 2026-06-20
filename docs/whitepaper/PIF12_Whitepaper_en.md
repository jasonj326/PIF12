# PIF12 Whitepaper — Pay It Forward, On-Chain

### A 12-Year On-Chain Experiment in Gratitude

> 📝 **DRAFT — 2026-05-31 · v1.0.0 (`PIF12Nexus`)**
> Drafted with the Forge (Claude Code) session for Jason J. Lai's review. Wording is a draft; the project and its intent are Jason's.

> **Version note.** This is the **v1.0.0** whitepaper, describing the deployed `PIF12Nexus` contract on **Ethereum**. An earlier design draft is archived under [`docs/whitepaper/archive/`](./archive/).

---

## Executive Summary

**PIF12** (Pay It Forward — 12-Year Legacy) is a twelve-year on-chain experiment in trust and gratitude, deployed on **Ethereum**. Each year, for twelve years, a non-transferable token — shaped after the Japanese *omamori* (御守) — marks a growing circle of people who choose to show up for one another.

PIF12 v1.0.0 makes one decisive design choice: **there is no score.** What remains is the simplest possible record of human connection:

- **how many *distinct* people you have helped**, and
- **how many *distinct* people have helped you.**

Counting *people*, not points — and not even events — removes the leaderboard, removes the gameability, and leaves only what matters: *did you actually show up for someone, and did someone show up for you.*

Around this core sit five quiet systems: **Soulbound** identity, a federated **Curator Network**, **co-attested mutual aid**, three-mode **social recovery**, and **gasless** participation so that no one needs to understand a wallet to receive a gift. All five are built into the deployed contract; they activate in phases — Year 1 (2026) is the claim year, and the Curator Network's Star layer switches on from Year 2 (2027) (see §14).

> **North Star.** *Every act of kindness is a star. Together, we are drawing a constellation that will light up the dark.* PIF12 is a **North Star, not a sun** — it gives **direction**, not heat. It is meant to be small, to record gratitude, and to be a little bit of fun. If partners join and the constellation grows, all the better.

---

## 1. Philosophy: What Pay-It-Forward Actually Means

Pay-It-Forward is not an economy and not a scoreboard. It is a chain reaction:

1. Someone helps you, expecting nothing back.
2. You accumulate a felt sense of being *held* by a community.
3. That experience moves you to help someone else.
4. The chain continues — not as transactions, but as ripples.

A faithful on-chain record of this should therefore:

- **count the people**, because connection is measured in faces, not figures;
- **not turn giving into a competition**, because giving should be intrinsic;
- **stay simple**, because the moment it becomes a game, it stops being a gift.

PIF12 v1.0.0 is the most honest expression of this the project has reached: **record gratitude, keep it simple, make it fun.**

---

## 2. The Omamori (御守)

For years, Jason kept a quiet ritual — sending blessings to people he cared about around Lunar New Year. PIF12 brings that ritual on-chain.

The form is borrowed from Japan's *omamori* — small temple charms holding a hand-written wish. PIF12 is not religious; it only borrows the spirit of the gesture: something small, deliberate, and *yours*. Each year, one token is minted as a Soulbound Token and given to those willing to walk the twelve-year journey. You can't buy it. You can't transfer it. **Its only value is that you actually came.**

A first circle starts the constellation — open to everyone whose path has crossed ours, with no cap on its size. From Year 2 (2027), as **Lightkeepers** carry the spirit forward, each one lights up another **Star**, and the constellation keeps growing.

---

## 3. Architecture at a Glance

`PIF12Nexus` is a single Solidity contract that stitches five systems into one ERC-1155.

| Layer | Choice | Why |
| :--- | :--- | :--- |
| **Chain** | Ethereum L1 | 12-year permanence (see §10) |
| **Token** | ERC-1155, Soulbound | Multi-token identity; non-transferable |
| **Upgradeability** | UUPS proxy | The 12-year experiment must be able to evolve |
| **Gasless** | ERC-2771 + Paymaster | Aim: members avoid gas (best-effort; relay claim in Year 1, Paymaster meta-tx from Year 2) |
| **License** | GPL-3.0-or-later | Copyleft: pay the openness forward (§9) |
| **Dependencies** | OpenZeppelin Upgradeable v5 | Audited, standard primitives |

Token id scheme:

- **ids 1–12** — the zodiac-year tokens (one shared id per year; supply equals the number of Lightkeepers inducted that year). Id 1 = Year of the Horse (2026) … id 12 = Year of the Snake (2037).
- **ids 100+** — Personal "Star" tokens, each a unique id with supply 1 (first issued from Year 2, 2027).

---

## 4. The Curator Network (Lightkeeper → Star)

PIF12 v1.0.0 replaces the original single-issuer model with a **federated Curator Network**: a circle of core members, each of whom may in turn invite their own.

The full network is built into the deployed contract, but it unfolds in phases: Year 1 (2026, Horse) is the claim year — Layer 1 only, open to an unlimited number of claimants; Layer-2 Star issuance activates from Year 2 (2027, Goat).

```
            發起人 Jason (Initiator)
                     │  mints a zodiac-year token
                     ▼
      Layer 1 — Lightkeeper (小太陽)   ← core members, the year's circle
                     │  issues a Star to people they admire
                     ▼
      Layer 2 — Star (星星)            ← the people a Lightkeeper lights up
                     ⊘ two-layer stop — Stars cannot sub-issue
```

- **The Initiator** mints a zodiac-year token to a **Lightkeeper** (the code's neutral term is *Curator*). This is done by an operational relay so the recipient never signs a transaction — they simply claim.
- **Each Lightkeeper** may — from Year 2 (2027), when issuance is switched on — gaslessly issue up to **50 Stars** to people they admire, attaching a custom image and a short message of appreciation (the message lives in the event log, never in storage — the front-end is the moderation layer).
- **The network stops at two layers.** A Star does not become a Lightkeeper; it cannot sub-issue. Trust radiates one hop, deliberately.
- **Time-bound, grace-protected.** A Lightkeeper can only be *inducted* within their zodiac year's window, but their right to issue Stars stays open until `max(year deadline, induction + 100 days)` — so someone inducted late in the year is never starved of time to curate. One honest consequence: because Star issuance is gated off throughout Year 1 (see §14), this window applies in practice from the Year-2 (2027) cohort onward. Year-1 members participate as holders of the Horse-year token; **Star issuance begins with the Year-2 cohort.**
- **Soft exclusion without confiscation.** If a member drifts from the spirit, the contract admin (the founder's wallet in the early years; a multisig from Year 3 — see §12) can `revokeCurator` — blocking *future* issuance while leaving their token and the Stars they already lit untouched. No token is ever seized. More often, exclusion is simply organic: the community withholds help, and `peopleHelpedBy` quietly stays low. There is no scarlet letter.

A single `issuanceEnabled` flag gates Layer-2 issuance — deployed off and kept off through Year 1 (2026: Lightkeepers claim), flipped on by the contract admin in Year 2 (2027) when the Star experience goes live. A feature already written, activated by a flag rather than a risky upgrade.

**Transparency: the Initiator is also a Lightkeeper.** Jason holds a year token and takes part as a member of the circle — the origin point, not a tier above it.

---

## 5. The Core Metric: Unique-People Counting

This is the heart of v1.0.0, and the cleanest the project has ever been.

Every member's profile is two numbers:

```
peopleHelped[a]    — how many DISTINCT people `a` has helped
peopleHelpedBy[a]  — how many DISTINCT people have helped `a`
```

That's it. No value, no cap, no cooldown, no score.

**Why count people, not events.** Helping the same person a hundred times still counts as **one**. To move a counter you need *another distinct person* to take part. Inflating it therefore requires recruiting many distinct, consenting members — so the cost of gaming scales with the size of a real social graph, not with the number of transactions. Sybil resistance falls out of the design for free.

**Why `peopleHelpedBy` is the truer signal.** `peopleHelped` is something you control — you can always go help others. `peopleHelpedBy` is conferred by *others*: it can only rise when distinct people *choose* to help you and you both confirm it. It is the community's collective, un-self-claimable judgment of who it has chosen to embrace. That makes it the natural measure of standing — and, gently, the natural mechanism of inclusion: a member out of step with the spirit simply does not accumulate it.

---

## 6. Mutual Aid: Co-Attestation

How does the contract *know* one person helped another? It requires both of them.

```
Step 1   giver   → recordHelp(recipient)        // creates a pending record; nothing counts yet
Step 2   recipient → confirmHelp(id, memo)       // recipient confirms, optionally with a thank-you note
```

On the **first** confirmed help for a given (giver, recipient) pair — and only the first — `peopleHelped[giver]` and `peopleHelpedBy[recipient]` each rise by one. Repeat help between the same pair is welcome (you can leave a fresh note), but never double-counts.

| Attack | Defense |
| :--- | :--- |
| A boosts a favored B unilaterally | B must confirm — recording ≠ counting |
| B fabricates received help | A must record first — no claim without a giver |
| Off-chain coercion ("confirm or else") | 30-day window; B can simply never confirm; record expires |
| Sybil clusters | members must hold an SBT to take part; counting *people* caps a cluster at its own size, and insular help-graphs are visible on-chain |

The optional `memo` is a free-text thank-you emitted to the event log only — never stored on-chain, never validated by the contract. The front-end decides what to render; on-chain log content is permanent and public by design.

---

## 7. Social Recovery — Three Modes, Admin by Default

Losing a wallet should not mean losing twelve years of identity. PIF12 offers three postures; the default requires no setup.

- **AdminDefault (default).** The Initiator's admin wallet — a single founder wallet in the early years, upgraded to a multisig from Year 3 (see §12) — can migrate a member's whole identity to a new wallet. Zero configuration — you are protected out of the box.
- **Guardian (opt-out).** Name two guardians, who must both already be network members. One initiates, the *other* executes, after a time-lock (48 h–30 days, extended for recently-active wallets). A briefly-compromised wallet cannot instantly lock out admin recovery, because changing your recovery mode is itself time-locked.
- **Lone Wolf (opt-out).** No one can recover you. Maximum self-sovereignty; maximum risk.

Recovery migrates everything that makes you *you*: tokens (by burn-and-mint, bypassing the soulbound lock), the two people-counters, Lightkeeper status and quota, and your recovery configuration. A 180-day cooldown on both wallets bounds any abuse.

All three modes are built into the deployed contract and live from day one; the default applies automatically with zero setup. What ships later is only the self-service interface for *switching* modes — until it does, any member who wants Guardian or Lone Wolf can simply ask the founder for help making the change.

---

## 8. Gasless — the Aim, Not a Promise

No member should *need* to understand a wallet, hold ETH, or sign a cryptic transaction to receive a gift.

- **Claiming a token** (live from Year 1, 2026) is relayed: the recipient logs in (e.g., via an embedded-wallet provider) and the operational relay mints to their address. They sign nothing on-chain.
- **Issuing a Star** (from Year 2, 2027) is a meta-transaction: the Lightkeeper signs typed data, a relayer submits it, and a **Paymaster** budget pays the gas.

The contract resolves the true actor through `_msgSender()` (ERC-2771), so a trusted forwarder can relay on anyone's behalf.

This is the **aim, not a guarantee.** A fully gas-free experience depends on the network not being congested and on the Paymaster budget holding up. The project would rather under-promise and over-deliver than commit to zero gas in every condition.

---

## 9. Licensing: Copyleft as Pay-It-Forward

PIF12 v1.0.0 is licensed **GPL-3.0-or-later** — a deliberate move from the earlier permissive plan.

The reasoning is itself thematic. A permissive licence (MIT) says "take this, do anything, even close it." A copyleft licence says "**take this, build on it, but keep it open for the next person.**" That second sentence *is* the Pay-It-Forward ethos, encoded in law. For a project whose entire identity is reciprocal generosity, the licence is part of the statement.

The contract incorporates MIT-licensed OpenZeppelin components; MIT is one-way compatible with GPL, and the original notices are retained (see `NOTICE`). This whitepaper text is CC BY-SA 4.0 — share-alike for prose, the same spirit applied to words.

---

## 10. Why Ethereum L1

PIF12 is a **twelve-year** commitment, and the chain it lives on is one of its very few near-**irreversible** decisions: the contract can be upgraded, but it cannot be moved without redeploying and migrating every token.

That single fact dominates the choice. A project whose entire thesis is *permanence* must run on the most permanent substrate available. Layer-2 networks offer cheaper gas and more momentary attention, but each is a young system carrying its own sequencer, treasury, and governance risk across a twelve-year horizon. The chain that is hottest this year may be cold in three.

So PIF12 optimizes for **survival, not hype** — credible neutrality and the highest probability of still being here in 2037. The gas cost of a low-frequency identity project (an open circle of members, each with at most a handful of on-chain actions a year) is modest and absorbed by the operational relay and, from Year 2, the Paymaster. And the narrative is, in the end, stronger: *committed to the most permanent chain, for twelve years* says more than *deployed wherever the attention was.*

This is the North Star applied to infrastructure: choose direction over heat.

---

## 11. Security Posture

PIF12 v1.0.0 ships with **internal testing and security review**. It has not yet had an external review — and the project says so plainly, everywhere it speaks.

- **48 Foundry tests**, all passing — covering deploy/init, role separation, minting, the soulbound lock, pause, the three recovery modes, the issuance gate, Star issuance, mutual-aid counting, and UUPS upgrade authorization.
- **Static analysis** with Slither.
- A real finding surfaced and fixed during this process: the contract exceeded the **EIP-170** 24 KB bytecode limit by ~2 KB; converting ~60 `require` strings to custom errors brought it comfortably under, with margin.

This posture matches the Year-1 surface, which is deliberately narrow: relay minting and the soulbound token only, with Star issuance code-gated off for the whole year. An **external security review is anchored before Star issuance is enabled in Year 2 (2027)** — a precondition, not an afterthought. Until that review is done, every external statement about PIF12 describes it as *security-reviewed*, never *audited* — a distinction the project keeps deliberately.

---

## 12. Governance Evolution (the 12-year arc)

PIF12 plans on a rolling three-year horizon: Years 1–3 below are committed; the later phases are the intended direction, re-confirmed every year (see §14).

- **Years 1–2 (Genesis — 2026 Horse / 2027 Goat).** Jason as Initiator; admin / upgrade / pause held by the founder's single wallet (a deliberately lightweight start — disclosed in §13); a narrow operational role handles minting.
- **Year 3 (2028, Monkey) and onward (Growth).** As core members emerge, admin migrates from the founder's single wallet to a multisig that includes community members — a role handover (`grantRole`, then `renounceRole`), no contract change required. Parameter changes move to off-chain governance (1 person, 1 vote — any SBT holder).
- **Years 6–8 (Maturity).** Jason steps toward a witness role; upgrade authority moves to the community.
- **Years 9–10 (Autonomy).** Upgrade authority is locked or renounced; the contract approaches immutability.
- **Years 11–12 (Legacy).** The final token (Year of the Snake) is minted; the project concludes; the contract remains as a public record.

A recorded future direction, *not* part of v1.0.0: by Years 5–6, the network may open so that more members can themselves induct others — many small suns, each with its own orbit. That is a major change to the two-layer model and is exactly what UUPS upgradeability is for. It is deliberately **not** built into v1; over-engineering Year 5 into Year 1 would only add complexity and attack surface.

---

## 13. Risks & Mitigations

**Status competition.** *Members start comparing counts.* — There is no value, no cap gap, no leaderboard; the metric is "distinct people," which reads as connection, not rank. Community norms set in Year 1 discourage treating it as a brag.

**Sybil clusters.** *A ring of members mutually "helps" to inflate counts.* — Counting people caps a ring at its own size; participation requires an SBT; insular help-graphs are visible and reviewable; `revokeCurator` blocks bad-actor issuance.

**Coercion.** *"Confirm my help, or else."* — The recipient simply never confirms; the record expires after 30 days; the public record of the attempt carries its own reputational cost.

**Chain longevity.** *Will the chain exist in 2037?* — Ethereum L1 is the highest-probability bet available; the contract notes that forks or migrations remain theoretically possible but are not planned.

**Centralization of admin power.** *The admin can migrate any default-mode member — and in Years 1–2 the admin is a single founder wallet, not yet a multisig.* — In Years 1–2, contract administration (upgrades, pause, default wallet recovery) is held by a single founder wallet — a deliberate lightweight start, disclosed here rather than discovered later. That one key can perform UUPS upgrades and instant default-mode recovery; it lives on a hardware wallet with an offline backup, and losing it would be treated as seriously as having it stolen. As core members emerge (target: Year 3, 2028), administration migrates to a community multisig; no contract change is required. Until then, any member may opt out of founder-default recovery into Guardian or Lone Wolf mode at any time, reclaiming that authority for themselves.

---

## 14. Roadmap (rolling three-year horizon)

The next three years are committed; everything beyond is direction, re-confirmed each year.

- **Year 1 (2026, Horse) — open Lightkeeper claim (target: June 21, 2026).** Deploy `PIF12Nexus` to Ethereum; anyone whose path has crossed ours claims a Year-of-the-Horse token — no cap on quantity. The year's work is the gasless claiming front-end and the landing page. Star issuance stays gated off all year.
- **Year 2 (2027, Goat) — Star issuance.** The two-layer structure begins: wire up gasless meta-transactions and the Paymaster; an **external security review** is completed before the contract admin flips `issuanceEnabled` on; Lightkeepers begin lighting up Stars (pSBTs).
- **Year 3 (2028, Monkey) — core members.** Core members emerge; admin migrates from the founder's single wallet to a community multisig — a role handover, not a contract change.
- **Years 4–12 (directional)** — one zodiac token per year; the roadmap is confirmed on a rolling three-year horizon, so later milestones stay directional: governance gradually decentralizes, and the project ultimately seeds **Republic Labs** — *res publica*, the public's matter: a self-sustaining community where members launch their own small experiments. By then, perhaps countless new PIF12s appear — a constellation of small experiments lighting up.

---

## North Star

> *Every act of kindness is a star. Together, we are drawing a constellation that will light up the dark.*

The earlier the design, the more it tried to *measure* kindness. v1.0.0 stops measuring and simply *records* it — who showed up for whom. The contract holds the record; the people hold the meaning.

The North Star does not give off heat. It gives direction.

---

**Document version:** v1.0.0 — draft, 2026-05-31
**Author:** Jason J. Lai · drafted with the Forge (Claude Code) session
**Status:** DRAFT — pending Jason's review; external security review anchored before Year-2 issuance is enabled
**Document licence:** CC BY-SA 4.0 · **Contract licence:** GPL-3.0-or-later
