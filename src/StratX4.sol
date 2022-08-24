// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SSTORE2} from "solmate/utils/SSTORE2.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {Auth, Authority} from "solmate/auth/authorities/RolesAuthority.sol";

import "./libraries/StratX3Lib.sol";

struct FeeConfig {
  uint256 feeRate;
  address feesController;
}

uint256 constant SIX_HOURS = 21600; // in blocks

interface IStratX4 {
  function earn() external returns (uint256 compoundedAssets);
  function pendingRewards() external returns (uint256);
  function pendingUserRewards(address user) external returns (uint256);
  function deposit(uint256 assets, address receiver)
    external
    returns (uint256 shares);
  function withdraw(uint256 assets, address receiver, address owner)
    external
    returns (uint256 shares);
  function pause() external;
  function unpause() external;
  function rewardToWant() external returns (uint256);
  function nextOptimalEarnBlock(uint256 _r, uint256 gasCost)
    external
    returns (uint256);
}

abstract contract StratX4 is ERC4626, Auth {
  using SafeTransferLib for ERC20;
  using FixedPointMathLib for uint256;

  uint256 constant PRECISION = 1e18;

  bool public paused;
  ERC20 public immutable earnedAddress;
  address public immutable farmContractAddress;
  address public feeConfigPointer; // SSTORE2 pointer
  uint256 public lastEarnBlock = block.number;
  uint256 public profitsVesting;
  uint256 public profitVestingPeriod = SIX_HOURS;
  address[] public rewarders;

  struct RescueCall {
    address target;
    bytes data;
  }

  event FeesUpdated(uint256 feeRate, address rewardsAddress);

  event Earn(uint256 rewardsHarvested, uint256 assetsIncrease);

  modifier isNotPaused() {
    require(!paused, "StratX4: Paused");
    _;
  }

  modifier isPaused() {
    require(paused, "StratX4: Must be paused");
    _;
  }

  constructor(
    address _asset,
    address _earnedAddress,
    address _farmContractAddress,
    FeeConfig memory _feeConfig,
    Authority _authority
  )
    ERC4626(ERC20(_asset), "Autofarm Strategy", "AUTOSTRAT")
    Auth(address(0), _authority)
  {
    earnedAddress = ERC20(_earnedAddress);
    farmContractAddress = _farmContractAddress;
    feeConfigPointer = SSTORE2.write(abi.encode(_feeConfig));
  }

  /**
   * ERC4626 compatibility ***
   */

  // totalAssets is adjusted to vest earned profits over a vesting period
  // to prevent front-running and remove the need for an entrance fee
  function totalAssets() public view override returns (uint256) {
    if (paused) {
      return asset.balanceOf(address(this));
    }

    return _lockedAssets() + asset.balanceOf(address(this)) - lockedProfit();
  }

  function lockedProfit() public view returns (uint256) {
    uint256 blocksSinceLastEarn = block.number - lastEarnBlock;
    uint256 _profitVestingPeriod = profitVestingPeriod;
    if (blocksSinceLastEarn >= _profitVestingPeriod) {
      return 0;
    }
    return profitsVesting.mulDivUp(
      _profitVestingPeriod - blocksSinceLastEarn, _profitVestingPeriod
    );
  }

  function _lockedAssets() internal view virtual returns (uint256) {}

  function afterDeposit(uint256 assets, uint256 shares) internal override {
    if (!paused) {
      _farm(assets);
    }
  }

  function beforeWithdraw(uint256 assets, uint256 shares) internal override {
    if (!paused) {
      uint256 balance = asset.balanceOf(address(this));
      if (balance < assets) {
        _unfarm(assets - balance);
      }
    }
  }

  function _mint(address from, uint256 amount) internal override {
    address[] memory _rewarders = rewarders;
    if (_rewarders.length > 0) {
      StratX3Lib._harvestReward(rewarders, from, amount, false);
    }
    super._mint(from, amount);
  }

  function _burn(address from, uint256 amount) internal override {
    address[] memory _rewarders = rewarders;
    if (_rewarders.length > 0) {
      StratX3Lib._harvestReward(_rewarders, from, amount, true);
    }
    super._burn(from, amount);
  }

  function _farm(uint256 wantAmt) internal virtual {}
  function _unfarm(uint256 wantAmt) internal virtual {}
  function _harvest() internal virtual {}
  function _emergencyUnfarm() internal virtual {}
  function pendingRewards() public view virtual returns (uint256) {}

  function pendingUserRewards(address user) public view returns (uint256) {
    return pendingRewards() * balanceOf[user] / totalSupply;
  }

  /**
   * Compounding ***
   */

  function earn()
    public
    requiresAuth
    isNotPaused
    returns (uint256 compoundedAssets)
  {
    _harvest();
    uint256 earnedAmt = earnedAddress.balanceOf(address(this));
    require(earnedAmt > 0, "StratX4: No harvest");

    // Handle Fees
    FeeConfig memory feeConfig =
      abi.decode(SSTORE2.read(feeConfigPointer), (FeeConfig));

    if (feeConfig.feeRate > 0 && feeConfig.feesController != address(0)) {
      uint256 fee = earnedAmt.mulDivUp(feeConfig.feeRate, PRECISION);
      require(fee > 0, "StratX4: No fees");
      earnedAmt -= fee;
      require(earnedAmt > 0, "StratX4: No harvest after fees");
      earnedAddress.safeTransfer(feeConfig.feesController, fee);
    }

    compoundedAssets = compound(earnedAmt);
    _farm(compoundedAssets);

    _setProfitsVesting(compoundedAssets);
    lastEarnBlock = block.number;

    emit Earn(earnedAmt, compoundedAssets);
  }

  // Increase vesting profits
  // Takes into account the previous unvested profits, if any
  // c.f. https://github.com/luiz-lvj/eth-amsterdam/blob/ff3a18581d73941fe520120fe2b239cf738b2b29/contracts/LeibnizVault.sol#L58
  function _setProfitsVesting(uint256 compoundedAssets) internal {
    uint256 prevVestingEnd = lastEarnBlock + profitVestingPeriod;

    if (block.number >= prevVestingEnd) {
      profitsVesting = compoundedAssets;
      return;
    }

    profitsVesting = (prevVestingEnd - block.number).mulDivUp(
      profitsVesting, profitVestingPeriod
    ) + compoundedAssets;
  }

  function compound(uint256 earnedAmt)
    internal
    virtual
    returns (uint256 assets)
  {}

  function ethToWant() public view virtual returns (uint256) {}
  function rewardToWant() public view virtual returns (uint256) {}

  function nextOptimalEarnBlock(uint256 _r, uint256 callCostInWei)
    external
    view
    returns (uint256)
  {
    require(_r > 0, "Cannot earn without yield");

    uint256 _totalAssets = totalAssets();
    uint256 gas = callCostInWei * ethToWant() / PRECISION;
    uint256 t0 = (gas + FixedPointMathLib.sqrt(gas * _totalAssets))
      / (_totalAssets * _r / PRECISION);
    uint256 totalAssetsIncrease = _totalAssets * _r * t0 / PRECISION - gas;
    uint256 t1 = gas / (totalAssetsIncrease * _r / PRECISION);
    return lastEarnBlock + t0 + t1;
  }

  /*
   * ADMIN
   */

  function setFeeConfig(FeeConfig calldata _feeConfig) public requiresAuth {
    feeConfigPointer = SSTORE2.write(abi.encode(_feeConfig));
    emit FeesUpdated(_feeConfig.feeRate, _feeConfig.feesController);
  }

  function pause() public isNotPaused requiresAuth {
    asset.safeApprove(farmContractAddress, 0);
    paused = true;
    _emergencyUnfarm();
  }

  function unpause() public isPaused requiresAuth {
    asset.safeApprove(farmContractAddress, type(uint256).max);
    paused = false;
    _farm(asset.balanceOf(address(this)));
  }

  /*
   * EMERGENCY MITIGATION
   */

  // Emergency calls for recovery
  // Use cases:
  // - Refund by farm through different contract
  // - Rewards on different external rewarder contract
  function rescueOperation(RescueCall[] calldata calls)
    public
    requiresAuth
    isPaused
  {
    require(paused, "StratX4: !paused");

    for (uint256 i; i < calls.length; i++) {
      RescueCall calldata call = calls[i];
      // Calls to the asset are disallowed
      // Try to rescue the funds to this contract, and let people
      // withdraw from this contract
      require(
        call.target != address(asset), "StratX4: rescue cannot call asset"
      );
      (bool succeeded,) = call.target.call(call.data);
      require(succeeded, "!succeeded");
    }
  }
}
