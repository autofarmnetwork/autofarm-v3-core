Autofarm V2
===========

## WHAT'S NEW in V2

### ERC4626 Tokenized Vault Standard compatibility:
- Transferable shares (for future Zap/Router implementation)
- Initial shares:token ratio is always 1-to-1

### 0% Entrance fee
- Profits are vested over a period of 6 hours

### Improved compounding
- New on-chain calculation for ideal compounding interval
- Dynamic fees: Fairer distribution of fees depending on APR.
- Ideal liquidity ratio: Calculate ideal ratio before adding liquidity

### Gas optimisations
- Use `immutable` for permanent data (saves gas like `constant`)
- Use SSTORE2 to reduce gas for reading/writing storage vars
- Reduced number of subswaps: Swap altogether to one of the tokens (e.g. WBNB) then swap ~half of the WBNB to the other token
- Bypass dex router, swap directly through pairs to remove
- Aggregate fees to FeesController and convert to AUTO, burn etc in bulk

### Improved security
- Team-decentralized emergency pause button. Assets will be withdrawn from the farm into the Strat.
- Trustless rescue operations: Allow devs to call arbitrary contracts that do not involve the Strat's asset token.
- Automated testing by forking mainnet for all vaults before deployment.


## Bibliography

- Yearn's ERC4626 Motivation: (https://twitter.com/iearnfinance/status/1511444220850184197?s=20&t=Bfb2UbL-y6mS6QwME0Un-A)
- Profit vesting: xERC4626 by fei-protocol (https://github.com/fei-protocol/ERC4626/blob/main/src/xERC4626.sol)
