// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {UniswapV2TestBase} from "./test-bases/UniswapV2TestBase.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {
  MultiRolesAuthority,
  Authority
} from "solmate/auth/authorities/MultiRolesAuthority.sol";

import {UniswapV2Helper} from "../src/libraries/UniswapV2Helper.sol";
import {Roles} from "../src/auth/Auth.sol";
import {AutofarmFeesController} from "../src/FeesController.sol";

contract FeesControllerTestBase is UniswapV2TestBase {
  AutofarmFeesController public feesController;

  address public treasury = makeAddr("treasury");
  address public sav = makeAddr("sav");
  address public deployer = makeAddr("deployer");
  address public keeper = makeAddr("keeper");

  function setUp() public virtual {
    MultiRolesAuthority auth =
      new MultiRolesAuthority(address(this), Authority(address(0)));
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
    uint256[] memory feeFactors = new uint256[](1);

    (pairsPath[0],) = addLiquidity(
      address(rewardToken), address(AUTOv2), 1 ether, 1 ether, address(0)
    );
    tokensPath[0] = address(AUTOv2);
    feeFactors[0] = 9970;

    UniswapV2Helper.SwapRoute memory swapRoute = UniswapV2Helper.SwapRoute({
      pairsPath: pairsPath,
      tokensPath: tokensPath,
      feeFactors: feeFactors
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
