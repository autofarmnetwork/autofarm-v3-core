// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {Auth, Authority} from "solmate/auth/authorities/RolesAuthority.sol";

import "./libraries/StratX3Lib.sol";

uint256 constant AROUND_SIX_HOURS = 21600; // in blocks
uint256 constant ONE_WEEK = 604800; // in seconds

contract SingleAUTOVault is ERC4626 {
  using FixedPointMathLib for uint256;

  address public constant AUTOv2 = 0xa184088a740c695E156F91f5cC086a06bb78b827;

  address public feesController;
  uint256 public lastEarnBlock = block.number;
  uint256 public profitsVesting;
  // TODO: change to immutable at least to accomodate different chain block times
  uint256 public profitVestingPeriod = AROUND_SIX_HOURS;
  address[] public rewarders;
  mapping(address => uint256) public depositLockedUntil;
  uint256 public constant LOCK_PERIOD = ONE_WEEK;

  struct RescueCall {
    address target;
    bytes data;
  }

  event Earn(uint256 assetsIncrease);

  constructor(address _feesController)
    ERC4626(ERC20(AUTOv2), "Single AUTO Vault", "AUTOSTRAT")
  {
    feesController = _feesController;
  }

  /**
   * ERC4626 compatibility ***
   */

  // totalAssets is adjusted to vest earned profits over a vesting period
  // to prevent front-running and remove the need for an entrance fee
  function totalAssets() public view override returns (uint256) {
    return asset.balanceOf(address(this)) - lockedProfit();
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

  function deposit(uint256 assets, address receiver)
    public
    override
    returns (uint256 shares)
  {
    shares = super.deposit(assets, receiver);
    depositLockedUntil[receiver] = block.timestamp + LOCK_PERIOD;
  }

  function mint(uint256 shares, address receiver)
    public
    override
    returns (uint256 assets)
  {
    assets = super.mint(shares, receiver);
    depositLockedUntil[receiver] = block.timestamp + LOCK_PERIOD;
  }

  function withdraw(uint256 assets, address owner, address receiver)
    public
    override
    returns (uint256 shares)
  {
    require(depositLockedUntil[owner] < block.timestamp);
    shares = super.withdraw(assets, owner, receiver);
  }

  function redeem(uint256 shares, address owner, address receiver)
    public
    override
    returns (uint256 assets)
  {
    require(depositLockedUntil[owner] < block.timestamp);
    assets = super.redeem(shares, owner, receiver);
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

  /**
   * Compounding ***
   */

  // Increase vesting profits
  // Takes into account the previous unvested profits, if any
  // c.f. https://github.com/luiz-lvj/eth-amsterdam/blob/ff3a18581d73941fe520120fe2b239cf738b2b29/contracts/LeibnizVault.sol#L58
  function setProfitsVesting(uint256 profit) public {
    require(msg.sender == feesController);

    uint256 prevVestingEnd = lastEarnBlock + profitVestingPeriod;

    if (block.number >= prevVestingEnd) {
      profitsVesting = profit;
      return;
    }

    profitsVesting = (prevVestingEnd - block.number).mulDivUp(
      profitsVesting, profitVestingPeriod
    ) + profit;
  }
}
