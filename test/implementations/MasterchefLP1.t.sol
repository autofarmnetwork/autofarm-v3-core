// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {Authority} from "solmate/auth/Auth.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {
  SwapRoute, ZapLiquidityConfig
} from "../../src/libraries/StratX4LibEarn.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockAuthority} from "../mocks/MockAuthority.sol";
import {IMasterchefV2} from "../../src/interfaces/IMasterchefV2.sol";
import {StratX4MasterchefLP1} from "../../src/implementations/MasterchefLP1.sol";
import {UniswapTestBase} from "../test-bases/UniswapTestBase.sol";

contract MasterchefLP1Test is UniswapTestBase {
  address public asset;

  ERC20 public tokenA;
  ERC20 public tokenB;
  ERC20 public tokenC;
  ERC20 public tokenD;

  address public pairAC;
  address public pairAD;

  StratX4MasterchefLP1 public strat;

  function setUp() public {
    tokenA = new MockERC20();
    tokenB = new MockERC20();
    tokenC = new MockERC20();
    tokenD = new MockERC20();
    address pair = factory.createPair(address(tokenA), address(tokenB));
    asset = pair;

    addLiquidity(
      address(tokenA),
      address(tokenB),
      1 ether, // amountTokenDesired
      1 ether, // amountTokenDesired
      address(0) // to
    );

    pairAC = addLiquidity(
      address(tokenC),
      address(tokenA),
      1 ether, // amountTokenDesired
      1 ether, // amountTokenDesired
      address(0) // to
    );

    deal(address(tokenC), address(this), type(uint256).max);
    deal(address(tokenA), address(this), 1);
    deal(address(tokenB), address(this), 1);
    deal(asset, address(this), 1);
    assertEq(
      ERC20(asset).balanceOf(address(this)),
      1,
      "initial output balance should be 1"
    );

    uint256[] memory swapFees = new uint256[](1);
    swapFees[0] = 9970;
    address[] memory pairsPath = new address[](1);
    pairsPath[0] = pairAC;
    address[] memory tokensPath = new address[](1);
    tokensPath[0] = address(tokenA);

    SwapRoute memory swapRoute = SwapRoute({
      swapFees: swapFees,
      pairsPath: pairsPath,
      tokensPath: tokensPath
    });
    ZapLiquidityConfig memory zapLiquidityConfig = ZapLiquidityConfig({
      swapFee: 9970,
      lpSubtokenIn: address(tokenA),
      lpSubtokenOut: address(tokenB)
    });

    strat = new StratX4MasterchefLP1(
      asset,
      makeAddr("feesController"),
      new MockAuthority(),
      makeAddr("farm"),
      0,
      address(tokenC),
      swapRoute,
      zapLiquidityConfig
    );

    pairAD = addLiquidity(
      address(tokenD),
      address(tokenA),
      1 ether, // amountTokenDesired
      1 ether, // amountTokenDesired
      address(0) // to
    );

    swapFees = new uint256[](1);
    swapFees[0] = 9970;
    pairsPath = new address[](1);
    pairsPath[0] = pairAD;
    tokensPath = new address[](1);
    tokensPath[0] = address(tokenA);
    swapRoute = SwapRoute({
      swapFees: swapFees,
      pairsPath: pairsPath,
      tokensPath: tokensPath
    });
    zapLiquidityConfig = ZapLiquidityConfig({
      swapFee: 9970,
      lpSubtokenIn: address(tokenA),
      lpSubtokenOut: address(tokenB)
    });

    strat.addEarnConfig(address(tokenD), abi.encode(swapRoute, zapLiquidityConfig));
  }

  function testEarn(uint96 amountIn) public {
    vm.assume(amountIn > 1e4);
    vm.mockCall(
      strat.farmContractAddress(),
      abi.encodeWithSelector(IMasterchefV2.withdraw.selector),
      ""
    );
    vm.mockCall(
      strat.farmContractAddress(),
      abi.encodeWithSelector(IMasterchefV2.deposit.selector),
      ""
    );
    deal(address(tokenC), address(strat), amountIn);
    strat.earn(address(tokenC), 1);
  }

  function testEarnAdditionalRewards(uint96 amountIn) public {
    vm.assume(amountIn > 1e4);
    vm.mockCall(
      strat.farmContractAddress(),
      abi.encodeWithSelector(IMasterchefV2.withdraw.selector),
      ""
    );
    vm.mockCall(
      strat.farmContractAddress(),
      abi.encodeWithSelector(IMasterchefV2.deposit.selector),
      ""
    );
    deal(address(tokenD), address(strat), amountIn);
    strat.earn(address(tokenD), 1);
  }
}
