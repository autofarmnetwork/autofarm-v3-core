// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {Auth, Authority} from "solmate/auth/authorities/RolesAuthority.sol";
import {Pausable} from "openzeppelin/security/Pausable.sol";
import {FlippedUint256, FlippedUint256Lib} from "./libraries/FlippedUint.sol";

abstract contract StratX4 is ERC4626, Auth, Pausable {
  using SafeTransferLib for ERC20;
  using FixedPointMathLib for uint256;
  using FixedPointMathLib for uint160;

  uint256 public constant FEE_RATE_PRECISION = 1e18;

  address public immutable farmContractAddress;
  address public immutable feesController;
  uint96 public immutable creationBlockNumber;
  mapping(address => FlippedUint256) public feesCollectable;
  uint256 public constant MAX_FEE_RATE = 1e17; // 10%
  uint256 public constant PROFIT_VESTING_PERIOD = 21600; // 6 hours

  uint256 public feeRate;
  ProfitVesting public profitVesting;

  event FeeSetAside(address earnedAddress, uint256 amount);
  event FeeCollected(address indexed earnedAddress, uint256 amount);
  event FeesUpdated(uint256 feeRate);
  event Earn(
    address indexed earnedAddress,
    uint256 assetsIncrease,
    uint256 earnedAmount,
    uint256 fee
  );

  struct ProfitVesting {
    // 96 bits should be enough for > 2500 years of operation,
    // if block time is 1 second
    uint96 lastEarnBlock;
    uint160 amount;
  }

  constructor(
    address _asset,
    address _farmContractAddress,
    address _feesController,
    Authority _authority
  )
    ERC4626(ERC20(_asset), "Autofarm Strategy", "AF-Strat")
    Auth(address(0), _authority)
  {
    farmContractAddress = _farmContractAddress;
    feesController = _feesController;

    uint96 _creationBlockNumber = uint96(block.number);
    profitVesting =
      ProfitVesting({lastEarnBlock: _creationBlockNumber, amount: 0});
    creationBlockNumber = _creationBlockNumber;

    ERC20(_asset).safeApprove(_farmContractAddress, type(uint256).max);
  }

  function depositWithPermit(
    uint256 assets,
    address receiver,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) public {
    asset.permit(msg.sender, address(this), assets, deadline, v, r, s);
    deposit(assets, receiver);
  }

  ///// ERC4626 compatibility /////

  function previewDeposit(uint256 assets) public view override whenNotPaused returns (uint256) {
    return super.previewDeposit(assets);
  }

  function previewMint(uint256 shares) public view override whenNotPaused returns (uint256) {
    return super.previewMint(shares);
  }

  // totalAssets is adjusted to vest earned profits over a vesting period
  // to prevent front-running and remove the need for an entrance fee
  function totalAssets() public view override returns (uint256 amount) {
    if (!paused()) {
      amount = lockedAssets();
      uint256 _vestingProfit = vestingProfit();
      if (_vestingProfit > amount) {
        _vestingProfit = amount;
      }
      amount -= _vestingProfit;
    } else {
      amount = asset.balanceOf(address(this));
    }
  }

  function vestingProfit() public view returns (uint256) {
    uint256 blocksSinceLastEarn = block.number - profitVesting.lastEarnBlock;
    if (blocksSinceLastEarn >= PROFIT_VESTING_PERIOD) {
      return 0;
    }
    return profitVesting.amount.mulDivUp(
      PROFIT_VESTING_PERIOD - blocksSinceLastEarn, PROFIT_VESTING_PERIOD
    );
  }

  function lockedAssets() internal view virtual returns (uint256);

  function afterDeposit(uint256 assets, uint256 /*shares*/ )
    internal
    virtual
    override
  {
    if (!paused()) {
      _farm(assets);
    }
  }

  function beforeWithdraw(uint256 assets, uint256 /*shares*/ )
    internal
    virtual
    override
  {
    if (!paused()) {
      _unfarm(assets);
    }
  }

  ///// FARM INTERACTION /////

  function _farm(uint256 wantAmt) internal virtual;
  function _unfarm(uint256 wantAmt) internal virtual;
  function _emergencyUnfarm() internal virtual;

  ///// Compounding /////

  function earn(address earnedAddress, uint256 minAmountOut)
    public
    requiresAuth
    whenNotPaused
    returns (uint256 profit)
  {
    require(minAmountOut > 0, "StratX4: minAmount Outmust be at least 1");
    harvest(earnedAddress);
    (uint256 earnedAmount, uint256 fee) = getEarnedAmountAfterFee(earnedAddress);

    require(earnedAmount > 1, "StratX4: Nothing earned after fees");
    earnedAmount -= 1;

    profit = compound(earnedAddress, earnedAmount);
    require(
      profit >= minAmountOut, "StratX4: Earn produces less than minAmountOut"
    );

    // Gas optimization: leave at least 1 wei in the Strat
    profit -= 1;

    _farm(profit);
    _vestProfit(profit);
    emit Earn(earnedAddress, profit, earnedAmount, fee);
  }

  // Calls external contract to retrieve reward tokens
  function harvest(address earnedAddress) internal virtual;

  // Swaps harvested reward tokens into assets
  function compound(address earnedAddress, uint256 earnedAmount)
    internal
    virtual
    returns (uint256 profit);

  // When earnedAddress == asset, and when the asset is somehow staked in this Strat instead of the farm
  // this will have to be adjusted to exclude the balance of deposits
  function getEarnedAmount(address earnedAddress, uint256 feeCollectable)
    internal
    view
    virtual
    returns (uint256)
  {
    return ERC20(earnedAddress).balanceOf(address(this)) - feeCollectable;
  }

  function getEarnedAmountAfterFee(address earnedAddress)
    internal
    returns (uint256 earnedAmount, uint256 fee)
  {
    uint256 _feeRate = feeRate; // Reduce SLOADs

    uint256 _feeCollectable = feesCollectable[earnedAddress].get();

    earnedAmount = getEarnedAmount(earnedAddress, _feeCollectable);

    if (_feeRate > 0) {
      fee = earnedAmount.mulDivUp(_feeRate, FEE_RATE_PRECISION);

      earnedAmount -= fee;

      feesCollectable[earnedAddress] =
        FlippedUint256Lib.create(_feeCollectable + fee);

      emit FeeSetAside(earnedAddress, fee);
    }
  }

  function minEarnedAmountToHarvest()
    public
    view
    returns (uint256 minEarnedAmount)
  {
    uint256 _feeRate = feeRate;

    if (_feeRate > 0) {
      minEarnedAmount = FEE_RATE_PRECISION / feeRate;
    }
  }

  /* @earnbot
   * Called in batches to decouple fees and compounding.
   * Should calc gas vs fees to decide when it is economical to collect fees
   * Optimize for gas by leaving 1 wei in the Strat
   */
  function collectFees(address earnedAddress)
    public
    whenNotPaused
    requiresAuth
    returns (uint256 amount)
  {
    amount = feesCollectable[earnedAddress].get();
    require(amount > 0, "No fees collectable");
    ERC20(earnedAddress).safeTransfer(feesController, amount);
    feesCollectable[earnedAddress] = FlippedUint256Lib.create(1);
    emit FeeCollected(earnedAddress, amount);
  }

  function collectableFee(address earnedAddress)
    public
    view
    returns (uint256 amount)
  {
    amount = feesCollectable[earnedAddress].get();
  }

  function _vestProfit(uint256 profit) internal {
    uint96 lastEarnBlock = profitVesting.lastEarnBlock;
    uint256 prevVestingEnd = lastEarnBlock + PROFIT_VESTING_PERIOD;

    uint256 vestingAmount = uint160(profit);

    // Carry over unvested profits
    if (block.number < prevVestingEnd && block.number != creationBlockNumber) {
      vestingAmount += profitVesting.amount.mulDivUp(
        prevVestingEnd - block.number, PROFIT_VESTING_PERIOD
      );
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
    _emergencyUnfarm();
    _pause();
    asset.safeApprove(farmContractAddress, 0);
  }

  function undeprecate() public whenPaused requiresAuth {
    _unpause();
    asset.safeApprove(farmContractAddress, type(uint256).max);
    _farm(asset.balanceOf(address(this)));
  }

  // Farm allowance should be unlikely to run out during the Strat's lifetime
  // given that the asset's fiat value per wei is within reasonable range
  // but if it does, it can be reset here
  function resetFarmAllowance() public requiresAuth whenNotPaused {
    asset.safeApprove(farmContractAddress, type(uint256).max);
  }

  // Emergency calls for funds recovery
  // Use cases:
  // - Refund by farm through a reimbursement contract
  function rescueOperation(address[] calldata targets, bytes[] calldata data)
    public
    requiresAuth
    whenPaused
  {
    require(
      targets.length == data.length, "StratX4: targets data length mismatch"
    );

    for (uint256 i; i < targets.length; i++) {
      // Try to rescue the funds to this contract, and let people
      // withdraw from this contract
      require(
        targets[i] != address(asset) && targets[i] != address(this),
        "StratX4: Illegal target"
      );
      (bool succeeded,) = targets[i].call(data[i]);
      require(succeeded, "!succeeded");
    }
  }
}
