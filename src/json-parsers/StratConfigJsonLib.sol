// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Vm.sol";
import {LibString} from "solmate/utils/LibString.sol";

import {UniswapV2Helper} from "../libraries/UniswapV2Helper.sol";

struct EarnConfig {
  address rewardToken;
  UniswapV2Helper.SwapRoute swapRoute;
  UniswapV2Helper.ZapLiquidityConfig zapLiquidityConfig;
}

struct EarnConfigJson {
  address rewardToken;
  SwapRouteJson swapRouteJson;
  ZapLiquidityConfigJson zapLiquidityConfigJson;
}

struct StratConfigJson {
  address asset;
  address farmContractAddress;
  uint256 pid;
}

struct SwapRouteJson {
  uint256[] feeFactors;
  address[] pairsPath;
  address[] tokensPath;
}

struct ZapLiquidityConfigJson {
  uint256 feeFactor;
  address lpSubtokenIn;
  address lpSubtokenOut;
}

library StratConfigJsonLib {
  function load(Vm vm, string memory json)
    internal
    returns (
      address asset,
      address farmContractAddress,
      uint256 pid,
      EarnConfig[] memory earnConfigs
    )
  {
    StratConfigJson memory stratConfigJson =
      abi.decode(vm.parseJson(json, ".strat"), (StratConfigJson));

    asset = stratConfigJson.asset;
    farmContractAddress = stratConfigJson.farmContractAddress;
    pid = stratConfigJson.pid;

    EarnConfigJson[] memory earnConfigsJson =
      abi.decode(vm.parseJson(json, ".earnConfigs"), (EarnConfigJson[]));

    earnConfigs = new EarnConfig[](earnConfigsJson.length);
    for (uint256 i; i < earnConfigsJson.length; i++) {
      earnConfigs[i].rewardToken = earnConfigsJson[i].rewardToken;
      earnConfigs[i].swapRoute = mapSwapRoute(earnConfigsJson[i].swapRouteJson);
      earnConfigs[i].zapLiquidityConfig =
        mapZapLiquidityConfig(earnConfigsJson[i].zapLiquidityConfigJson);
    }
  }

  function mapSwapRoute(SwapRouteJson memory swapRouteJson)
    internal
    pure
    returns (UniswapV2Helper.SwapRoute memory swapRoute)
  {
    swapRoute.feeFactors = swapRouteJson.feeFactors;
    swapRoute.pairsPath = swapRouteJson.pairsPath;
    swapRoute.tokensPath = swapRouteJson.tokensPath;
  }

  function mapZapLiquidityConfig(
    ZapLiquidityConfigJson memory zapLiquidityConfigJson
  )
    internal
    pure
    returns (UniswapV2Helper.ZapLiquidityConfig memory zapLiquidityConfig)
  {
    zapLiquidityConfig.feeFactor = zapLiquidityConfigJson.feeFactor;
    zapLiquidityConfig.lpSubtokenIn = zapLiquidityConfigJson.lpSubtokenIn;
    zapLiquidityConfig.lpSubtokenOut = zapLiquidityConfigJson.lpSubtokenOut;
  }
}
