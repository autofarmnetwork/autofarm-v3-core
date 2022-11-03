// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {SSTORE2} from "solmate/utils/SSTORE2.sol";
import {Authority} from "solmate/auth/Auth.sol";

import {StratX4} from "./StratX4.sol";
import {
  StratX4LibEarn,
  ZapLiquidityConfig,
  SwapRoute
} from "./libraries/StratX4LibEarn.sol";

abstract contract StratX4Compounding is StratX4 {
  error CompoundConfigNotFound(address compoundConfigPointer);

  address public immutable mainRewardToken;
  mapping(address => address) harvestConfigPointers;
  mapping(address => address) compoundConfigPointers;

  constructor(
    address _asset,
    address _farmContractAddress,
    address _feesController,
    Authority _authority,
    address _mainRewardToken,
    bytes memory _mainCompoundConfigData
  ) StratX4(_asset, _farmContractAddress, _feesController, _authority) {
    mainRewardToken = _mainRewardToken;
    compoundConfigPointers[_mainRewardToken] =
      SSTORE2.write(_mainCompoundConfigData);
  }

  function _harvestMainReward() internal virtual;

  function harvest(address earnedAddress) internal override {
    if (earnedAddress == mainRewardToken) {
      return _harvestMainReward();
    }

    address harvestConfigPointer = harvestConfigPointers[earnedAddress];
    if (harvestConfigPointer == address(0)) {
      return;
    }

    bytes memory harvestConfigData = SSTORE2.read(harvestConfigPointer);
    if (harvestConfigData.length == 0) {
      return;
    }

    (address target, bytes memory data) =
      abi.decode(harvestConfigData, (address, bytes));

    require(
      target != address(asset) && target != earnedAddress
        && target != farmContractAddress,
      "Illegal call target"
    );

    if (target == address(0)) {
      return _harvestMainReward();
    }
    (bool success,) = target.call(data);
    require(success, "Failed to call target contract method");
  }

  function compound(address earnedAddress, uint256 earnedAmount)
    internal
    override
    returns (uint256)
  {
    if (earnedAddress == address(asset)) {
      return earnedAmount;
    }

    address compoundConfigPointer = compoundConfigPointers[earnedAddress];
    if (compoundConfigPointer == address(0)) {
      revert CompoundConfigNotFound(address(0));
    }

    bytes memory compoundConfigData = SSTORE2.read(compoundConfigPointer);
    if (compoundConfigData.length == 0) {
      revert CompoundConfigNotFound(compoundConfigPointer);
    }

    return _compound(earnedAddress, earnedAmount, compoundConfigData);
  }

  function _compound(
    address earnedAddress,
    uint256 earnedAmount,
    bytes memory compoundConfigData
  ) internal virtual returns (uint256);

  // Keeper methods

  function addHarvestConfig(
    address earnedAddress,
    address target,
    bytes memory data
  ) public whenNotPaused requiresAuth {
    require(
      earnedAddress != address(0) && checkTargetIsLegal(earnedAddress),
      "Illegal earnedAddress"
    );
    require(
      target != earnedAddress && checkTargetIsLegal(target),
      "Illegal call target"
    );

    harvestConfigPointers[earnedAddress] =
      SSTORE2.write(abi.encode(target, data));
  }

  function addEarnConfig(address earnedAddress, bytes memory compoundConfigData)
    public
    virtual
    whenNotPaused
    requiresAuth
  {
    require(
      earnedAddress != address(0) && checkTargetIsLegal(earnedAddress),
      "Illegal earnedAddress"
    );

    // More sanity checks

    compoundConfigPointers[earnedAddress] = SSTORE2.write(compoundConfigData);
  }

  function checkTargetIsLegal(address addr) internal view returns (bool) {
    return addr != address(this) && addr != address(asset)
      && addr != address(mainRewardToken) && addr != farmContractAddress;
  }
}
