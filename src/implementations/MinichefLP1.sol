// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {SSTORE2Map} from "sstore2/SSTORE2Map.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Authority} from "solmate/auth/Auth.sol";
import {SSTORE2} from "solmate/utils/SSTORE2.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {StratX4Compounding} from "../StratX4Compounding.sol";
import {IMinichefV2} from "../interfaces/IMinichef.sol";
import {
  StratX4LibEarn,
  ZapLiquidityConfig,
  SwapRoute
} from "../libraries/StratX4LibEarn.sol";

contract StratX4MinichefLP1 is StratX4Compounding {
  using SafeTransferLib for ERC20;

  uint256 public immutable pid; // pid of pool in farmContractAddress

  constructor(
    address _asset,
    address _feesController,
    Authority _authority,
    address _farmContractAddress,
    uint256 _pid,
    address _mainRewardToken,
    SwapRoute memory _swapRoute,
    ZapLiquidityConfig memory _zapLiquidityConfig
  )
    StratX4Compounding(
      _asset,
      _farmContractAddress,
      _feesController,
      _authority,
      _mainRewardToken,
      abi.encode(_swapRoute, _zapLiquidityConfig)
    )
  {
    pid = _pid;
  }

  // ERC4626 compatibility

  function lockedAssets() internal view override returns (uint256) {
    return IMinichefV2(farmContractAddress).userInfo(pid, address(this)).amount;
  }

  // Farming

  function _farm(uint256 wantAmt) internal override {
    IMinichefV2(farmContractAddress).deposit(pid, wantAmt, address(this));
  }

  function _unfarm(uint256 wantAmt) internal override {
    IMinichefV2(farmContractAddress).withdraw(pid, wantAmt, address(this));
  }

  function _emergencyUnfarm() internal override {
    IMinichefV2(farmContractAddress).emergencyWithdraw(pid, address(this));
  }

  // Compounding

  function _harvestMainReward() internal override {
    IMinichefV2(farmContractAddress).harvest(pid, address(this));
  }

  function _compound(
    address earnedAddress,
    uint256 earnedAmount,
    bytes memory compoundConfigData
  ) internal override returns (uint256) {
    (SwapRoute memory swapRoute, ZapLiquidityConfig memory zapLiquidityConfig) =
      abi.decode(compoundConfigData, (SwapRoute, ZapLiquidityConfig));

    return StratX4LibEarn.swapExactTokensToLiquidity1(
      earnedAddress, address(asset), earnedAmount, swapRoute, zapLiquidityConfig
    );
  }
}
