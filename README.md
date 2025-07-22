# 🌐 STX Synthetic Smart Contract

The `stx-synthetic` smart contract enables decentralized creation and management of synthetic assets backed by STX collateral. Built on the [Stacks blockchain](https://www.stacks.co/) using Clarity, this protocol lets users mint, burn, and liquidate synthetic tokens pegged to real-world assets without holding the underlying tokens.

---

## ⚙️ Features

- 🪙 **Mint Synthetic Assets**: Lock STX to generate synthetic tokens representing external assets.
- 🔐 **Collateral Management**: Enforces required collateral ratios; triggers liquidation when thresholds are breached.
- 🔄 **Burn & Redeem**: Burn synthetic tokens to retrieve locked STX.
- 🧠 **Oracle Price Feed**: Pull real-time asset pricing from decentralized oracles.
- 📊 **Transparent Storage**: On-chain data structures for balances, asset metadata, and collateral positions.

---

## 📦 Project Structure


---

## 🚀 Getting Started

### Requirements

- [Clarinet](https://github.com/hirosystems/clarinet) for local development
- STX wallet (e.g. Hiro Wallet)
- Node.js and npm for testing support

### Installation

```bash
git clone https://github.com/your-username/stx-synthetic.git
cd stx-synthetic
npm install
clarinet check
clarinet test
📜 Contract Functions
Function	Description
mint-synthetic	Mints synthetic tokens using locked STX collateral
burn-synthetic	Burns synthetic tokens and unlocks STX
get-price	Fetches asset price from oracle
get-collateral	Retrieves a user’s collateral balance
liquidate	Triggers forced liquidation on undercollateralized positions
See full function signatures in contracts/stx-synthetic.clar.

🔬 Testing
Run unit tests using Clarinet:

bash
clarinet test
Mock oracle responses and edge cases are included.


🗳️ Governance via token voting

💬 DAO-based fee adjustments

📡 Enhanced oracle failover protection


🔗 Links
Stacks Docs

Clarity Reference

Clarinet CLI
