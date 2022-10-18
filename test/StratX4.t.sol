// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Authority} from "solmate/auth/Auth.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {MockAuthority} from "./mocks/MockAuthority.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockStrat} from "./mocks/MockStrat.sol";

import {StratX4} from "../src/StratX4.sol";

contract StratX4Test is Test {
  using FixedPointMathLib for uint256;

  ERC20 public asset; // mock asset
  ERC20 public rewardToken; // mock asset
  // feesController
  // mock Authority: owner = this test contract
  Authority public authority;
  MockStrat public strat;

  event FeeSetAside(address earnedAddress, uint256 amount);
  event FarmDeposit(uint256 amount);
  event FarmWithdraw(uint256 amount);
  event FarmHarvest();
  event Earn(address indexed earnedAddress, uint256 profit, uint256 earnedAmount, uint256 fee);

  function setUp() public {
    asset = new MockERC20();
    rewardToken = new MockERC20();
    authority = new MockAuthority();
    strat = new MockStrat(
      address(asset),
      address(uint160(uint256(keccak256("farm")))),
      address(uint160(uint256(keccak256("feesController")))),
      1e14,
      authority
    );
  }

  function testTotalAssets() public {
    assertEq(strat.totalAssets(), 0);
    deal(address(asset), address(strat), 1 ether);
    assertEq(strat.totalAssets(), 1 ether);
  }

  function testDeposit(uint96 amount) public {
    vm.assume(amount > 0);
    deal(address(asset), address(this), amount);
    asset.approve(address(strat), amount);

    vm.expectEmit(false, false, false, true, address(strat));
    emit FarmDeposit(amount);

    strat.deposit(amount, address(this));
  }

  function testEarn(uint96 earnedAmount, uint96 profit) public {
    strat.debug__warmFeesCollectable(address(rewardToken));
    uint256 minHarvest = strat.minEarnedAmountToHarvest();
    vm.assume(earnedAmount > minHarvest && profit > 0);

    vm.expectEmit(false, false, false, true, address(strat));
    emit FarmHarvest();
    vm.expectEmit(false, false, false, false, address(strat));
    emit FeeSetAside(address(rewardToken), 0);
    vm.expectEmit(false, false, false, true, address(strat));
    emit FarmDeposit(profit);
    vm.expectEmit(true, false, false, false, address(strat));
    emit Earn(address(rewardToken), 0, 0, 0);

    deal(address(rewardToken), address(strat), earnedAmount);

    vm.mockCall(address(strat), abi.encodeWithSelector(MockStrat.mock__compound.selector), abi.encode(profit));
    strat.earn(address(rewardToken));
  }

  // also Test when reward is the staked token
  function testHandleFees(uint96[] memory harvests) public {
    vm.assume(harvests.length > 0);
    uint256 totalHarvested;
    uint256 totalFees;

    // Comment or uncomment to check cold vs warm SSTORE gas usage
    strat.debug__warmFeesCollectable(address(rewardToken));

    uint256 minHarvest = strat.minEarnedAmountToHarvest();

    for (uint256 i; i < harvests.length; i++) {
      uint256 harvested = harvests[i];
      vm.assume(harvested >= minHarvest); // When harvested is too small, fees will be 0 and it will fail

      totalHarvested += harvested;
      uint256 expectedFee = uint256(harvested).mulDivUp(strat.feeRate(), strat.FEE_RATE_PRECISION());
      totalFees += expectedFee;

      vm.expectEmit(true, false, false, true, address(strat));
      emit FeeSetAside(address(rewardToken), expectedFee);

      // simulate harvest rewards
      deal(address(rewardToken), address(strat), rewardToken.balanceOf(address(strat)) + harvested);

      (uint256 earnedAmount, uint256 fee) = strat.public__handleFees(address(rewardToken));

      assertEq(fee, expectedFee, "fee should equal expected");
      assertEq(earnedAmount, harvested - expectedFee, "should return new earnedAmount less fees");

      // Simulate compounding the rewards
      deal(address(rewardToken), address(strat), rewardToken.balanceOf(address(strat)) + expectedFee - harvested); // simulate harvest rewards
    }

    assertEq(strat.feesCollectable(address(rewardToken)).get(), totalFees, "Collectible fees should add up");

    strat.collectFees(address(rewardToken));
    assertEq(
      rewardToken.balanceOf(strat.feesController()),
      totalFees,
      "Rewards should be sent to feesController according to feeRate (and rounded up)"
    );
    assertEq(strat.collectableFee(address(rewardToken)), 0, "After collection there should be none collectable");
  }

  function testVestingProfits(uint96[2][] memory earns) public {
    vm.assume(earns.length > 0);

    uint256 currentBlock = block.number;
    uint256 prevTotalAssets = strat.totalAssets();
    uint256 totalVesting;
    uint256 vestedSinceLastEarn;

    // Test overlapping and non-overlapping earns
    for (uint256 i; i < earns.length; i++) {
      uint96 amount = earns[i][0];
      uint96 blocks = earns[i][1];

      currentBlock += blocks;

      vm.assume(amount > 0 && blocks > 0 && blocks < 1e5);

      vm.roll(currentBlock);
      (uint96 lastEarnBlock, uint160 profitsVesting) = strat.profitVesting();

      vestedSinceLastEarn = strat.totalAssets() - prevTotalAssets;
      prevTotalAssets = strat.totalAssets();

      deal(address(asset), strat.farmContractAddress(), asset.balanceOf(strat.farmContractAddress()) + amount);
      strat.public__vestProfit(amount);

      (lastEarnBlock, profitsVesting) = strat.profitVesting();
      console2.log(block.number);

      assertEq(lastEarnBlock, currentBlock, "lastEarnBlock should be set");

      totalVesting += amount;
      totalVesting -= vestedSinceLastEarn;

      assertEq(profitsVesting, totalVesting, "profitsVesting should be set");
      assertEq(strat.vestingProfit(), totalVesting, "vestingProfit should be set");

      assertEq(strat.totalAssets(), prevTotalAssets, "totalAssets should remain the same before and after");
    }

    // Test vesting after earn
    vm.roll(currentBlock + strat.PROFIT_VESTING_PERIOD() / 2);
    assertEq(
      strat.totalAssets(),
      prevTotalAssets + totalVesting.mulDivDown(strat.PROFIT_VESTING_PERIOD() / 2, strat.PROFIT_VESTING_PERIOD()),
      "totalAssets should increase linearly, rounded down"
    );
    assertEq(
      strat.vestingProfit(),
      totalVesting.mulDivUp(strat.PROFIT_VESTING_PERIOD() / 2, strat.PROFIT_VESTING_PERIOD()),
      "vesting profit should be linear, rounded up"
    );

    vm.roll(currentBlock + strat.PROFIT_VESTING_PERIOD());
    assertEq(strat.totalAssets(), prevTotalAssets + totalVesting, "totalAssets should include vested profit");
    assertEq(strat.vestingProfit(), 0, "profit should vest completely");

    vm.roll(currentBlock + strat.PROFIT_VESTING_PERIOD() * 2);
    assertEq(strat.totalAssets(), prevTotalAssets + totalVesting, "totalAssets should stay constant after vesting");
  }
}
