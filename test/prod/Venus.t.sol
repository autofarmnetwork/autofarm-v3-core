// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {MockAuthority} from "../mocks/MockAuthority.sol";
import {LibString} from "solmate/utils/LibString.sol";
import {MultiRolesAuthority} from
  "solmate/auth/authorities/MultiRolesAuthority.sol";

import {AutofarmFeesController} from "../../src/FeesController.sol";
import {StratX4Venus} from "../../src/implementations/Venus.sol";
import {
  VenusStratConfigJsonLib,
  EarnConfig
} from "../../src/json-parsers/VenusStratConfigJsonLib.sol";

string constant STRAT_CONFIG_FILE = "/vaults-config/bsc/venus-USDC.json";

contract DeployStrat is Test {
  using stdJson for string;

  StratX4Venus public strat;

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl("bsc"));
    deployStrat();
  }

  function deployStrat() internal {
    string memory root = vm.projectRoot();
    string memory path = string.concat(root, STRAT_CONFIG_FILE);
    string memory json = vm.readFile(path);

    (
      address asset,
      address farmContractAddress,
      EarnConfig[] memory earnConfigs
    ) = VenusStratConfigJsonLib.load(vm, json);

    strat = new StratX4Venus(
      asset,
      vm.envAddress("FEES_CONTROLLER_ADDRESS"),
      MultiRolesAuthority(vm.envAddress("AUTHORITY_ADDRESS")),
      farmContractAddress,
      earnConfigs[0].rewardToken,
      earnConfigs[0].swapRoute
    );
    for (uint256 i = 1; i < earnConfigs.length; i++) {
      strat.addEarnConfig(
        earnConfigs[i].rewardToken, abi.encode(earnConfigs[i].swapRoute)
      );
    }
  }

  function testDepositAndWithdraw(uint96 amountIn, uint96 amountOut) public {
    vm.assume(amountIn > 1e18);

    deal(address(strat.asset()), address(this), amountIn);
    strat.asset().approve(address(strat), type(uint256).max);
    uint256 initialBalance = strat.asset().balanceOf(address(this));

    strat.deposit(amountIn, address(this));

    uint256 shares = ERC20(address(strat)).balanceOf(address(this));
    uint256 balance = strat.asset().balanceOf(address(this));
    amountOut = uint96(bound(amountOut, 1e16, strat.totalAssets()));

    assertApproxEqRel(
      strat.totalAssets(), amountIn, 0.1e18, "totalAssets must increase"
    );
    assertEq(shares, amountIn, "shares must be minted");
    assertEq(initialBalance - balance, amountIn, "user balance must decrease");

    strat.withdraw(amountOut, address(this), address(this));
    shares = ERC20(address(strat)).balanceOf(address(this));
    balance = strat.asset().balanceOf(address(this));
    // TODO: restore
    assertApproxEqRel(
      shares, amountIn - amountOut, 0.1e18, "remaining shares wonky"
    );
    assertApproxEqRel(balance, amountOut, 0.1e18, "final balance wonky");
  }

  function testEarn() public {
    deal(address(strat.mainRewardToken()), address(strat), 1 ether);

    address rewardToken = strat.mainRewardToken();
    vm.prank(vm.envAddress("KEEPER_ADDRESS"));
    (uint256 compoundedAssets,,) = strat.earn(rewardToken, 1);
    assertGt(compoundedAssets, 0, "earn harvests less than expected harvest");
  }

  function testHarvestAndEarn() public {
    uint256 amountIn = 1e18;
    deal(address(strat.asset()), address(this), amountIn);
    strat.asset().approve(address(strat), type(uint256).max);
    strat.deposit(amountIn, address(this));
    vm.roll(block.number + 5000);

    address rewardToken = strat.mainRewardToken();
    vm.prank(vm.envAddress("KEEPER_ADDRESS"));
    (uint256 compoundedAssets,,) = strat.earn(rewardToken, 1);
    assertGt(compoundedAssets, 0, "earn harvests less than expected harvest");
  }

  /*
  function testLeverage() public {
    uint256 amountIn = 1e18;

    deal(address(strat.asset()), address(this), amountIn);
    strat.asset().approve(address(strat), type(uint256).max);
    uint256 initialBalance = strat.asset().balanceOf(address(this));

    strat.deposit(amountIn, address(this));

    uint256 shares = ERC20(address(strat)).balanceOf(address(this));
    uint256 balance = strat.asset().balanceOf(address(this));
    strat.leverage();
    strat.leverage();
    vm.roll(block.number + 1000);
  }

  function testGetRate() public {
    uint256 borrowRate = strat.getBorrowRateAtLeverageDepth(0.9e18, 2);
    emit log_named_decimal_uint("borrowRate", borrowRate, 18);
  }
  */
}
