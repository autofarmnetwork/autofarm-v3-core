// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {MockERC20} from "../mocks/MockERC20.sol";
import {
  IUniswapV2Factory,
  IUniswapV2Router01,
  IUniswapV2Pair
} from "../../src/interfaces/Uniswap.sol";

abstract contract UniswapTestBase is Test {
  IUniswapV2Factory public immutable factory;

  constructor() {
    factory = IUniswapV2Factory(deployFactory());
  }

  function deployFactory() internal returns (address _factory) {
    _factory = deployCode(
      "./uniswap-v2-build/UniswapV2Factory.json", abi.encode(address(this))
    );
  }

  function addLiquidity(
    address tokenA,
    address tokenB,
    uint256 amountA,
    uint256 amountB,
    address to
  ) internal returns (address pair, uint256 liquidity) {
    return addLiquidityForFactory(
      tokenA, tokenB, amountA, amountB, to, address(factory)
    );
  }

  function addLiquidityForFactory(
    address tokenA,
    address tokenB,
    uint256 amountA,
    uint256 amountB,
    address to,
    address _factory
  ) internal returns (address pair, uint256 liquidity) {
    pair = IUniswapV2Factory(_factory).getPair(tokenA, tokenB);
    if (pair == address(0)) {
      pair = IUniswapV2Factory(_factory).createPair(tokenA, tokenB);
    }

    deal(tokenA, pair, ERC20(tokenA).balanceOf(pair) + amountA);
    deal(tokenB, pair, ERC20(tokenB).balanceOf(pair) + amountB);
    liquidity = IUniswapV2Pair(pair).mint(to);
  }
}
