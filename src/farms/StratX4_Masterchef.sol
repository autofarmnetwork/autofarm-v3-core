// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import "../StratX4.sol";
import "../interfaces/IPancakeswapFarm.sol";

/*
 * Farm Requirements
 * - Fork of masterchef (supports interface)
 * - should not be upgradable / destroyable to prevent stuck deposit/withdrawal
 */
abstract contract StratX4_Masterchef is StratX4 {
  using SafeTransferLib for ERC20;
  using FixedPointMathLib for uint256;

  // Farm
  uint256 public immutable pid; // pid of pool in farmContractAddress
  bytes4 public immutable pendingRewardsSelector;

  constructor(
    address _asset,
    address _earnedAddress,
    address _farmContractAddress,
    uint256 _pid,
    bytes4 _pendingRewardsSelector,
    FeeConfig memory _feeConfig,
    Authority _authority
  )
    StratX4(_asset, _earnedAddress, _farmContractAddress, _feeConfig, _authority)
  {
    pid = _pid;
    pendingRewardsSelector = _pendingRewardsSelector;
  }

  // ERC4626 compatibility

  function _lockedAssets() internal view override returns (uint256) {
    return IPancakeswapFarm(farmContractAddress).userInfo(pid, address(this))
      .amount;
  }

  function pendingRewards() public view override returns (uint256) {
    (bool success, bytes memory data) = farmContractAddress.staticcall(
      abi.encodeWithSelector(pendingRewardsSelector, pid, address(this))
    );
    require(success, "StratX4_Masterchef: pendingRewards failed");
    return abi.decode(data, (uint256));
  }

  // Farming

  function _farm(uint256 wantAmt) internal override {
    IPancakeswapFarm(farmContractAddress).deposit(pid, wantAmt);
  }

  function _unfarm(uint256 wantAmt) internal override {
    IPancakeswapFarm(farmContractAddress).withdraw(pid, wantAmt);
  }

  function _harvest() internal override {
    IPancakeswapFarm(farmContractAddress).withdraw(pid, 0);
  }

  function _emergencyUnfarm() internal override {
    IPancakeswapFarm(farmContractAddress).emergencyWithdraw(pid);
  }
}
