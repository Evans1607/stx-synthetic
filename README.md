# STX Synthetic Assets Protocol

A Clarity smart contract implementation for minting and managing synthetic assets backed by STX collateral with dynamic price feeds, liquidation mechanisms, and advanced risk management.

## Features

### Core Functionality
- 🏦 STX-backed synthetic asset minting
- 📈 Oracle-driven price feeds
- 💰 Configurable collateral ratios
- 🔄 Liquidation system for undercollateralized positions
- 💸 Fee collection (0.50% default)
- ⏸️ Emergency pause functionality

### Risk Management
- Minimum 100% collateralization requirement
- Dynamic price updates via trusted oracle
- Liquidation mechanism for undercollateralized positions
- Configurable fee structure
- Emergency pause mechanism

## Contract Interface

### Administrative Functions
```clarity
(set-owner (new-owner principal))
(set-oracle (new-oracle principal))
(pause-unpause (flag bool))
(set-fee-bps (new-fee uint))
(withdraw-treasury (to principal) (amount uint))
```

### Asset Management
```clarity
(create-asset (symbol (string-ascii 8)) (collateral-ratio uint) (initial-price uint))
(update-collateral-ratio (symbol (string-ascii 8)) (new-ratio uint))
(update-price (symbol (string-ascii 8)) (new-price uint))
```

### User Operations
```clarity
(mint (symbol (string-ascii 8)) (amount uint) (token-contract <token-trait>))
(redeem (symbol (string-ascii 8)) (amount uint) (token-contract <token-trait>))
(liquidate (user principal) (symbol (string-ascii 8)) (token-contract <token-trait>))
```

### Read-Only Functions
```clarity
(get-asset-info (symbol (string-ascii 8)))
(get-user-position (user principal) (symbol (string-ascii 8)))
(get-collateralization-ratio (user principal) (symbol (string-ascii 8)))
(get-treasury)
(is-paused)
(get-fee-bps)
(get-owner)
(get-oracle)
```

## Error Codes

| Code | Description |
|------|-------------|
| `u100` | Not owner |
| `u101` | Not oracle |
| `u102` | Asset exists |
| `u103` | Asset not found |
| `u104` | Insufficient collateral |
| `u105` | Insufficient balance |
| `u106` | Invalid amount |
| `u107` | Price not set |
| `u108` | Contract paused |
| `u109` | Not undercollateralized |
| `u110` | Token contract not set |



### Testing
```bash
# Run tests
clarinet test

# Check contract
clarinet check
```

### Deployment
1. Configure `Testnet.toml` or `Mainnet.toml`
2. Set initial owner address
3. Deploy contract
4. Configure oracle address
5. Create initial synthetic assets

## Security

- Access control for administrative functions
- Emergency pause mechanism
- Protected price feeds
- Safeguards against common vulnerabilities
- Comprehensive error handling

