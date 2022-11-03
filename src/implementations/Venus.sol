// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Authority} from "solmate/auth/Auth.sol";

import {StratX4Compounding} from "../StratX4Compounding.sol";
import {IVToken, IVenusUnitroller} from "../interfaces/Venus.sol";
import {StratX4LibEarn, SwapRoute} from "../libraries/StratX4LibEarn.sol";

error VenusError(uint256 returnCode);

contract StratX4Venus is StratX4Compounding {
  address public immutable venusDistributionAddress =
    0xfD36E2c2a6789Db23113685031d7F16329158384;
  uint256 public borrowRate = 1e18;

  constructor(
    address _asset,
    address _feesController,
    Authority _authority,
    address _farmContractAddress, // VToken
    address _mainRewardToken,
    SwapRoute memory _swapRoute
  )
    StratX4Compounding(
      _asset,
      _farmContractAddress,
      _feesController,
      _authority,
      _mainRewardToken,
      abi.encode(_swapRoute)
    )
  {
    address[] memory markets = new address[](1);
    markets[0] = _farmContractAddress;
    uint256[] memory enterMarketsResponse =
      IVenusUnitroller(venusDistributionAddress).enterMarkets(markets);
    if (enterMarketsResponse[0] != 0) {
      revert VenusError(enterMarketsResponse[0]);
    }
  }

  // ERC4626 compatibility

  function lockedAssets() internal view override returns (uint256) {
    return IVToken(farmContractAddress).balanceOf(address(this))
      * IVToken(farmContractAddress).exchangeRateStored() / 1e18;
  }

  // Farming

  function _farm(uint256 wantAmt) internal override {
    uint256 returnCode = IVToken(farmContractAddress).mint(wantAmt);
    if (returnCode != 0) {
      revert VenusError(returnCode);
    }
  }

  function _unfarm(uint256 wantAmt) internal override {
    IVToken(farmContractAddress).redeemUnderlying(wantAmt);
  }

  function _emergencyUnfarm() internal override {
    _unfarm(lockedAssets());
  }

  // Compounding

  function _harvestMainReward() internal override {
    address[] memory holders = new address[](1);
    holders[0] = address(this);
    IVToken[] memory markets = new IVToken[](1);
    markets[0] = IVToken(farmContractAddress);

    IVenusUnitroller(venusDistributionAddress).claimVenus(
      holders, markets, true, true
    );
  }

  function _compound(
    address earnedAddress,
    uint256 earnedAmount,
    bytes memory compoundConfigData
  ) internal override returns (uint256) {
    SwapRoute memory swapRoute = abi.decode(compoundConfigData, (SwapRoute));

    return StratX4LibEarn.swapExactTokensForTokens(
      earnedAddress,
      earnedAmount,
      swapRoute.swapFees,
      swapRoute.pairsPath,
      swapRoute.tokensPath
    );
  }
}
