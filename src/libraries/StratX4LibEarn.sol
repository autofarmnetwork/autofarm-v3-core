// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SSTORE2} from "solmate/utils/SSTORE2.sol";
import {IUniswapV2Router02} from
  "@uniswap/v2-periphery/interfaces/IUniswapV2Router02.sol";

import "./Uniswap.sol";
import "../interfaces/IPancakePair.sol";
import "./StratX3Lib.sol";
import "../StratX4.sol";

error EarnFailed();

/*
 * StratX4LibEarn
 * - Swaps reward tokens into asset tokens.
 * - Responsible for all vault earns?
 *
 * Strategies
 * 0. No swaps: Reward and asset tokens are the same
 * 1. Asset is TOKEN-REWARD LP: do one side swap liquidity
 * 2. Asset is BASE-TOKEN LP: swap token to BASE and do one side liquidity
 * 3. (Optional) Asset is TOKEN-TOKEN: Swap to base(s) and buy tokens separately
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
  uint256 swapFee; // set to 0 if dynamic
  address tokenOut;
}

struct LP1EarnConfig {
  SwapConfig[] earnedToBasePath;
  // address[] earnedToAUTOPath; // sav

  // token0 and token1
  address tokenBase;
  address tokenOther;
  uint256 pairSwapFee; // set to 0 if dynamic
  // For gas oracle
  address oracleRouter; // dex to use
  address[] baseToEthPath;
  address[] baseToRewardPath;
}

// Biswap
interface IUniswapV2PairDynamicFee {
  function swapFee() external view returns (uint32);
}

library StratX4LibEarn {
  using SafeTransferLib for ERC20;
  using FixedPointMathLib for uint256;

  function setEarnConfig(LP1EarnConfig memory _earnConfig)
    internal
    returns (address earnConfigPointer)
  {
    // TODO: check that swaps link to correct tokens
    earnConfigPointer = SSTORE2.write(abi.encode(_earnConfig));
  }

  function _getPairSwapFee(address pair) internal view returns (uint256) {
    return (1000 - IUniswapV2PairDynamicFee(pair).swapFee()) * 10;
  }

  function compoundLP1(
    ERC20 asset,
    uint256 earnedAmt,
    ERC20 earnedAddress,
    address earnConfigPointer
  )
    internal
    returns (uint256 assets)
  {
    LP1EarnConfig memory earnConfig =
      abi.decode(SSTORE2.read(earnConfigPointer), (LP1EarnConfig));

    // Swap to base
    uint256 swapAmount = earnedAmt;
    if (earnConfig.earnedToBasePath.length > 0) {
      ERC20(earnedAddress).safeTransfer(
        earnConfig.earnedToBasePath[0].pair, swapAmount
      );

      for (uint256 i; i < earnConfig.earnedToBasePath.length;) {
        SwapConfig memory swapConfig = earnConfig.earnedToBasePath[i];
        swapAmount = Uniswap._swap(
          swapConfig.pair,
          swapConfig.swapFee > 0
            ? swapConfig.swapFee
            : _getPairSwapFee(swapConfig.pair),
          i == 0
            ? address(earnedAddress)
            : earnConfig.earnedToBasePath[i - 1].tokenOut,
          i == earnConfig.earnedToBasePath.length - 1
            ? earnConfig.tokenBase
            : swapConfig.tokenOut,
          swapAmount,
          i == earnConfig.earnedToBasePath.length - 1
            ? address(this)
            : earnConfig.earnedToBasePath[i + 1].pair
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
      earnConfig.pairSwapFee > 0
        ? earnConfig.pairSwapFee
        : _getPairSwapFee(address(asset)),
      baseAmount,
      earnConfig.tokenBase,
      earnConfig.tokenOther
    );

    assets = Uniswap.oneSidedSwap(
      address(asset),
      swapAmount,
      tokenAmountOut,
      earnConfig.tokenBase,
      earnConfig.tokenOther,
      baseAmount,
      address(this)
    );
  }

  /*
   * Oracles
   * <!> Used only externally, to check optimal compounding frequency.
   */

  function rewardToWantLP1(ERC20 asset, address earnConfigPointer)
    internal
    view
    returns (uint256)
  {
    LP1EarnConfig memory earnConfig =
      abi.decode(SSTORE2.read(earnConfigPointer), (LP1EarnConfig));
    uint256 lpTotalSupply = asset.totalSupply();
    uint256 reserveBase;
    {
      (uint256 reserve0, uint256 reserve1,) =
        IPancakePair(address(asset)).getReserves();
      reserveBase =
        earnConfig.tokenBase < earnConfig.tokenOther ? reserve0 : reserve1;
    }
    uint256 reserveBaseInReward =
      earnConfig.baseToRewardPath.length >= 2
      ? oracle(earnConfig.oracleRouter, reserveBase, earnConfig.baseToRewardPath)
      : reserveBase;
    return lpTotalSupply * 1e18 / (reserveBaseInReward * 2);
  }

  function ethToWantLP1(ERC20 asset, address earnConfigPointer)
    internal
    view
    returns (uint256)
  {
    LP1EarnConfig memory earnConfig =
      abi.decode(SSTORE2.read(earnConfigPointer), (LP1EarnConfig));
    uint256 lpTotalSupply = asset.totalSupply();
    uint256 reserveBase;
    {
      (uint256 reserve0, uint256 reserve1,) =
        IPancakePair(address(asset)).getReserves();
      reserveBase =
        earnConfig.tokenBase < earnConfig.tokenOther ? reserve0 : reserve1;
    }
    uint256 reserveBaseInEth =
      earnConfig.baseToEthPath.length >= 2
      ? oracle(earnConfig.oracleRouter, reserveBase, earnConfig.baseToEthPath)
      : reserveBase;

    return lpTotalSupply * 1e18 / (reserveBaseInEth * 2);
  }

  function oracle(address router, uint256 amountIn, address[] memory path)
    internal
    view
    returns (uint256 amountOut)
  {
    uint256[] memory amounts =
      IUniswapV2Router02(router).getAmountsOut(amountIn, path);
    amountOut = amounts[amounts.length - 1];
  }
}