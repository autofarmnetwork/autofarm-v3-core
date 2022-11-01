// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {Authority} from "solmate/auth/Auth.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {
  SwapRoute, ZapLiquidityConfig
} from "../src/libraries/StratX4LibEarn.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockAuthority} from "./mocks/MockAuthority.sol";
import {IMasterchefV2} from "../src/interfaces/IMasterchefV2.sol";
import {StratX4Compounding} from "../src/StratX4Compounding.sol";
import {UniswapTestBase} from "./test-bases/UniswapTestBase.sol";

contract MockStrat is StratX4Compounding {
  constructor(
    address _asset,
    address _farmContractAddress,
    address _feesController,
    Authority _authority,
    address _mainRewardToken,
    bytes memory _mainCompoundConfigData
  )
  StratX4Compounding(
    _asset,
    _farmContractAddress,
    _feesController,
    _authority,
    _mainRewardToken,
    _mainCompoundConfigData
  )
  {}

  function _compound(
    address earnedAddress,
    uint256 earnedAmount,
    bytes memory compoundConfigData
  ) internal override returns (uint256) {
    return 1;
  }
  function _emergencyUnfarm() internal override {
  }
  function _farm(uint256 wantAmt) internal override {
  }
  function _harvestMainReward() internal override {
  }
  function _unfarm(uint256 wantAmt) internal override {
  }
  function lockedAssets() internal view override returns (uint256) {
  }
}

contract StratX4CompoundingTest is Test {

  ERC20 public asset = new MockERC20();
  ERC20 public mainRewardToken = new MockERC20();
  ERC20 public extraRewardToken = new MockERC20();
  ERC20 public unknownRewardToken = new MockERC20();
  address[] public illegalTargets;

  MockStrat public strat;

  function setUp() public {
    strat = new MockStrat(
      address(asset),
      makeAddr("farm"),
      makeAddr("feesController"),
      new MockAuthority(),
      address(mainRewardToken),
      "mock compound config"
    );
    illegalTargets.push(address(strat));
    illegalTargets.push(address(strat.asset()));
    illegalTargets.push(address(strat.farmContractAddress()));
    illegalTargets.push(address(strat.mainRewardToken()));
  }

  function testCompoundMainRewardToken(uint96 amountIn) public {
    vm.assume(amountIn > 1);
    deal(address(mainRewardToken), address(strat), amountIn);
    strat.earn(address(mainRewardToken), 1);
  }

  function testHarvestExtraRewardToken(uint96 amountIn) public {
    vm.assume(amountIn > 1);
    address target = makeAddr("target");
    bytes memory data = "data";
    strat.addHarvestConfig(
      address(extraRewardToken),
      target,
      data
    );
    strat.addEarnConfig(address(extraRewardToken), "mock compound config");

    deal(address(extraRewardToken), address(strat), amountIn);
    vm.expectCall(target, data);
    strat.earn(address(extraRewardToken), 1);
  }

  function testCompoundUnknownRewardToken(uint96 amountIn) public {
    vm.assume(amountIn > 1);
    deal(address(unknownRewardToken), address(strat), amountIn);
    vm.expectRevert(
      abi.encodeWithSelector(
        StratX4Compounding.CompoundConfigNotFound.selector,
        address(0)
      )
    );
    strat.earn(address(unknownRewardToken), 1);
  }

  function testAddIllegalRewardTokenCompoundConfig() public {
    for (uint256 i; i < illegalTargets.length; i++) {
      vm.expectRevert("Illegal earnedAddress");
      strat.addEarnConfig(illegalTargets[i], "mock compound config");
    }
  }

  function testAddIllegalRewardTokenHarvestConfigToken() public {
    for (uint256 i; i < illegalTargets.length; i++) {
      vm.expectRevert("Illegal earnedAddress");
      strat.addEarnConfig(illegalTargets[i], "mock compound config");
    }
  }

  function testAddIllegalRewardTokenHarvestConfigTarget() public {
    for (uint256 i; i < illegalTargets.length; i++) {
      vm.expectRevert("Illegal call target");
      strat.addHarvestConfig(address(unknownRewardToken), illegalTargets[i], "mock calldata");
    }
  }
}
