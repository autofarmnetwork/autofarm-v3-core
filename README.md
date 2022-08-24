Autofarm V2
===========

## WHAT'S NEW in V2

### ERC4626 compatibility:
- Transferable shares (for future Zap/Router implementation)
- Initial shares:token ratio is always 1
- Ideal add liquidity ratio: Calculate ideal ratio before adding liquidity

### 0% Entrance fee
- Profits are vested over a period of 6 hours

### Improved compounding
- New calculation for ideal compounding interval
- Dynamic fees: Fairer distribution of fees depending on APR.

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


