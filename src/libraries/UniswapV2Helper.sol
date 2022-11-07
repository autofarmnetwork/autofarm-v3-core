// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import "@uniswap/v2-core/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/interfaces/IUniswapV2Factory.sol";

library TransferHelper {
  function safeApprove(address token, address to, uint256 value) internal {
    // bytes4(keccak256(bytes('approve(address,uint256)')));
    (bool success, bytes memory data) =
      address(token).call(abi.encodeWithSelector(0x095ea7b3, to, value));
    require(
      success && (data.length == 0 || abi.decode(data, (bool))),
      "TransferHelper::safeApprove: approve failed"
    );
  }

  function safeTransfer(address token, address to, uint256 value) internal {
    // bytes4(keccak256(bytes('transfer(address,uint256)')));
    (bool success, bytes memory data) =
      address(token).call(abi.encodeWithSelector(0xa9059cbb, to, value));
    require(
      success && (data.length == 0 || abi.decode(data, (bool))),
      "TransferHelper::safeTransfer: transfer failed"
    );
  }

  function safeTransferFrom(
    address token,
    address from,
    address to,
    uint256 value
  ) internal {
    // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
    (bool success, bytes memory data) =
      address(token).call(abi.encodeWithSelector(0x23b872dd, from, to, value));
    require(
      success && (data.length == 0 || abi.decode(data, (bool))),
      "TransferHelper::transferFrom: transferFrom failed"
    );
  }

  function safeTransferETH(address to, uint256 value) internal {
    (bool success,) = to.call{value: value}(new bytes(0));
    require(success, "TransferHelper::safeTransferETH: ETH transfer failed");
  }
}

library UniswapV2Helper {
  using TransferHelper for address;

  struct SwapRoute {
    address[] pairsPath;
    address[] tokensPath;
    uint256[] feeFactors; // set to 0 if dynamic
  }

  struct ZapLiquidityConfig {
    address lpSubtokenIn;
    address lpSubtokenOut;
    uint256 feeFactor; // set to 0 if dynamic
  }

  /**
   * UniswapV2Library functions **
   */

  function getAmountOut(
    uint256 amountIn,
    uint256 reserve0,
    uint256 reserve1,
    uint256 feeFactor
  ) internal pure returns (uint256) {
    uint256 amountInWithFee = amountIn * feeFactor / 10000;
    uint256 nominator = amountInWithFee * reserve1;
    uint256 denominator = amountInWithFee + reserve0;
    return nominator / denominator;
  }

  // Slightly modified version of getAmountsOut
  function getAmountsOut(
    address factory,
    uint256 feeFactor,
    uint256 amountIn,
    address[] memory path
  ) internal view returns (uint256[] memory amounts) {
    require(path.length >= 2, "UniswapV2Library: INVALID_PATH");
    amounts = new uint[](path.length);
    amounts[0] = amountIn;
    for (uint256 i; i < path.length - 1;) {
      address pair = IUniswapV2Factory(factory).getPair(path[i], path[i + 1]);
      (uint256 reserveIn, uint256 reserveOut) =
        getReserves(pair, path[i], path[i + 1]);
      amounts[i + 1] =
        getAmountOut(amounts[i], reserveIn, reserveOut, feeFactor);
      unchecked {
        i++;
      }
    }
  }

  function getAmountsOutFromPairs(
    uint256 amountIn,
    uint256[] memory feeFactors,
    address[] memory pairsPath,
    address[] memory tokensPath
  ) internal view returns (uint256[] memory amounts) {
    require(tokensPath.length > 1, "UniswapV2Library: INVALID_PATH");
    require(
      tokensPath.length == pairsPath.length + 1,
      "UniswapV2Library: INVALID_PATH"
    );

    amounts = new uint[](tokensPath.length);
    amounts[0] = amountIn;
    for (uint256 i; i < pairsPath.length;) {
      (uint256 reserveIn, uint256 reserveOut) =
        getReserves(pairsPath[i], tokensPath[i], tokensPath[i + 1]);
      amounts[i + 1] =
        getAmountOut(amounts[i], reserveIn, reserveOut, feeFactors[i]);
      unchecked {
        i++;
      }
    }
  }

  // returns sorted token addresses, used to handle return values from pairs sorted in this order
  function sortTokens(address tokenA, address tokenB)
    internal
    pure
    returns (address token0, address token1)
  {
    require(tokenA != tokenB, "UniswapV2Library: IDENTICAL_ADDRESSES");
    (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    require(token0 != address(0), "UniswapV2Library: ZERO_ADDRESS");
  }

  function getReserves(address pair, address tokenA, address tokenB)
    internal
    view
    returns (uint256 reserveA, uint256 reserveB)
  {
    (address token0,) = sortTokens(tokenA, tokenB);
    (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
    (reserveA, reserveB) =
      tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
  }

  // calculates the CREATE2 address for a pair without making any external calls
  function pairFor(
    address factory,
    bytes32 INIT_HASH_CODE,
    address tokenA,
    address tokenB
  ) internal pure returns (address pair) {
    (address token0, address token1) = sortTokens(tokenA, tokenB);
    pair = address(
      uint160(
        uint256(
          keccak256(
            abi.encodePacked(
              hex"ff",
              factory,
              keccak256(abi.encodePacked(token0, token1)),
              INIT_HASH_CODE
            )
          )
        )
      )
    );
  }

  function getPair(
    address factory,
    bytes32 INIT_HASH_CODE,
    address token0,
    address token1
  ) internal view returns (address pair) {
    if (INIT_HASH_CODE != bytes32(0)) {
      pair = pairFor(factory, INIT_HASH_CODE, token0, token1);
    } else {
      // Some dexes do not have/use INIT_HASH_CODE
      pair = IUniswapV2Factory(factory).getPair(token0, token1);
    }
  }

  function quote(uint256 amountA, uint256 reserveA, uint256 reserveB)
    internal
    pure
    returns (uint256 amountB)
  {
    require(amountA > 0, "UniswapV2Library: INSUFFICIENT_AMOUNT");
    require(
      reserveA > 0 && reserveB > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY"
    );
    amountB = amountA * reserveB / reserveA;
  }

  function _addLiquidity(
    IUniswapV2Pair pair,
    address tokenA,
    address tokenB,
    uint256 amountADesired,
    uint256 amountBDesired,
    uint256 amountAMin,
    uint256 amountBMin
  ) internal view returns (uint256 amountA, uint256 amountB) {
    (uint256 reserve0, uint256 reserve1,) = pair.getReserves();
    (uint256 reserveA, uint256 reserveB) =
      tokenA > tokenB ? (reserve0, reserve1) : (reserve1, reserve0);
    if (reserveA == 0 && reserveB == 0) {
      (amountA, amountB) = (amountADesired, amountBDesired);
    } else {
      uint256 amountBOptimal = quote(amountADesired, reserveA, reserveB);
      if (amountBOptimal <= amountBDesired) {
        require(
          amountBOptimal >= amountBMin, "UniswapV2Router: INSUFFICIENT_B_AMOUNT"
        );
        (amountA, amountB) = (amountADesired, amountBOptimal);
      } else {
        uint256 amountAOptimal = quote(amountBDesired, reserveB, reserveA);
        assert(amountAOptimal <= amountADesired);
        require(
          amountAOptimal >= amountAMin, "UniswapV2Router: INSUFFICIENT_A_AMOUNT"
        );
        (amountA, amountB) = (amountAOptimal, amountBDesired);
      }
    }
  }

  /**
   * Swap helpers **
   */

  function calcSimpleZap(
    address pair,
    uint256 feeFactor,
    uint256 amountIn,
    address tokenIn,
    address tokenOut
  ) internal view returns (uint256 swapAmount, uint256 tokenAmountOut) {
    uint112 reserveInput;
    uint112 reserveOutput;
    {
      (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
      (reserveInput, reserveOutput) =
        tokenIn > tokenOut ? (reserve1, reserve0) : (reserve0, reserve1);
    }
    swapAmount = FixedPointMathLib.sqrt(
      reserveInput * (amountIn + reserveInput)
    ) - reserveInput;
    tokenAmountOut =
      getAmountOut(swapAmount, reserveInput, reserveOutput, feeFactor);
  }

  /**
   * Autoswap Router methods **
   */

  // Swaps one side of an LP and add liquidity
  function addLiquidityFromOneSide(
    address pair,
    uint256 swapAmount,
    uint256 subtokenAmountOut,
    address subtokenIn,
    address subtokenOut,
    uint256 amountIn,
    address to
  ) internal returns (uint256 outAmount) {
    subtokenIn.safeTransfer(pair, swapAmount);

    (address token0,) = sortTokens(subtokenIn, subtokenOut);
    (uint256 amountOutA, uint256 amountOutB) = subtokenIn == token0
      ? (uint256(0), subtokenAmountOut)
      : (subtokenAmountOut, uint256(0));
    IUniswapV2Pair(pair).swap(amountOutA, amountOutB, address(this), "");

    subtokenIn.safeTransfer(address(pair), amountIn - swapAmount);
    subtokenOut.safeTransfer(address(pair), subtokenAmountOut);
    outAmount = IUniswapV2Pair(pair).mint(to);
  }

  function swapWithTransferIn(
    address pair,
    uint256 feeFactor,
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    address to
  ) internal returns (uint256 amountOut) {
    tokenIn.safeTransfer(pair, amountIn);
    return swap(pair, feeFactor, tokenIn, tokenOut, amountIn, to);
  }

  function swap(
    address pair,
    uint256 feeFactor,
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    address to
  ) internal returns (uint256 amountOut) {
    (uint256 reserve0, uint256 reserve1) = getReserves(pair, tokenIn, tokenOut);
    amountOut = getAmountOut(amountIn, reserve0, reserve1, feeFactor);
    (address token0,) = sortTokens(tokenIn, tokenOut);
    (uint256 amountOutA, uint256 amountOutB) =
      tokenIn == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
    IUniswapV2Pair(pair).swap(amountOutA, amountOutB, to, "");
  }

  function swapSupportingFeeOnTransfer(
    address pair,
    uint256 feeFactor,
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    address to
  ) internal returns (uint256 amountOut) {
    (uint256 reserveInput, uint256 reserveOutput) =
      getReserves(pair, tokenIn, tokenOut);
    tokenIn.safeTransfer(pair, amountIn);
    amountIn = IERC20(tokenIn).balanceOf(pair) - reserveInput;
    amountOut = getAmountOut(amountIn, reserveInput, reserveOutput, feeFactor);
    (address token0,) = sortTokens(tokenIn, tokenOut);
    (uint256 amountOutA, uint256 amountOutB) =
      tokenIn == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
    IUniswapV2Pair(pair).swap(amountOutA, amountOutB, to, "");
  }

  function swapExactTokensForTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    uint256[] memory feeFactors,
    address[] memory pairsPath,
    address[] memory tokensPath
  ) internal returns (uint256 amountOut) {
    require(pairsPath.length > 0);

    uint256[] memory amountsOut =
      getAmountsOutFromPairs(amountIn, feeFactors, pairsPath, tokensPath);

    amountOut = amountsOut[amountsOut.length - 1];
    require(
      amountOut >= amountOutMin, "UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT"
    );

    tokensPath[0].safeTransfer(pairsPath[0], amountIn);

    for (uint256 i = 0; i < pairsPath.length;) {
      (address token0,) =
        sortTokens(tokensPath[i], tokensPath[i + 1]);
      (uint256 amountOutA, uint256 amountOutB) = tokensPath[i] == token0
        ? (uint256(0), amountsOut[i + 1])
        : (amountsOut[i + 1], uint256(0));
      IUniswapV2Pair(pairsPath[i]).swap(
        amountOutA,
        amountOutB,
        i == pairsPath.length - 1 ? address(this) : pairsPath[i + 1],
        ""
      );
      unchecked {
        i++;
      }
    }
  }

  function swapExactTokensToLiquidity1(
    address tokenOut,
    uint256 amountIn,
    SwapRoute memory swapRoute,
    ZapLiquidityConfig memory zapLiquidityConfig
  ) internal returns (uint256 amountOut) {
    // sanity checks

    // Swap to reserve tokenIn
    if (swapRoute.pairsPath.length > 0) {
      amountOut = swapExactTokensForTokens(
        amountIn,
        1,
        swapRoute.feeFactors,
        swapRoute.pairsPath,
        swapRoute.tokensPath
      );
    } else {
      amountOut = amountIn;
    }

    amountOut -= 1;

    (uint256 swapAmount, uint256 tokenAmountOut) = calcSimpleZap(
      tokenOut,
      zapLiquidityConfig.feeFactor,
      amountOut,
      zapLiquidityConfig.lpSubtokenIn,
      zapLiquidityConfig.lpSubtokenOut
    );

    zapLiquidityConfig.lpSubtokenIn.safeTransfer(tokenOut, swapAmount);
    if (zapLiquidityConfig.lpSubtokenIn < zapLiquidityConfig.lpSubtokenOut) {
      IUniswapV2Pair(tokenOut).swap(0, tokenAmountOut, address(this), "");
    } else {
      IUniswapV2Pair(tokenOut).swap(tokenAmountOut, 0, address(this), "");
    }
    tokenAmountOut -= 1;
    zapLiquidityConfig.lpSubtokenIn.safeTransfer(
      tokenOut, amountOut - swapAmount
    );
    zapLiquidityConfig.lpSubtokenOut.safeTransfer(tokenOut, tokenAmountOut);
    amountOut = IUniswapV2Pair(tokenOut).mint(address(this));
  }

  function swapExactTokensToLiquidity1WithDynamicFees(
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
        swapRoute.feeFactors[i] = getPairSwapFee(swapRoute.pairsPath[i]);
        unchecked {
          i++;
        }
      }

      amountOut = swapExactTokensForTokens(
        amountIn,
        1,
        swapRoute.feeFactors,
        swapRoute.pairsPath,
        swapRoute.tokensPath
      );
    } else {
      amountOut = amountIn;
    }

    amountOut -= 1;

    (uint256 swapAmount, uint256 tokenAmountOut) = calcSimpleZap(
      tokenOut,
      getPairSwapFee(tokenOut),
      amountOut,
      zapLiquidityConfig.lpSubtokenIn,
      zapLiquidityConfig.lpSubtokenOut
    );

    zapLiquidityConfig.lpSubtokenIn.safeTransfer(tokenOut, swapAmount);
    if (zapLiquidityConfig.lpSubtokenIn < zapLiquidityConfig.lpSubtokenOut) {
      IUniswapV2Pair(tokenOut).swap(0, tokenAmountOut, address(this), "");
    } else {
      IUniswapV2Pair(tokenOut).swap(tokenAmountOut, 0, address(this), "");
    }
    tokenAmountOut -= 1;
    zapLiquidityConfig.lpSubtokenIn.safeTransfer(
      tokenOut, amountOut - swapAmount
    );
    zapLiquidityConfig.lpSubtokenOut.safeTransfer(tokenOut, tokenAmountOut);
    amountOut = IUniswapV2Pair(tokenOut).mint(address(this));
  }
}
