// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Vm.sol";
import {LibString} from "solmate/utils/LibString.sol";

import {SwapRoute, ZapLiquidityConfig} from "../libraries/StratX4LibEarn.sol";

struct EarnConfig {
  address rewardToken;
  SwapRoute swapRoute;
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
  address[] pairsPath;
  uint256[] swapFees;
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
    returns (SwapRoute memory swapRoute)
  {
    swapRoute.swapFees = swapRouteJson.swapFees;
    swapRoute.pairsPath = swapRouteJson.pairsPath;
    swapRoute.tokensPath = swapRouteJson.tokensPath;
  }
}
