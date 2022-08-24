// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "solmate/utils/FixedPointMathLib.sol";
import "solmate/tokens/ERC20.sol";
import "solmate/utils/SafeTransferLib.sol";

import "@uniswap/v2-core/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/interfaces/IUniswapV2Factory.sol";

library Uniswap {
  using SafeTransferLib for ERC20;
  using SafeTransferLib for address;

  /**
   * UniswapV2Library functions **
   */

  function getAmountOut(
    uint256 amountIn,
    uint256 reserve0,
    uint256 reserve1,
    uint256 fee
  )
    internal
    pure
    returns (uint256)
  {
    uint256 amountInWithFee = amountIn * fee / 10000;
    uint256 nominator = amountInWithFee * reserve1;
    uint256 denominator = amountInWithFee + reserve0;
    return nominator / denominator;
  }

  // Slightly modified version of getAmountsOut
  function getAmountsOut(
    address factory,
    uint256 swapFee,
    uint256 amountIn,
    address[] memory path
  )
    internal
    view
    returns (uint256[] memory amounts)
  {
    require(path.length >= 2, "UniswapV2Library: INVALID_PATH");
    amounts = new uint[](path.length);
    amounts[0] = amountIn;
    for (uint256 i; i < path.length - 1; i++) {
      address pair = IUniswapV2Factory(factory).getPair(path[i], path[i + 1]);
      (uint256 reserveIn, uint256 reserveOut) =
        getReserves(pair, path[i], path[i + 1]);
      amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut, swapFee);
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
  )
    internal
    pure
    returns (address pair)
  {
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
  )
    internal
    view
    returns (address pair)
  {
    if (INIT_HASH_CODE != bytes32("")) {
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
    require(amountA > 0, "PancakeLibrary: INSUFFICIENT_AMOUNT");
    require(
      reserveA > 0 && reserveB > 0, "PancakeLibrary: INSUFFICIENT_LIQUIDITY"
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
  )
    internal
    view
    returns (uint256 amountA, uint256 amountB)
  {
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
    uint256 swapFee,
    uint256 amountIn,
    address tokenIn,
    address tokenOut
  )
    internal
    view
    returns (uint256 swapAmount, uint256 tokenAmountOut)
  {
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
      Uniswap.getAmountOut(swapAmount, reserveInput, reserveOutput, swapFee);
  }

  /**
   * Autoswap Router methods **
   */

  // Swaps one side of an LP and add liquidity
  function oneSidedSwap(
    address pair,
    uint256 swapAmount,
    uint256 tokenAmountOut,
    address inToken,
    address otherToken,
    uint256 amountIn,
    address to
  )
    internal
    returns (uint256 outAmount)
  {
    ERC20(inToken).safeTransfer(pair, swapAmount);
    if (inToken < otherToken) {
      IUniswapV2Pair(pair).swap(0, tokenAmountOut, address(this), "");
    } else {
      IUniswapV2Pair(pair).swap(tokenAmountOut, 0, address(this), "");
    }
    ERC20(inToken).safeTransfer(address(pair), amountIn - swapAmount);
    ERC20(otherToken).safeTransfer(address(pair), tokenAmountOut);
    outAmount = IUniswapV2Pair(pair).mint(to);
  }

  function _swap(
    address pair,
    uint256 fee,
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    address to
  )
    internal
    returns (uint256 amountOut)
  {
    (uint256 reserve0, uint256 reserve1) = getReserves(pair, tokenIn, tokenOut);
    amountOut = getAmountOut(amountIn, reserve0, reserve1, fee);
    // TODO: amount is already in pair if linear path
    // TODO: pass to next pair directly if linear path
    if (tokenIn < tokenOut) {
      IUniswapV2Pair(pair).swap(0, amountOut, to, "");
    } else {
      IUniswapV2Pair(pair).swap(amountOut, 0, to, "");
    }
  }

  function swap(
    address pair,
    uint256 fee,
    address tokenIn,
    address tokenOut,
    uint256 amountIn
  )
    internal
    returns (uint256 amountOut)
  {
    ERC20(tokenIn).safeTransfer(pair, amountIn);
    (uint256 reserve0, uint256 reserve1) = getReserves(pair, tokenIn, tokenOut);
    amountOut = getAmountOut(amountIn, reserve0, reserve1, fee);
    // TODO: amount is already in pair if linear path
    // TODO: pass to next pair directly if linear path
    if (tokenIn < tokenOut) {
      IUniswapV2Pair(pair).swap(0, amountOut, address(this), "");
    } else {
      IUniswapV2Pair(pair).swap(amountOut, 0, address(this), "");
    }
  }

  function swapSupportingFeeOnTransfer(
    address pair,
    uint256 fee,
    address tokenIn,
    address tokenOut,
    uint256 amountIn
  )
    internal
    returns (uint256 amountOut)
  {
    (uint256 reserveInput, uint256 reserveOutput) =
      getReserves(pair, tokenIn, tokenOut);
    ERC20(tokenIn).safeTransfer(pair, amountIn);
    amountIn = ERC20(tokenIn).balanceOf(pair) - reserveInput;
    amountOut = getAmountOut(amountIn, reserveInput, reserveOutput, fee);
    // TODO: amount is already in pair if linear path
    // TODO: pass to next pair directly if linear path
    if (tokenIn < tokenOut) {
      IUniswapV2Pair(pair).swap(0, amountOut, address(this), "");
    } else {
      IUniswapV2Pair(pair).swap(amountOut, 0, address(this), "");
    }
  }
}