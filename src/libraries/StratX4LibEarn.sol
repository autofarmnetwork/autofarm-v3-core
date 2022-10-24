// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {SSTORE2} from "solmate/utils/SSTORE2.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router02} from
  "@uniswap/v2-periphery/interfaces/IUniswapV2Router02.sol";

import {Uniswap} from "./Uniswap.sol";

/*
 * StratX4LibEarn
 * - Swaps reward tokens into asset tokens.
 * - Responsible for all vault earns?
 *
 * LP Strategies
 * -. No swaps: Reward and asset tokens are the same
 * 0. Asset is TOKEN-REWARD LP: do one side swap liquidity
 * 1. Asset is BASE-TOKEN LP: swap token to BASE and do one side liquidity
 * 2. (Optional) Asset is TOKEN-TOKEN: Swap to base(s) and buy tokens separately
 *    (does not pass the asset LP)
 * Steps:
 * Convert reward to some base token
 * if base is one of token0 or token1: convert base token one sided
 * - swap using asset LP
 * - swap using another LP
 * if base is not in LP: convert to token0 and token1
 * - swap using other LPs
 */

struct SwapRoute {
  address[] pairsPath;
  address[] tokensPath;
  uint256[] swapFees; // set to 0 if dynamic
}

struct ZapLiquidityConfig {
  address lpSubtokenIn;
  address lpSubtokenOut;
  uint256 swapFee; // set to 0 if dynamic
}

interface IUniswapV2PairDynamicFee {
  function swapFee() external view returns (uint32);
}

library StratX4LibEarn {
  using SafeTransferLib for ERC20;

  function swapExactTokensForTokens(
    address tokenIn,
    uint256 amountIn,
    uint256[] memory swapFees,
    address[] memory pairsPath,
    address[] memory tokensPath
  ) internal returns (uint256 amountOut) {
    require(pairsPath.length > 0);

    amountOut = amountIn;
    ERC20(tokenIn).safeTransfer(pairsPath[0], amountIn);

    for (uint256 i; i < pairsPath.length;) {
      amountOut = Uniswap._swap(
        pairsPath[i],
        swapFees[i],
        i == 0 ? tokenIn : tokensPath[i - 1],
        tokensPath[i],
        amountOut,
        i == pairsPath.length - 1 ? address(this) : pairsPath[i + 1]
      );
      unchecked {
        i++;
      }
    }
  }

  function swapExactTokensToLiquidity1(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    SwapRoute memory swapRoute,
    ZapLiquidityConfig memory zapLiquidityConfig
  ) internal returns (uint256 amountOut) {
    // sanity checks

    // Swap to reserve tokenIn
    if (swapRoute.pairsPath.length > 0) {
      amountOut = swapExactTokensForTokens(
        tokenIn,
        amountIn,
        swapRoute.swapFees,
        swapRoute.pairsPath,
        swapRoute.tokensPath
      );
    } else {
      amountOut = amountIn;
    }

    amountOut -= 1;

    (uint256 swapAmount, uint256 tokenAmountOut) = Uniswap.calcSimpleZap(
      tokenOut,
      zapLiquidityConfig.swapFee,
      amountOut,
      zapLiquidityConfig.lpSubtokenIn,
      zapLiquidityConfig.lpSubtokenOut
    );

    ERC20(zapLiquidityConfig.lpSubtokenIn).safeTransfer(tokenOut, swapAmount);
    if (zapLiquidityConfig.lpSubtokenIn < zapLiquidityConfig.lpSubtokenOut) {
      IUniswapV2Pair(tokenOut).swap(0, tokenAmountOut, address(this), "");
    } else {
      IUniswapV2Pair(tokenOut).swap(tokenAmountOut, 0, address(this), "");
    }
    tokenAmountOut -= 1;
    ERC20(zapLiquidityConfig.lpSubtokenIn).safeTransfer(
      tokenOut, amountOut - swapAmount
    );
    ERC20(zapLiquidityConfig.lpSubtokenOut).safeTransfer(
      tokenOut, tokenAmountOut
    );
    amountOut = IUniswapV2Pair(tokenOut).mint(address(this));
  }

  function swapExactTokensToLiquidity1WithDynamicFees(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    SwapRoute memory swapRoute,
    ZapLiquidityConfig memory zapLiquidityConfig,
    function (address) returns (uint256) getPairSwapFee
  ) internal returns (uint256 amountOut) {
    // sanity checks

    // Swap to reserve tokenIn
    if (swapRoute.pairsPath.length > 0) {
      for (uint256 i; i < swapRoute.pairsPath.length;) {
        swapRoute.swapFees[i] = getPairSwapFee(swapRoute.pairsPath[i]);
        unchecked {
          i++;
        }
      }

      amountOut = swapExactTokensForTokens(
        tokenIn,
        amountIn,
        swapRoute.swapFees,
        swapRoute.pairsPath,
        swapRoute.tokensPath
      );
    } else {
      amountOut = amountIn;
    }

    amountOut -= 1;

    (uint256 swapAmount, uint256 tokenAmountOut) = Uniswap.calcSimpleZap(
      tokenOut,
      getPairSwapFee(tokenOut),
      amountOut,
      zapLiquidityConfig.lpSubtokenIn,
      zapLiquidityConfig.lpSubtokenOut
    );

    ERC20(zapLiquidityConfig.lpSubtokenIn).safeTransfer(tokenOut, swapAmount);
    if (zapLiquidityConfig.lpSubtokenIn < zapLiquidityConfig.lpSubtokenOut) {
      IUniswapV2Pair(tokenOut).swap(0, tokenAmountOut, address(this), "");
    } else {
      IUniswapV2Pair(tokenOut).swap(tokenAmountOut, 0, address(this), "");
    }
    tokenAmountOut -= 1;
    ERC20(zapLiquidityConfig.lpSubtokenIn).safeTransfer(
      tokenOut, amountOut - swapAmount
    );
    ERC20(zapLiquidityConfig.lpSubtokenOut).safeTransfer(
      tokenOut, tokenAmountOut
    );
    amountOut = IUniswapV2Pair(tokenOut).mint(address(this));
  }
}
