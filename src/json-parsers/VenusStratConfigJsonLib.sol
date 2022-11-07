// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Vm.sol";
import {LibString} from "solmate/utils/LibString.sol";

import {UniswapV2Helper} from "../libraries/UniswapV2Helper.sol";

struct EarnConfig {
  address rewardToken;
  UniswapV2Helper.SwapRoute swapRoute;
}

struct EarnConfigJson {
  address rewardToken;
  SwapRouteJson swapRouteJson;
}

struct StratConfigJson {
  address asset;
  address farmContractAddress;
}

struct SwapRouteJson {
  uint256[] feeFactors;
  address[] pairsPath;
  address[] tokensPath;
}

library VenusStratConfigJsonLib {
  function load(Vm vm, string memory json)
    internal
    returns (
      address asset,
      address farmContractAddress,
      EarnConfig[] memory earnConfigs
    )
  {
    StratConfigJson memory stratConfigJson =
      abi.decode(vm.parseJson(json, ".strat"), (StratConfigJson));

    asset = stratConfigJson.asset;
    farmContractAddress = stratConfigJson.farmContractAddress;

    EarnConfigJson[] memory earnConfigsJson =
      abi.decode(vm.parseJson(json, ".earnConfigs"), (EarnConfigJson[]));

    earnConfigs = new EarnConfig[](earnConfigsJson.length);
    for (uint256 i; i < earnConfigsJson.length; i++) {
      earnConfigs[i].rewardToken = earnConfigsJson[i].rewardToken;
      earnConfigs[i].swapRoute = mapSwapRoute(earnConfigsJson[i].swapRouteJson);
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
}
