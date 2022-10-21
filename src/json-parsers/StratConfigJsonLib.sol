// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Vm.sol";
import {LibString} from "solmate/utils/LibString.sol";

import {SwapRoute, ZapLiquidityConfig} from "../libraries/StratX4LibEarn.sol";

struct StratConfigJson {
  address asset;
  address farmContractAddress;
  address mainRewardToken;
  uint256 pid;
  SwapRouteJson swapRouteJson;
  ZapLiquidityConfigJson zapLiquidityConfigJson;
}

struct SwapRouteJson {
  address[] pairsPath;
  uint256[] swapFees;
  address[] tokensPath;
}

struct ZapLiquidityConfigJson {
  address lpSubtokenIn;
  address lpSubtokenOut;
  uint256 swapFee;
}

library StratConfigJsonLib {
  function load(Vm vm, string memory json)
    internal
    returns (
      address asset,
      address farmContractAddress,
      uint256 pid,
      address mainRewardToken,
      SwapRoute memory swapRoute,
      ZapLiquidityConfig memory zapLiquidityConfig
    )
  {
    StratConfigJson memory stratConfigJson = abi.decode(vm.parseJson(json), (StratConfigJson));

    asset = stratConfigJson.asset;
    farmContractAddress = stratConfigJson.farmContractAddress;
    pid = stratConfigJson.pid;
    mainRewardToken = stratConfigJson.mainRewardToken;

    swapRoute = mapSwapRoute(stratConfigJson.swapRouteJson);
    zapLiquidityConfig = mapZapLiquidityConfig(stratConfigJson.zapLiquidityConfigJson);
  }

  function mapSwapRoute(SwapRouteJson memory swapRouteJson)
    internal
    pure
    returns (SwapRoute memory swapRoute)
  {
    swapRoute.swapFees = swapRouteJson.swapFees;
    swapRoute.pairsPath = swapRouteJson.pairsPath;
    swapRoute.tokensPath = swapRouteJson.tokensPath;
  }

  function mapZapLiquidityConfig(ZapLiquidityConfigJson memory zapLiquidityConfigJson)
    internal
    pure
    returns (ZapLiquidityConfig memory zapLiquidityConfig)
  {
    zapLiquidityConfig.swapFee = zapLiquidityConfigJson.swapFee;
    zapLiquidityConfig.lpSubtokenIn = zapLiquidityConfigJson.lpSubtokenIn;
    zapLiquidityConfig.lpSubtokenOut = zapLiquidityConfigJson.lpSubtokenOut;
  }
}
