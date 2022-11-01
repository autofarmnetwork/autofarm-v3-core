// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import "forge-std/Test.sol";
import "forge-std/console2.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {MockAuthority} from "../test/mocks/MockAuthority.sol";
import {LibString} from "solmate/utils/LibString.sol";
import {MultiRolesAuthority} from
  "solmate/auth/authorities/MultiRolesAuthority.sol";

import {AutofarmFeesController} from "../src/FeesController.sol";
import {StratX4MinichefLP1} from "../src/implementations/MinichefLP1.sol";
import {
  SwapRoute, ZapLiquidityConfig
} from "../src/libraries/StratX4LibEarn.sol";
import {
  StratConfigJsonLib,
  EarnConfig
} from "../src/json-parsers/StratConfigJsonLib.sol";

contract DeployStrat is Script {
  using stdJson for string;

  StratX4MinichefLP1 public strat;

  function run() public {
    vm.startBroadcast();
    deployStrat();
    vm.stopBroadcast();
  }

  function deployStrat() internal {
    string memory root = vm.projectRoot();
    string memory path = string.concat(root, vm.envString("STRAT_CONFIG_FILE"));
    string memory json = vm.readFile(path);

    (
      address asset,
      address farmContractAddress,
      uint256 pid,
      EarnConfig[] memory earnConfigs
    ) = StratConfigJsonLib.load(vm, json);

    strat = new StratX4MinichefLP1(
      asset,
      vm.envAddress("FEES_CONTROLLER_ADDRESS"),
      MultiRolesAuthority(vm.envAddress("AUTHORITY_ADDRESS")),
      farmContractAddress,
      pid,
      earnConfigs[0].rewardToken,
      earnConfigs[0].swapRoute,
      earnConfigs[0].zapLiquidityConfig
    );
    for (uint256 i = 1; i < earnConfigs.length; i++) {
      strat.addEarnConfig(
        earnConfigs[i].rewardToken,
        abi.encode(
          earnConfigs[i].swapRoute,
          earnConfigs[i].zapLiquidityConfig
        )
      );
    }
  }

  /*
  function setUp() public {
    vm.createSelectFork(vm.rpcUrl(vm.envString("CHAIN")));
    vm.startPrank(vm.addr(vm.envUint("PRIVATE_KEY")));
    // deployStrat();
    vm.stopPrank();
  }

  function testDepositAndWithdrawal(uint96 amountIn, uint96 amountOut) public {
    vm.assume(amountIn > 0);
    amountOut = uint96(bound(amountOut, 0, amountIn));

    deal(address(strat.asset()), address(this), type(uint256).max);
    strat.asset().approve(address(strat), type(uint256).max);
    uint256 initialBalance = strat.asset().balanceOf(address(this));

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

  function testEarnMain() public {
    address rewardToken = strat.mainRewardToken();
    deal(rewardToken, address(strat), 1 ether);

    vm.prank(vm.envAddress("KEEPER_ADDRESS"));
    uint256 compoundedAssets = strat.earn(rewardToken, 1);
    assertGt(compoundedAssets, 0, "earn harvests less than expected harvest");
  }

  function testEarnExtra() public {
    address rewardToken = 0xD4949664cD82660AaE99bEdc034a0deA8A0bd517;
    deal(rewardToken, address(strat), 1 ether);

    vm.prank(vm.envAddress("KEEPER_ADDRESS"));
    uint256 compoundedAssets = strat.earn(rewardToken, 1);
    assertGt(compoundedAssets, 0, "earn harvests less than expected harvest");
  }
*/
}
