// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {MockERC20} from "./mocks/MockERC20.sol";
import {
  SwapRoute,
  ZapLiquidityConfig,
  StratX4LibEarn
} from "../src/libraries/StratX4LibEarn.sol";
import {UniswapTestBase} from "./test-bases/UniswapTestBase.sol";

contract StratX4LibEarnTest is UniswapTestBase {
  ERC20 public tokenA;
  ERC20 public tokenB;
  ERC20 public tokenC;

  address public pairAB;
  address public pairAC;

  function setUp() public {
    tokenA = new MockERC20();
    tokenB = new MockERC20();
    tokenC = new MockERC20();

    address pair = factory.createPair(address(tokenA), address(tokenB));
    pairAC = factory.createPair(address(tokenA), address(tokenC));
    pairAB = pair;

    addLiquidity(address(tokenA), address(tokenB), 1 ether, 1 ether, address(0));
    addLiquidity(address(tokenA), address(tokenC), 1 ether, 1 ether, address(0));

    deal(address(tokenC), address(this), type(uint256).max);

    // Comment on/off these wei to check gas optimization
    deal(address(tokenA), address(this), 1);
    deal(address(tokenB), address(this), 1);
    deal(pairAB, address(this), 1);
  }

  // C -> Pair(A, B)
  function testSwapExactTokensForLiquidity1(uint96 amountIn) public {
    vm.assume(amountIn > 1e4);

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

    uint256 amountOut = StratX4LibEarn.swapExactTokensToLiquidity1(
      address(tokenC), pairAB, amountIn, swapRoute, zapLiquidityConfig
    );

    assertEq(
      ERC20(pairAB).balanceOf(address(this)),
      amountOut + 1,
      "output balance should be positive"
    );
    assertGt(tokenA.balanceOf(address(this)), 1, "tokenA balance should be 1");
    assertGt(tokenB.balanceOf(address(this)), 1, "tokenB balance should be 1");
    assertGt(tokenC.balanceOf(address(this)), 1, "tokenC balance should be 1");
  }

  function getPairSwapFee(address) internal returns (uint256) {
    return 9970;
  }

  function testSwapExactTokensForLiquidity1WithDynamicFees(uint96 amountIn)
    public
  {
    vm.assume(amountIn > 1e4);

    // For gas optimization check
    uint256 initialOutBalance = ERC20(pairAB).balanceOf(address(this));

    uint256[] memory swapFees = new uint256[](1);
    swapFees[0] = 0;
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

    uint256 amountOut = StratX4LibEarn
      .swapExactTokensToLiquidity1WithDynamicFees(
      address(tokenC),
      pairAB,
      amountIn,
      swapRoute,
      zapLiquidityConfig,
      getPairSwapFee
    );

    assertEq(
      ERC20(pairAB).balanceOf(address(this)),
      amountOut + initialOutBalance,
      "output balance should be positive"
    );
    assertGe(tokenA.balanceOf(address(this)), 1, "tokenA balance should be +ve");
    assertGe(tokenB.balanceOf(address(this)), 1, "tokenB balance should be +ve");
    assertGe(tokenC.balanceOf(address(this)), 1, "tokenC balance should be +ve");
  }
}
