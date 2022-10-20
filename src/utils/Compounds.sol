// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

library Compounds {
  uint256 constant PRECISION = 1e18;

  function nextOptimalEarnBlocks(
    uint256 _r,
    uint256 callCostInWei,
    uint256 totalAssets,
    uint256 ethInWant
  ) external pure returns (uint256) {
    require(_r > 0, "Cannot earn without yield");

    uint256 gas = callCostInWei * ethInWant / PRECISION;
    uint256 t0 = (gas + FixedPointMathLib.sqrt(gas * totalAssets))
      / (totalAssets * _r / PRECISION);
    uint256 totalAssetsIncrease = totalAssets * _r * t0 / PRECISION - gas;
    uint256 t1 = gas / (totalAssetsIncrease * _r / PRECISION);
    return t0 + t1;
  }
}
