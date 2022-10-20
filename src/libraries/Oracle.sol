pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router02} from
  "@uniswap/v2-periphery/interfaces/IUniswapV2Router02.sol";

library Oracle {
  /*
   * Oracles
   * <!> Used only externally, to check optimal compounding frequency.
   */

  function tokenInLP(
    ERC20 asset,
    address tokenBase,
    address tokenOther,
    address oracleRouter,
    address[] memory baseToRewardPath
  ) internal view returns (uint256) {
    uint256 lpTotalSupply = asset.totalSupply();
    uint256 reserveBase;
    {
      (uint256 reserve0, uint256 reserve1,) =
        IUniswapV2Pair(address(asset)).getReserves();
      reserveBase = tokenBase < tokenOther ? reserve0 : reserve1;
    }
    uint256 reserveBaseInReward = baseToRewardPath.length >= 2
      ? oracle(oracleRouter, reserveBase, baseToRewardPath)
      : reserveBase;
    return lpTotalSupply * 1e18 / (reserveBaseInReward * 2);
  }

  function ethToWantLP1(
    ERC20 asset,
    address tokenBase,
    address tokenOther,
    address oracleRouter,
    address[] memory baseToEthPath
  ) internal view returns (uint256) {
    uint256 lpTotalSupply = asset.totalSupply();
    uint256 reserveBase;
    {
      (uint256 reserve0, uint256 reserve1,) =
        IUniswapV2Pair(address(asset)).getReserves();
      reserveBase = tokenBase < tokenOther ? reserve0 : reserve1;
    }
    uint256 reserveBaseInEth = baseToEthPath.length >= 2
      ? oracle(oracleRouter, reserveBase, baseToEthPath)
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
