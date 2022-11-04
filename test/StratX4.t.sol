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

  ERC20 public asset;
  ERC20 public rewardToken;
  Authority public authority;
  MockStrat public strat;
  address public feesController;
  address public farmContractAddress;
  address public user;
  uint256 public userPrivateKey = 0xBEEF;
  bytes32 constant PERMIT_TYPEHASH = keccak256(
    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
  );

  event FeeSetAside(address earnedAddress, uint256 amount);
  event FarmDeposit(uint256 amount);
  event FarmWithdraw(uint256 amount);
  event FarmEmergencyWithdraw();
  event FarmHarvest();
  event Earn(
    address indexed earnedAddress,
    uint256 profit,
    uint256 earnedAmount,
    uint256 fee
  );

  function setUp() public {
    asset = new MockERC20();
    rewardToken = new MockERC20();
    authority = new MockAuthority();
    feesController = makeAddr("feesController");
    farmContractAddress = makeAddr("farm");
    user = vm.addr(userPrivateKey);
    strat = new MockStrat(
      address(asset),
      farmContractAddress,
      feesController,
      authority
    );
    strat.setFeeRate(1e14);
  }

  function testTotalAssetsWhenPaused() public {
    strat.deprecate();
    deal(address(asset), address(strat), 1 ether);
    assertEq(strat.totalAssets(), 1 ether);
  }

  function testDepositShouldFarm() public {
    uint256 amount = 1;
    deal(address(asset), address(user), amount);

    vm.prank(user);
    asset.approve(address(strat), amount);

    vm.expectEmit(false, false, false, true, address(strat));
    emit FarmDeposit(amount);

    vm.prank(user);
    strat.deposit(amount, address(user));
  }

  function testDepositWhenDeprecatedShouldFail() public {
    strat.deprecate();
    uint256 amount = 1;
    deal(address(asset), address(user), amount);

    vm.startPrank(user);
    asset.approve(address(strat), amount);
    vm.expectRevert("Pausable: paused");
    strat.deposit(amount, address(user));
  }

  function testWithdrawWhenDeprecatedShouldSucceed() public {
    uint256 amount = 1;
    deal(address(asset), address(user), amount);

    vm.startPrank(user);
    asset.approve(address(strat), amount);
    strat.deposit(amount, address(user));
    assertEq(asset.balanceOf(address(user)), 0);
    strat.deprecate();
    strat.withdraw(amount, address(user), address(user));
    assertEq(asset.balanceOf(address(user)), amount);
  }

  function testDepositWithPermit() public {
    uint256 amount = 1;
    deal(address(asset), address(user), amount);

    vm.prank(user);

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(
      userPrivateKey,
      keccak256(
        abi.encodePacked(
          "\x19\x01",
          asset.DOMAIN_SEPARATOR(),
          keccak256(
            abi.encode(
              PERMIT_TYPEHASH, user, address(strat), amount, 0, block.timestamp
            )
          )
        )
      )
    );

    vm.expectEmit(false, false, false, true, address(strat));
    emit FarmDeposit(amount);

    vm.prank(user);
    strat.depositWithPermit(amount, address(user), block.timestamp, v, r, s);
  }

  function testWithdrawShouldUnfarm() public {
    uint256 amount = 1;
    deal(address(asset), address(strat), amount);
    deal(address(strat), address(user), amount);

    vm.expectEmit(false, false, false, true, address(strat));
    emit FarmWithdraw(amount);

    vm.prank(user);
    strat.withdraw(amount, address(user), address(user));
  }

  function testEarnNothingHarvested() public {
    vm.expectRevert("StratX4: Nothing earned after fees collection");
    strat.earn(address(rewardToken), 1);
  }

  function testEarnNoProfit() public {
    uint256 earnedAmount = strat.minEarnedAmountToHarvest() - 1;
    deal(address(rewardToken), address(strat), earnedAmount);
    vm.mockCall(
      address(strat),
      abi.encodeWithSelector(MockStrat.mock__compound.selector),
      abi.encode(0)
    );
    vm.expectRevert("StratX4: Earn produces less than minAmountOut");
    strat.earn(address(rewardToken), 1);
  }

  function testEarn(uint96 earnedAmount, uint96 profit) public {
    strat.debug__warmFeesCollectable(address(rewardToken));
    uint256 minHarvest = strat.minEarnedAmountToHarvest();
    vm.assume(earnedAmount >= minHarvest && profit > 1);

    vm.expectEmit(false, false, false, true, address(strat));
    emit FarmHarvest();
    vm.expectEmit(false, false, false, false, address(strat));
    emit FeeSetAside(address(rewardToken), 0);
    vm.expectEmit(false, false, false, true, address(strat));
    emit FarmDeposit(profit - 1);
    vm.expectEmit(true, false, false, false, address(strat));
    emit Earn(address(rewardToken), 0, 0, 0);

    deal(address(rewardToken), address(strat), earnedAmount);

    vm.mockCall(
      address(strat),
      abi.encodeWithSelector(MockStrat.mock__compound.selector),
      abi.encode(profit)
    );
    strat.earn(address(rewardToken), 1);
  }

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
      uint256 expectedFee =
        uint256(harvested).mulDivUp(strat.feeRate(), strat.FEE_RATE_PRECISION());
      totalFees += expectedFee;

      vm.expectEmit(true, false, false, true, address(strat));
      emit FeeSetAside(address(rewardToken), expectedFee);

      // simulate harvest rewards
      deal(
        address(rewardToken),
        address(strat),
        rewardToken.balanceOf(address(strat)) + harvested
      );

      (uint256 earnedAmount, uint256 fee) =
        strat.public__handleFees(address(rewardToken));

      assertEq(fee, expectedFee, "fee should equal expected");
      assertEq(
        earnedAmount,
        harvested - expectedFee,
        "should return new earnedAmount less fees"
      );

      // Simulate compounding the rewards
      deal(
        address(rewardToken),
        address(strat),
        rewardToken.balanceOf(address(strat)) + expectedFee - harvested
      ); // simulate harvest rewards
    }

    assertEq(
      strat.feesCollectable(address(rewardToken)).get(),
      totalFees,
      "Collectible fees should add up"
    );

    // deal(address(rewardToken), feesController, 1); // simulate 1 wei optimization on feesController

    if (totalFees == 0) {
      vm.expectRevert("No fees collectable");
    }
    strat.collectFees(address(rewardToken));
    if (totalFees > 0) {
      assertEq(
        rewardToken.balanceOf(strat.feesController()),
        totalFees,
        "Rewards should be sent to feesController according to feeRate"
      );
      assertEq(
        strat.collectableFee(address(rewardToken)),
        1,
        "After collection there should be 1 wei left"
      );
    }
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

      deal(
        address(asset),
        address(farmContractAddress),
        asset.balanceOf(address(farmContractAddress)) + amount
      );
      strat.public__vestProfit(amount);

      (lastEarnBlock, profitsVesting) = strat.profitVesting();
      console2.log(block.number);

      assertEq(lastEarnBlock, currentBlock, "lastEarnBlock should be set");

      totalVesting += amount;
      totalVesting -= vestedSinceLastEarn;

      assertEq(profitsVesting, totalVesting, "profitsVesting should be set");
      assertEq(
        strat.vestingProfit(), totalVesting, "vestingProfit should be set"
      );

      assertEq(
        strat.totalAssets(),
        prevTotalAssets,
        "totalAssets should remain the same before and after"
      );
    }

    // Test vesting after earn
    vm.roll(currentBlock + strat.PROFIT_VESTING_PERIOD() / 2);
    assertEq(
      strat.totalAssets(),
      prevTotalAssets
        + totalVesting.mulDivDown(
          strat.PROFIT_VESTING_PERIOD() / 2, strat.PROFIT_VESTING_PERIOD()
        ),
      "totalAssets should increase linearly, rounded down"
    );
    assertEq(
      strat.vestingProfit(),
      totalVesting.mulDivUp(
        strat.PROFIT_VESTING_PERIOD() / 2, strat.PROFIT_VESTING_PERIOD()
      ),
      "vesting profit should be linear, rounded up"
    );

    vm.roll(currentBlock + strat.PROFIT_VESTING_PERIOD());
    assertEq(
      strat.totalAssets(),
      prevTotalAssets + totalVesting,
      "totalAssets should include vested profit"
    );
    assertEq(strat.vestingProfit(), 0, "profit should vest completely");

    vm.roll(currentBlock + strat.PROFIT_VESTING_PERIOD() * 2);
    assertEq(
      strat.totalAssets(),
      prevTotalAssets + totalVesting,
      "totalAssets should stay constant after vesting"
    );
  }

  function testDeprecate() public {
    assertGt(
      ERC20(asset).allowance(
        address(strat), address(strat.farmContractAddress())
      ),
      0
    );

    vm.expectEmit(false, false, false, true, address(strat));
    emit FarmEmergencyWithdraw();

    strat.deprecate();
    assertEq(
      ERC20(asset).allowance(
        address(strat), address(strat.farmContractAddress())
      ),
      0
    );
  }

  function testUndeprecate() public {
    strat.deprecate();

    uint256 assets = 1 ether;
    deal(address(asset), address(strat), assets);

    vm.expectEmit(false, false, false, true, address(strat));
    emit FarmDeposit(assets);

    strat.undeprecate();
    assertEq(
      ERC20(asset).allowance(
        address(strat), address(strat.farmContractAddress())
      ),
      type(uint256).max
    );
  }

  function testRescueOperationWhenNotDeprecated() public {
    address[] memory targets = new address[](0);
    bytes[] memory dataArr = new bytes[](0);

    vm.expectRevert("Pausable: not paused");
    strat.rescueOperation(targets, dataArr);
  }

  function testRescueOperation() public {
    strat.deprecate();
    address target = makeAddr("target");
    bytes memory data = bytes("data");

    address[] memory targets = new address[](1);
    bytes[] memory dataArr = new bytes[](1);

    targets[0] = target;
    dataArr[0] = data;

    vm.expectCall(target, data);
    strat.rescueOperation(targets, dataArr);
  }

  function testRescueOperationIllegalAddress() public {
    strat.deprecate();
    address target = address(asset);
    bytes memory data =
      abi.encodeCall(ERC20.transfer, (makeAddr("hacker"), 1 ether));

    address[] memory targets = new address[](1);
    bytes[] memory dataArr = new bytes[](1);

    targets[0] = target;
    dataArr[0] = data;

    vm.expectRevert("StratX4: Illegal target");
    strat.rescueOperation(targets, dataArr);
  }
}
