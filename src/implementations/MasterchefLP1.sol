// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SSTORE2Map} from "sstore2/SSTORE2Map.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Authority} from "solmate/auth/Auth.sol";
import {SSTORE2} from "solmate/utils/SSTORE2.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {StratX4} from "../StratX4.sol";
import {IMasterchefV2} from "../interfaces/IMasterchefV2.sol";
import {
  StratX4LibEarn,
  ZapLiquidityConfig,
  SwapRoute
} from "../libraries/StratX4LibEarn.sol";

contract StratX4MasterchefLP1 is StratX4 {
  using SafeTransferLib for ERC20;

  address public immutable mainRewardToken;
  uint256 public immutable pid; // pid of pool in farmContractAddress
  address public immutable mainCompoundConfigPointer;

  constructor(
    address _asset,
    address _feesController,
    Authority _authority,
    address _farmContractAddress,
    uint256 _pid,
    address _mainRewardToken,
    SwapRoute memory _swapRoute,
    ZapLiquidityConfig memory _zapLiquidityConfig
  ) StratX4(_asset, _farmContractAddress, _feesController, _authority) {
    pid = _pid;

    mainRewardToken = _mainRewardToken;
    mainCompoundConfigPointer = SSTORE2.write(
      abi.encode(_swapRoute, _zapLiquidityConfig)
    );
  }

  // ERC4626 compatibility

  function lockedAssets() internal view override returns (uint256) {
    return IMasterchefV2(farmContractAddress).userInfo(pid, address(this))
      .amount;
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

  function harvestConfigKey(address earnedAddress)
    internal
    pure
    returns (bytes32)
  {
    return bytes32(abi.encodePacked(uint160(earnedAddress), uint96(1)));
  }

  function earnConfigKey(address earnedAddress) internal pure returns (bytes32) {
    return bytes32(abi.encodePacked(uint160(earnedAddress), uint96(2)));
  }

  function harvest(address earnedAddress) internal override {
    if (earnedAddress == mainRewardToken) {
      return _harvestMainReward();
    }

    (address target, bytes memory data) = abi.decode(
      SSTORE2Map.read(harvestConfigKey(earnedAddress)), (address, bytes)
    );
    require(
      target != address(0) && target != address(asset)
        && target != earnedAddress && target != farmContractAddress,
      "Illegal call target"
    );

    (bool success,) = target.call(data);
    require(success, "Failed to call target contract method");
  }

  function _harvestMainReward() internal {
    IMasterchefV2(farmContractAddress).withdraw(pid, 0);
  }

  function compound(address earnedAddress, uint256 earnedAmount)
    internal
    override
    returns (uint256)
  {
    if (earnedAddress == mainRewardToken) {
      return compoundMainReward(earnedAmount);
    }

    (SwapRoute memory swapRoute, ZapLiquidityConfig memory zapLiquidityConfig) =
    abi.decode(
      SSTORE2Map.read(earnConfigKey(earnedAddress)),
      (SwapRoute, ZapLiquidityConfig)
    );
    return StratX4LibEarn.swapExactTokensToLiquidity1(
      earnedAddress, address(asset), earnedAmount, swapRoute, zapLiquidityConfig
    );
  }

  function compoundMainReward(uint256 earnedAmount) internal returns (uint256) {
    (SwapRoute memory swapRoute, ZapLiquidityConfig memory zapLiquidityConfig) =
    abi.decode(
      SSTORE2.read(mainCompoundConfigPointer), (SwapRoute, ZapLiquidityConfig)
    );

    return StratX4LibEarn.swapExactTokensToLiquidity1(
      mainRewardToken,
      address(asset),
      earnedAmount,
      swapRoute,
      zapLiquidityConfig
    );
  }

  // Keeper methods

  function addHarvestConfig(
    address earnedAddress,
    address target,
    bytes memory data
  ) public whenNotPaused requiresAuth {
    require(
      earnedAddress != address(0) &&
      earnedAddress != address(this) &&
      earnedAddress != address(asset) &&
      earnedAddress != address(mainRewardToken) &&
      earnedAddress != earnedAddress &&
      earnedAddress != farmContractAddress,
      "Illegal call target"
    );
    require(
      target != address(0) &&
      target != address(this) &&
      target != address(asset) &&
      target != address(mainRewardToken) &&
      target != earnedAddress &&
      target != farmContractAddress,
      "Illegal call target"
    );
    SSTORE2Map.write(harvestConfigKey(earnedAddress), abi.encode(target, data));
  }

  function addEarnConfig(
    address earnedAddress,
    SwapRoute memory swapRoute,
    ZapLiquidityConfig memory zapLiquidityConfig
  ) public whenNotPaused requiresAuth {
    require(
      earnedAddress != address(0) &&
      earnedAddress != address(this) &&
      earnedAddress != address(asset) &&
      earnedAddress != address(mainRewardToken) &&
      earnedAddress != farmContractAddress,
      "Illegal call target"
    );

    SSTORE2Map.write(
      earnConfigKey(earnedAddress), abi.encode(swapRoute, zapLiquidityConfig)
    );
  }
}
