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
  IUniswapV2Router01 public immutable router;

  constructor() {
    factory = IUniswapV2Factory(
      deployCode(
        "./uniswap-build/UniswapV2Factory.json", abi.encode(address(this))
      )
    );

    router = IUniswapV2Router01(
      deployCode(
        "./uniswap-build/UniswapV2Router02.json",
        abi.encode(address(factory), makeAddr("WETH"))
      )
    );
  }

  function addLiquidity(
    address tokenA,
    address tokenB,
    uint256 amountA,
    uint256 amountB,
    address to
  ) internal returns (address pair) {
    pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);
    if (pair == address(0)) {
      pair = IUniswapV2Factory(factory).createPair(tokenA, tokenB);
    }

    deal(tokenA, pair, amountA);
    deal(tokenB, pair, amountB);
    IUniswapV2Pair(pair).mint(to);
  }
}
