# Legacy contracts — design iterations (do not deploy)

These are **superseded** design iterations kept for history. The shipping
contract is [`../PIF12Nexus.sol`](../PIF12Nexus.sol) (v1.0.0).

| File | Iteration | Why retired |
|------|-----------|-------------|
| `PIF12.sol` | V6 (2026-04) | Karma numeric model; pre-Curator-Network; targeted Base. |
| `Neo-PIF.sol` | V7 (2026-05) | Intermediate redesign; superseded by the V8 → v1.0.0 rewrite (unique-people counting, Curator Network, GPL, EIP-170 custom errors). |

They are excluded from compilation (`skip` in `foundry.toml`) and are **not**
audited, tested, or maintained. Reference only.
