// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {Authority} from "solmate/auth/Auth.sol";
import {StratX4} from "../../src/StratX4.sol";
import {FlippedUint256, FlippedUint256Lib} from "../../src/libraries/FlippedUint.sol";

error CallToUnmockedFunction(string functionName);

contract MockStrat is StratX4 {
  using SafeTransferLib for ERC20;

  event FarmDeposit(uint256 amount);
  event FarmWithdraw(uint256 amount);
  event FarmHarvest();

  constructor(
    address _asset,
    address _feesController,
    uint256 _feeRate,
    Authority _authority
  ) StratX4(_asset, _feesController, _feeRate, _authority) {}

  // Farming mechanism are disabled for tests
  function _farm(uint256 amount) internal override {
    emit FarmDeposit(amount);
  }

  function _unfarm(uint256 amount) internal override {
    emit FarmWithdraw(amount);
  }

  function _emergencyUnfarm() internal override {}

  // Compounding mechanism should be simulated by the tests
  function harvest(address) internal override {
    emit FarmHarvest();
  }

  function compound(address earnedAddress, uint256 earnedAmount) internal view override returns (uint256) {
    return this.mock__compound(earnedAddress, earnedAmount);
  }

  function mock__compound(address, uint256) public pure returns (uint256) {
    revert CallToUnmockedFunction("mock__compound");
  }

  // Expose internal functions for testing
  function public__handleFees(address earnedAddress) public returns (uint256, uint256) {
    return getEarnedAmountAfterFee(earnedAddress);
  }

  function public__vestProfit(uint256 profit) public {
    _vestProfit(profit);
  }

  // Should return array
  // or remove completely
  function pendingRewards() public view override returns (uint256) {}

  function lockedAssets() internal pure override returns (uint256) {
    return 0;
  }

  function debug__warmFeesCollectable(address earnedAddress) public {
    feesCollectable[earnedAddress] = FlippedUint256Lib.create(0);
  }
}
