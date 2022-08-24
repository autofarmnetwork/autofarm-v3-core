// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "solmate/tokens/ERC20.sol";
import {Authority} from "solmate/auth/Auth.sol";
import {MultiRolesAuthority} from
  "solmate/auth/authorities/MultiRolesAuthority.sol";
import {Roles, Configurer, deployer, keeper} from "../src/auth/Auth.sol";
import {AutofarmFeesController} from "../src/FeesController.sol";
import "constants/tokens.sol";
import "constants/chains.sol";

/*
Requirements:
Happy Paths:
	- Forwards fees to platform, SAV, and burn
Sad Paths:
  - Unexpected funds
*/

address constant biswapFactory = 0x858E3312ed3A876947EA49d572A7C42DE08af7EE;
address constant biswapRouter = 0x3a6d8cA21D1CF76F653A67577FA0D27453350dD8;
uint256 constant biswapSwapFee = 9980;

address constant treasury = 0x8f95f25ff3eCb84e83B8DEd75670e377484FC5A8;
address constant SAV = 0xFaBbf2Ae3E337f7442fDaB0483226A6B977A6432;

contract StratX4FeesWithoutConfigTest is Test {
  AutofarmFeesController public feesController;

  function setUp() public {
    vm.createSelectFork(BSC_RPC_URL);
    MultiRolesAuthority auth = Configurer.createAuthority();
    auth.setUserRole(keeper, uint8(Roles.Keeper), true);
    feesController = new AutofarmFeesController(
     auth,
     treasury,
     SAV,
     address(0), // voting controller
     64,
     0
    );
  }

  function testForwardFeesWithoutFirstAddingRewardCfgRevert() public {
    vm.prank(keeper);
    vm.expectRevert(bytes("FeesController: RewardCfg uninitialized"));
    feesController.forwardFees(ERC20(BSW), 0);
  }
}

contract StratX4FeesTest is Test {
  AutofarmFeesController public feesController;

  function setUp() public {
    vm.createSelectFork(BSC_RPC_URL);
    MultiRolesAuthority auth = Configurer.createAuthority();
    auth.setUserRole(keeper, uint8(Roles.Keeper), true);
    auth.setUserRole(deployer, uint8(Roles.Gov), true);
    auth.setOwner(deployer);
    // Configurer.addUser(auth, Roles.Dev, address(this));
    feesController = new AutofarmFeesController(
  	auth,
  	treasury,
  	SAV,
  	address(0), // voting controller
  	64,
  	0
  );

    AutofarmFeesController.SwapConfig[] memory pathToAUTO =
      new AutofarmFeesController.SwapConfig[](2);
    pathToAUTO[0] = AutofarmFeesController.SwapConfig({
      pair: BSW_BNB_PAIR,
      swapFee: biswapSwapFee,
      tokenOut: WBNB
    });
    pathToAUTO[1] = AutofarmFeesController.SwapConfig({
      pair: WBNB_AUTO_PAIR,
      swapFee: biswapSwapFee,
      tokenOut: AUTO
    });
    vm.prank(deployer);
    feesController.setRewardCfg(BSW, pathToAUTO);
  }

  function testForwardFeesWhenNoRewardsRevert() public {
    vm.prank(keeper);
    vm.expectRevert(bytes("FeesController: No fees to platform"));
    feesController.forwardFees(ERC20(BSW), 0);
  }

  function testForwardFees(uint96 rewardsAmt) public {
    vm.assume(rewardsAmt > 1e6);
    deal(BSW, address(feesController), rewardsAmt);

    uint256 initialTreasuryBalance = ERC20(BSW).balanceOf(treasury);
    uint256 initialSAVBalance = ERC20(AUTO).balanceOf(SAV);

    vm.prank(keeper);
    feesController.forwardFees(ERC20(BSW), 0);

    assertGt(ERC20(BSW).balanceOf(treasury), initialTreasuryBalance);
    assertGt(ERC20(AUTO).balanceOf(SAV), initialSAVBalance);
  }
}