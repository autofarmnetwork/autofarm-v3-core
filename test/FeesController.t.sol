// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {UniswapTestBase} from "./test-bases/UniswapTestBase.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

import {SwapRoute} from "../src/libraries/StratX4LibEarn.sol";
import {Roles, AutofarmAuthority} from "../src/auth/Auth.sol";
import {AutofarmFeesController} from "../src/FeesController.sol";

contract FeesControllerTestBase is UniswapTestBase {
  AutofarmFeesController public feesController;

  address public treasury = makeAddr("treasury");
  address public sav = makeAddr("sav");
  address public deployer = makeAddr("deployer");
  address public keeper = makeAddr("keeper");

  function setUp() public virtual {
    AutofarmAuthority auth = new AutofarmAuthority(address(this));
    auth.setUserRole(keeper, uint8(Roles.Keeper), true);
    auth.setUserRole(deployer, uint8(Roles.Gov), true);
    feesController = new AutofarmFeesController(
      auth,
      treasury,
      sav,
      64,
      0
    );
  }
}

contract FeesControllerWithoutConfigTest is FeesControllerTestBase {
  function testForwardFeesWithoutFirstAddingRewardCfgRevert() public {
    vm.prank(keeper);
    vm.expectRevert(bytes("FeesController: RewardCfg uninitialized"));
    feesController.forwardFees(makeAddr("Unknown token"), 0);
  }
}

contract FeesControllerTest is FeesControllerTestBase {
  ERC20 public rewardToken;
  ERC20 public AUTOv2;

  function setUp() public override {
    super.setUp();
    rewardToken = new MockERC20();
    address AUTOv2Address = feesController.AUTOv2();
    vm.etch(AUTOv2Address, address(new MockERC20()).code);
    AUTOv2 = MockERC20(AUTOv2Address);

    address[] memory pairsPath = new address[](1);
    address[] memory tokensPath = new address[](1);
    uint256[] memory swapFees = new uint256[](1);

    pairsPath[0] = addLiquidity(
      address(rewardToken), address(AUTOv2), 1 ether, 1 ether, address(0)
    );
    tokensPath[0] = address(AUTOv2);
    swapFees[0] = 9970;

    SwapRoute memory swapRoute = SwapRoute({
      pairsPath: pairsPath,
      tokensPath: tokensPath,
      swapFees: swapFees
    });

    vm.prank(deployer);
    feesController.setRewardCfg(address(rewardToken), swapRoute);
  }

  function testForwardFeesWhenNoRewardsRevert() public {
    vm.prank(keeper);
    vm.expectRevert(bytes("FeesController: No fees to platform"));
    feesController.forwardFees(address(rewardToken), 0);
  }

  function testForwardFees(uint96 rewardsAmt) public {
    vm.assume(rewardsAmt > 1e6);
    deal(address(rewardToken), address(feesController), rewardsAmt);

    uint256 initialTreasuryBalance = rewardToken.balanceOf(treasury);
    uint256 initialSAVBalance = AUTOv2.balanceOf(feesController.SAV());

    vm.prank(keeper);
    feesController.forwardFees(address(rewardToken), 0);

    assertGt(
      rewardToken.balanceOf(treasury),
      initialTreasuryBalance,
      "Treasury balance did not increase"
    );
    assertGt(
      AUTOv2.balanceOf(feesController.SAV()),
      initialSAVBalance,
      "SAV balance did not increase"
    );
  }
}
