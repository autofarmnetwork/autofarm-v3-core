// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {Auth, Authority} from "solmate/auth/authorities/RolesAuthority.sol";
import {Pausable} from "openzeppelin/security/Pausable.sol";
import {FlippedUint256, FlippedUint256Lib} from "./libraries/FlippedUint.sol";

error NothingEarnedAfterFees(address earnedAddress, uint256 earnedAmount, uint256 feeCollectable);

abstract contract StratX4 is ERC4626, Auth, Pausable {
  using SafeTransferLib for ERC20;
  using FixedPointMathLib for uint256;
  using FixedPointMathLib for uint160;

  uint256 public constant FEE_RATE_PRECISION = 1e18;

  address public immutable feesController;
  uint96 public immutable creationBlock;
  mapping(address => FlippedUint256) public feesCollectable;
  uint256 public constant MAX_FEE_RATE = 1e17; // 10%
  uint256 public constant PROFIT_VESTING_PERIOD = 21600; // 6 hours

  uint256 public feeRate;
  ProfitVesting public profitVesting;

  event FeeSetAside(address earnedAddress, uint256 amount);
  event FeeCollected(address indexed earnedAddress, uint256 amount);
  event FeesUpdated(uint256 feeRate);
  event Earn(address indexed earnedAddress, uint256 assetsIncrease, uint256 earnedAmount, uint256 fee);

  struct ProfitVesting {
    // 96 bits should be enough for > 2500 years of operation,
    // if block time is 1 second
    uint96 lastEarnBlock;
    uint160 amount;
  }

  struct RescueCall {
    address target;
    bytes data;
  }

  constructor(
    address _asset,
    address _feesController,
    uint256 _feeRate,
    Authority _authority
  ) ERC4626(ERC20(_asset), "Autofarm Strategy", "AF-Strat") Auth(address(0), _authority) {
    require(_feeRate <= MAX_FEE_RATE, "StratX4: feeRate exceeds limit");

    feesController = _feesController;
    feeRate = _feeRate;

    uint96 _creationBlock = uint96(block.number);
    profitVesting = ProfitVesting({lastEarnBlock: _creationBlock, amount: 0});
    creationBlock = _creationBlock;
  }

  ///// ERC4626 compatibility /////

  // totalAssets is adjusted to vest earned profits over a vesting period
  // to prevent front-running and remove the need for an entrance fee
  function totalAssets() public view override returns (uint256 amount) {
    amount = asset.balanceOf(address(this));

    if (!paused()) {
      amount += lockedAssets();
      uint256 _vestingProfit = vestingProfit();
      if (_vestingProfit > amount) {
        _vestingProfit = amount;
      }
      amount -= _vestingProfit;
    }
  }

  function vestingProfit() public view returns (uint256) {
    uint256 blocksSinceLastEarn = block.number - profitVesting.lastEarnBlock;
    if (blocksSinceLastEarn >= PROFIT_VESTING_PERIOD) {
      return 0;
    }
    return profitVesting.amount.mulDivUp(PROFIT_VESTING_PERIOD - blocksSinceLastEarn, PROFIT_VESTING_PERIOD);
  }

  function lockedAssets() internal view virtual returns (uint256);

  function afterDeposit(uint256 assets, uint256 /*shares*/ ) internal override {
    if (!paused()) {
      _farm(assets);
    }
  }

  function beforeWithdraw(uint256 assets, uint256 /*shares*/ ) internal override {
    if (!paused()) {
      _unfarm(assets);
    }
  }

  ///// FARM INTERACTION /////

  function _farm(uint256 wantAmt) internal virtual;
  function _unfarm(uint256 wantAmt) internal virtual;
  function _emergencyUnfarm() internal virtual;
  function pendingRewards() public view virtual returns (uint256);

  ///// Compounding /////

  function earn(address earnedAddress) public requiresAuth whenNotPaused returns (uint256 profit) {
    harvest(earnedAddress);
    (uint256 earnedAmount, uint256 fee) = getEarnedAmountAfterFee(earnedAddress);

    // Gas optimization: leave at least 1 wei in the Strat
    profit = compound(earnedAddress, earnedAmount) - 1;

    require(profit > 0, "StratX4: Earn produces no profit");

    _farm(profit);
    _vestProfit(profit);
    emit Earn(earnedAddress, profit, earnedAmount, fee);
  }

  function harvest(address earnedAddress) internal virtual;
  function compound(address earnedAddress, uint256 earnedAmount) internal virtual returns (uint256);

  function getEarnedAmountAfterFee(address earnedAddress) internal returns (uint256 earnedAmount, uint256 fee) {
    uint256 _feeRate = feeRate; // Reduce SLOADs

    uint256 _feeCollectable = feesCollectable[earnedAddress].get();

    // When earnedAddress == asset, and when the asset is somehow staked in this Strat instead of the farm
    // this might reflect the wrong amount.
    // Normally that would only happen in a paused strat,
    // but it is possible for the farm to "push" the assets back to the Strat.
    earnedAmount = ERC20(earnedAddress).balanceOf(address(this)) - _feeCollectable;

    if (_feeRate > 0) {
      fee = earnedAmount.mulDivUp(_feeRate, FEE_RATE_PRECISION);
      earnedAmount -= fee;

      if (earnedAmount <= fee) {
        revert NothingEarnedAfterFees(earnedAddress, earnedAmount, _feeCollectable);
      }
      feesCollectable[earnedAddress] = FlippedUint256Lib.create(_feeCollectable + fee);

      emit FeeSetAside(earnedAddress, fee);
    }
  }

  function minEarnedAmountToHarvest() public view returns (uint256) {
    return FEE_RATE_PRECISION / feeRate;
  }

  /* @earnbot
   * Called in batches to decouple fees and compounding.
   * Should calc gas vs fees to decide when it is economical to collect fees
   * Optimize for gas by leaving 1 wei in the Strat
   */
  function collectFees(address earnedAddress) public whenNotPaused requiresAuth {
    uint256 amount = feesCollectable[earnedAddress].get() - 1;
    require(amount > 0, "No fees collectable");
    ERC20(earnedAddress).safeTransfer(feesController, amount);
    feesCollectable[earnedAddress] = FlippedUint256Lib.create(1);
    emit FeeCollected(earnedAddress, amount);
  }

  function collectableFee(address earnedAddress) public view returns (uint256 amount) {
    amount = feesCollectable[earnedAddress].get();
  }

  function _vestProfit(uint256 profit) internal {
    uint96 lastEarnBlock = profitVesting.lastEarnBlock;
    uint256 prevVestingEnd = lastEarnBlock + PROFIT_VESTING_PERIOD;

    uint256 vestingAmount = uint160(profit);

    // Carry over unvested profits
    if (block.number < prevVestingEnd && block.number != creationBlock) {
      vestingAmount += profitVesting.amount.mulDivUp(prevVestingEnd - block.number, PROFIT_VESTING_PERIOD);
    }
    profitVesting.lastEarnBlock = uint96(block.number);
    profitVesting.amount = uint160(vestingAmount);
  }

  ///// KEEPER FUNCTIONALITIES /////

  /*
   * Sets the feeRate.
   * The Keeper adjusts the feeRate periodically according to the vault's APR.
   */
  function setFeeRate(uint256 _feeRate) public requiresAuth {
    require(_feeRate <= MAX_FEE_RATE, "StratX4: feeRate exceeds limit");

    feeRate = _feeRate;
    emit FeesUpdated(_feeRate);
  }

  ///// DEV FUNCTIONALITIES /////

  function deprecate() public whenNotPaused requiresAuth {
    _pause();
    _emergencyUnfarm();
  }

  function undeprecate() public whenPaused requiresAuth {
    _unpause();
    _farm(asset.balanceOf(address(this)));
  }

  // Emergency calls for recovery
  // Use cases:
  // - Refund by farm through different contract
  // - Rewards on different external rewarder contract
  function rescueOperation(RescueCall[] calldata calls) public requiresAuth whenPaused {
    for (uint256 i; i < calls.length; i++) {
      RescueCall calldata call = calls[i];
      // Calls to the asset are disallowed
      // Try to rescue the funds to this contract, and let people
      // withdraw from this contract
      require(call.target != address(asset), "StratX4: rescue cannot call asset");
      (bool succeeded,) = call.target.call(call.data);
      require(succeeded, "!succeeded");
    }
  }
}
