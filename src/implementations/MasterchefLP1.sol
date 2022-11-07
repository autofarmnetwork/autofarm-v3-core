// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {SSTORE2Map} from "sstore2/SSTORE2Map.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Authority} from "solmate/auth/Auth.sol";
import {SSTORE2} from "solmate/utils/SSTORE2.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {StratX4Compounding} from "../StratX4Compounding.sol";
import {IMasterchefV2} from "../interfaces/IMasterchefV2.sol";
import {UniswapV2Helper} from "../libraries/UniswapV2Helper.sol";

contract StratX4MasterchefLP1 is StratX4Compounding {
  using SafeTransferLib for ERC20;

  uint256 public immutable pid; // pid of pool in farmContractAddress

  constructor(
    address _asset,
    address _feesController,
    Authority _authority,
    address _farmContractAddress,
    uint256 _pid,
    address _mainRewardToken,
    UniswapV2Helper.SwapRoute memory _swapRoute,
    UniswapV2Helper.ZapLiquidityConfig memory _zapLiquidityConfig
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
    return
      IMasterchefV2(farmContractAddress).userInfo(pid, address(this)).amount;
  }

  // Farming

  function _farm(uint256 wantAmt) internal override {
    IMasterchefV2(farmContractAddress).deposit(pid, wantAmt);
  }

  function _unfarm(uint256 wantAmt) internal override {
    IMasterchefV2(farmContractAddress).withdraw(pid, wantAmt);
  }

  function _emergencyUnfarm() internal override {
    IMasterchefV2(farmContractAddress).emergencyWithdraw(pid);
  }

  // Compounding

  function _harvestMainReward() internal override {
    IMasterchefV2(farmContractAddress).withdraw(pid, 0);
  }

  function _compound(
    address /* earnedAddress */,
    uint256 earnedAmount,
    bytes memory compoundConfigData
  ) internal override returns (uint256) {
    (
      UniswapV2Helper.SwapRoute memory swapRoute,
      UniswapV2Helper.ZapLiquidityConfig memory zapLiquidityConfig
    ) = abi.decode(
      compoundConfigData, (UniswapV2Helper.SwapRoute, UniswapV2Helper.ZapLiquidityConfig)
    );

    return UniswapV2Helper.swapExactTokensToLiquidity1(
      address(asset), earnedAmount, swapRoute, zapLiquidityConfig
    );
  }
}
