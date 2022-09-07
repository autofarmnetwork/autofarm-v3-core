// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import "forge-std/console2.sol";

import {Roles, Configurer, keeper, deployer} from "../src/auth/Auth.sol";
import "solmate/tokens/ERC20.sol";
import {MultiRolesAuthority} from "solmate/auth/authorities/MultiRolesAuthority.sol";
import {FeeConfig} from "../src/StratX4.sol";
import {SwapConfig, LP1EarnConfig} from "../src/libraries/StratX4LibEarn.sol";
import {StratX4} from "../src/StratX4.sol";
import {AutofarmFeesController} from "../src/FeesController.sol";

/*
Requirements:
Happy Paths:
	- Deposit & Withdraw
	- Earn
	- Fees
	- Deprecate
	- Roles: keeper, dev
	- Rescue operations
Sad Paths:
  - Withdrawal above user's shares
  - Users' balances after other's deposits, withdrawals, and earn must go up 
  - Reentrancy
	- Farm rugs
	- Farm returns less
	- Farm returns another token
	- Earn problems:
	  - Overlapping vestings
Edge cases:
  - Unexpected funds transfered into strat
*/

address constant biswapFactory = 0x858E3312ed3A876947EA49d572A7C42DE08af7EE;
address constant biswapRouter = 0x3a6d8cA21D1CF76F653A67577FA0D27453350dD8;
address constant biswapFarm = 0xDbc1A13490deeF9c3C12b44FE77b503c1B061739;
uint256 constant biswapWBNBAUTOpid = 87;
uint256 constant biswapSwapFee = 9990;

address constant treasury = 0x8f95f25ff3eCb84e83B8DEd75670e377484FC5A8;
address constant SAV = 0xFaBbf2Ae3E337f7442fDaB0483226A6B977A6432;

uint256 constant RANDOM_SEED_1 = 223123479866;

abstract contract StratX4TestBase is Test {
  uint256 constant FEE_RATE = 3e16;
  MultiRolesAuthority auth;
  address feesController;
  FeeConfig defaultFeeConfig;
  StratX4 public strat;

  constructor(string memory chain, uint256 blockNumber) {
    vm.createSelectFork(vm.rpcUrl(chain), blockNumber);
    feesController = vm.addr(RANDOM_SEED_1);
    defaultFeeConfig = FeeConfig({feeRate: FEE_RATE, feesController: feesController});
    auth = Configurer.createAuthority(address(this));
    auth.setUserRole(keeper, uint8(Roles.Keeper), true);
    auth.setUserRole(deployer, uint8(Roles.Guardian), true);
    auth.setUserRole(deployer, uint8(Roles.Dev), true);
  }
}

abstract contract StratX4UserTest is StratX4TestBase {
  uint256 internal initialBalance;

  function setUp() public {
    deal(address(strat.asset()), address(this), type(uint256).max);
    strat.asset().approve(address(strat), type(uint256).max);
    initialBalance = strat.asset().balanceOf(address(this));
  }

  function testDepositAndWithdrawal(uint96 amountIn, uint96 amountOut) public {
    vm.assume(amountIn > 0);
    amountOut = uint96(bound(amountOut, 0, amountIn));

    strat.deposit(amountIn, address(this));

    uint256 shares = ERC20(address(strat)).balanceOf(address(this));
    uint256 balance = strat.asset().balanceOf(address(this));
    assertEq(shares, amountIn);
    assertEq(initialBalance - balance, amountIn);

    strat.withdraw(amountOut, address(this), address(this));
    shares = ERC20(address(strat)).balanceOf(address(this));
    balance = strat.asset().balanceOf(address(this));
    assertEq(shares, amountIn - amountOut);
    assertEq(balance, initialBalance - amountIn + amountOut);
  }

  function testUnexpectedFunds(uint96 amountIn, uint96 amountOut) public {
    vm.assume(amountIn > 0);
    amountOut = uint96(bound(amountOut, 0, amountIn));

    strat.deposit(amountIn, address(this));

    uint256 shares = ERC20(address(strat)).balanceOf(address(this));
    uint256 balance = strat.asset().balanceOf(address(this));
    assertEq(shares, amountIn);
    assertEq(initialBalance - balance, amountIn);

    // Unexpected transfer into strat
    deal(address(strat.asset()), address(strat), 10 ether);

    strat.withdraw(amountOut, address(this), address(this));
    shares = ERC20(address(strat)).balanceOf(address(this));
    balance = strat.asset().balanceOf(address(this));
    assertGe(shares, amountIn - amountOut);
    assertGe(balance, initialBalance - amountIn + amountOut);
  }

  function testWithdrawalWhenPaused(uint96 amountIn, uint96 amountOut) public {
    vm.assume(amountIn > 0);
    amountOut = uint96(bound(amountOut, 0, amountIn));

    strat.deposit(amountIn, address(this));

    uint256 shares = ERC20(address(strat)).balanceOf(address(this));
    uint256 balance = strat.asset().balanceOf(address(this));
    assertEq(shares, amountIn);
    assertEq(initialBalance - balance, amountIn);

    vm.prank(deployer);
    strat.pause();

    strat.withdraw(amountOut, address(this), address(this));
    shares = ERC20(address(strat)).balanceOf(address(this));
    balance = strat.asset().balanceOf(address(this));
    assertEq(shares, amountIn - amountOut);
    assertEq(balance, initialBalance - amountIn + amountOut);
  }
}

abstract contract StratX4EarnTest is StratX4TestBase {
  uint256 constant aprDetectionBlocks = 1e3;
  uint256 constant earnTxCost = 330000 * 5 gwei;
  uint256 constant tvl = 282150047013890714705;

  uint256 internal interestPerBlock;
  uint256 internal blocksBetweenCompounds;
  uint256 internal expectedHarvest;
  uint256 internal pendingRewards;

  function setUp() public {
    deal(address(strat.asset()), address(this), tvl);
    strat.asset().approve(address(strat), tvl);
    strat.deposit(tvl, address(this));

    vm.roll(block.number + aprDetectionBlocks);
    uint256 testHarvest = strat.pendingRewards() * strat.rewardToWant();
    interestPerBlock = testHarvest / tvl / aprDetectionBlocks;
    console2.log("detected APR per block", interestPerBlock, interestPerBlock * 60 * 60 * 24 * 365 / 3 / 1e14);

    uint256 nextEarnBlock = strat.nextOptimalEarnBlock(interestPerBlock, earnTxCost);
    blocksBetweenCompounds = nextEarnBlock - block.number;
    vm.roll(nextEarnBlock);
    pendingRewards = strat.pendingRewards();
    assertGt(pendingRewards, 0);
    expectedHarvest = pendingRewards * strat.rewardToWant() / 1e18;

    console2.log("blocks between earns", blocksBetweenCompounds, blocksBetweenCompounds * 3 / 60 / 60 / 24);
    console2.log("pendingRewards", strat.pendingRewards());
    console2.log("expected harvest", expectedHarvest);
  }

  function testEarn() public {
    vm.prank(keeper);
    uint256 compoundedAssets = strat.earn();
    console2.log(compoundedAssets);
    assertGe(compoundedAssets, expectedHarvest * 920 / 1000, "earn harvests less than expected harvest");
  }

  function testFeesDepositedIntoController() public {
    vm.prank(keeper);
    strat.earn();
    ERC20 rewardToken = ERC20(strat.getEarnedAddress(0));
    assertGe(rewardToken.balanceOf(address(feesController)), pendingRewards * FEE_RATE / 1e18);
  }

  function testHarvestVesting() public {
    uint256 totalAssetsBeforeEarn = strat.totalAssets();
    vm.prank(keeper);
    uint256 compoundedAssets = strat.earn();
    assertEq(strat.profitsVesting(), compoundedAssets, "vesting harvest less than compounded amount");
    assertEq(strat.totalAssets(), totalAssetsBeforeEarn, "totalAssets should not change right after earn");
    vm.roll(block.number + strat.profitVestingPeriod());
    assertEq(
      strat.totalAssets(), strat.profitsVesting() + totalAssetsBeforeEarn, "harvests did not vest within vesting period"
    );
  }

  function testEarnAfterFeesChange() public {
    vm.prank(keeper);
    uint256 compoundedAssets = strat.earn();
    console2.log(compoundedAssets);
    assertGe(compoundedAssets, expectedHarvest * 920 / 1000, "earn harvests less than expected harvest");
  }

  function testEarnByUnauthorizedRevert() public {
    vm.prank(address(123));
    vm.expectRevert(bytes("UNAUTHORIZED"));
    strat.earn();
  }
}
