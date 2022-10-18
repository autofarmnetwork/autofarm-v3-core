// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {SSTORE2} from "solmate/utils/SSTORE2.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/interfaces/IUniswapV2Router02.sol";

import {Uniswap} from "./Uniswap.sol";

error EarnFailed();

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

struct SwapConfig {
  address pair;
  address tokenOut;
}

struct LP1Config {
  uint256 pairSwapFee; // set to 0 if dynamic
  SwapConfig[] earnedToBasePath;
}

// Biswap
interface IUniswapV2PairDynamicFee {
  function swapFee() external view returns (uint32);
}

library StratX4LibEarn {
  using SafeTransferLib for ERC20;

  function _getPairSwapFee(address pair) internal view returns (uint256) {
    return (1000 - IUniswapV2PairDynamicFee(pair).swapFee()) * 10;
  }

  function compoundLP1(
    ERC20 asset,
    address tokenBase,
    address tokenOther,
    uint256 earnedAmt,
    ERC20 earnedAddress,
    LP1Config memory earnConfig
  ) internal returns (uint256 assets) {
    // Swap to base
    uint256 swapAmount = earnedAmt;
    if (earnConfig.earnedToBasePath.length > 0) {
      ERC20(earnedAddress).safeTransfer(earnConfig.earnedToBasePath[0].pair, swapAmount);

      for (uint256 i; i < earnConfig.earnedToBasePath.length;) {
        SwapConfig memory swapConfig = earnConfig.earnedToBasePath[i];
        swapAmount = Uniswap._swap(
          swapConfig.pair,
          earnConfig.pairSwapFee > 0 ? earnConfig.pairSwapFee : _getPairSwapFee(swapConfig.pair),
          i == 0 ? address(earnedAddress) : earnConfig.earnedToBasePath[i - 1].tokenOut,
          i == earnConfig.earnedToBasePath.length - 1 ? tokenBase : swapConfig.tokenOut,
          swapAmount,
          i == earnConfig.earnedToBasePath.length - 1 ? address(this) : earnConfig.earnedToBasePath[i + 1].pair
        );
        unchecked {
          i++;
        }
      }
    }

    uint256 baseAmount = swapAmount;
    uint256 tokenAmountOut;
    (swapAmount, tokenAmountOut) = Uniswap.calcSimpleZap(
      address(asset),
      earnConfig.pairSwapFee > 0 ? earnConfig.pairSwapFee : _getPairSwapFee(address(asset)),
      baseAmount,
      tokenBase,
      tokenOther
    );

    assets =
      Uniswap.oneSidedSwap(address(asset), swapAmount, tokenAmountOut, tokenBase, tokenOther, baseAmount, address(this));
  }
}
