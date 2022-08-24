// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import "../interfaces/IPancakePair.sol";

import "../StratX4_Masterchef.sol";
import {LP1EarnConfig, StratX4LibEarn} from "../libraries/StratX4LibEarn.sol";

contract StratX4_Masterchef_LP1 is StratX4_Masterchef {
  address public immutable earnConfigPointer; // SSTORE2 pointer

  constructor(
    address _asset,
    address _earnedAddress,
    address _farmContractAddress,
    uint256 _pid,
    bytes4 _pendingRewardsSelector,
    FeeConfig memory _feeConfig,
    Authority _authority,
    LP1EarnConfig memory _earnConfig
  )
    StratX4_Masterchef(
      _asset,
      _earnedAddress,
      _farmContractAddress,
      _pid,
      _pendingRewardsSelector,
      _feeConfig,
      _authority
    )
  {
    earnConfigPointer = StratX4LibEarn.setEarnConfig(_earnConfig);
  }

  function compound(uint256 earnedAmt) internal override returns (uint256) {
    return StratX4LibEarn.compoundLP1(
      asset, earnedAmt, ERC20(earnedAddress), earnConfigPointer
    );
  }

  /*
   * Oracles
   */
  function ethToWant() public view override returns (uint256) {
    return StratX4LibEarn.ethToWantLP1(asset, earnConfigPointer);
  }

  function rewardToWant() public view override returns (uint256) {
    return StratX4LibEarn.rewardToWantLP1(asset, earnConfigPointer);
  }
}